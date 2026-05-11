#!/system/bin/sh
# hnc_dpid_guard.sh — HNC v5.3.0-rc13
# Purpose:
#   Keep passive DPI capture responsive when Android recreates or briefly downs
#   the hotspot interface.  The hnc_dpid binary is intentionally side-effect
#   free; this guard only controls its lifecycle and writes a waiting state.
#
# Strategy:
#   1. Do not start hnc_dpid while the configured hotspot iface is down.
#   2. Use a fast startup retry window: 0 / 100 / 200 / 500 ms / 1 s / 1.5 s / 2 s.
#   3. Use ip monitor link/address when available to kill/rebind immediately on
#      interface changes; fall back to a low-frequency 3 s check.
#   4. If dpid reports "network is down" while the iface is up, restart it once
#      the short backoff allows the AF_PACKET socket to bind cleanly.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:/data/local/hnc/bin:$PATH

HNC_DIR=${HNC_DIR:-/data/local/hnc}
RUN="$HNC_DIR/run"
LOG_DIR="$HNC_DIR/logs"
LOG="$LOG_DIR/dpid_guard.log"
REAL_BIN="$HNC_DIR/bin/hnc_dpid"
CONFIG="$HNC_DIR/etc/dpi_config.json"
PID_FILE="$RUN/dpid.pid"
CHILD_PID_FILE="$RUN/dpid.child.pid"
MON_PID_FILE="$RUN/dpid.monitor.pid"
EVENT_FILE="$RUN/dpid.netlink.event"
LOCKDIR="$RUN/dpid_guard.lock"
START_TS=$(date +%s 2>/dev/null || echo 0)

mkdir -p "$RUN" "$LOG_DIR" 2>/dev/null || true

log() {
    echo "[$(TZ=Asia/Shanghai date '+%H:%M:%S' 2>/dev/null)] [DPID-GUARD] $*" >> "$LOG" 2>/dev/null || true
}

sleep_s() {
    sleep "$1" 2>/dev/null || sleep 1
}

json_escape() {
    # Small shell-safe JSON string escape for status messages.
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'
}

write_waiting_state() {
    local iface="$1"
    local reason="$2"
    local now up esc_iface esc_reason
    now=$(date +%s 2>/dev/null || echo 0)
    up=$((now - START_TS)); [ "$up" -lt 0 ] && up=0
    esc_iface=$(json_escape "$iface")
    esc_reason=$(json_escape "$reason")
    cat > "$RUN/dpi_state.json.tmp" <<EOF_STATE
{"schema_version":1,"timestamp":$now,"version":"0.1.0-rc1.2-fixed+rc13-guard","mode":"blind","interface":"$esc_iface","uptime_s":$up,"blind_reason":"$esc_reason","stats":{"packets":0,"dns_events":0,"tls_events":0,"kernel_drops":0,"ignored_packets":0,"parse_errors":0}}
EOF_STATE
    mv -f "$RUN/dpi_state.json.tmp" "$RUN/dpi_state.json" 2>/dev/null || true
}

read_json_string_key() {
    local key="$1" file="$2"
    [ -f "$file" ] || return 1
    # Good enough for dpi_config.json's flat string keys.
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -1
}

read_json_bool_key() {
    local key="$1" file="$2"
    [ -f "$file" ] || return 1
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$file" | head -1
}

get_iface() {
    local cfg_iface hint detected
    cfg_iface=$(read_json_string_key iface "$CONFIG" 2>/dev/null)
    if [ -n "$cfg_iface" ]; then
        printf '%s\n' "$cfg_iface"
        return 0
    fi
    hint=$(cat "$RUN/hotspot_iface" 2>/dev/null | head -1)
    if [ -n "$hint" ]; then
        printf '%s\n' "$hint"
        return 0
    fi
    if [ -x "$HNC_DIR/bin/device_detect.sh" ]; then
        detected=$(sh "$HNC_DIR/bin/device_detect.sh" iface 2>/dev/null | head -1)
        if [ -n "$detected" ]; then
            printf '%s\n' "$detected"
            return 0
        fi
    fi
    printf '%s\n' wlan2
}

iface_exists() {
    [ -n "$1" ] && [ -e "/sys/class/net/$1" ]
}

iface_up() {
    local iface="$1" line op
    [ -n "$iface" ] || return 1
    [ -e "/sys/class/net/$iface" ] || return 1
    line=$(ip -o link show "$iface" 2>/dev/null | head -1)
    echo "$line" | grep -q '<[^>]*UP[^>]*>' && return 0
    # Some Android Wi-Fi/AP interfaces report operstate=unknown while IFF_UP is
    # true.  Accept unknown only when the link exists and ip(8) did not say DOWN.
    op=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
    [ "$op" = "up" ] && return 0
    echo "$line" | grep -q 'state UNKNOWN' && ! echo "$line" | grep -q 'state DOWN' && return 0
    return 1
}

kill_child() {
    local child
    child=$(cat "$CHILD_PID_FILE" 2>/dev/null)
    if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
        kill "$child" 2>/dev/null || true
        sleep_s 0.2
        kill -0 "$child" 2>/dev/null && kill -9 "$child" 2>/dev/null || true
    fi
    rm -f "$CHILD_PID_FILE" 2>/dev/null || true
}

