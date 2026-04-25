#!/system/bin/sh

# v3.5.0 alpha-0: PATH 健壮性,见 service.sh
[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH
# json_set.sh — 纯 Shell JSON 字段更新工具，不依赖 python3
#
# 用法:
#   json_set.sh device  <mac> <field> <value>   # 更新 .devices[mac][field]
#   json_set.sh bl_add  <mac>                   # 加入 blacklist
#   json_set.sh bl_del  <mac>                   # 从 blacklist 删除
#   json_set.sh reset                           # 清空 devices 和 blacklist
#
# 原理：用 awk 直接做文本替换，适用于我们固定格式的 rules.json
# rules.json 格式固定可预测，不需要通用 JSON 解析器

HNC=${HNC:-/data/local/hnc}
RULES=$HNC/data/rules.json
TMP=$HNC/data/rules.tmp

# ═══════════════════════════════════════════════════════════════
# v3.4.11 P0-2 修复:加 mkdir 文件锁,防并发写竞态
#
# 之前的问题:
#   - 所有写命令(top/device/bl_add/bl_del/reset/cfg_set/name_*)都用
#     `awk ... > "$TMP" && mv "$TMP" "$RULES"`,共用同一个 $TMP
#   - 两个并发 shell 同时写 → 第二个 mv 用半写完的临时文件覆盖 → JSON 破损
#   - shUpdate 串行 5 次 kexec 写 5 个字段,user 快速点击两次"应用"或
#     setTimeout(doRefresh, 100) 跟 user 点击交错 → 触发竞态
#
# 修复:用 mkdir 原子操作做锁(POSIX 标准,所有 ash/busybox 都支持),
# 5 秒超时(50 × 100ms)。trap 退出时自动释放。
# ═══════════════════════════════════════════════════════════════
LOCKDIR=$HNC/run/json.lock
mkdir -p $HNC/run 2>/dev/null

# v3.4.11 内部加固:sleep 0.1 在 busybox ash 不一定支持小数,
# 改用 usleep(支持微秒,busybox 大部分版本有)。usleep 也失败则 fall back
# 到 sleep 1(慢 10 倍但能用)。同时加陈旧锁检测:
# 如果锁目录存在超过 10 秒(可能是上次崩溃没释放),强制清掉再重试。
_short_sleep() {
    usleep 100000 2>/dev/null && return 0
    sleep 1
}

# v3.5.1 P0-4 修复:之前 force_break 在 2 秒后无条件 rmdir 锁目录,
# 不检查持锁进程是否还活着 → 大文件 awk 慢的时候,持锁进程 A 还在工作,
# 进程 B 强拆锁进入,A 和 B 同时 mv 到 .tmp,JSON 损坏。
#
# 修复:锁目录里写持锁 PID,force_break 之前先 kill -0 检查存活,
# 只有持锁进程已死才强拆。

acquire_lock() {
    local i=0
    local force_break=20  # 第 20 次重试时(=2 秒)考虑强拆陈旧锁
    while [ $i -lt 50 ]; do
        if mkdir "$LOCKDIR" 2>/dev/null; then
            # 成功获取锁,写自己 PID
            echo $$ > "$LOCKDIR/pid" 2>/dev/null
            # rc3.1.34 修 #3: 之前 trap 第一句 `rmdir "$LOCKDIR/pid"` 是死代码 ——
            # pid 是 echo 写的普通文件不是目录, rmdir 永远 fail 但被 2>/dev/null 吞掉.
            # 教训 #8 反模式本身. 移除死代码, 只留正确的 rm + rmdir.
            trap 'rm -f "$LOCKDIR/pid" 2>/dev/null; rmdir "$LOCKDIR" 2>/dev/null' EXIT INT TERM
            return 0
        fi
        # 第 20 次重试时检查是否真的陈旧
        if [ $i -eq $force_break ]; then
            local lock_pid
            lock_pid=$(cat "$LOCKDIR/pid" 2>/dev/null)
            if [ -z "$lock_pid" ]; then
                # 锁目录存在但没 PID 文件 — 可能是上一版残留或刚 mkdir 还没 echo
                # 给一次机会再等一轮,而不是立刻拆
                _short_sleep
                i=$((i+1))
                continue
            fi
            if kill -0 "$lock_pid" 2>/dev/null; then
                # 持锁进程还活着,不拆,继续等
                echo "json_set: lock held by alive PID $lock_pid, waiting" >&2
            else
                # 持锁进程已死,安全强拆
                echo "json_set: force-break stale lock (dead PID $lock_pid)" >&2
                rm -f "$LOCKDIR/pid" 2>/dev/null
                rmdir "$LOCKDIR" 2>/dev/null
            fi
        fi
        _short_sleep
        i=$((i+1))
    done
    return 1
}
release_lock() {
    rm -f "$LOCKDIR/pid" 2>/dev/null
    rmdir "$LOCKDIR" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# v3.3.0 新增：统一的 JSON 值编码函数
# 规则：
#   - true / false / null → 原样（JSON 字面量）
#   - 严格数字（整数或浮点，可带负号）→ 原样
#   - 其他一律当字符串 → 加 JSON 双引号
#
# 关键修复：原实现 `*[!0-9.-]*` 允许 "192.168.1.5" 当数字，
# 导致 IP 写入 JSON 时不带引号，破坏 JSON 格式。
# ═══════════════════════════════════════════════════════════════
json_encode() {
    local v=$1
    case "$v" in
        true|false|null)
            echo "$v" ;;
        '')
            echo '""' ;;
        *)
            # 严格数字匹配：可选负号 + 整数 + 可选小数部分
            if echo "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
                echo "$v"
            else
                # 转义内嵌的双引号和反斜杠，避免破坏 JSON
                local esc
                esc=$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')
                echo "\"$esc\""
            fi
            ;;
    esac
}

