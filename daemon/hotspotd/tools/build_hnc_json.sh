#!/system/bin/sh
# Build helper for hnc_json C prototype. Optional; CI/device packaging can wire
# this in after validation.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-clang}"
OUT="${1:-$DIR/hnc_json_c}"
"$CC" -Os -Wall -Wextra -o "$OUT" "$DIR/hnc_json.c"
chmod 755 "$OUT"
echo "$OUT"
