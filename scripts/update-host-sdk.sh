#!/usr/bin/env bash
# update-host-sdk.sh [host-sdk.jar 路径]
#
# 把 UIN Tool 宿主导出的 host-sdk.jar 同步到本仓库，并更新 sha256 记录。
# 默认从同级目录的 UIN_Tool 工程取；也可以显式传路径或设置 UIN_TOOL_REPO。
#
#   bash scripts/update-host-sdk.sh /path/to/UIN_Tool
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:-}
if [ -z "$SRC" ]; then
    SRC="${UIN_TOOL_REPO:-$ROOT_DIR/../UIN_Tool}/app/src/main/assets/compiler/host-sdk.jar"
elif [ -d "$SRC" ]; then
    SRC="$SRC/app/src/main/assets/compiler/host-sdk.jar"
fi

[ -f "$SRC" ] || { echo "❌ 找不到 host-sdk.jar: $SRC" >&2; exit 1; }

cp "$SRC" "$ROOT_DIR/assets/host-sdk.jar"
python3 "$ROOT_DIR/scripts/tpk.py" host-sdk --jar "$ROOT_DIR/assets/host-sdk.jar"
python3 "$ROOT_DIR/scripts/tpk.py" host-sdk-sha --jar "$ROOT_DIR/assets/host-sdk.jar" \
    > "$ROOT_DIR/assets/host-sdk.sha256"
echo "✅ 已更新 assets/host-sdk.jar 与 assets/host-sdk.sha256"