# 确保目录和文件存在
mkdir -p $HNC/data
[ -f $RULES ] || cat > $RULES << 'EOF'
{"version":1,"whitelist_mode":false,"devices":{},"blacklist":[],"whitelist":[]}
EOF

# v3.4.6: device_names.json 路径与初始化
NAMES_FILE=$HNC/data/device_names.json
ensure_names_file() {
    [ -f "$NAMES_FILE" ] || echo '{}' > "$NAMES_FILE"
}

CMD=$1

# v3.4.11 P0-2: 写命令统一加锁,读命令不加锁(避免阻塞 cfg_get / name_get)
# 注意:device_patch 不在此列表 — 它内部递归调 `sh "$0" device`,
# device 命令本身会 acquire_lock,加在外层会自己跟自己抢锁导致 5 秒超时回归
case "$CMD" in
    top|device|bl_add|bl_del|reset|cfg_set|name_set|name_del|tpl_set|tpl_del|token_revoke|token_revoke_all|token_prune)
        acquire_lock || { echo "json_set: lock timeout (5s)" >&2; exit 2; }
        ;;
esac

# ── 原子写入：先写临时文件，再 mv ──────────────────────────
atomic_write() {
    mv "$TMP" "$RULES"
}

case "$CMD" in

# ── 更新顶层字段（hotspot_auto / whitelist_mode 等）────────
# v3.3.0 修复：
#   1) 原 awk 正则 `($0 ~ """ field """)` 被 shell+awk 解析为字面量 " field "，
#      根本不引用 field 变量，匹配永远失败
#   2) 原字符串分支 JVAL=""$VALUE"" 经 shell 合并后等于 $VALUE，JSON 里写出裸串
#   3) 原实现只替换已存在字段；若字段不存在则无效。现补上“插入”分支
top)
    FIELD=$2; VALUE=$3
    JVAL=$(json_encode "$VALUE")

    if grep -q "\"$FIELD\"[[:space:]]*:" "$RULES" 2>/dev/null; then
        # 字段已存在：精确替换该字段的值
        # 关键：单行 JSON 不能用 line-sub，否则会替换到文件里第一个字段
        awk -v field="$FIELD" -v val="$JVAL" '
        {
            pat="\"" field "\"[[:space:]]*:[[:space:]]*[^,}]*"
            rep="\"" field "\": " val
            gsub(pat, rep)
            print
        }' "$RULES" > "$TMP" && atomic_write
    else
        # 字段不存在：在首层对象的 "{" 之后插入
        awk -v field="$FIELD" -v val="$JVAL" '
        BEGIN { depth=0; inserted=0 }
        {
            if (!inserted) {
                n=split($0,chars,"")
                for(i=1;i<=n;i++){
                    if(chars[i]=="{") {
                        depth++
                        if(depth==1) {
                            # 在这一行的 "{" 后插入新字段
                            pre=substr($0,1,i)
                            post=substr($0,i+1)
                            # 若 "{" 后紧接 "}"（空对象），新字段不需要逗号
                            if (post ~ /^[[:space:]]*\}/) {
                                $0 = pre "\"" field "\": " val post
                            } else {
                                $0 = pre "\"" field "\": " val "," post
                            }
                            inserted=1
                            break
                        }
                    }
                }
            }
            print
        }' "$RULES" > "$TMP" && atomic_write
    fi
    ;;

