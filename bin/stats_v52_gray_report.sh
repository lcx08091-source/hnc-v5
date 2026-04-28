#!/system/bin/sh
# stats_v52_gray_report.sh — v5.2-rc1.3 gray observation report exporter.
# Read-only: aggregates v5.2 stats gray-release signals for human review.
# It does not enable RC, switch stats source, or touch tc/iptables/watchdog.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC_DIR=${HNC_DIR:-${HNC:-/data/local/hnc}}
MODDIR=${MODDIR:-/data/adb/modules/hotspot_network_control}
BIN="$HNC_DIR/bin"
RUN="$HNC_DIR/run"
OUT_BASE=${HNC_V52_REPORT_OUT:-/sdcard/Download}
MODE=${1:-text}
TS="$(date +%s 2>/dev/null || echo 0)"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
OUT_JSON="$RUN/stats_v52_gray_report.json"
OUT_TXT="$RUN/stats_v52_gray_report.txt"
OUT_MD="$RUN/stats_v52_gray_report.md"
mkdir -p "$RUN" 2>/dev/null

json_escape() {
  # Android-compatible JSON string escape for one-line diagnostic fields.
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '
}

trim_one_line() { printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'; }

helper_json() {
  h="$1"
  if [ -x "$BIN/$h" ]; then
    sh "$BIN/$h" json 2>/dev/null
  else
    printf '{"ok":false,"status":"missing","helper":"%s"}' "$h"
  fi
}

helper_text() {
  h="$1"
  if [ -x "$BIN/$h" ]; then
    sh "$BIN/$h" text 2>/dev/null
  else
    printf 'missing helper: %s\n' "$h"
  fi
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

mark_level() {
  level="$1"; reason="$2"
  case "$level" in
    fail) FAILS=$((FAILS+1)) ;;
    warn) WARNS=$((WARNS+1)) ;;
    pass) PASSES=$((PASSES+1)) ;;
  esac
  [ -n "$reason" ] || return 0
  if [ -n "$OBSERVATIONS" ]; then OBSERVATIONS="$OBSERVATIONS; $level:$reason"; else OBSERVATIONS="$level:$reason"; fi
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

SELF_JSON="$(helper_json stats_v52_install_selfcheck.sh)"
WEB_JSON="$(helper_json stats_v52_web_status.sh)"
DEVICE_JSON="$(helper_json stats_v52_device_check.sh)"
COMPARE_JSON="$(helper_json stats_compare.sh)"
READINESS_JSON="$(helper_json stats_migration_readiness.sh)"
SMOKE_JSON="$(helper_json stats_v52_rc_smoke.sh)"
RC1_JSON="$(helper_json stats_v52_rc1_switch.sh)"
RC_CONTROL_JSON="$(helper_json stats_v52_rc_control.sh)"
SOURCE_JSON="$(helper_json stats_source_diag.sh)"
SHADOW_JSON="$(helper_json stats_shadow_diag.sh)"
HEALTH_JSON="$(helper_json stats_health_summary.sh)"

SELF_STATUS="$(str_key_of status "$SELF_JSON" unknown)"
WEB_STATUS="$(str_key_of status "$WEB_JSON" unknown)"
WEB_SEVERITY="$(str_key_of severity "$WEB_JSON" unknown)"
DEVICE_STATUS="$(str_key_of status "$DEVICE_JSON" unknown)"
COMPARE_STATUS="$(str_key_of status "$COMPARE_JSON" unknown)"
READINESS_STATUS="$(str_key_of status "$READINESS_JSON" unknown)"
SMOKE_STATUS="$(str_key_of status "$SMOKE_JSON" unknown)"
RC1_STATUS="$(str_key_of status "$RC1_JSON" unknown)"
RC_CONTROL_STATUS="$(str_key_of status "$RC_CONTROL_JSON" unknown)"
SOURCE_STATUS="$(str_key_of status "$SOURCE_JSON" unknown)"
SHADOW_STATUS="$(str_key_of status "$SHADOW_JSON" unknown)"
HEALTH_STATUS="$(str_key_of status "$HEALTH_JSON" unknown)"

