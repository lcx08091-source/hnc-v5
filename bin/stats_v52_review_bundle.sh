#!/system/bin/sh
# stats_v52_review_bundle.sh — v5.2-rc1.12 scrubbed gray-review bundle exporter.
# Read-only: generates a sanitized bundle that can be sent to Claude/Gemini/GPT.
# It does not enable RC, switch stats source, or touch tc/iptables/watchdog.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
MODDIR=${MODDIR:-/data/adb/modules/hotspot_network_control}
BIN="$HNC_DIR/bin"
RUN="$HNC_DIR/run"
OUT_BASE=${HNC_V52_REVIEW_OUT:-/sdcard/Download}
MODE=${1:-text}
TS="$(date +%s 2>/dev/null || echo 0)"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
OUT_JSON="$RUN/stats_v52_review_bundle.json"
OUT_TXT="$RUN/stats_v52_review_bundle.txt"
OUT_MD="$RUN/stats_v52_review_bundle.md"
HELPER_TIMEOUT=${HNC_HELPER_TIMEOUT:-8}
mkdir -p "$RUN" 2>/dev/null

json_escape() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

redact_stream() {
  sed \
    -e 's/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/<ipv4>/g' \
    -e 's/[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]/<mac>/g' \
    -e 's/"token"[[:space:]]*:[[:space:]]*"[^"]*"/"token":"<redacted>"/g' \
    -e 's/"secret"[[:space:]]*:[[:space:]]*"[^"]*"/"secret":"<redacted>"/g' \
    -e 's/"password"[[:space:]]*:[[:space:]]*"[^"]*"/"password":"<redacted>"/g' \
    -e 's/"auth"[[:space:]]*:[[:space:]]*"[^"]*"/"auth":"<redacted>"/g' \
    -e 's/[A-Za-z0-9._%+-][A-Za-z0-9._%+-]*@[A-Za-z0-9.-][A-Za-z0-9.-]*\.[A-Za-z][A-Za-z]*/<email>/g'
}

run_helper_timeout_raw() {
  h="$1"; mode="$2"; missing_fallback="$3"; timeout_fallback="${4:-$3}"; empty_fallback="${5:-$3}"; limit="${6:-$HELPER_TIMEOUT}"
  if [ ! -f "$BIN/$h" ]; then
    printf '%s' "$missing_fallback"
    return 0
  fi
  tmp="$RUN/.review_${h}_${mode}_$$.out"
  done="$RUN/.review_${h}_${mode}_$$.done"
  rm -f "$tmp" "$done" 2>/dev/null
  ( sh "$BIN/$h" "$mode" >"$tmp" 2>/dev/null; echo $? >"$done" ) &
  pid=$!
  ( sleep "$limit" 2>/dev/null || sleep 8; [ -f "$done" ] || kill "$pid" 2>/dev/null; sleep 1; [ -f "$done" ] || kill -9 "$pid" 2>/dev/null ) &
  watchdog=$!
  wait "$pid" 2>/dev/null
  kill "$watchdog" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    cat "$tmp"
  elif [ -f "$done" ]; then
    printf '%s' "$empty_fallback"
  else
    printf '%s' "$timeout_fallback"
  fi
  rm -f "$tmp" "$done" 2>/dev/null
}

helper_json() {
  h="$1"
  run_helper_timeout_raw "$h" json "{\"ok\":false,\"status\":\"missing\",\"helper\":\"$h\"}" "{\"ok\":false,\"status\":\"timeout\",\"helper\":\"$h\"}" "{\"ok\":false,\"status\":\"empty\",\"helper\":\"$h\"}" | redact_stream
}

helper_text() {
  h="$1"
  run_helper_timeout_raw "$h" text "missing helper: $h\n" "timeout helper: $h\n" "empty helper output: $h\n" | redact_stream
}

helper_markdown() {
  h="$1"
  run_helper_timeout_raw "$h" markdown "# missing helper: $h\n" "# timeout helper: $h\n" "# empty helper output: $h\n" | redact_stream
}

str_key_of() {
  key="$1"; body="$2"; def="$3"
  val="$(printf '%s' "$body" | sed -n 's/.*"'"$key"'":"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$def"
}

bool_key_of() {
  key="$1"; body="$2"
  case "$body" in *\"$key\":true*) echo true ;; *\"$key\":false*) echo false ;; *) echo false ;; esac
}

module_version() {
  mp=""
  [ -f "$MODDIR/module.prop" ] && mp="$MODDIR/module.prop"
  [ -z "$mp" ] && [ -f "$HNC_DIR/module.prop" ] && mp="$HNC_DIR/module.prop"
  if [ -n "$mp" ]; then
    VERSION="$(awk -F= '$1=="version"{print $2; exit}' "$mp" 2>/dev/null)"
    VERSION_CODE="$(awk -F= '$1=="versionCode"{print $2; exit}' "$mp" 2>/dev/null)"
    MODULE_PROP="$mp"
  else
    VERSION="unknown"; VERSION_CODE="unknown"; MODULE_PROP=""
  fi
}