# ── 更新设备字段 ──────────────────────────────────────────
device)
    MAC=$2; FIELD=$3; VALUE=$4
    JVAL=$(json_encode "$VALUE")

    # 检查 devices 里有没有这个 MAC 的条目
    if grep -q "\"$MAC\"[[:space:]]*:[[:space:]]*{" "$RULES" 2>/dev/null; then
        # MAC 存在：尝试更新或插入字段
        # v3.3.0：改用 match/substr 按 MAC 块精确定位，支持单行/多行 JSON
        if grep -oE "\"$MAC\"[[:space:]]*:[[:space:]]*\{[^}]*\"$FIELD\"[[:space:]]*:" "$RULES" >/dev/null 2>&1; then
            # 字段存在：在 MAC 块内替换
            awk -v mac="$MAC" -v field="$FIELD" -v val="$JVAL" '
            {
                line=$0
                mac_pat="\"" mac "\"[[:space:]]*:[[:space:]]*\\{[^}]*\\}"
                if (match(line, mac_pat)) {
                    block=substr(line, RSTART, RLENGTH)
                    rest =substr(line, RSTART+RLENGTH)
                    pre  =substr(line, 1, RSTART-1)
                    fpat ="\"" field "\"[[:space:]]*:[[:space:]]*[^,}]*"
                    frep ="\"" field "\": " val
                    gsub(fpat, frep, block)
                    print pre block rest
                } else {
                    print line
                }
            }' "$RULES" > "$TMP" && atomic_write
        else
            # 字段不存在：在 MAC 块的 "{" 后插入新字段
            awk -v mac="$MAC" -v field="$FIELD" -v val="$JVAL" '
            {
                line=$0
                mac_pat="\"" mac "\"[[:space:]]*:[[:space:]]*\\{"
                if (match(line, mac_pat)) {
                    brace_end=RSTART+RLENGTH
                    pre =substr(line, 1, brace_end-1)
                    post=substr(line, brace_end)
                    if (post ~ /^[[:space:]]*\}/) {
                        line = pre "\"" field "\": " val post
                    } else {
                        line = pre "\"" field "\": " val "," post
                    }
                }
                print line
            }' "$RULES" > "$TMP" && atomic_write
        fi
    else
        # MAC 不存在：在 "devices": { 后插入新条目
        awk -v mac="$MAC" -v field="$FIELD" -v val="$JVAL" '
        {
            line=$0
            if (match(line, /"devices"[[:space:]]*:[[:space:]]*\{/)) {
                brace_end=RSTART+RLENGTH
                pre =substr(line, 1, brace_end-1)
                post=substr(line, brace_end)
                new_entry="\"" mac "\": {\"" field "\": " val "}"
                if (post ~ /^[[:space:]]*\}/) {
                    # 空 devices 对象
                    line = pre new_entry post
                } else {
                    line = pre new_entry "," post
                }
            }
            print line
        }' "$RULES" > "$TMP" && atomic_write
    fi
    ;;

# ── 批量更新设备多个字段（从 stdin 读 JSON patch）─────────
device_patch)
    MAC=$2
    # 从第3个参数起读取 key=value 对
    shift 2
    TMPJSON="{}"
    while [ $# -ge 2 ]; do
        K=$1; V=$2; shift 2
        JVAL=$(json_encode "$V")
        TMPJSON=$(echo "$TMPJSON" | sed "s/}$/,\"$K\":$JVAL}/")
        # 修复开头的 {, → {
        TMPJSON=$(echo "$TMPJSON" | sed 's/^{,/{/')
    done
    # 逐字段调用 device 更新
    echo "$TMPJSON" | tr ',' '\n' | grep ':' | while IFS=: read -r k v; do
        k=$(echo $k | tr -d '" {}')
        v=$(echo $v | tr -d ' {}')
        sh "$0" device "$MAC" "$k" "$v"
    done
    ;;

# ── 加入黑名单 ────────────────────────────────────────────
# v3.3.0 修复：
#   原实现 gsub(/\]/, ...) 会替换文件中所有的 ]，单行 JSON 下
#   把 whitelist 和 blacklist 一起污染了。改用 match+substr 精确
#   定位 "blacklist":[...] 范围。
bl_add)
    MAC=$2
    # 已在黑名单则不重复添加
    grep -oE "\"blacklist\"[[:space:]]*:[[:space:]]*\[[^]]*\"$MAC\"" "$RULES" >/dev/null 2>&1 && exit 0

    awk -v mac="$MAC" '
    {
        line=$0
        pat="\"blacklist\"[[:space:]]*:[[:space:]]*\\[[^]]*\\]"
        if (match(line, pat)) {
            block=substr(line, RSTART, RLENGTH)
            pre  =substr(line, 1, RSTART-1)
            rest =substr(line, RSTART+RLENGTH)
            # 空数组：[]  → ["mac"]
            if (block ~ /\[[[:space:]]*\]$/) {
                sub(/\[[[:space:]]*\]$/, "[\"" mac "\"]", block)
            } else {
                # 非空：在末尾 ] 前追加 ,"mac"
                sub(/\]$/, ",\"" mac "\"]", block)
            }
            line = pre block rest
        }
        print line
    }' "$RULES" > "$TMP" && atomic_write
    ;;

