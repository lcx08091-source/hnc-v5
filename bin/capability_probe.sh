#!/system/bin/sh
# HNC hotfix17.0 capability_probe.sh
# Safe tc capability probe using a disposable dummy interface. The result is
# written to /data/local/hnc/run/capabilities.json and consumed by WebUI,
# tc_manager.sh, watchdog.sh and hnc_httpd.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

HNC=${HNC:-/data/local/hnc}
RUN="$HNC/run"
LOGDIR="$HNC/logs"
OUT="$RUN/capabilities.json"
RAW="$RUN/capabilities.raw.log"
mkdir -p "$RUN" "$LOGDIR" 2>/dev/null || true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CAP] $*"; }
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}

find_bin() {
    # Prefer a future bundled full iproute2 tc if present; otherwise use system tc.
    for c in "$HNC/bin/hnc_tc" "$HNC/bin/tc" /system/bin/tc /vendor/bin/tc /system/xbin/tc; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    command -v tc 2>/dev/null && return 0
    echo tc
}

TC_BIN=$(find_bin)
IP_BIN=$(command -v ip 2>/dev/null || echo ip)
DUMMY="hnc_probe_dummy_$$"
PEER="hnc_probe_peer_$$"
IFB="hnc_probe_ifb_$$"
TMPERR="$RUN/cap_probe_err.$$"

