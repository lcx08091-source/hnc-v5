#!/system/bin/sh
# HNC v5.3 Smart Queue / SQM manager
# Low-risk controller for fq_codel/CAKE leaf mode. It never rewrites system BPF,
# never replaces the hotspot root qdisc directly, and defaults to off.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
RUN="$HNC_DIR/run"
DATA="$HNC_DIR/data"
LOG="$HNC_DIR/logs/sqm.log"
CAP_FILE="$RUN/capabilities.json"
RULES_FILE="$DATA/rules.json"
SQM_MODE_FILE="$RUN/sqm_mode"
SQM_PROFILE_FILE="$RUN/sqm_profile"
mkdir -p "$RUN" "$DATA" "$(dirname "$LOG")" 2>/dev/null || true

log() { echo "[$(date '+%H:%M:%S')] [SQM] $*" >> "$LOG" 2>/dev/null || true; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'; }

find_tc() {
    for c in "$HNC_DIR/bin/hnc_tc" "$HNC_DIR/bin/tc" /system/bin/tc /vendor/bin/tc /system/xbin/tc; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    command -v tc 2>/dev/null || echo tc
}
TC_BIN=$(find_tc)

json_top_string() {
    local key=$1 file=${2:-$RULES_FILE}
    [ -f "$file" ] || return 1
    tr -d '\n' < "$file" 2>/dev/null \
        | grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
        | head -1 \
        | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

norm_mode() {
    local v
    v=$(printf '%s' "$1" | tr -d '\r\n ' | tr 'A-Z' 'a-z')
    case "$v" in
        off|disable|disabled|0|false|no|"") echo off ;;
        fq|fq-codel|fqcodel|fq_codel|lowlatency|low-latency) echo fq_codel ;;
        cake) echo cake ;;
        game|gaming) echo game ;;
        auto|smart|sqm) echo auto ;;
        *) echo invalid ;;
    esac
}

current_mode() {
    local v
    v=$(cat "$SQM_MODE_FILE" 2>/dev/null | head -1)
    [ -n "$v" ] || v=$(json_top_string sqm_mode 2>/dev/null || echo off)
    norm_mode "$v"
}

cap_bool() {
    local key=$1
    [ -f "$CAP_FILE" ] || { echo unknown; return 0; }
    if grep -Eq '"'"$key"'"[[:space:]]*:[[:space:]]*true' "$CAP_FILE" 2>/dev/null; then echo true; return 0; fi
    if grep -Eq '"'"$key"'"[[:space:]]*:[[:space:]]*false' "$CAP_FILE" 2>/dev/null; then echo false; return 0; fi
    echo unknown
}

cap_string() {
    local key=$1
    [ -f "$CAP_FILE" ] || return 1
    tr -d '\n' < "$CAP_FILE" 2>/dev/null \
        | grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
        | head -1 | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

recommended_mode() {
    local cake fqc rec
    cake=$(cap_bool tc_cake_supported)
    fqc=$(cap_bool tc_fq_codel_supported)
    rec=$(cap_string sqm_recommended_mode 2>/dev/null || echo "")
    [ -n "$rec" ] && [ "$rec" != "off" ] && { echo "$rec"; return 0; }
    [ "$cake" = true ] && { echo cake; return 0; }
    [ "$fqc" = true ] && { echo fq_codel; return 0; }
    echo off
}

mode_available() {
    local mode=$1 cake fqc
    cake=$(cap_bool tc_cake_supported)
    fqc=$(cap_bool tc_fq_codel_supported)
    case "$mode" in
        off) return 0 ;;
        fq_codel|game) [ "$fqc" != false ] ;;
        cake) [ "$cake" != false ] ;;
        auto) [ "$cake" != false ] || [ "$fqc" != false ] ;;
        *) return 1 ;;
    esac
}

write_mode() {
    local mode=$1
    echo "$mode" > "$SQM_MODE_FILE" 2>/dev/null || return 1
    if [ -x "$HNC_DIR/bin/json_set.sh" ]; then
        HNC="$HNC_DIR" sh "$HNC_DIR/bin/json_set.sh" top sqm_mode "$mode" >/dev/null 2>&1 || true
    fi
    log "mode set to $mode"
}

