#!/usr/bin/env bash
# 校验 assets/host-sdk.jar：结构正确，且与 assets/host-sdk.sha256 记录一致。
#
# 更新 host-sdk 的流程见 README「更新 host-sdk」。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
JAR="$ROOT_DIR/assets/host-sdk.jar"
SHA_FILE="$ROOT_DIR/assets/host-sdk.sha256"

[ -f "$JAR" ] || { echo "❌ 缺少 $JAR" >&2; exit 1; }

python3 "$ROOT_DIR/scripts/tpk.py" host-sdk --jar "$JAR"

if [ -f "$SHA_FILE" ]; then
    expected=$(tr -d '[:space:]' < "$SHA_FILE")
    actual=$(python3 "$ROOT_DIR/scripts/tpk.py" host-sdk-sha --jar "$JAR")
    if [ "$expected" != "$actual" ]; then
        echo "❌ host-sdk.jar 与 assets/host-sdk.sha256 不一致" >&2
        echo "   记录: $expected" >&2
        echo "   实际: $actual" >&2
        echo "   如果你刚更新了 host-sdk，请同步更新 assets/host-sdk.sha256。" >&2
        exit 1
    fi
    echo "  ✅ host-sdk.sha256 一致"
else
    echo "  ⚠️  没有 assets/host-sdk.sha256，跳过哈希校验" >&2
fi
