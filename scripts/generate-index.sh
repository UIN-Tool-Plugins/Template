#!/usr/bin/env bash
# generate-index.sh <dist_dir> [source.json]
#
# 扫描 dist/plugins/*/ 生成 source.json。真正的实现是 scripts/tpk.py index。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DIST_DIR=${1:-dist}
META=${2:-}

if [ -z "$META" ]; then
    if [ -f source.json ]; then
        META=source.json
    elif [ -f ../source.json ]; then
        META=../source.json
    fi
fi

if [ -n "$META" ]; then
    exec python3 "$SCRIPT_DIR/tpk.py" index --dist "$DIST_DIR" --meta "$META"
fi
exec python3 "$SCRIPT_DIR/tpk.py" index --dist "$DIST_DIR"
