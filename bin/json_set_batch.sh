#!/system/bin/sh
# json_set_batch.sh - hotfix18.2 safe batch wrapper
# Correctness-first replacement for the old regex batch writer.
# Usage: sh json_set_batch.sh device <MAC> <field1> <val1> [<field2> <val2> ...]

[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && \
    export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

HNC=${HNC:-/data/local/hnc}
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" = "$0" ] && SCRIPT_DIR="."
JSON_SET=${JSON_SET:-$SCRIPT_DIR/json_set.sh}

[ "$1" = "device" ] || { echo "usage: $0 device <MAC> <k> <v> [<k> <v> ...]" >&2; exit 2; }
shift
MAC=$1; shift
[ -n "$MAC" ] || { echo "missing MAC" >&2; exit 2; }
echo "$MAC" | grep -qiE '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' || { echo "bad MAC: $MAC" >&2; exit 2; }
[ $# -ge 2 ] && [ $(( $# % 2 )) -eq 0 ] || { echo "need k v pairs" >&2; exit 2; }

# Do not acquire json.lock here. json_set.sh owns the unified lock. Taking it
# here would deadlock when json_set.sh tries to take the same mkdir lock.
# hotfix18.2 intentionally trades batch atomicity for JSON correctness; hnc_json
# will later provide atomic multi-field updates safely.
while [ $# -ge 2 ]; do
    K=$1; V=$2; shift 2
    case "$K" in
        ''|*[!A-Za-z0-9_.-]*) echo "bad field: $K" >&2; exit 2 ;;
    esac
    sh "$JSON_SET" device "$MAC" "$K" "$V"
    rc=$?
    [ $rc -eq 0 ] || { echo "json_set_batch: failed field=$K rc=$rc" >&2; exit $rc; }
done
exit 0
