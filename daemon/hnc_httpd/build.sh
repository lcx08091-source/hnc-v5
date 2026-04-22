#!/bin/sh
# 交叉编译 hnc_httpd arm64 Android 二进制
# 使用: sh build.sh
# 需要: Go 1.22+ 且 CGO 不依赖(CGO_ENABLED=0)
set -e
cd "$(dirname "$0")"

export GOOS=android
export GOARCH=arm64
export CGO_ENABLED=0

echo "Building hnc_httpd for android/arm64..."
go build -ldflags="-s -w" -o hnc_httpd .

echo "OK: $(ls -la hnc_httpd)"
file hnc_httpd