# ── 从黑名单删除 ──────────────────────────────────────────
# v3.3.0 修复：原 gsub 不加范围限制，会把 devices 块里同 MAC 的键也删掉
bl_del)
    MAC=$2
    awk -v mac="$MAC" '
    {
        line=$0
        pat="\"blacklist\"[[:space:]]*:[[:space:]]*\\[[^]]*\\]"
        if (match(line, pat)) {
            block=substr(line, RSTART, RLENGTH)
            pre  =substr(line, 1, RSTART-1)
            rest =substr(line, RSTART+RLENGTH)
            # 删除 "mac", 或 ,"mac" 或独立 "mac"
            gsub("\"" mac "\",", "", block)
            gsub(",\"" mac "\"", "", block)
            gsub("\"" mac "\"", "", block)
            line = pre block rest
        }
        print line
    }' "$RULES" > "$TMP" && atomic_write
    ;;

# ── 清空所有规则 ──────────────────────────────────────────
reset)
    cat > "$RULES" << 'EOF'
{"version":1,"whitelist_mode":false,"devices":{},"blacklist":[],"whitelist":[]}
EOF
    ;;

# ── 初始化目录结构 ────────────────────────────────────────
init_dirs)
    mkdir -p "$HNC/bin" "$HNC/api" "$HNC/webroot" "$HNC/data" "$HNC/logs" "$HNC/run"
    chmod 755 "$HNC" "$HNC/bin" "$HNC/api" "$HNC/webroot" "$HNC/data" "$HNC/logs" "$HNC/run"
    [ -f "$RULES" ] || cat > "$RULES" << 'EOF'
{"version":1,"whitelist_mode":false,"devices":{},"blacklist":[],"whitelist":[]}
EOF
    chmod 644 "$RULES"
    echo "HNC dirs initialized"
    ;;

# ── 写入 config.json 字段 ────────────────────────────────────
# rc3.1.13.2 弃用警告 (review §6 P1):
#   config.json 自 rc3.1.13 弃用, 字段全部迁移到 rules.json (用 'top' 子命令).
#   middleware 不读 config.json, 写入将被忽略. 保留命令是为了不破坏未审到的
#   调用方, 但每次调用 stderr 留痕 + boot.log 会反复出现 WARN, 让回归立即可见.
#   rc3.1.14 后若 boot.log 无此 WARN 累积则可考虑彻底删除.
cfg_set)
    KEY=$2; VAL=$3
    echo "json_set.sh: WARN: cfg_set is DEPRECATED since rc3.1.13, writes to config.json are IGNORED by middleware. Use 'top' subcommand instead. (key=$KEY caller=$(ps -o comm= -p $PPID 2>/dev/null || echo unknown))" >&2
    CFG=$HNC/data/config.json
    [ -f "$CFG" ] || echo '{}' > "$CFG"
    JVAL=$(json_encode "$VAL")
    if grep -q "\"$KEY\"" "$CFG" 2>/dev/null; then
        sed -i "s|\"$KEY\"[[:space:]]*:[[:space:]]*[^,}]*|\"$KEY\": $JVAL|g" "$CFG"
    else
        sed -i "s|}$|,\"$KEY\": $JVAL}|" "$CFG"
    fi
    echo "ok"
    ;;

# ── 读取 config.json 字段 ────────────────────────────────────
# v3.3.0 修复：原 sed 's/.*: *//' 是贪婪匹配，对 "22:00" 这种
# 含冒号的值会把 "22:" 也当分隔符吃掉，返回 "00"。
# 改用只匹配到第一个冒号的版本。
cfg_get)
    KEY=$2
    CFG=$HNC/data/config.json
    grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CFG" 2>/dev/null \
        | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//' && exit 0
    grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*[^,}[:space:]]*" "$CFG" 2>/dev/null \
        | head -1 | sed 's/^[^:]*:[[:space:]]*//'
    ;;

