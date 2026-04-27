#!/usr/bin/env sh
set -eu

ROOT="${TMPDIR:-$(pwd)/.tmp}/hnc_stats_health_summary_test.$$"
rm -rf "$ROOT" 2>/dev/null || true
mkdir -p "$ROOT/bin" "$ROOT/run" "$ROOT/data"

cp "$(dirname "$0")/../../bin/stats_health_summary.sh" "$ROOT/bin/stats_health_summary.sh"
chmod 755 "$ROOT/bin/stats_health_summary.sh"

for h in stats_diag.sh stats_identity_diag.sh stats_retention_diag.sh stats_shadow_diag.sh stats_shadow_control.sh stats_compare.sh; do
  cat > "$ROOT/bin/$h" <<'EOF2'
#!/usr/bin/env sh
echo '{"ok":true,"status":"ok"}'
EOF2
  chmod 755 "$ROOT/bin/$h"
done

HNC="$ROOT" HNC_TEST_MODE=1 sh "$ROOT/bin/stats_health_summary.sh" json > "$ROOT/out.ok.json"
grep -q '"status":"ok"' "$ROOT/out.ok.json"
grep -q '"stats_shadow_control":"ok"' "$ROOT/out.ok.json"
grep -q '"stats_compare":"ok"' "$ROOT/out.ok.json"
[ -f "$ROOT/run/stats_health_summary.json" ]
[ -f "$ROOT/run/stats_health_summary.txt" ]
rm -rf "$ROOT" 2>/dev/null || true

echo "PASS stats_health_summary"
