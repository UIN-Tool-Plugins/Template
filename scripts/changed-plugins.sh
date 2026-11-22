#!/usr/bin/env bash
# changed-plugins.sh <before-sha> <head-sha>
#
# 输出本次需要重新构建的插件 ID，每行一个。规则：
#   - FULL_BUILD=1、before 为空或是 000... 时：全部
#   - scripts/、assets/、.github/workflows/ 有改动：全部（构建逻辑变了）
#   - 其它情况：只输出 plugins/<id>/... 里发生改动的 <id>
#   - 只改 source.json：不重建插件（索引仍会重新生成）
#   - 删除插件：不构建，部署阶段会从 dist 移除
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

BEFORE=${1:-}
HEAD=${2:-HEAD}

# 本地 Android 共享存储常出现「可疑的仓库所有权」；这个脚本只读 diff。
GIT=(git -c "safe.directory=$ROOT_DIR")
if ! "${GIT[@]}" rev-parse --git-dir >/dev/null 2>&1; then
    GIT=(git -c 'safe.directory=*')
fi

all_plugins() {
    for dir in plugins/*/; do
        [ -d "$dir" ] || continue
        [ -f "$dir/plugin.json" ] || continue
        basename "$dir"
    done
}

if [ "${FULL_BUILD:-0}" = "1" ] || [ "${FULL_BUILD:-0}" = "true" ] || [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
    all_plugins
    exit 0
fi

if ! "${GIT[@]}" cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
    echo "⚠️ 找不到 before 提交 $BEFORE，按全量构建" >&2
    all_plugins
    exit 0
fi

CHANGED_FILES=$("${GIT[@]}" diff --name-only --diff-filter=d "$BEFORE" "$HEAD" || true)

if echo "$CHANGED_FILES" | grep -Eq '^(scripts/|assets/|\.github/workflows/)'; then
    echo "构建逻辑有改动，按全量构建" >&2
    all_plugins
    exit 0
fi

echo "$CHANGED_FILES" \
    | awk -F/ '$1 == "plugins" && NF >= 3 && $2 != "" { print $2 }' \
    | sort -u
