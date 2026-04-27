#!/system/bin/sh
# stats_v52_rc_smoke.sh — HNC hotfix22.1 v5.2 stats RC smoke gate
# Read-only smoke checker for staged v5.2 stats migration.
# It does not enable/disable RC, rewrite stats files, or touch tc/iptables/watchdog.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
BIN="$HNC_DIR/bin"
RUN="$HNC_DIR/run"
MODE=${1:-json}
OUT_JSON="$RUN/stats_v52_rc_smoke.json"
OUT_TXT="$RUN/stats_v52_rc_smoke.txt"
mkdir -p "$RUN" 2>/dev/null

json_escape() { printf '%s' ""; }
helper_json() { h="$1"; if [ -x "$BIN/$h" ]; then sh "$BIN/$h" json 2>/dev/null; else echo '{"ok":false,"status":"missing"}'; fi; }
status_of() { v="$1"; s="$(printf '%s' "$v" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"; [ -n "$s" ] || s="unknown"; echo "$s"; }
bool_of() { key="$1"; v="$2"; b="$(printf '%s' "$v" | sed -n "s/.*\"$key\":\(true\|false\).*/\1/p" | head -1)"; [ -n "$b" ] || b=false; echo "$b"; }
class_of_status() { case "$1" in ok|pass|ready|enabled|legacy|shadow|disabled) echo ok ;; warn|unknown|missing|not_ready|warmup) echo warn ;; fail|bad|error|blocked|enabled_not_ready) echo fail ;; *) echo warn ;; esac; }

RC_JSON="$(helper_json stats_v52_rc_control.sh)"
READINESS_JSON="$(helper_json stats_migration_readiness.sh)"
SHADOW_JSON="$(helper_json stats_shadow_diag.sh)"
COMPARE_JSON="$(helper_json stats_compare.sh)"
SOURCE_JSON="$(helper_json stats_source_diag.sh)"

RC_STATUS="$(status_of "$RC_JSON")"
RC_ENABLED="$(bool_of enabled "$RC_JSON")"
READY_STATUS="$(status_of "$READINESS_JSON")"
READY_BOOL="$(bool_of ready "$READINESS_JSON")"
SHADOW_STATUS="$(status_of "$SHADOW_JSON")"
COMPARE_STATUS="$(status_of "$COMPARE_JSON")"
SOURCE_STATUS="$(status_of "$SOURCE_JSON")"

STATUS="pass"
RECOMMENDATION="v5.2 stats RC smoke check passed; continue monitoring compare/readiness diagnostics"

if [ "$RC_STATUS" = missing ] || [ "$RC_STATUS" = unknown ]; then
  STATUS="fail"
  RECOMMENDATION="stats_v52_rc_control.sh is missing or unreadable; do not use v5.2 RC"
elif [ "$RC_ENABLED" != true ]; then
  STATUS="disabled"
  RECOMMENDATION="v5.2 stats RC is disabled; keep legacy stats active until readiness is ready"
elif [ "$READY_BOOL" != true ] || [ "$READY_STATUS" != ready ]; then
  STATUS="fail"
  RECOMMENDATION="v5.2 stats RC is enabled but readiness is not ready; disable RC and inspect diagnostics"
else
  for s in "$SHADOW_STATUS" "$COMPARE_STATUS" "$SOURCE_STATUS"; do
    c="$(class_of_status "$s")"
    case "$c" in fail) STATUS="fail" ;; warn) [ "$STATUS" = pass ] && STATUS="warn" ;; esac
  done
  if [ "$STATUS" = fail ]; then
    RECOMMENDATION="v5.2 stats RC smoke detected a failing component; disable RC and collect diagnostics"
  elif [ "$STATUS" = warn ]; then
    RECOMMENDATION="v5.2 stats RC smoke has warnings; keep legacy fallback and collect more samples"
  fi
fi

{
  echo "HNC v5.2 stats RC smoke"
  echo "status=$STATUS"
  echo "recommendation=$RECOMMENDATION"
  echo "rc_status=$RC_STATUS"
  echo "rc_enabled=$RC_ENABLED"
  echo "readiness_status=$READY_STATUS"
  echo "readiness_ready=$READY_BOOL"
  echo "shadow_status=$SHADOW_STATUS"
  echo "compare_status=$COMPARE_STATUS"
  echo "source_status=$SOURCE_STATUS"
} > "$OUT_TXT"

printf '{"ok":true,"status":"%s","recommendation":"%s","components":{"v52_rc_control":"%s","rc_enabled":%s,"migration_readiness":"%s","readiness_ready":%s,"stats_shadow":"%s","stats_compare":"%s","stats_source":"%s"},"paths":{"json":"%s","text":"%s"}}\n' \
  "$(json_escape "$STATUS")" "$(json_escape "$RECOMMENDATION")" "$(json_escape "$RC_STATUS")" "$RC_ENABLED" "$(json_escape "$READY_STATUS")" "$READY_BOOL" "$(json_escape "$SHADOW_STATUS")" "$(json_escape "$COMPARE_STATUS")" "$(json_escape "$SOURCE_STATUS")" "$(json_escape "$OUT_JSON")" "$(json_escape "$OUT_TXT")" > "$OUT_JSON"

case "$MODE" in text|status) cat "$OUT_TXT" ;; *) cat "$OUT_JSON" ;; esac
exit 0
