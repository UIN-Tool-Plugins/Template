#!/usr/bin/env bash
# deploy-dist.sh <dist 仓库目录> <build 目录> [source.json]
#
# 把 build/ 里的 TPK 和元数据同步到 dist 分支工作区，重新生成 source.json，
# 然后提交并推送。由 CI 调用；本地想预览 dist 也可以直接跑。
#
# 环境变量：
#   DIST_PUSH=0   只生成不提交（本地预览）
set -euo pipefail

DIST_REPO=${1:-}
BUILD=${2:-}
SOURCE_META=${3:-source.json}
[ -n "$DIST_REPO" ] || { echo "用法: deploy-dist.sh <dist目录> <build目录> [source.json]" >&2; exit 1; }
[ -d "$DIST_REPO" ] || { echo "❌ dist 目录不存在: $DIST_REPO" >&2; exit 1; }
[ -d "$BUILD" ] || { echo "❌ build 目录不存在: $BUILD" >&2; exit 1; }

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TPK_PY="$ROOT_DIR/scripts/tpk.py"
BUILD=$(cd "$BUILD" && pwd)
DIST_REPO=$(cd "$DIST_REPO" && pwd)

case "$SOURCE_META" in
    /*) ;;
    *) SOURCE_META="$ROOT_DIR/$SOURCE_META" ;;
esac

cd "$DIST_REPO"
mkdir -p plugins

# ---------- 1. 删除源仓库里已经不存在的插件 ----------
for dist_plugin in plugins/*/; do
    [ -d "$dist_plugin" ] || continue
    plugin_id=$(basename "$dist_plugin")
    if [ ! -d "$ROOT_DIR/plugins/$plugin_id" ]; then
        echo "  🗑️  移除已删除的插件: $plugin_id"
        rm -rf "$dist_plugin"
    fi
done

# ---------- 2. 同步本次构建产物 ----------
BUILT=()
shopt -s nullglob
for tpk in "$BUILD"/*.tpk; do
    plugin_id=$(basename "$tpk" .tpk)
    meta="$BUILD/meta/$plugin_id.json"
    if [ ! -f "$meta" ]; then
        echo "❌ 缺少构建元数据: $meta" >&2
        exit 1
    fi

    source_dir="$ROOT_DIR/plugins/$plugin_id"
    [ -d "$source_dir" ] || { echo "❌ 源目录不存在: $source_dir" >&2; exit 1; }

    target="plugins/$plugin_id"
    mkdir -p "$target"
    cp "$tpk" "$target/$plugin_id.tpk"
    python3 "$TPK_PY" export-plugin-json --meta "$meta" --output "$target/plugin.json"

    version=$(python3 - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    meta = json.load(handle)
print(meta.get("version", 1))
PY
)
    printf '%s\n' "$version" > "$target/.version"

    sha=$(python3 - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    meta = json.load(handle)
print(meta.get("sha256", ""))
PY
)
    printf '%s\n' "$sha" > "$target/.sha256"

    signer=$(python3 - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    meta = json.load(handle)
print(meta.get("signerSha256", ""))
PY
)
    if [ -n "$signer" ]; then
        printf '%s\n' "$signer" > "$target/.signer"
    else
        rm -f "$target/.signer"
    fi

    built_at=$(python3 - "$meta" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    meta = json.load(handle)
print(meta.get("builtAt", ""))
PY
)
    printf '%s\n' "$built_at" > "$target/.built"

    # 索引和远程列表统一使用 plugins/<id>/icon.png
    icon_rel=$(python3 "$TPK_PY" get --plugin-json "$source_dir/plugin.json" --field icon --default icon.png)
    if [ -f "$source_dir/$icon_rel" ]; then
        cp "$source_dir/$icon_rel" "$target/icon.png"
    fi

    # 显示标记：dist 里保留 visible，索引据此排除 0 / false（隐藏）
    if [ -f "$source_dir/visible" ]; then
        cp "$source_dir/visible" "$target/visible"
    else
        rm -f "$target/visible"
    fi

    BUILT+=("$plugin_id")
done

# ---------- 3. 索引 ----------
if [ ! -f "$SOURCE_META" ]; then
    SOURCE_META="$ROOT_DIR/source.json"
fi
bash "$ROOT_DIR/scripts/generate-index.sh" "$DIST_REPO" "$SOURCE_META"

if [ "${DIST_PUSH:-1}" = "0" ]; then
    echo "✅ dist 已更新（DIST_PUSH=0，未提交）"
    exit 0
fi

# ---------- 4. 提交并推送 ----------
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git add -A
if git diff --staged --quiet; then
    echo "✅ dist 没有变化"
    exit 0
fi

# 标题只写数量：commit 首行同时也是 Actions 运行名和 git log 的标题，
# 点名插件会随数量无限变长。具体改了什么看 CI 日志或 dist 的 diff。
if [ "${#BUILT[@]}" -gt 0 ]; then
    git commit -q -m "build: update ${#BUILT[@]} plugin(s)"
else
    git commit -q -m "build: refresh plugin index"
fi

for attempt in 1 2 3; do
    if git push origin HEAD:dist; then
        if [ "${#BUILT[@]}" -gt 0 ]; then
            echo "✅ 已推送 dist（${#BUILT[@]} 个插件）"
        else
            echo "✅ 已推送 dist（仅索引）"
        fi
        exit 0
    fi
    echo "⚠️  推送失败，第 $attempt 次重试..."
    # CI 常见是 shallow clone：先补历史再 rebase，避免直接 pull 失败。
    git fetch --deepen=50 origin dist >/dev/null 2>&1 || true
    git rebase origin/dist >/dev/null 2>&1 \
        || git pull --rebase origin dist >/dev/null 2>&1 \
        || true
    sleep 2
done

echo "❌ 推送 dist 失败（重试 3 次）" >&2
exit 1
