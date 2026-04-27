#!/system/bin/sh
# stats_migration_readiness.sh — HNC hotfix21.9 stats migration readiness gate
# Read-only helper. It does not enable shadow stats, switch WebUI source, or modify stats data.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
DATA="$HNC_DIR/data"
RUN="$HNC_DIR/run"
BIN="$HNC_DIR/bin"
MODE=${1:-json}
OUT_JSON="$RUN/stats_migration_readiness.json"
OUT_TXT="$RUN/stats_migration_readiness.txt"
mkdir -p "$RUN" 2>/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\n/ /g; s/\t/ /g'
}

file_lines() {
  f="$1"
  [ -f "$f" ] || { echo 0; return; }
  wc -l < "$f" 2>/dev/null | tr -d ' ' | sed 's/[^0-9].*$//'
}

file_size() {
  f="$1"
  [ -f "$f" ] || { echo 0; return; }
  wc -c < "$f" 2>/dev/null | tr -d ' ' | sed 's/[^0-9].*$//'
}

status_of() {
  v="$1"
  s="$(printf '%s' "$v" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$s" ] || s="unknown"
  echo "$s"
}

bool_has() { [ -x "$BIN/$1" ] && echo true || echo false; }

helper_json() {
  h="$1"
  if [ -x "$BIN/$h" ]; then
    sh "$BIN/$h" json 2>/dev/null
  else
    echo '{"ok":false,"status":"missing"}'
  fi
}

legacy_raw="$DATA/stats_raw.jsonl"
legacy_daily="$DATA/stats_daily.jsonl"
shadow_raw="$DATA/stats_shadow_raw.jsonl"
shadow_daily="$DATA/stats_shadow_daily.jsonl"
legacy_raw_lines=$(file_lines "$legacy_raw")
legacy_daily_lines=$(file_lines "$legacy_daily")
shadow_raw_lines=$(file_lines "$shadow_raw")
shadow_daily_lines=$(file_lines "$shadow_daily")
legacy_raw_size=$(file_size "$legacy_raw")
legacy_daily_size=$(file_size "$legacy_daily")
shadow_raw_size=$(file_size "$shadow_raw")
shadow_daily_size=$(file_size "$shadow_daily")

shadow_status="$(status_of "$(helper_json stats_shadow_diag.sh)")"
shadow_control_status="$(status_of "$(helper_json stats_shadow_control.sh)")"
source_status="$(status_of "$(helper_json stats_source_diag.sh)")"
compare_status="$(status_of "$(helper_json stats_compare.sh)")"
retention_status="$(status_of "$(helper_json stats_retention_diag.sh)")"
identity_status="$(status_of "$(helper_json stats_identity_diag.sh)")"

has_shadow_diag=$(bool_has stats_shadow_diag.sh)
has_shadow_rollup=$(bool_has stats_shadow_rollup.sh)
has_shadow_control=$(bool_has stats_shadow_control.sh)
has_source_diag=$(bool_has stats_source_diag.sh)
has_compare=$(bool_has stats_compare.sh)
has_retention=$(bool_has stats_retention_diag.sh)
has_identity=$(bool_has stats_identity_diag.sh)

shadow_has_raw=false
shadow_has_daily=false
[ "$shadow_raw_lines" != 0 ] && shadow_has_raw=true
[ "$shadow_daily_lines" != 0 ] && shadow_has_daily=true

READY=false
STATUS="not_ready"
REASON="shadow stats is not ready for default WebUI or v5.2 switch"

