#!/bin/sh
# 交叉编译 hnc_httpd arm64 Android 二进制
# 使用: sh build.sh
# 需要: Go 1.22+ 且 CGO 不依赖(CGO_ENABLED=0)
set -e
cd "$(dirname "$0")"

export GOOS=android
export GOARCH=arm64
export CGO_ENABLED=0

# rc5.1.1 修 X-G2: 从 module.prop 读 version 注入 binary, 消除硬编码
VERSION=$(grep "^version=" ../../module.prop 2>/dev/null | cut -d= -f2)
[ -z "$VERSION" ] && VERSION="dev"

echo "Building hnc_httpd for android/arm64 (version=$VERSION)..."
go build -ldflags="-s -w -X main.version=$VERSION" -o hnc_httpd .

echo "OK: $(ls -la hnc_httpd)"
file hnc_httpd
