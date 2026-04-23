#!/system/bin/sh
# json_set_batch.sh - rc5.1.1 UX 优化
# 一次 awk 更新 rules.json 内某 MAC 设备的多个字段 (省 200-300ms vs 多次 json_set.sh)
# 用法: sh json_set_batch.sh device <MAC> <field1> <val1> [<field2> <val2> ...]
[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && \
    export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC=${HNC:-/data/local/hnc}
RULES=$HNC/data/rules.json
TMP=$HNC/data/rules.tmp.batch.$$
LOCK=$HNC/run/json_set.lock

[ "$1" != "device" ] && { echo "usage: $0 device <MAC> <k> <v> [<k> <v> ...]" >&2; exit 2; }
shift
MAC=$1; shift
[ -z "$MAC" ] && { echo "missing MAC" >&2; exit 2; }
[ $# -lt 2 ] || [ $(($# % 2)) -ne 0 ] && { echo "need k v pairs" >&2; exit 2; }

# 用 mkdir 锁, 跟 json_set.sh 一致
mkdir -p "$(dirname "$LOCK")" 2>/dev/null
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
    i=$((i+1))
    [ $i -gt 50 ] && { echo "lock timeout" >&2; exit 3; }
    sleep 0.05
done
trap 'rmdir "$LOCK" 2>/dev/null; rm -f "$TMP" 2>/dev/null' EXIT INT TERM

# 把 k v k v ... 拼成 "k1\tv1\nk2\tv2\n..." 传给 awk
KVS=""
while [ $# -ge 2 ]; do
    K=$1; V=$2; shift 2
    # JSON 编码: 数字/布尔不加引号, 其他加引号
    case "$V" in
        true|false) JV="$V" ;;
        ''|*[!0-9.-]*) JV="\"$V\"" ;;   # 含非数字字符: 字符串
        *) JV="$V" ;;                    # 纯数字
    esac
    # 用 ASCII 0x1F 当字段分隔符避免冲突
    KVS="${KVS}${K}$(printf '\037')${JV}$(printf '\036')"
done

# 单 awk 批量更新
awk -v mac="$MAC" -v kvs="$KVS" '
BEGIN {
    FS = "\037"; RS_KV = "\036"
    n = split(kvs, items, "\036")
    nk = 0
    for (i=1; i<=n; i++) {
        if (items[i] == "") continue
        m = split(items[i], parts, "\037")
        if (m < 2) continue
        kvkeys[++nk] = parts[1]
        kvvals[parts[1]] = parts[2]
    }
}
{
    line = $0
    # MAC 块: "xx:xx:..." : { ... }
    mac_pat = "\"" mac "\"[[:space:]]*:[[:space:]]*\\{[^}]*\\}"
    if (match(line, mac_pat)) {
        block = substr(line, RSTART, RLENGTH)
        pre   = substr(line, 1, RSTART-1)
        rest  = substr(line, RSTART+RLENGTH)
        for (i=1; i<=nk; i++) {
            k = kvkeys[i]; v = kvvals[k]
            fpat = "\"" k "\"[[:space:]]*:[[:space:]]*[^,}]*"
            frep = "\"" k "\": " v
            if (match(block, fpat)) {
                # 字段已存在: 替换
                bpre = substr(block, 1, RSTART-1)
                bpost = substr(block, RSTART+RLENGTH)
                block = bpre frep bpost
            } else {
                # 字段不存在: 在闭合 } 前插入
                # 找最后一个 }
                close_pos = match(block, /\}[[:space:]]*$/)
                if (close_pos > 0) {
                    block = substr(block, 1, close_pos-1) ", " frep substr(block, close_pos)
                }
            }
        }
        line = pre block rest
    }
    print line
}' "$RULES" > "$TMP" || { echo "awk failed" >&2; exit 4; }

# 简单完整性校验: 至少应该是 { ... } 结构
[ ! -s "$TMP" ] && { echo "tmp empty" >&2; exit 5; }
head -c1 "$TMP" | grep -q '{' || { echo "tmp not json" >&2; exit 6; }

mv "$TMP" "$RULES" && exit 0
exit 7