module_version

GRAY_JSON="$(helper_json stats_v52_gray_report.sh)"
SELF_JSON="$(helper_json stats_v52_install_selfcheck.sh)"
WEB_JSON="$(helper_json stats_v52_web_status.sh)"
DEVICE_JSON="$(helper_json stats_v52_device_check.sh)"
SMOKE_JSON="$(helper_json stats_v52_rc_smoke.sh)"
READINESS_JSON="$(helper_json stats_migration_readiness.sh)"
COMPARE_JSON="$(helper_json stats_compare.sh)"
RC1_JSON="$(helper_json stats_v52_rc1_switch.sh)"
HEALTH_JSON="$(helper_json stats_health_summary.sh)"

GRAY_STATUS="$(str_key_of status "$GRAY_JSON" unknown)"
SELF_STATUS="$(str_key_of status "$SELF_JSON" unknown)"
WEB_STATUS="$(str_key_of status "$WEB_JSON" unknown)"
WEB_SEVERITY="$(str_key_of severity "$WEB_JSON" unknown)"
DEVICE_STATUS="$(str_key_of status "$DEVICE_JSON" unknown)"
SMOKE_STATUS="$(str_key_of status "$SMOKE_JSON" unknown)"
READINESS_STATUS="$(str_key_of status "$READINESS_JSON" unknown)"
COMPARE_STATUS="$(str_key_of status "$COMPARE_JSON" unknown)"
RC1_STATUS="$(str_key_of status "$RC1_JSON" unknown)"
HEALTH_STATUS="$(str_key_of status "$HEALTH_JSON" unknown)"

REVIEW_READY="$(bool_key_of review_ready "$GRAY_JSON")"
GRAY_READY="$(bool_key_of gray_ready "$GRAY_JSON")"
LEGACY_DEFAULT_PRESERVED="$(bool_key_of legacy_default_preserved "$RC1_JSON")"
RC1_ENABLED="$(bool_key_of rc1_enabled "$RC1_JSON")"
DEFAULT_SOURCE="$(str_key_of default_source "$RC1_JSON" legacy)"

STATUS=pass
REASON="scrubbed review bundle generated; legacy default preserved"
case "$GRAY_STATUS:$SELF_STATUS:$DEVICE_STATUS:$SMOKE_STATUS" in
  *fail*|*blocked*|*missing*|*unknown*) STATUS=fail; REASON="one or more gray-review inputs are failed/missing/unknown" ;;
  *warn*|*not_ready*|*warmup*|*disabled*) STATUS=warn; REASON="one or more gray-review inputs are warnings or still warming up" ;;
esac
[ "$LEGACY_DEFAULT_PRESERVED" = true ] || { STATUS=fail; REASON="legacy default is not preserved"; }
[ "$DEFAULT_SOURCE" = legacy ] || { STATUS=fail; REASON="default source is not legacy"; }

RECOMMENDATION="send this scrubbed bundle to reviewers; keep legacy stats default during v5.2-rc1.x observation"
[ "$STATUS" = warn ] && RECOMMENDATION="send this bundle for review, but keep legacy default and do not widen gray rollout until warnings are understood"
[ "$STATUS" = fail ] && RECOMMENDATION="do not enable or widen v5.2 stats; keep legacy default and fix failed/missing review inputs first"

cat > "$OUT_TXT" <<TXT
HNC v5.2-rc1.12 scrubbed review bundle status
status=$STATUS
reason=$REASON
recommendation=$RECOMMENDATION
version=$VERSION
versionCode=$VERSION_CODE
module_prop=$MODULE_PROP
review_ready=$REVIEW_READY
gray_ready=$GRAY_READY
legacy_default_preserved=$LEGACY_DEFAULT_PRESERVED
default_source=$DEFAULT_SOURCE
rc1_enabled=$RC1_ENABLED
gray_report_status=$GRAY_STATUS
install_selfcheck_status=$SELF_STATUS
web_status=$WEB_STATUS
web_severity=$WEB_SEVERITY
device_check_status=$DEVICE_STATUS
smoke_status=$SMOKE_STATUS
readiness_status=$READINESS_STATUS
compare_status=$COMPARE_STATUS
rc1_switch_status=$RC1_STATUS
health_summary_status=$HEALTH_STATUS
redaction=enabled
paths.json=$OUT_JSON
paths.text=$OUT_TXT
paths.markdown=$OUT_MD
TXT

cat > "$OUT_MD" <<MD
# HNC v5.2-rc1.12 脱敏灰度审查包

## 结论

- status: **$STATUS**
- reason: $REASON
- recommendation: $RECOMMENDATION

## 版本与默认策略

- version: $VERSION
- versionCode: $VERSION_CODE
- default_source: $DEFAULT_SOURCE
- legacy_default_preserved: $LEGACY_DEFAULT_PRESERVED
- rc1_enabled: $RC1_ENABLED

## 灰度门禁摘要