status_json() {
    local iface=${1:-} mode rec cake fqc autorate supported active qdisc tcver profile
    [ -n "$iface" ] || iface=$(cat "$RUN/iface.cache" 2>/dev/null | head -1 | tr -d '\r\n')
    mode=$(current_mode)
    rec=$(recommended_mode)
    cake=$(cap_bool tc_cake_supported)
    fqc=$(cap_bool tc_fq_codel_supported)
    autorate=$(cap_bool tc_cake_autorate_ingress_supported)
    supported=false
    mode_available "$mode" && supported=true
    [ "$mode" = off ] && active=false || active=$supported
    profile=$(cat "$SQM_PROFILE_FILE" 2>/dev/null | head -1 | tr -d '\r\n')
    [ -n "$profile" ] || profile=balanced
    qdisc=""
    if [ -n "$iface" ]; then
        qdisc=$("$TC_BIN" qdisc show dev "$iface" 2>/dev/null | head -8 | tr '\r\n' ' ' | cut -c1-360)
    fi
    cat <<EOF_JSON
{
  "schema": 1,
  "mode": "$(json_escape "$mode")",
  "profile": "$(json_escape "$profile")",
  "recommended_mode": "$(json_escape "$rec")",
  "active": $active,
  "mode_supported": $supported,
  "tc_fq_codel_supported": $fqc,
  "tc_cake_supported": $cake,
  "tc_cake_autorate_ingress_supported": $autorate,
  "iface": "$(json_escape "$iface")",
  "tc_binary": "$(json_escape "$TC_BIN")",
  "qdisc_head": "$(json_escape "$qdisc")"
}
EOF_JSON
}

usage() {
    cat <<EOF_USAGE
Usage: sqm_manager.sh <command> [args]

Commands:
  status [iface]          Print SQM status JSON
  get-mode                Print current mode
  set-mode <mode>         Persist mode: off | fq_codel | cake | auto | game
  set-profile <profile>   Persist profile: balanced | game | bulk | custom
  recommended             Print recommended mode from capabilities.json
  apply [iface]           Safe refresh: run tc_manager.sh restore to rebuild leaves

Notes:
  - Default mode is off; v5.2.1 behavior is preserved.
  - fq_codel/cake only affects delay-free per-device class leaves.
  - Any real netem delay/jitter/loss still forces netem.
EOF_USAGE
}

cmd=${1:-status}
case "$cmd" in
    status)
        status_json "$2" ;;
    get-mode)
        current_mode ;;
    recommended)
        recommended_mode ;;
    set-mode)
        mode=$(norm_mode "$2")
        if [ "$mode" = invalid ]; then
            echo "ERROR: invalid mode '$2'" >&2
            exit 2
        fi
        if ! mode_available "$mode"; then
            echo "WARN: mode '$mode' not confirmed by capabilities; saving anyway for future probe" >&2
        fi
        write_mode "$mode" || exit 1
        status_json ;;
    set-profile)
        profile=$(printf '%s' "$2" | tr -d '\r\n ' | tr 'A-Z' 'a-z')
        case "$profile" in balanced|game|bulk|custom) ;; *) profile=balanced ;; esac
        echo "$profile" > "$SQM_PROFILE_FILE" 2>/dev/null || exit 1
        if [ -x "$HNC_DIR/bin/json_set.sh" ]; then
            HNC="$HNC_DIR" sh "$HNC_DIR/bin/json_set.sh" top sqm_profile "$profile" >/dev/null 2>&1 || true
        fi
        log "profile set to $profile"
        status_json ;;
    apply)
        iface=${2:-$(cat "$RUN/iface.cache" 2>/dev/null | head -1 | tr -d '\r\n')}
        [ -x "$HNC_DIR/bin/tc_manager.sh" ] || { echo "ERROR: tc_manager.sh not found" >&2; exit 1; }
        HNC_DIR="$HNC_DIR" sh "$HNC_DIR/bin/tc_manager.sh" restore >/dev/null 2>&1 || rc=$?
        rc=${rc:-0}
        log "apply requested iface=$iface rc=$rc"
        status_json "$iface"
        exit "$rc" ;;
    -h|--help|help)
        usage ;;
    *)
        usage >&2
        exit 2 ;;
esac
