#!/system/bin/sh
# stats_shadow_rollup.sh — HNC hotfix21.4 shadow stats daily rollup
#
# This is part of the v5.2 stats migration shadow path. It only reads/writes
# shadow stats files and never replaces the legacy stats pipeline.
#
# Usage:
#   sh stats_shadow_rollup.sh YYYY-MM-DD
#
# Output:
#   data/stats_shadow_daily.jsonl

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
DATA="$HNC_DIR/data"
RUN="$HNC_DIR/run"
LOG="$HNC_DIR/logs/stats.log"
RAW="$DATA/stats_shadow_raw.jsonl"
DAILY="$DATA/stats_shadow_daily.jsonl"
TARGET_DATE="$1"

log() {
  [ -d "$(dirname "$LOG")" ] || mkdir -p "$(dirname "$LOG")" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STATS_SHADOW_ROLLUP] $*" >> "$LOG" 2>/dev/null || true
}

case "$TARGET_DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "usage: $0 YYYY-MM-DD" >&2; exit 2 ;;
esac

mkdir -p "$DATA" "$RUN" 2>/dev/null
[ -f "$RAW" ] || { log "raw missing, skip target=$TARGET_DATE"; exit 0; }

TMP_ROLL="$RUN/stats_shadow_rollup.$$"
TMP_DAILY="$RUN/stats_shadow_daily.$$"
trap 'rm -f "$TMP_ROLL" "$TMP_DAILY" 2>/dev/null' EXIT INT TERM

now=$(date +%s 2>/dev/null)
case "$now" in ''|*[!0-9]*) now=0 ;; esac

awk -v target="$TARGET_DATE" -v now="$now" '
function str_field(line, key,    pat, val) {
  pat = "\"" key "\":\"[^\"]*\""
  if (match(line, pat)) {
    val = substr(line, RSTART, RLENGTH)
    sub("^\"" key "\":\"", "", val)
    sub("\"$", "", val)
    return val
  }
  return ""
}
function num_field(line, key,    pat, val) {
  pat = "\"" key "\":[0-9]+"
  if (match(line, pat)) {
    val = substr(line, RSTART, RLENGTH)
    sub(".*:", "", val)
    return val + 0
  }
  return -1
}
function endpoint(id, mac, rxv, txv, tsv) {
  if (id == "") return
  if (last_seen[id] == "" || tsv >= last_seen[id]) {
    last_seen[id] = tsv; last_rx[id] = rxv; last_tx[id] = txv; last_mac[id] = mac
  }
}
function baseline(id, mac, rxv, txv, tsv) {
  if (id == "") return
  if (base_seen[id] == "" || tsv >= base_seen[id]) {
    base_seen[id] = tsv; base_rx[id] = rxv; base_tx[id] = txv; base_mac[id] = mac
  }
}
function firstsample(id, mac, rxv, txv, tsv) {
  if (id == "") return
  if (first_seen[id] == "" || tsv < first_seen[id]) {
    first_seen[id] = tsv; first_rx[id] = rxv; first_tx[id] = txv; first_mac[id] = mac
  }
}
{
  datev = str_field($0, "date")
  # hotfix21.3 rows have no date. Leave them for diagnostics instead of trying
  # non-portable epoch conversion on Android/toybox.
  if (datev == "") next
  id = str_field($0, "device_id")
  mac = str_field($0, "mac")
  rxv = num_field($0, "rx")
  txv = num_field($0, "tx")
  tsv = num_field($0, "ts")
  if (id == "" || mac == "" || rxv < 0 || txv < 0 || tsv < 0) next
  if (datev < target) baseline(id, mac, rxv, txv, tsv)
  else if (datev == target) { firstsample(id, mac, rxv, txv, tsv); endpoint(id, mac, rxv, txv, tsv); samples[id]++ }
}
END {
  for (id in last_seen) {
    if (base_seen[id] != "") { brx = base_rx[id]; btx = base_tx[id]; btype = "previous_day" }
    else { brx = first_rx[id]; btx = first_tx[id]; btype = "first_sample" }
    drx = last_rx[id] - brx
    dtx = last_tx[id] - btx
    if (drx < 0) { drx = last_rx[id]; btype = btype "+counter_reset" }
    if (dtx < 0) { dtx = last_tx[id]; btype = btype "+counter_reset" }
    printf "{\"schema\":1,\"date\":\"%s\",\"device_id\":\"%s\",\"mac\":\"%s\",\"rx\":%d,\"tx\":%d,\"samples\":%d,\"baseline\":\"%s\",\"source\":\"shadow_rollup\",\"updated_ts\":%d}\n", target, id, last_mac[id], drx, dtx, samples[id], btype, now
  }
}' "$RAW" > "$TMP_ROLL"

# Idempotent replacement: keep rows for other dates, then append target rows.
if [ -f "$DAILY" ]; then
  awk -v target="$TARGET_DATE" '$0 !~ ("\"date\":\"" target "\"") { print }' "$DAILY" > "$TMP_DAILY"
else
  : > "$TMP_DAILY"
fi

[ -s "$TMP_ROLL" ] && cat "$TMP_ROLL" >> "$TMP_DAILY"
mv -f "$TMP_DAILY" "$DAILY"
rows=$(wc -l < "$TMP_ROLL" 2>/dev/null | tr -d ' ')
log "rolled target=$TARGET_DATE rows=${rows:-0}"
exit 0