SAFE_TO_ENABLE_RC="$(bool_key_of safe_to_enable_rc "$SELF_JSON")"
FIRST_BOOT_SAFE="$(bool_key_of first_boot_safe "$SELF_JSON")"
INSTALL_READY="$(bool_key_of install_ready "$SELF_JSON")"
RC_ENABLE_READY="$(bool_key_of rc_enable_ready "$DEVICE_JSON")"
LEGACY_DEFAULT_PRESERVED="$(bool_key_of legacy_default_preserved "$RC1_JSON")"
RC1_ENABLED="$(bool_key_of rc1_enabled "$RC1_JSON")"
RC_ENABLED="$(bool_key_of rc_enabled "$RC1_JSON")"
DEFAULT_SOURCE="$(str_key_of default_source "$RC1_JSON" legacy)"

FAILS=0
WARNS=0
PASSES=0
OBSERVATIONS=""

case "$SELF_STATUS" in pass) mark_level pass "install selfcheck pass" ;; warn) mark_level warn "install selfcheck warn" ;; fail|blocked|missing|unknown) mark_level fail "install selfcheck $SELF_STATUS" ;; *) mark_level warn "install selfcheck $SELF_STATUS" ;; esac
case "$WEB_SEVERITY" in ok|pass) mark_level pass "web status severity $WEB_SEVERITY" ;; warn) mark_level warn "web status severity warn" ;; fail) mark_level fail "web status severity fail" ;; *) mark_level warn "web status severity $WEB_SEVERITY" ;; esac
case "$DEVICE_STATUS" in pass|ready) mark_level pass "device check $DEVICE_STATUS" ;; warn|warmup|not_ready|disabled) mark_level warn "device check $DEVICE_STATUS" ;; fail|blocked|missing|unknown) mark_level fail "device check $DEVICE_STATUS" ;; *) mark_level warn "device check $DEVICE_STATUS" ;; esac
case "$COMPARE_STATUS" in pass|ok|ready) mark_level pass "stats compare $COMPARE_STATUS" ;; warn|drift|disabled|warmup|not_ready) mark_level warn "stats compare $COMPARE_STATUS" ;; fail|blocked|missing|unknown) mark_level warn "stats compare $COMPARE_STATUS" ;; *) mark_level warn "stats compare $COMPARE_STATUS" ;; esac
case "$READINESS_STATUS" in ready|pass|ok) mark_level pass "readiness $READINESS_STATUS" ;; not_ready|warmup|disabled) mark_level warn "readiness $READINESS_STATUS" ;; blocked|fail|missing|unknown) mark_level fail "readiness $READINESS_STATUS" ;; *) mark_level warn "readiness $READINESS_STATUS" ;; esac
case "$SMOKE_STATUS" in pass|ok) mark_level pass "smoke $SMOKE_STATUS" ;; disabled|warn|warmup) mark_level warn "smoke $SMOKE_STATUS" ;; fail|blocked|missing|unknown) mark_level fail "smoke $SMOKE_STATUS" ;; *) mark_level warn "smoke $SMOKE_STATUS" ;; esac
case "$RC1_STATUS" in pass|ok|disabled|ready) mark_level pass "rc1 switch $RC1_STATUS" ;; warn|not_ready|warmup) mark_level warn "rc1 switch $RC1_STATUS" ;; blocked|drift|fail|missing|unknown) mark_level fail "rc1 switch $RC1_STATUS" ;; *) mark_level warn "rc1 switch $RC1_STATUS" ;; esac

if [ "$DEFAULT_SOURCE" != legacy ]; then mark_level fail "default source is $DEFAULT_SOURCE, expected legacy for rc1.x"; fi
if [ "$LEGACY_DEFAULT_PRESERVED" != true ]; then mark_level fail "legacy_default_preserved is false"; fi

OVERALL="pass"
[ "$WARNS" -gt 0 ] && OVERALL="warn"
[ "$FAILS" -gt 0 ] && OVERALL="fail"

REVIEW_READY=false
GRAY_READY=false
SAFE_ROLLBACK_EXPECTED=true
[ "$FAILS" -eq 0 ] && REVIEW_READY=true
[ "$FAILS" -eq 0 ] && [ "$SAFE_TO_ENABLE_RC" = true ] && [ "$RC_ENABLE_READY" = true ] && GRAY_READY=true

