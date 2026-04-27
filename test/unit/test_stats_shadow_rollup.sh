#!/system/bin/sh
# hotfix21.4 stats shadow rollup tests
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_BASE="$ROOT_DIR/.tmp/test_stats_shadow_rollup.$$"
rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE/data" "$TMP_BASE/run" "$TMP_BASE/logs"

cat > "$TMP_BASE/data/stats_shadow_raw.jsonl" <<'JSON'
{"schema":1,"ts":1000,"date":"2026-04-25","device_id":"mac:aa:bb:cc:dd:ee:01","mac":"aa:bb:cc:dd:ee:01","rx":100,"tx":50,"ips":"192.168.43.10","ip_count":1,"source":"iptables"}
{"schema":1,"ts":2000,"date":"2026-04-26","device_id":"mac:aa:bb:cc:dd:ee:01","mac":"aa:bb:cc:dd:ee:01","rx":160,"tx":90,"ips":"192.168.43.10","ip_count":1,"source":"iptables"}
{"schema":1,"ts":3000,"date":"2026-04-26","device_id":"mac:aa:bb:cc:dd:ee:01","mac":"aa:bb:cc:dd:ee:01","rx":260,"tx":140,"ips":"192.168.43.10","ip_count":1,"source":"iptables"}
{"schema":1,"ts":2100,"date":"2026-04-26","device_id":"mac:aa:bb:cc:dd:ee:02","mac":"aa:bb:cc:dd:ee:02","rx":20,"tx":30,"ips":"192.168.43.11","ip_count":1,"source":"iptables"}
{"schema":1,"ts":3100,"date":"2026-04-26","device_id":"mac:aa:bb:cc:dd:ee:02","mac":"aa:bb:cc:dd:ee:02","rx":80,"tx":55,"ips":"192.168.43.11","ip_count":1,"source":"iptables"}
{"schema":1,"ts":4000,"date":"2026-04-27","device_id":"mac:aa:bb:cc:dd:ee:01","mac":"aa:bb:cc:dd:ee:01","rx":300,"tx":160,"ips":"192.168.43.10","ip_count":1,"source":"iptables"}
JSON

HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 sh "$ROOT_DIR/bin/stats_shadow_rollup.sh" 2026-04-26
[ -f "$TMP_BASE/data/stats_shadow_daily.jsonl" ]

grep -q '"date":"2026-04-26"' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"device_id":"mac:aa:bb:cc:dd:ee:01"' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"rx":160' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"tx":90' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"baseline":"previous_day"' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"device_id":"mac:aa:bb:cc:dd:ee:02"' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"rx":60' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"tx":25' "$TMP_BASE/data/stats_shadow_daily.jsonl"
grep -q '"baseline":"first_sample"' "$TMP_BASE/data/stats_shadow_daily.jsonl"

# Rollup is idempotent: re-running for the same date must replace rows, not duplicate them.
HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 sh "$ROOT_DIR/bin/stats_shadow_rollup.sh" 2026-04-26
count=$(grep -c '"date":"2026-04-26"' "$TMP_BASE/data/stats_shadow_daily.jsonl")
[ "$count" = "2" ]

OUT="$(HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 sh "$ROOT_DIR/bin/stats_shadow_diag.sh" json)"
echo "$OUT" | grep -q '"daily_lines":2'
echo "$OUT" | grep -q '"daily_invalid_lines":0'
echo "$OUT" | grep -q '"daily_unique_devices":2'

rm -rf "$TMP_BASE"
echo "test_stats_shadow_rollup.sh: OK"
