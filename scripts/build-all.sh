#!/usr/bin/env bash
# build-all.sh [插件ID...]
#
# 本地构建全部或指定插件，产物在 build/。
# 版本号从 dist/ 读取（可用 PREV_DIR 指定其他目录）；没有 dist 时从 1 开始。
# 密钥、REQUIRE_SIGNING 等环境变量与 build-plugin.sh 相同。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

PREV_DIR=${PREV_DIR:-"$ROOT_DIR/dist"}
mkdir -p build

if [ "$#" -gt 0 ]; then
    PLUGINS=("$@")
else
    PLUGINS=()
    for dir in plugins/*/; do
        [ -d "$dir" ] || continue
        [ -f "$dir/plugin.json" ] || continue
        PLUGINS+=("$(basename "$dir")")
    done
fi

[ "${#PLUGINS[@]}" -gt 0 ] || { echo "没有找到插件"; exit 1; }

bash scripts/check-host-sdk.sh

FAIL=0
for plugin_id in "${PLUGINS[@]}"; do
    plugin_dir="plugins/$plugin_id"
    if [ ! -d "$plugin_dir" ]; then
        echo "❌ 插件不存在: $plugin_id"
        FAIL=$((FAIL + 1))
        continue
    fi

    prev=0
    version_file="$PREV_DIR/plugins/$plugin_id/.version"
    if [ -f "$version_file" ]; then
        prev=$(cat "$version_file")
    fi

    if ! bash scripts/build-plugin.sh "$plugin_dir" "build/$plugin_id.tpk" "$prev"; then
        echo "❌ 构建失败: $plugin_id"
        FAIL=$((FAIL + 1))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    echo "❌ $FAIL 个插件构建失败"
    exit 1
fi

echo "✅ 构建完成：${#PLUGINS[@]} 个插件，产物在 build/"