case "$shadow_status $shadow_control_status $source_status $compare_status $retention_status $identity_status" in
  *fail*|*bad*|*error*)
    STATUS="blocked"
    REASON="one or more stats diagnostics reported failure"
    ;;
  *)
    if [ "$has_shadow_diag" = true ] && [ "$has_shadow_rollup" = true ] && [ "$has_source_diag" = true ] && [ "$has_compare" = true ] && [ "$shadow_has_raw" = true ] && [ "$shadow_has_daily" = true ]; then
      READY=true
      STATUS="ready"
      REASON="shadow stats has raw/daily data and comparison diagnostics are available"
    elif [ "$shadow_has_raw" = true ] && [ "$shadow_has_daily" = false ]; then
      STATUS="warmup"
      REASON="shadow raw exists but shadow daily rollup has not been produced yet"
    elif [ "$shadow_has_raw" = false ]; then
      STATUS="not_ready"
      REASON="shadow raw data is empty or missing"
    else
      STATUS="not_ready"
      REASON="required shadow stats helpers are missing or incomplete"
    fi
    ;;
esac

if [ "$READY" = true ]; then
  RECOMMENDATION="safe to test optional shadow WebUI source; keep legacy as default until several builds compare cleanly"
else
  RECOMMENDATION="keep legacy stats as default; continue collecting shadow stats and diagnostics"
fi

{
  echo "HNC stats migration readiness"
  echo "status=$STATUS"
  echo "ready=$READY"
  echo "reason=$REASON"
  echo "recommendation=$RECOMMENDATION"
  echo "shadow_status=$shadow_status"
  echo "shadow_control_status=$shadow_control_status"
  echo "source_status=$source_status"
  echo "compare_status=$compare_status"
  echo "retention_status=$retention_status"
  echo "identity_status=$identity_status"
  echo "legacy_raw_lines=$legacy_raw_lines"
  echo "legacy_daily_lines=$legacy_daily_lines"
  echo "shadow_raw_lines=$shadow_raw_lines"
  echo "shadow_daily_lines=$shadow_daily_lines"
  echo "has_shadow_diag=$has_shadow_diag"
  echo "has_shadow_rollup=$has_shadow_rollup"
  echo "has_shadow_control=$has_shadow_control"
  echo "has_source_diag=$has_source_diag"
  echo "has_compare=$has_compare"
} > "$OUT_TXT"

printf '{"ok":true,"status":"%s","ready":%s,"reason":"%s","recommendation":"%s","components":{"shadow":"%s","shadow_control":"%s","source":"%s","compare":"%s","retention":"%s","identity":"%s"},"helpers":{"stats_shadow_diag":%s,"stats_shadow_rollup":%s,"stats_shadow_control":%s,"stats_source_diag":%s,"stats_compare":%s,"stats_retention_diag":%s,"stats_identity_diag":%s},"files":{"legacy_raw":{"path":"%s","lines":%s,"size":%s},"legacy_daily":{"path":"%s","lines":%s,"size":%s},"shadow_raw":{"path":"%s","lines":%s,"size":%s},"shadow_daily":{"path":"%s","lines":%s,"size":%s}},"paths":{"json":"%s","text":"%s"}}\n' \
  "$(json_escape "$STATUS")" "$READY" "$(json_escape "$REASON")" "$(json_escape "$RECOMMENDATION")" \
  "$(json_escape "$shadow_status")" "$(json_escape "$shadow_control_status")" "$(json_escape "$source_status")" "$(json_escape "$compare_status")" "$(json_escape "$retention_status")" "$(json_escape "$identity_status")" \
  "$has_shadow_diag" "$has_shadow_rollup" "$has_shadow_control" "$has_source_diag" "$has_compare" "$has_retention" "$has_identity" \
  "$(json_escape "$legacy_raw")" "$legacy_raw_lines" "$legacy_raw_size" \
  "$(json_escape "$legacy_daily")" "$legacy_daily_lines" "$legacy_daily_size" \
  "$(json_escape "$shadow_raw")" "$shadow_raw_lines" "$shadow_raw_size" \
  "$(json_escape "$shadow_daily")" "$shadow_daily_lines" "$shadow_daily_size" \
  "$(json_escape "$OUT_JSON")" "$(json_escape "$OUT_TXT")" > "$OUT_JSON"

case "$MODE" in
  text|status) cat "$OUT_TXT" ;;
  json|*) cat "$OUT_JSON" ;;
esac
exit 0