cleanup_guard() {
    local mon
    kill_child
    mon=$(cat "$MON_PID_FILE" 2>/dev/null)
    [ -n "$mon" ] && kill "$mon" 2>/dev/null || true
    rm -f "$MON_PID_FILE" "$PID_FILE" "$CHILD_PID_FILE" 2>/dev/null || true
    rm -rf "$LOCKDIR" 2>/dev/null || true
}
trap cleanup_guard EXIT INT TERM

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    old=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        log "another guard already running pid=$old"
        exit 0
    fi
    rm -rf "$LOCKDIR" 2>/dev/null || true
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ > "$PID_FILE"

if [ ! -x "$REAL_BIN" ]; then
    write_waiting_state "" "hnc_dpid binary missing; DPI disabled"
    log "missing binary: $REAL_BIN"
    exit 0
fi

start_monitor() {
    command -v ip >/dev/null 2>&1 || return 0
    ( ip monitor link address 2>/dev/null | while IFS= read -r line; do
          iface=$(get_iface)
          case "$line" in
              *"$iface"*|*wlan*|*ap*|*swlan*|*rndis*|*usb*)
                  date +%s > "$EVENT_FILE" 2>/dev/null || true
                  child=$(cat "$CHILD_PID_FILE" 2>/dev/null)
                  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
                      log "netlink event for iface=$iface, request immediate rebind: $line"
                      kill "$child" 2>/dev/null || true
                  fi
                  ;;
          esac
      done ) &
    echo $! > "$MON_PID_FILE"
    log "netlink monitor started pid=$(cat "$MON_PID_FILE" 2>/dev/null)"
}

start_monitor

# Fast retry offsets after startup or after an interface-loss event.
FAST_DELAYS="0 0.1 0.2 0.5 1 1.5 2"
fast_index=1
last_iface=""
last_event_seen=""

while true; do
    disabled=$(read_json_bool_key disable_capture "$CONFIG" 2>/dev/null)
    iface=$(get_iface)

    if [ "$disabled" = "true" ]; then
        # Let real dpid write the official disabled state.
        log "disable_capture=true; launching real dpid once"
    else
        if ! iface_exists "$iface"; then
            write_waiting_state "$iface" "waiting for hotspot interface $iface to appear; rc13 guard will rebind immediately on netlink event"
            log "iface $iface missing; waiting"
            sleep_s 3
            continue
        fi
        if ! iface_up "$iface"; then
            write_waiting_state "$iface" "waiting for hotspot interface $iface to be UP; rc13 guard fast-retry/netlink rebind active"
            # Startup fast window, then low-frequency fallback.
            delay=$(echo "$FAST_DELAYS" | awk -v i="$fast_index" '{print $i}')
            [ -z "$delay" ] && delay=3
            [ "$fast_index" -lt 7 ] && fast_index=$((fast_index + 1))
            sleep_s "$delay"
            continue
        fi
    fi

    if [ "$iface" != "$last_iface" ]; then
        log "target iface changed: $last_iface -> $iface"
        last_iface="$iface"
    fi
    fast_index=1

    log "launching hnc_dpid on iface=$iface"
    "$REAL_BIN" -config "$CONFIG" >> "$LOG_DIR/dpid.log" 2>&1 &
    child=$!
    echo "$child" > "$CHILD_PID_FILE"

    # Monitor child.  During the first 5 s use a 200 ms cadence to catch the
    # exact wlan up/race window; after that use 3 s to save power.
    child_start=$(date +%s 2>/dev/null || echo 0)
    while kill -0 "$child" 2>/dev/null; do
        now=$(date +%s 2>/dev/null || echo 0)
        age=$((now - child_start))
        cur_iface=$(get_iface)
        ev=$(cat "$EVENT_FILE" 2>/dev/null)
        if [ -n "$ev" ] && [ "$ev" != "$last_event_seen" ]; then
            last_event_seen="$ev"
            log "event file changed; rechecking capture binding"
            kill "$child" 2>/dev/null || true
            break
        fi
        if [ "$cur_iface" != "$iface" ]; then
            log "iface changed while running: $iface -> $cur_iface; rebind"
            kill "$child" 2>/dev/null || true
            break
        fi
        if [ "$disabled" != "true" ] && ! iface_up "$iface"; then
            write_waiting_state "$iface" "hotspot interface $iface went down; rc13 guard is rebinding"
            log "iface $iface down while running; rebind when up"
            kill "$child" 2>/dev/null || true
            break
        fi
        if grep -qi 'network is down' "$RUN/dpi_state.json" 2>/dev/null; then
            # The original rc12 failure: dpid started while AP iface was in the
            # small down/up transition window and stayed blind.  Kill it so the
            # next iteration can bind after IFF_UP is stable.
            log "dpi_state reports network is down; restart capture immediately"
            kill "$child" 2>/dev/null || true
            break
        fi
        if [ "$age" -lt 5 ]; then sleep_s 0.2; else sleep_s 3; fi
    done
    wait "$child" 2>/dev/null || true
    rm -f "$CHILD_PID_FILE" 2>/dev/null || true

    # Small damping: event-driven kills restart immediately after this; genuine
    # repeated failure gets the short backoff first and then the 3 s fallback.
    sleep_s 0.2
    fast_index=1
done
