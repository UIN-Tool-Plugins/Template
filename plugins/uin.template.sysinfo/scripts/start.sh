#!/bin/sh
# 启动 C 后端。TPK 解压后可能丢掉可执行位，这里补一次再 exec。
set -e
cd "$(dirname "$0")/.."
chmod +x ./sysinfo_server 2>/dev/null || true
exec ./sysinfo_server
