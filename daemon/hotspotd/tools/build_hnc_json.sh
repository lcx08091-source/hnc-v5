#!/system/bin/sh
# Build helper for the optional hnc_json C read-only helper.
# Default output path is the module runtime location bin/hnc_json_c when the
# script is run from the source tree; pass an explicit output path to override.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../../.." 2>/dev/null && pwd)"
CC="${CC:-clang}"
OUT="${1:-$ROOT/bin/hnc_json_c}"
mkdir -p "$(dirname "$OUT")"
"$CC" -Os -Wall -Wextra -Werror -o "$OUT" "$DIR/hnc_json.c"
chmod 755 "$OUT"
echo "$OUT"
