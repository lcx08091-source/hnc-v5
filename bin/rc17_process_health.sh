#!/system/bin/sh
# rc17_process_health.sh — lightweight HNC process health JSON
# Distinguishes main supervisor instances (PPID=1 or pidfile target) from
# temporary child shells so WebUI does not flag normal guard/watchdog helpers as duplicates.

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:/data/local/hnc/bin:$PATH

HNC_DIR=${HNC_DIR:-/data/local/hnc}
RUN="$HNC_DIR/run"
NOW=$(date +%s 2>/dev/null || echo 0)
PS_OUT="$(ps -ef 2>/dev/null || ps -A 2>/dev/null)"

count_pidof(){ pidof "$1" 2>/dev/null | wc -w | tr -d ' '; }
count_lines(){ printf '%s\n' "$PS_OUT" | grep "$1" | grep -v grep | wc -l | tr -d ' '; }
count_main(){
  pat="$1"
  printf '%s\n' "$PS_OUT" | awk -v p="$pat" '$0 ~ p && $3==1 {c++} END{print c+0}'
}
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g'; }
pid_alive(){ [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

HTTPD=$(count_pidof hnc_httpd)
DPID=$(count_pidof hnc_dpid)
HOTSPOTD=$(count_pidof hotspotd)
WATCHDOG_TOTAL=$(count_lines '[w]atchdog.sh')
WATCHDOG_MAIN=$(count_main '/data/local/hnc/bin/watchdog\.sh')
GUARD_TOTAL=$(count_lines '[h]nc_dpid_guard.sh')
GUARD_MAIN=$(count_main '/data/local/hnc/bin/hnc_dpid_guard\.sh')

HTTPD_PID=$(cat "$RUN/httpd.pid" 2>/dev/null)
DPID_PID=$(cat "$RUN/dpid.pid" 2>/dev/null)
DPID_CHILD_PID=$(cat "$RUN/dpid.child.pid" 2>/dev/null)
GUARD_PID=$(cat "$RUN/dpid_guard.pid" 2>/dev/null)
HOTSPOTD_PID=$(cat "$RUN/hotspotd.pid" 2>/dev/null)
WATCHDOG_PID=$(cat "$RUN/watchdog.pid" 2>/dev/null)

HTTPD_PID_OK=false; pid_alive "$HTTPD_PID" && HTTPD_PID_OK=true
DPID_PID_OK=false; pid_alive "$DPID_PID" && DPID_PID_OK=true
DPID_CHILD_PID_OK=false; pid_alive "$DPID_CHILD_PID" && DPID_CHILD_PID_OK=true
GUARD_PID_OK=false; pid_alive "$GUARD_PID" && GUARD_PID_OK=true
HOTSPOTD_PID_OK=false; pid_alive "$HOTSPOTD_PID" && HOTSPOTD_PID_OK=true
WATCHDOG_PID_OK=false; pid_alive "$WATCHDOG_PID" && WATCHDOG_PID_OK=true

STATUS=ok
DETAIL="主实例正常"
[ "$HTTPD" -ne 1 ] && STATUS=warn && DETAIL="hnc_httpd 数量异常"
[ "$DPID" -ne 1 ] && STATUS=warn && DETAIL="hnc_dpid 数量异常"
[ "$HOTSPOTD" -ne 1 ] && STATUS=warn && DETAIL="hotspotd 数量异常"
[ "$WATCHDOG_MAIN" -gt 1 ] && STATUS=warn && DETAIL="watchdog 主实例重复"
[ "$GUARD_MAIN" -gt 1 ] && STATUS=warn && DETAIL="dpid_guard 主实例重复"
[ "$WATCHDOG_TOTAL" -gt 3 ] && STATUS=warn && DETAIL="watchdog 子进程偏多"
[ "$GUARD_TOTAL" -gt 6 ] && STATUS=warn && DETAIL="dpid_guard 子进程偏多"
[ "$HOTSPOTD_PID_OK" != true ] && STATUS=warn && DETAIL="hotspotd pidfile 不可用"
[ "$GUARD_PID_OK" != true ] && STATUS=warn && DETAIL="dpid_guard pidfile 不可用"
[ "$WATCHDOG_PID_OK" != true ] && STATUS=warn && DETAIL="watchdog pidfile 不可用"

DETAIL_ESC=$(json_escape "$DETAIL")
cat <<EOF_JSON
{"schema_version":1,"timestamp":$NOW,"status":"$STATUS","detail":"$DETAIL_ESC","counts":{"hnc_httpd":$HTTPD,"hnc_dpid":$DPID,"hotspotd":$HOTSPOTD,"watchdog_total":$WATCHDOG_TOTAL,"watchdog_main":$WATCHDOG_MAIN,"dpid_guard_total":$GUARD_TOTAL,"dpid_guard_main":$GUARD_MAIN},"pidfiles":{"httpd":{"pid":"$HTTPD_PID","alive":$HTTPD_PID_OK},"dpid":{"pid":"$DPID_PID","alive":$DPID_PID_OK},"dpid_child":{"pid":"$DPID_CHILD_PID","alive":$DPID_CHILD_PID_OK},"dpid_guard":{"pid":"$GUARD_PID","alive":$GUARD_PID_OK},"hotspotd":{"pid":"$HOTSPOTD_PID","alive":$HOTSPOTD_PID_OK},"watchdog":{"pid":"$WATCHDOG_PID","alive":$WATCHDOG_PID_OK}}}
EOF_JSON