# ── 读取 rules.json 顶层字段（v3.3.0 新增）──────────────────
top_get)
    KEY=$2
    # 先尝试字符串字段（带引号），取引号内的完整内容
    result=$(grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$RULES" 2>/dev/null \
        | head -1 | sed 's/^[^:]*:[[:space:]]*"//; s/"$//')
    if [ -n "$result" ]; then
        echo "$result"
    else
        # 数字/布尔字段
        grep -o "\"$KEY\"[[:space:]]*:[[:space:]]*[^,}[:space:]]*" "$RULES" 2>/dev/null \
            | head -1 | sed 's/^[^:]*:[[:space:]]*//'
    fi
    ;;

# ═══════════════════════════════════════════════════════════════
# v4.1.0-rc3 新增: 读取 .devices[<mac>][<key>]
# 用法: json_set.sh device_get <mac> <key>
# 用途: Go 端 actionDelaySet/Clear 需要读 per-device 的 mark_id
# 旧 bug: 之前 Go 调 top_get mark_id 读顶层是错的, mark_id 是 per-device
# ═══════════════════════════════════════════════════════════════
device_get)
    MAC=$2
    KEY=$3
    [ -z "$MAC" ] && { echo "device_get: mac required" >&2; exit 1; }
    [ -z "$KEY" ] && { echo "device_get: key required" >&2; exit 1; }
    # awk 扫整个文件, 找 "<mac>":{ ... "<key>": <value> ... }
    awk -v m="$MAC" -v k="$KEY" '
    BEGIN { RS="" }
    {
        # 在整个文件内容里找 "<mac>"
        idx = index($0, "\"" m "\"")
        if (idx == 0) next
        tail = substr($0, idx)
        # 在 tail 里找 "<key>":<value>
        pat = "\"" k "\"[[:space:]]*:[[:space:]]*"
        if (match(tail, pat)) {
            rest = substr(tail, RSTART + RLENGTH)
            # 字符串值
            if (match(rest, /^"[^"]*"/)) {
                print substr(rest, RSTART + 1, RLENGTH - 2)
                exit 0
            }
            # 数字/布尔值 (到逗号/空白/} 为止)
            if (match(rest, /^[^,}[:space:]]+/)) {
                print substr(rest, RSTART, RLENGTH)
                exit 0
            }
        }
    }
    ' "$RULES" 2>/dev/null
    ;;

# ═══════════════════════════════════════════════════════════════
# v3.4.6: 设备手动命名 (data/device_names.json)
# ═══════════════════════════════════════════════════════════════
# 文件格式（单行 JSON,扁平 MAC -> name 映射）:
#   {"e2:0d:4a:48:5d:40":"Mi-10","aa:bb:cc:dd:ee:ff":"客厅打印机"}
#
# 子命令:
#   name_set  <mac> <name>   设置或更新设备名
#   name_get  <mac>          获取设备名(找不到则空)
#   name_del  <mac>          删除条目
#   name_list                打印整个文件(供调试)
#
# 这是 v3.4.6 设备命名功能的"路线 A":手动命名,优先级最高,
# 永远凌驾于 mDNS 自动发现 / DHCP lease / MAC 兜底之上。
# ═══════════════════════════════════════════════════════════════

