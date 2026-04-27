#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$ROOT/.tmp/test_stats_v52_rc_smoke"
rm -rf "$TMP"
mkdir -p "$TMP/bin" "$TMP/run"
cp "$ROOT/bin/stats_v52_rc_smoke.sh" "$TMP/bin/"
chmod 755 "$TMP/bin/stats_v52_rc_smoke.sh"
export HNC_TEST_MODE=1
export HNC="$TMP"
export HNC_DIR="$TMP"

mkhelper() {
  name="$1"; body="$2"
  {
    echo '#!/usr/bin/env sh'
    echo "$body"
  } > "$TMP/bin/$name"
  chmod 755 "$TMP/bin/$name"
}

out="$(sh "$TMP/bin/stats_v52_rc_smoke.sh" json)"
echo "$out" | grep '"status":"fail"' >/dev/null

mkhelper stats_v52_rc_control.sh 'echo "{\"ok\":true,\"status\":\"disabled\",\"enabled\":false}"'
mkhelper stats_migration_readiness.sh 'echo "{\"ok\":true,\"status\":\"ready\",\"ready\":true}"'
out="$(sh "$TMP/bin/stats_v52_rc_smoke.sh" json)"
echo "$out" | grep '"status":"disabled"' >/dev/null

mkhelper stats_v52_rc_control.sh 'echo "{\"ok\":true,\"status\":\"enabled\",\"enabled\":true}"'
mkhelper stats_shadow_diag.sh 'echo "{\"ok\":true,\"status\":\"ok\"}"'
mkhelper stats_compare.sh 'echo "{\"ok\":true,\"status\":\"ok\"}"'
mkhelper stats_source_diag.sh 'echo "{\"ok\":true,\"status\":\"legacy\"}"'
out="$(sh "$TMP/bin/stats_v52_rc_smoke.sh" json)"
echo "$out" | grep '"status":"pass"' >/dev/null

mkhelper stats_compare.sh 'echo "{\"ok\":true,\"status\":\"fail\"}"'
out="$(sh "$TMP/bin/stats_v52_rc_smoke.sh" json)"
echo "$out" | grep '"status":"fail"' >/dev/null

echo "[OK] stats_v52_rc_smoke"
