#!/bin/bash
# package-tpk.sh <plugin_dir> <output.tpk>
# 默认打包脚本：将插件目录内容打包为 .tpk
set -e

PLUGIN_DIR="$1"
OUTPUT="$2"

cd "$PLUGIN_DIR"
zip -r "$OUTPUT" . \
  -x "type" \
  -x "build.sh" \
  -x "visible" \
  -x "*.DS_Store" \
  -x "src/*" \
  -x "libs/*"
