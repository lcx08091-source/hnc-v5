#!/system/bin/sh
# HNC hotfix18.6 JSON health panel backend
# Read-only summary for WebUI/KSU. Does not modify live JSON.

set +e
HNC="${HNC:-/data/local/hnc}"
BIN="$HNC/bin"
RUN="$HNC/run"
DATA="$HNC/data"
BACKUP_DIR="$DATA/.json_backups"
TS="$(date +%s 2>/dev/null || echo 0)"

json_escape() {
  # keep Android ash compatible; enough for short status strings/paths
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\n/ /g; s/\t/ /g'
}

file_ok() {
  f="$1"
  [ -f "$f" ] || { echo missing; return; }
  if [ -x "$BIN/json_guard.sh" ]; then
    sh "$BIN/json_guard.sh" "$f" >/dev/null 2>&1 && echo ok || echo bad
  else
    echo unknown
  fi
}

DOC_RC=127
DOC_MSG="json_doctor.sh missing"
if [ -x "$BIN/json_doctor.sh" ]; then
  DOC_OUT="$(sh "$BIN/json_doctor.sh" status 2>&1)"
  DOC_RC=$?
  DOC_MSG="$DOC_OUT"
fi

OVERALL="ok"
[ "$DOC_RC" = "0" ] || OVERALL="warn"

RULES_STATUS="$(file_ok "$DATA/rules.json")"
NAMES_STATUS="$(file_ok "$DATA/device_names.json")"
TPL_STATUS="$(file_ok "$DATA/templates.json")"
TOK_STATUS="$(file_ok "$DATA/remote_tokens.json")"
DEV_STATUS="$(file_ok "$DATA/devices.json")"

for s in "$RULES_STATUS" "$NAMES_STATUS" "$TPL_STATUS" "$TOK_STATUS" "$DEV_STATUS"; do
  [ "$s" = bad ] && OVERALL="fail"
  [ "$s" = missing ] && [ "$OVERALL" = ok ] && OVERALL="warn"
done

BACKUP_COUNT=0
[ -d "$BACKUP_DIR" ] && BACKUP_COUNT="$(ls "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')"
LATEST_BACKUP=""
[ -d "$BACKUP_DIR" ] && LATEST_BACKUP="$(ls -t "$BACKUP_DIR" 2>/dev/null | head -1)"

LAST_BUNDLE="$(ls -t /sdcard/Download/hnc-json-debug-*.tar.gz 2>/dev/null | head -1)"
HAS_TC_STATE=false
[ -f "$RUN/tc_state.json" ] && HAS_TC_STATE=true
HAS_CAP=false
[ -f "$RUN/capabilities.json" ] && HAS_CAP=true

LEGACY_FALLBACK_COUNT=0
[ -f "$RUN/json_legacy_fallback.count" ] && LEGACY_FALLBACK_COUNT="$(cat "$RUN/json_legacy_fallback.count" 2>/dev/null)"
case "$LEGACY_FALLBACK_COUNT" in *[!0-9]*|"") LEGACY_FALLBACK_COUNT=0 ;; esac
LEGACY_FALLBACK_LAST=""
[ -f "$RUN/json_legacy_fallback.log" ] && LEGACY_FALLBACK_LAST="$(tail -1 "$RUN/json_legacy_fallback.log" 2>/dev/null)"
HAS_LEGACY_FALLBACK_STATUS=false
[ -x "$BIN/json_legacy_fallback_status.sh" ] && HAS_LEGACY_FALLBACK_STATUS=true
[ "$LEGACY_FALLBACK_COUNT" != 0 ] && [ "$OVERALL" = ok ] && OVERALL="warn"

# Refresh json_health files if doctor exists, but status is read-only.
[ -x "$BIN/json_doctor.sh" ] && sh "$BIN/json_doctor.sh" status >/dev/null 2>&1

cat <<JSON
{
  "ok": true,
  "timestamp": $TS,
  "overall": "$(json_escape "$OVERALL")",
  "json_doctor_rc": "$DOC_RC",
  "json_doctor_message": "$(json_escape "$DOC_MSG")",
  "files": {
    "rules.json": "$(json_escape "$RULES_STATUS")",
    "device_names.json": "$(json_escape "$NAMES_STATUS")",
    "templates.json": "$(json_escape "$TPL_STATUS")",
    "remote_tokens.json": "$(json_escape "$TOK_STATUS")",
    "devices.json": "$(json_escape "$DEV_STATUS")"
  },
  "backup_count": $BACKUP_COUNT,
  "latest_backup": "$(json_escape "$LATEST_BACKUP")",
  "last_bundle": "$(json_escape "$LAST_BUNDLE")",
  "has_tc_state": $HAS_TC_STATE,
  "has_capabilities": $HAS_CAP,
  "legacy_fallback": {
    "count": $LEGACY_FALLBACK_COUNT,
    "last": "$(json_escape "$LEGACY_FALLBACK_LAST")",
    "has_status_helper": $HAS_LEGACY_FALLBACK_STATUS,
    "log": "$(json_escape "$RUN/json_legacy_fallback.log")",
    "count_file": "$(json_escape "$RUN/json_legacy_fallback.count")"
  },
  "paths": {
    "json_health_json": "$(json_escape "$RUN/json_health.json")",
    "json_health_txt": "$(json_escape "$RUN/json_health.txt")",
    "backup_dir": "$(json_escape "$BACKUP_DIR")"
  }
}
JSON