RECOMMENDATION="v5.2-rc1.3 gray observation looks clean; keep legacy default while monitoring shadow stats before any wider rollout"
[ "$OVERALL" = warn ] && RECOMMENDATION="keep legacy default; review warnings and continue gray observation before enabling or widening v5.2 stats"
[ "$OVERALL" = fail ] && RECOMMENDATION="do not enable or widen v5.2 stats; keep legacy default and fix failed gray-check items or rollback"

# Store helper text snapshots for easier human review. These are read-only helper calls.
SELF_TEXT="$(helper_text stats_v52_install_selfcheck.sh | head -80)"
WEB_TEXT="$(helper_text stats_v52_web_status.sh | head -80)"
DEVICE_TEXT="$(helper_text stats_v52_device_check.sh | head -120)"
COMPARE_TEXT="$(helper_text stats_compare.sh | head -120)"
READINESS_TEXT="$(helper_text stats_migration_readiness.sh | head -120)"
SMOKE_TEXT="$(helper_text stats_v52_rc_smoke.sh | head -120)"
RC1_TEXT="$(helper_text stats_v52_rc1_switch.sh | head -100)"

cat > "$OUT_TXT" <<TXT
HNC v5.2-rc1.3 gray observation report
status=$OVERALL
review_ready=$REVIEW_READY
gray_ready=$GRAY_READY
version=$VERSION
versionCode=$VERSION_CODE
module_prop=$MODULE_PROP
legacy_default_preserved=$LEGACY_DEFAULT_PRESERVED
default_source=$DEFAULT_SOURCE
rc1_enabled=$RC1_ENABLED
rc_enabled=$RC_ENABLED
install_ready=$INSTALL_READY
first_boot_safe=$FIRST_BOOT_SAFE
safe_to_enable_rc=$SAFE_TO_ENABLE_RC
rc_enable_ready=$RC_ENABLE_READY
selfcheck_status=$SELF_STATUS
web_status=$WEB_STATUS
web_severity=$WEB_SEVERITY
device_check_status=$DEVICE_STATUS
compare_status=$COMPARE_STATUS
readiness_status=$READINESS_STATUS
smoke_status=$SMOKE_STATUS
rc1_switch_status=$RC1_STATUS
rc_control_status=$RC_CONTROL_STATUS
source_status=$SOURCE_STATUS
shadow_status=$SHADOW_STATUS
health_status=$HEALTH_STATUS
failures=$FAILS
warnings=$WARNS
passes=$PASSES
observations=$OBSERVATIONS
recommendation=$RECOMMENDATION
paths.json=$OUT_JSON
paths.text=$OUT_TXT
paths.markdown=$OUT_MD
TXT

cat > "$OUT_MD" <<MD
# HNC v5.2-rc1.3 灰度观察报告

## 结论

- overall: **$OVERALL**
- review_ready: **$REVIEW_READY**
- gray_ready: **$GRAY_READY**
- recommendation: $RECOMMENDATION

## 版本与默认状态

- version: $VERSION
- versionCode: $VERSION_CODE
- default_source: $DEFAULT_SOURCE
- legacy_default_preserved: $LEGACY_DEFAULT_PRESERVED
- rc1_enabled: $RC1_ENABLED
- rc_enabled: $RC_ENABLED

## 关键门禁

| 项目 | 状态 |
|---|---|
| install selfcheck | $SELF_STATUS |
| WebUI gray status | $WEB_STATUS / severity=$WEB_SEVERITY |
| real-device check | $DEVICE_STATUS |
| stats compare | $COMPARE_STATUS |
| migration readiness | $READINESS_STATUS |
| RC smoke | $SMOKE_STATUS |
| RC1 switch | $RC1_STATUS |
| RC control | $RC_CONTROL_STATUS |
| source diag | $SOURCE_STATUS |
| shadow diag | $SHADOW_STATUS |
| health summary | $HEALTH_STATUS |

## 安全开关

- install_ready: $INSTALL_READY
- first_boot_safe: $FIRST_BOOT_SAFE
- safe_to_enable_rc: $SAFE_TO_ENABLE_RC
- rc_enable_ready: $RC_ENABLE_READY
- safe_rollback_expected: $SAFE_ROLLBACK_EXPECTED

## 观察记录

$OBSERVATIONS

## 原始输出摘要

### install selfcheck

