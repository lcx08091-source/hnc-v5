#!/system/bin/sh
# stats_shadow_diag.sh — hotfix21.3 read-only diagnostics for shadow stats.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
DATA="$HNC_DIR/data"
BIN="$HNC_DIR/bin"
RAW="$DATA/stats_shadow_raw.jsonl"
CONFIG="$DATA/config.json"
MODE=${1:-json}
NOW=$(date +%s 2>/dev/null)
case "$NOW" in ''|*[!0-9]*) NOW=0 ;; esac

file_size() { [ -f "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }
line_count() { [ -f "$1" ] && wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

enabled="false"
reason="disabled_by_default"
case "${HNC_STATS_SHADOW_ENABLE:-}" in
  1|true|TRUE|yes|YES) enabled="true"; reason="env:HNC_STATS_SHADOW_ENABLE" ;;
  0|false|FALSE|no|NO) enabled="false"; reason="env:HNC_STATS_SHADOW_ENABLE" ;;
  *)
    if [ -f "$CONFIG" ] && grep -q '"stats_shadow_enabled"[[:space:]]*:[[:space:]]*true' "$CONFIG" 2>/dev/null; then
      enabled="true"; reason="config:stats_shadow_enabled"
    fi
    ;;
esac

raw_exists=false
[ -f "$RAW" ] && raw_exists=true
raw_lines=$(line_count "$RAW")
raw_size=$(file_size "$RAW")
invalid_lines=0
last_ts=0
unique_devices=0
if [ -f "$RAW" ]; then
  invalid_lines=$(awk '
  BEGIN{bad=0}
  $0 !~ /^\{"schema":1,"ts":[0-9]+,"device_id":"mac:[0-9a-f:]+","mac":"[0-9a-f:]+","rx":[0-9]+,"tx":[0-9]+,"ips":"[0-9.,]*","ip_count":[0-9]+,"source":"iptables"\}$/ {bad++}
  END{print bad+0}' "$RAW" 2>/dev/null)
  last_ts=$(awk 'match($0, /"ts":[0-9]+/) { s=substr($0,RSTART,RLENGTH); sub(/.*:/,"",s); if ((s+0)>last) last=s+0 } END{print last+0}' "$RAW" 2>/dev/null)
  unique_devices=$(sed -nE 's/.*"device_id":"(mac:[0-9a-f:]+)".*/\1/p' "$RAW" 2>/dev/null | sort -u | wc -l | tr -d ' ')
fi

stale_seconds=0
if [ "$NOW" -gt 0 ] && [ "$last_ts" -gt 0 ]; then stale_seconds=$((NOW - last_ts)); fi
status="ok"
[ "$invalid_lines" -gt 0 ] && status="warn"

if [ "$MODE" = "text" ]; then
  cat <<EOF2
HNC stats shadow diagnostics
status=$status
enabled=$enabled
reason=$reason
sample_helper=$BIN/stats_shadow_sample.sh
raw_file=$RAW
raw_exists=$raw_exists
raw_lines=$raw_lines
raw_size_bytes=$raw_size
invalid_lines=$invalid_lines
unique_devices=$unique_devices
last_ts=$last_ts
stale_seconds=$stale_seconds
EOF2
  exit 0
fi

cat <<EOF2
{"ok":true,"status":"$status","enabled":$enabled,"reason":"$reason","sample_helper":"$BIN/stats_shadow_sample.sh","raw_file":"$RAW","raw_exists":$raw_exists,"raw_lines":${raw_lines:-0},"raw_size_bytes":${raw_size:-0},"invalid_lines":${invalid_lines:-0},"unique_devices":${unique_devices:-0},"last_ts":${last_ts:-0},"stale_seconds":${stale_seconds:-0}}
EOF2
exit 0