cleanup() {
    "$TC_BIN" qdisc del dev "$DUMMY" root >/dev/null 2>&1 || true
    "$TC_BIN" qdisc del dev "$DUMMY" clsact >/dev/null 2>&1 || true
    "$TC_BIN" qdisc del dev "$DUMMY" ingress >/dev/null 2>&1 || true
    "$IP_BIN" link del "$DUMMY" >/dev/null 2>&1 || true
    "$IP_BIN" link del "$PEER" >/dev/null 2>&1 || true
    "$IP_BIN" link del "$IFB" >/dev/null 2>&1 || true
    rm -f "$TMPERR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

run_tc() {
    : > "$TMPERR"
    "$TC_BIN" "$@" > /dev/null 2>"$TMPERR"
}
run_ip() {
    : > "$TMPERR"
    "$IP_BIN" "$@" > /dev/null 2>"$TMPERR"
}
last_err() { head -1 "$TMPERR" 2>/dev/null | tr '\r\n' ' ' | cut -c1-180; }

probe_root_qdisc() {
    # $1=name, rest=tc args after qdisc replace dev DUMMY root
    "$TC_BIN" qdisc del dev "$DUMMY" root >/dev/null 2>&1 || true
    : > "$TMPERR"
    "$TC_BIN" qdisc replace dev "$DUMMY" root "$@" > /dev/null 2>"$TMPERR"
}

reset_ingress() {
    "$TC_BIN" qdisc del dev "$DUMMY" clsact >/dev/null 2>&1 || true
    "$TC_BIN" qdisc del dev "$DUMMY" ingress >/dev/null 2>&1 || true
}
ensure_ingress_parent() {
    reset_ingress
    if run_tc qdisc add dev "$DUMMY" clsact; then
        echo clsact
        return 0
    fi
    if run_tc qdisc add dev "$DUMMY" ingress; then
        echo ingress
        return 0
    fi
    echo none
    return 1
}

# Basic tc binary check.
TC_VERSION=$({ "$TC_BIN" -V 2>&1 || true; } | head -1 | tr '\r\n' ' ' | cut -c1-160)
[ -n "$TC_VERSION" ] || TC_VERSION="unknown"
TC_BINARY_OK=false
run_tc qdisc show >/dev/null 2>&1 && TC_BINARY_OK=true

DUMMY_CREATE=false
PEER_CREATE=false
if run_ip link add dev "$DUMMY" type dummy; then
    DUMMY_CREATE=true
    run_ip link set dev "$DUMMY" up || true
fi
if run_ip link add dev "$PEER" type dummy; then
    PEER_CREATE=true
    run_ip link set dev "$PEER" up || true
fi

# Defaults: null means unknown/unsafe to decide. Existing HNC gates only disable on explicit false.
TC_HTB=null; TC_HTB_ERR=""
TC_TBF=null; TC_TBF_ERR=""
TC_NETEM=null; TC_NETEM_ERR=""
TC_INGRESS=null; TC_CLSACT=null; TC_U32=null; TC_FLOWER=null; TC_MATCHALL=null; TC_POLICE=null; TC_MIRRED=null
TC_U32_ERR=""; TC_FLOWER_ERR=""; TC_MATCHALL_ERR=""; TC_POLICE_ERR=""; TC_MIRRED_ERR=""

if [ "$DUMMY_CREATE" = true ] && [ "$TC_BINARY_OK" = true ]; then
    if probe_root_qdisc handle 1: htb default 9999; then TC_HTB=true; else TC_HTB=false; TC_HTB_ERR=$(last_err); fi
    if probe_root_qdisc tbf rate 1mbit burst 32kbit latency 400ms; then TC_TBF=true; else TC_TBF=false; TC_TBF_ERR=$(last_err); fi
    if probe_root_qdisc netem delay 50ms; then TC_NETEM=true; else TC_NETEM=false; TC_NETEM_ERR=$(last_err); fi
    "$TC_BIN" qdisc del dev "$DUMMY" root >/dev/null 2>&1 || true

    reset_ingress
    if run_tc qdisc add dev "$DUMMY" ingress; then TC_INGRESS=true; else TC_INGRESS=false; fi
    reset_ingress
    if run_tc qdisc add dev "$DUMMY" clsact; then TC_CLSACT=true; else TC_CLSACT=false; fi

    PARENT=$(ensure_ingress_parent)
    if [ "$PARENT" != none ]; then
        if run_tc filter add dev "$DUMMY" parent ffff: protocol ip prio 10 u32 match ip src 0.0.0.0/0; then
            TC_U32=true
        else
            TC_U32=false; TC_U32_ERR=$(last_err)
        fi
        "$TC_BIN" filter del dev "$DUMMY" parent ffff: >/dev/null 2>&1 || true

        if run_tc filter add dev "$DUMMY" parent ffff: protocol ip prio 11 u32 match ip src 0.0.0.0/0 police rate 1mbit burst 32k drop; then
            TC_POLICE=true
        else
            TC_POLICE=false; TC_POLICE_ERR=$(last_err)
        fi
        "$TC_BIN" filter del dev "$DUMMY" parent ffff: >/dev/null 2>&1 || true

        if [ "$PEER_CREATE" = true ] && run_tc filter add dev "$DUMMY" parent ffff: protocol ip prio 12 u32 match ip src 0.0.0.0/0 action mirred egress redirect dev "$PEER"; then
            TC_MIRRED=true
        else
            TC_MIRRED=false; TC_MIRRED_ERR=$(last_err)
        fi
        "$TC_BIN" filter del dev "$DUMMY" parent ffff: >/dev/null 2>&1 || true

        if run_tc filter add dev "$DUMMY" parent ffff: protocol ip prio 13 matchall action drop; then
            TC_MATCHALL=true
        else
            TC_MATCHALL=false; TC_MATCHALL_ERR=$(last_err)
        fi
        "$TC_BIN" filter del dev "$DUMMY" parent ffff: >/dev/null 2>&1 || true

        if run_tc filter add dev "$DUMMY" parent ffff: protocol ip prio 14 flower src_ip 0.0.0.0/0 action drop; then
            TC_FLOWER=true
        else
            TC_FLOWER=false; TC_FLOWER_ERR=$(last_err)
        fi
        "$TC_BIN" filter del dev "$DUMMY" parent ffff: >/dev/null 2>&1 || true
    fi
fi

IFB_CREATE=false
if run_ip link add dev "$IFB" type ifb; then
    IFB_CREATE=true
    run_ip link del "$IFB" || true
fi

# Compatibility + mode decisions.
UPLINK_SUPPORTED=false
[ "$IFB_CREATE" = true ] && [ "$TC_MIRRED" = true ] && [ "$TC_HTB" = true ] && UPLINK_SUPPORTED=true
UPLINK_POLICE_SUPPORTED=false
[ "$TC_POLICE" = true ] && UPLINK_POLICE_SUPPORTED=true

DOWNLINK_MODE=unknown
if [ "$TC_HTB" = true ]; then DOWNLINK_MODE=htb; elif [ "$TC_TBF" = true ]; then DOWNLINK_MODE=tbf_global; elif [ "$TC_HTB" = false ]; then DOWNLINK_MODE=unsupported; fi
UPLINK_MODE=unsupported
if [ "$UPLINK_SUPPORTED" = true ]; then UPLINK_MODE=ifb_htb; elif [ "$UPLINK_POLICE_SUPPORTED" = true ]; then UPLINK_MODE=police; fi
DELAY_MODE=unknown
if [ "$TC_NETEM" = true ] && [ "$TC_HTB" = true ]; then DELAY_MODE=netem; elif [ "$TC_NETEM" = false ] || [ "$TC_HTB" = false ]; then DELAY_MODE=unsupported; fi

IFACE=""
[ -f "$RUN/iface.cache" ] && IFACE=$(cat "$RUN/iface.cache" 2>/dev/null | head -1 | tr -d '\r\n')
REAL_QDISC=""
if [ -n "$IFACE" ]; then
    REAL_QDISC=$("$TC_BIN" qdisc show dev "$IFACE" 2>&1 | head -3 | tr '\r\n' ' ' | cut -c1-240)
fi

NOW=$(date +%s 2>/dev/null || echo 0)
TMP="$OUT.tmp.$$"
cat > "$TMP" <<EOF_JSON
{
  "schema": 2,
  "generated_at": $NOW,
  "probe": "hotfix17_dummy_sandbox",
  "tc_binary": "$(json_escape "$TC_BIN")",
  "tc_binary_source": "$(case "$TC_BIN" in "$HNC"/*) echo bundled ;; *) echo system ;; esac)",
  "tc_binary_ok": $TC_BINARY_OK,
  "tc_version": "$(json_escape "$TC_VERSION")",
  "dummy_create": $DUMMY_CREATE,
  "dummy_iface": "$(json_escape "$DUMMY")",
  "probe_iface": "$(json_escape "$IFACE")",
  "probe_iface_qdisc": "$(json_escape "$REAL_QDISC")",

  "tc_htb": $TC_HTB,
  "tc_htb_supported": $TC_HTB,
  "tc_htb_error": "$(json_escape "$TC_HTB_ERR")",
  "tc_tbf_supported": $TC_TBF,
  "tc_tbf_error": "$(json_escape "$TC_TBF_ERR")",
  "tc_netem": $TC_NETEM,
  "tc_netem_supported": $TC_NETEM,
  "tc_netem_error": "$(json_escape "$TC_NETEM_ERR")",
  "tc_ingress_supported": $TC_INGRESS,
  "tc_clsact_supported": $TC_CLSACT,
  "tc_u32_supported": $TC_U32,
  "tc_u32_error": "$(json_escape "$TC_U32_ERR")",
  "tc_flower_supported": $TC_FLOWER,
  "tc_flower_error": "$(json_escape "$TC_FLOWER_ERR")",
  "tc_matchall": $TC_MATCHALL,
  "tc_matchall_supported": $TC_MATCHALL,
  "tc_matchall_error": "$(json_escape "$TC_MATCHALL_ERR")",
  "tc_police_supported": $TC_POLICE,
  "tc_police_error": "$(json_escape "$TC_POLICE_ERR")",
  "tc_mirred": $TC_MIRRED,
  "tc_mirred_supported": $TC_MIRRED,
  "tc_mirred_error": "$(json_escape "$TC_MIRRED_ERR")",
  "tc_ifb": $IFB_CREATE,
  "tc_ifb_create": $IFB_CREATE,
  "ifb_supported": $IFB_CREATE,

  "uplink_supported": $UPLINK_SUPPORTED,
  "uplink_police_supported": $UPLINK_POLICE_SUPPORTED,
  "downlink_mode": "$(json_escape "$DOWNLINK_MODE")",
  "uplink_mode": "$(json_escape "$UPLINK_MODE")",
  "delay_mode": "$(json_escape "$DELAY_MODE")"
}
EOF_JSON

mv -f "$TMP" "$OUT" 2>/dev/null || cp -f "$TMP" "$OUT" 2>/dev/null
chmod 644 "$OUT" 2>/dev/null || true

{
    log "tc=$TC_BIN version=$TC_VERSION dummy=$DUMMY_CREATE htb=$TC_HTB tbf=$TC_TBF netem=$TC_NETEM ifb=$IFB_CREATE mirred=$TC_MIRRED police=$TC_POLICE"
    log "modes: downlink=$DOWNLINK_MODE uplink=$UPLINK_MODE delay=$DELAY_MODE iface=$IFACE qdisc=$REAL_QDISC"
} | tee "$RAW" 2>/dev/null

exit 0