name_set)
    MAC=$2; NAME=$3
    [ -z "$MAC" ] && { echo "name_set: mac required" >&2; exit 1; }
    [ -z "$NAME" ] && { echo "name_set: name required" >&2; exit 1; }
    ensure_names_file

    # 转小写 mac
    MAC=$(echo "$MAC" | tr 'A-Z' 'a-z')

    # JSON 编码 name(转义反斜杠和双引号 + 去控制字符)
    # v3.4.11 P0-5/P0-6 修复:
    #   1) tr -d 去掉控制字符,跟 device_detect.sh 一致
    #   2) 不用 awk -v(避免 awk 二次解析反斜杠把 JSON escape 撤销)
    # v3.5.0 alpha-2 修复:
    #   原 v3.4.11 用 `getline pair < "/dev/stdin"; close("/dev/stdin")`,
    #   在某些 awk 实现(mawk / 老 gawk / busybox awk)上 close("/dev/stdin")
    #   会段错误。改用临时文件传 NEW_PAIR,awk 用 getline 从文件读,
    #   兼容所有 awk 实现。
    NAME_ESC=$(printf '%s' "$NAME" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')
    NEW_PAIR="\"$MAC\":\"$NAME_ESC\""
    PAIR_TMP="${NAMES_FILE}.pair.$$"
    printf '%s' "$NEW_PAIR" > "$PAIR_TMP"

    # 用 awk 替换或插入,通过文件传 NEW_PAIR(awk 不会二次解析文件内容)
    # rc3.1.34 修 #33: 之前 match() 只替换 first hit 的 entry. 如果 device_names.json
    # 因为外部手动编辑 / 旧版 bug 留下了同 mac 多个 entry, 替换后仍有残留 →
    # hnc_lookup_manual_name (C 端) 取 first hit 不一定是新版 → 显示混乱.
    # 修法: while + match 循环把所有同 mac entry 全删, 然后插入新 pair (相当于
    # "去重 + 写入" 两步合并). 注意: pat 不能是 pair 字符串本身, 否则 pair 里
    # 的 mac 字面会被匹掉 — 用 mac key 模式 (跟原来一致).
    awk -v mac="$MAC" -v pairfile="$PAIR_TMP" '
    BEGIN { getline pair < pairfile }
    {
        # 1. 删掉所有同 mac 的旧 entry (包括前置 `,`)
        pat = "\"" mac "\":\"[^\"]*\""
        while (match($0, pat)) {
            # 计算包括前置/后置逗号的删除范围, 避免留 `,,` 或 `{,xxx`
            lhs = substr($0, 1, RSTART-1)
            rhs = substr($0, RSTART + RLENGTH)
            # 末尾 `,` 优先 (后续还有 entry 时), 否则前置 `,` (它是末位 entry)
            if (substr(rhs, 1, 1) == ",") {
                rhs = substr(rhs, 2)
            } else if (substr(lhs, length(lhs), 1) == ",") {
                lhs = substr(lhs, 1, length(lhs)-1)
            }
            $0 = lhs rhs
        }
        # 2. 插入新 entry
        if ($0 ~ /^\{\}[[:space:]]*$/) {
            $0 = "{" pair "}"
        } else if ($0 ~ /^\{[[:space:]]*\}[[:space:]]*$/) {
            # 容错: `{ }` (含空白)
            $0 = "{" pair "}"
        } else {
            # 非空对象 -> 在末尾 } 前插入 ,"mac":"name"
            sub(/\}[[:space:]]*$/, "," pair "}", $0)
        }
        print
    }
    ' "$NAMES_FILE" > "${NAMES_FILE}.tmp" && mv "${NAMES_FILE}.tmp" "$NAMES_FILE"
    rm -f "$PAIR_TMP"
    ;;

name_get)
    MAC=$2
    [ -z "$MAC" ] && exit 0
    [ -f "$NAMES_FILE" ] || exit 0
    MAC=$(echo "$MAC" | tr 'A-Z' 'a-z')
    # 提取 "mac":"name" 中的 name
    grep -o "\"$MAC\":\"[^\"]*\"" "$NAMES_FILE" 2>/dev/null \
        | head -1 \
        | sed "s/^\"$MAC\":\"//; s/\"$//"
    ;;

name_del)
    MAC=$2
    [ -z "$MAC" ] && exit 0
    [ -f "$NAMES_FILE" ] || exit 0
    MAC=$(echo "$MAC" | tr 'A-Z' 'a-z')

    awk -v mac="$MAC" '
    {
        pat = "\"" mac "\":\"[^\"]*\""
        # 删除条目以及前后的逗号(如果有)
        # 三种位置:中间 (前后都有逗号)、开头 (后跟逗号)、末尾 (前面有逗号)
        gsub(",?" pat ",?", ",", $0)
        # 清理可能产生的 ,, -> ,
        gsub(/,,/, ",", $0)
        # 清理可能产生的 {, -> {
        gsub(/\{,/, "{", $0)
        # 清理可能产生的 ,} -> }
        gsub(/,\}/, "}", $0)
        print
    }
    ' "$NAMES_FILE" > "${NAMES_FILE}.tmp" && mv "${NAMES_FILE}.tmp" "$NAMES_FILE"
    ;;

name_list)
    ensure_names_file
    cat "$NAMES_FILE"
    ;;