\`\`\`text
$SELF_TEXT
\`\`\`

### WebUI status

\`\`\`text
$WEB_TEXT
\`\`\`

### real-device check

\`\`\`text
$DEVICE_TEXT
\`\`\`

### stats compare

\`\`\`text
$COMPARE_TEXT
\`\`\`

### migration readiness

\`\`\`text
$READINESS_TEXT
\`\`\`

### RC smoke

\`\`\`text
$SMOKE_TEXT
\`\`\`

### RC1 switch

\`\`\`text
$RC1_TEXT
\`\`\`
MD

cat > "$OUT_JSON" <<JSON
{"ok":true,"timestamp":$TS,"status":"$(json_escape "$OVERALL")","review_ready":$REVIEW_READY,"gray_ready":$GRAY_READY,"version":"$(json_escape "$VERSION")","versionCode":"$(json_escape "$VERSION_CODE")","module_prop":"$(json_escape "$MODULE_PROP")","default_source":"$(json_escape "$DEFAULT_SOURCE")","legacy_default_preserved":$LEGACY_DEFAULT_PRESERVED,"rc1_enabled":$RC1_ENABLED,"rc_enabled":$RC_ENABLED,"install_ready":$INSTALL_READY,"first_boot_safe":$FIRST_BOOT_SAFE,"safe_to_enable_rc":$SAFE_TO_ENABLE_RC,"rc_enable_ready":$RC_ENABLE_READY,"safe_rollback_expected":$SAFE_ROLLBACK_EXPECTED,"statuses":{"selfcheck":"$(json_escape "$SELF_STATUS")","web_status":"$(json_escape "$WEB_STATUS")","web_severity":"$(json_escape "$WEB_SEVERITY")","device_check":"$(json_escape "$DEVICE_STATUS")","compare":"$(json_escape "$COMPARE_STATUS")","readiness":"$(json_escape "$READINESS_STATUS")","smoke":"$(json_escape "$SMOKE_STATUS")","rc1_switch":"$(json_escape "$RC1_STATUS")","rc_control":"$(json_escape "$RC_CONTROL_STATUS")","source":"$(json_escape "$SOURCE_STATUS")","shadow":"$(json_escape "$SHADOW_STATUS")","health":"$(json_escape "$HEALTH_STATUS")"},"failures":$FAILS,"warnings":$WARNS,"passes":$PASSES,"observations":"$(json_escape "$OBSERVATIONS")","recommendation":"$(json_escape "$RECOMMENDATION")","paths":{"json":"$(json_escape "$OUT_JSON")","text":"$(json_escape "$OUT_TXT")","markdown":"$(json_escape "$OUT_MD")"}}
JSON

make_bundle() {
  OUT_DIR="$OUT_BASE/hnc-v52-gray-report-$STAMP"
  mkdir -p "$OUT_DIR" 2>/dev/null || return 1
  cp -af "$OUT_JSON" "$OUT_TXT" "$OUT_MD" "$OUT_DIR/" 2>/dev/null
  for f in stats_v52_install_selfcheck stats_v52_web_status stats_v52_device_check stats_compare stats_migration_readiness stats_v52_rc_smoke stats_v52_rc1_switch stats_v52_rc_control stats_source_diag stats_shadow_diag stats_health_summary; do
    [ -f "$RUN/$f.json" ] && cp -af "$RUN/$f.json" "$OUT_DIR/" 2>/dev/null
    [ -f "$RUN/$f.txt" ] && cp -af "$RUN/$f.txt" "$OUT_DIR/" 2>/dev/null
  done
  if command -v tar >/dev/null 2>&1; then
    (cd "$OUT_BASE" 2>/dev/null && tar -czf "hnc-v52-gray-report-$STAMP.tar.gz" "hnc-v52-gray-report-$STAMP" 2>/dev/null)
    [ -f "$OUT_BASE/hnc-v52-gray-report-$STAMP.tar.gz" ] && echo "$OUT_BASE/hnc-v52-gray-report-$STAMP.tar.gz" > "$RUN/stats_v52_gray_report_bundle.path"
  fi
  echo "$OUT_DIR"
}

case "$MODE" in
  json) cat "$OUT_JSON" ;;
  markdown|md) cat "$OUT_MD" ;;
  bundle) make_bundle ;;
  *) cat "$OUT_TXT" ;;
esac
exit 0
