#!/usr/bin/env bash
# 编译测试辅助（userdata）并运行离线测试
#   用法: tests/run.sh [lua 可执行文件] [lua 头文件目录]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
LUA="${1:-lua}"
INC="${2:-/usr/include/lua5.4}"
build="$(mktemp -d)"
gcc -shared -fPIC -I"$INC" -o "$build/mockud.so" "$here/native/mockud.c"
cd "$build"
LUA_CPATH="$build/?.so;;" "$LUA" "$here/mock_test.lua" "$here/../reframework/autorun/DD2_ItemSpawner.lua"