# ═══════════════════════════════════════════════════════════════
# 限速/延迟模板 (data/templates.json)
# ═══════════════════════════════════════════════════════════════
# 文件格式（单行 JSON,name -> 字段对象映射）:
#   {"游戏":{"down_mbps":50,"up_mbps":20,"delay_ms":0,"jitter_ms":0,"loss_pct":0},
#    "办公":{"down_mbps":10,"up_mbps":5,"delay_ms":0,"jitter_ms":0,"loss_pct":0}}
#
# 子命令:
#   tpl_set  <name> <down_mbps> <up_mbps> <delay_ms> <jitter_ms> <loss_pct>
#     整体设置一个模板(新建或覆盖)。数字参数必须是非负整数或浮点。
#   tpl_del  <name>
#     删除一个模板。不存在则 no-op。
#   tpl_list
#     输出整个 templates.json(供 WebUI 读取)。
#
# 设计选择:
#   - 独立文件,不污染 rules.json(rules 已经承载 11+ 字段,再加 templates 会膨胀)
#   - 和 device_names.json 同级,同样"扁平 name -> value"的映射结构
#   - value 是对象而非字符串,awk 操作参考 device 命令的嵌套对象模式
# ═══════════════════════════════════════════════════════════════

tpl_set)
    NAME=$2
    DOWN=${3:-0}; UP=${4:-0}; DELAY=${5:-0}; JITTER=${6:-0}; LOSS=${7:-0}
    [ -z "$NAME" ] && { echo "tpl_set: name required" >&2; exit 1; }

    # 数字参数白名单:非负整数或浮点
    # 挡住 NaN / Infinity / 字母 / shell 特殊字符等奇怪输入被拼进 JSON
    for _val in "$DOWN" "$UP" "$DELAY" "$JITTER" "$LOSS"; do
        case "$_val" in
            ''|*[!0-9.]*|.*|*..*)
                echo "tpl_set: invalid number: $_val" >&2
                exit 1 ;;
        esac
    done

    TPL_FILE=$HNC/data/templates.json
    [ -f "$TPL_FILE" ] || echo '{}' > "$TPL_FILE"

    # 转义 name: 去控制字符 + 转义 \ 和 "
    # (允许中文/空格/emoji,UTF-8 字节原样通过)
    NAME_ESC=$(printf '%s' "$NAME" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')
    ENTRY="\"$NAME_ESC\":{\"down_mbps\":$DOWN,\"up_mbps\":$UP,\"delay_ms\":$DELAY,\"jitter_ms\":$JITTER,\"loss_pct\":$LOSS}"

    # 通过文件传 ENTRY 给 awk,避免 awk -v 二次解析反斜杠撤销 JSON 转义
    # (同 name_set v3.5.0 修复的模式)
    PAIR_TMP="${TPL_FILE}.pair.$$"
    printf '%s' "$ENTRY" > "$PAIR_TMP"

    awk -v name="$NAME_ESC" -v pairfile="$PAIR_TMP" '
    BEGIN { getline pair < pairfile }
    {
        # "name":{...} 条目级匹配。[^}]* 保证不跨条目,
        # 因为每个模板对象内部只含 primitive 字段,不再嵌套 {}。
        pat = "\"" name "\"[[:space:]]*:[[:space:]]*\\{[^}]*\\}"
        if (match($0, pat)) {
            # 模板已存在,整体替换
            $0 = substr($0, 1, RSTART-1) pair substr($0, RSTART+RLENGTH)
        } else {
            # 插入新条目
            if ($0 ~ /^\{[[:space:]]*\}[[:space:]]*$/) {
                $0 = "{" pair "}"
            } else {
                sub(/\}[[:space:]]*$/, "," pair "}", $0)
            }
        }
        print
    }
    ' "$TPL_FILE" > "${TPL_FILE}.tmp" && mv "${TPL_FILE}.tmp" "$TPL_FILE"
    rm -f "$PAIR_TMP"
    ;;

tpl_del)
    NAME=$2
    [ -z "$NAME" ] && exit 0
    TPL_FILE=$HNC/data/templates.json
    [ -f "$TPL_FILE" ] || exit 0

    NAME_ESC=$(printf '%s' "$NAME" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')

    awk -v name="$NAME_ESC" '
    {
        pat = "\"" name "\"[[:space:]]*:[[:space:]]*\\{[^}]*\\}"
        gsub(",?" pat ",?", ",", $0)
        gsub(/,,/, ",", $0)
        gsub(/\{,/, "{", $0)
        gsub(/,\}/, "}", $0)
        print
    }
    ' "$TPL_FILE" > "${TPL_FILE}.tmp" && mv "${TPL_FILE}.tmp" "$TPL_FILE"
    ;;

tpl_list)
    TPL_FILE=$HNC/data/templates.json
    if [ -f "$TPL_FILE" ]; then
        cat "$TPL_FILE"
    else
        echo '{}'
    fi
    ;;

