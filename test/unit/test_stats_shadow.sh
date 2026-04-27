#!/system/bin/sh
# hotfix21.4 stats shadow writer + diagnostics smoke tests
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_BASE="$ROOT_DIR/.tmp/test_stats_shadow.$$"
rm -rf "$TMP_BASE"
mkdir -p "$TMP_BASE/data" "$TMP_BASE/run" "$TMP_BASE/logs" "$TMP_BASE/bin"

cat > "$TMP_BASE/data/devices.json" <<'JSON'
{"aa:bb:cc:dd:ee:01":{"ip":"192.168.43.10","mac":"aa:bb:cc:dd:ee:01"},"aa:bb:cc:dd:ee:02":{"ip":"192.168.43.11","mac":"aa:bb:cc:dd:ee:02"}}
JSON

STATS_ALL_CMD='printf "%s\n" "192.168.43.10 100 50" "192.168.43.11 20 30" "192.168.43.99 999 999"' \
  HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 sh "$ROOT_DIR/bin/stats_shadow_sample.sh"

[ -f "$TMP_BASE/data/stats_shadow_raw.jsonl" ]
lines=$(wc -l < "$TMP_BASE/data/stats_shadow_raw.jsonl" | tr -d ' ')
[ "$lines" = "2" ]
grep -q '"date":"' "$TMP_BASE/data/stats_shadow_raw.jsonl"
grep -q '"device_id":"mac:aa:bb:cc:dd:ee:01"' "$TMP_BASE/data/stats_shadow_raw.jsonl"
grep -q '"source":"iptables"' "$TMP_BASE/data/stats_shadow_raw.jsonl"
[ -f "$TMP_BASE/run/stats_shadow_last_date" ]

OUT="$(HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 HNC_STATS_SHADOW_ENABLE=1 sh "$ROOT_DIR/bin/stats_shadow_diag.sh" json)"
echo "$OUT" | grep -q '"enabled":true'
echo "$OUT" | grep -q '"raw_lines":2'
echo "$OUT" | grep -q '"unique_devices":2'
echo "$OUT" | grep -q '"invalid_lines":0'
echo "$OUT" | grep -q '"rollup_helper":'

TXT="$(HNC_DIR="$TMP_BASE" HNC_TEST_MODE=1 sh "$ROOT_DIR/bin/stats_shadow_diag.sh" text)"
echo "$TXT" | grep -q 'HNC stats shadow diagnostics'
echo "$TXT" | grep -q 'rollup_helper='
echo "$TXT" | grep -q 'daily_file='

rm -rf "$TMP_BASE"
echo "test_stats_shadow.sh: OK"
