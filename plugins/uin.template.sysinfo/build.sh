#!/bin/bash
# build.sh - 编译 C 源码为二进制程序
# 用法: build.sh <plugin_dir> <output.tpk>
set -e

PLUGIN_DIR=$(cd "$1" && pwd)
OUTPUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
PLUGIN_ID=$(basename "$PLUGIN_DIR")

echo "  🔨 Compiling C source..."

# 编译 C → 二进制
SRC_FILE="$PLUGIN_DIR/src/sysinfo_server.c"
if [ ! -f "$SRC_FILE" ]; then
  echo "❌ $PLUGIN_ID: src/sysinfo_server.c not found"
  exit 1
fi

gcc -O2 -o "$PLUGIN_DIR/sysinfo_server" "$SRC_FILE" -lm
echo "  ✅ Compiled sysinfo_server"

# 打包 TPK
cd "$PLUGIN_DIR"
zip -r "$OUTPUT" . \
  -x "type" \
  -x "build.sh" \
  -x "*.DS_Store" \
  -x "src/*"

echo "  ✅ Packaged: $OUTPUT"