# ═══ v4.0 Patch 2.a: token 管理命令 ═══════════════════════════════
# tokens.json 是 Map by TokenID:
#   {"version":1,"tokens":{"<TokenID>":{"hash":"...","created":...,
#     "last_seen":...,"label":"...","ip_hint":"...","revoked":false}}}
# 文件权限 600(敏感数据)。写入用 tmp+mv 原子,配合 acquire_lock 保证并发安全。
# 与 httpd 协同: httpd 每次 auth 前 stat tokens.json,mtime 变就 reload。

token_revoke)
    # 用法: token_revoke <TokenID>
    # 把指定 TokenID 的 revoked 设为 true。TokenID 不存在时静默(幂等)。
    TID=$2
    if [ -z "$TID" ]; then
        echo "Usage: json_set.sh token_revoke <TokenID>" >&2
        exit 1
    fi
    # TokenID 严格 base64url [A-Za-z0-9_-],防注入
    case "$TID" in
        *[!A-Za-z0-9_-]*|"")
            echo "token_revoke: invalid TokenID format" >&2
            exit 1
            ;;
    esac
    TOKENS_FILE=$HNC/data/remote_tokens.json
    TOKENS_TMP=$HNC/data/remote_tokens.tmp
    [ -f "$TOKENS_FILE" ] || echo '{"version":1,"tokens":{}}' > "$TOKENS_FILE"

    # 策略: 用 awk 状态机进入 "TokenID":{ 对象后改 revoked:false -> true
    # POSIX awk(busybox/toybox 通用), 不用 gawk match(,,arr)
    awk -v tid="$TID" '
    BEGIN { in_target = 0; depth = 0 }
    {
        line = $0
        if (in_target) {
            # 统计本行大括号深度变化
            brace_delta = 0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "{") brace_delta++
                else if (c == "}") brace_delta--
            }
            sub(/"revoked"[ \t]*:[ \t]*false/, "\"revoked\": true", line)
            depth += brace_delta
            if (depth <= 0) in_target = 0
        } else {
            pat = "\"" tid "\"[ \t]*:[ \t]*\\{"
            if (match(line, pat)) {
                in_target = 1
                depth = 0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1)
                    if (c == "{") depth++
                    else if (c == "}") depth--
                }
                if (depth <= 0) in_target = 0
                sub(/"revoked"[ \t]*:[ \t]*false/, "\"revoked\": true", line)
            }
        }
        print line
    }
    ' "$TOKENS_FILE" > "$TOKENS_TMP" && mv "$TOKENS_TMP" "$TOKENS_FILE"
    chmod 600 "$TOKENS_FILE" 2>/dev/null
    ;;

token_revoke_all)
    # 所有 tokens[*].revoked 从 false 改 true
    TOKENS_FILE=$HNC/data/remote_tokens.json
    TOKENS_TMP=$HNC/data/remote_tokens.tmp
    [ -f "$TOKENS_FILE" ] || echo '{"version":1,"tokens":{}}' > "$TOKENS_FILE"
    awk '
    { sub(/"revoked"[ \t]*:[ \t]*false/, "\"revoked\": true"); print }
    ' "$TOKENS_FILE" > "$TOKENS_TMP" && mv "$TOKENS_TMP" "$TOKENS_FILE"
    chmod 600 "$TOKENS_FILE" 2>/dev/null
    ;;

token_prune)
    # 维护命令:移除 last_seen > 90 天 + revoked=true 且 last_seen > 30 天 的条目
    # json_set.sh 的 shell awk 实现 token_prune 过于脆弱(多行 JSON + busybox/toybox
    # 语法差异),改为 touch marker,让 httpd daily GC goroutine 用 Go json 库做。
    PRUNE_REQ="$HNC/run/httpd_prune_request"
    mkdir -p "$HNC/run" 2>/dev/null
    touch "$PRUNE_REQ" 2>/dev/null
    echo "token_prune requested (httpd GC will execute on next cycle)"
    ;;

*)
    echo "Usage: json_set.sh {device|bl_add|bl_del|reset|init_dirs|cfg_set|cfg_get|top|top_get|name_set|name_get|name_del|name_list|tpl_set|tpl_del|tpl_list|token_revoke|token_revoke_all|token_prune} [args...]"
    exit 1
    ;;
esac