| 项目 | 状态 |
|---|---|
| gray report | $GRAY_STATUS |
| install selfcheck | $SELF_STATUS |
| WebUI status | $WEB_STATUS / severity=$WEB_SEVERITY |
| device check | $DEVICE_STATUS |
| smoke | $SMOKE_STATUS |
| readiness | $READINESS_STATUS |
| compare | $COMPARE_STATUS |
| rc1 switch | $RC1_STATUS |
| health summary | $HEALTH_STATUS |

## 脱敏说明

本报告会尽量脱敏 IPv4、MAC、邮箱、token、password、secret、auth 等字段。它适合发给 Claude / Gemini / GPT 做交叉审查。完整原始日志仍应只留在本机。

## 给其他 AI 的审查问题

请重点审查：

1. v5.2 stats 灰度是否仍保持 legacy stats 默认。
2. 是否存在 readiness 通过但 device_check/smoke/compare 没有通过的矛盾。
3. 是否应该继续观察，还是可以进入 v5.2-rc2。
4. 是否有任何会误触发 stats RC enable、切换默认 stats source、破坏回滚路径的风险。
5. 报告中是否仍有疑似隐私或敏感字段没有被脱敏。

## gray_report 摘要

\`\`\`text
$(helper_markdown stats_v52_gray_report.sh | head -220)
\`\`\`
MD

cat > "$OUT_JSON" <<JSON
{"ok":true,"status":"$(json_escape "$STATUS")","timestamp":$TS,"version":"$(json_escape "$VERSION")","versionCode":"$(json_escape "$VERSION_CODE")","reason":"$(json_escape "$REASON")","recommendation":"$(json_escape "$RECOMMENDATION")","redaction_enabled":true,"review_ready":$REVIEW_READY,"gray_ready":$GRAY_READY,"legacy_default_preserved":$LEGACY_DEFAULT_PRESERVED,"default_source":"$(json_escape "$DEFAULT_SOURCE")","rc1_enabled":$RC1_ENABLED,"signals":{"gray_report_status":"$(json_escape "$GRAY_STATUS")","install_selfcheck_status":"$(json_escape "$SELF_STATUS")","web_status":"$(json_escape "$WEB_STATUS")","web_severity":"$(json_escape "$WEB_SEVERITY")","device_check_status":"$(json_escape "$DEVICE_STATUS")","smoke_status":"$(json_escape "$SMOKE_STATUS")","readiness_status":"$(json_escape "$READINESS_STATUS")","compare_status":"$(json_escape "$COMPARE_STATUS")","rc1_switch_status":"$(json_escape "$RC1_STATUS")","health_summary_status":"$(json_escape "$HEALTH_STATUS")"},"paths":{"json":"$(json_escape "$OUT_JSON")","text":"$(json_escape "$OUT_TXT")","markdown":"$(json_escape "$OUT_MD")"}}
JSON

make_bundle() {
  BUNDLE_DIR="$OUT_BASE/hnc-v52-rc1.12-review-$STAMP"
  mkdir -p "$BUNDLE_DIR/cmd" "$BUNDLE_DIR/run" 2>/dev/null || return 1
  cp -af "$OUT_TXT" "$BUNDLE_DIR/summary.txt" 2>/dev/null
  cp -af "$OUT_MD" "$BUNDLE_DIR/review.md" 2>/dev/null
  cp -af "$OUT_JSON" "$BUNDLE_DIR/review.json" 2>/dev/null
  helper_json stats_v52_gray_report.sh > "$BUNDLE_DIR/cmd/stats_v52_gray_report.json" 2>/dev/null
  helper_text stats_v52_gray_report.sh > "$BUNDLE_DIR/cmd/stats_v52_gray_report.txt" 2>/dev/null
  helper_json stats_v52_install_selfcheck.sh > "$BUNDLE_DIR/cmd/stats_v52_install_selfcheck.json" 2>/dev/null
  helper_json stats_v52_web_status.sh > "$BUNDLE_DIR/cmd/stats_v52_web_status.json" 2>/dev/null
  helper_json stats_v52_device_check.sh > "$BUNDLE_DIR/cmd/stats_v52_device_check.json" 2>/dev/null
  helper_json stats_v52_rc_smoke.sh > "$BUNDLE_DIR/cmd/stats_v52_rc_smoke.json" 2>/dev/null
  helper_json stats_migration_readiness.sh > "$BUNDLE_DIR/cmd/stats_migration_readiness.json" 2>/dev/null
  helper_json stats_compare.sh > "$BUNDLE_DIR/cmd/stats_compare.json" 2>/dev/null
  helper_json stats_v52_rc1_switch.sh > "$BUNDLE_DIR/cmd/stats_v52_rc1_switch.json" 2>/dev/null
  echo "$BUNDLE_DIR"
}

case "$MODE" in
  json) cat "$OUT_JSON" ;;
  markdown|md) cat "$OUT_MD" ;;
  bundle) make_bundle ;;
  *) cat "$OUT_TXT" ;;
esac
exit 0
