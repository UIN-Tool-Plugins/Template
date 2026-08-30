#!/bin/bash
# generate-index.sh <dist_dir>
# 扫描 dist 目录下的插件文件夹，生成 source.json
# visible 文件内容为 1/true 时，该插件不写入 source.json（但仍保留在 dist 中）
set -e

DIST_DIR="$1"
REPO_NAME=$(git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//')
SOURCE_ID=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')

# 读取 main 分支的 source.json 获取源元数据
META_JSON="../source.json"
if [ -f "$META_JSON" ]; then
  SOURCE_NAME=$(jq -r '.name // "'"$REPO_NAME"'"' "$META_JSON")
  SOURCE_DESC=$(jq -r '.description // ""' "$META_JSON")
  SOURCE_MAINTAINER=$(jq -r '.maintainer // ""' "$META_JSON")
else
  SOURCE_NAME="$REPO_NAME"
  SOURCE_DESC=""
  SOURCE_MAINTAINER=""
fi

# 开始生成
cat > "$DIST_DIR/source.json" <<EOF
{
  "sourceId": "$SOURCE_ID",
  "name": "$SOURCE_NAME",
  "description": "$SOURCE_DESC",
  "maintainer": "$SOURCE_MAINTAINER",
  "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "plugins": [
EOF

FIRST=true
VISIBLE_COUNT=0
HIDDEN_COUNT=0

for plugin_dir in "$DIST_DIR"/plugins/*/; do
  [ -d "$plugin_dir" ] || continue
  PLUGIN_ID=$(basename "$plugin_dir")

  # 检查 visible 文件：内容为 1/true 则隐藏，不写入 source.json
  VISIBLE_FILE="$plugin_dir/visible"
  if [ -f "$VISIBLE_FILE" ]; then
    VISIBLE_VAL=$(cat "$VISIBLE_FILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    if [ "$VISIBLE_VAL" = "1" ] || [ "$VISIBLE_VAL" = "true" ]; then
      HIDDEN_COUNT=$((HIDDEN_COUNT + 1))
      echo "  ⏭️  Hidden: $PLUGIN_ID (visible file = $VISIBLE_VAL)"
      continue
    fi
  fi

  # 从 .version 文件读取版本号
  VERSION_FILE="$plugin_dir/.version"
  if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE")
  else
    VERSION=1
  fi

  # 从 dist 目录的 plugin.json 读取元数据
  PLUGIN_JSON="$plugin_dir/plugin.json"
  if [ ! -f "$PLUGIN_JSON" ]; then
    echo "⚠️ Skip $PLUGIN_ID: plugin.json not found"
    continue
  fi

  NAME=$(jq -r '.name' "$PLUGIN_JSON")
  VERSION_NAME=$(jq -r '.versionName // "1.0.0"' "$PLUGIN_JSON")
  AUTHOR=$(jq -r '.author // ""' "$PLUGIN_JSON")
  DESC=$(jq -r '.description // ""' "$PLUGIN_JSON")
  CATEGORY=$(jq -r '.category // "未分类"' "$PLUGIN_JSON")

  # 计算 .tpk 大小
  TPK_FILE="$plugin_dir/$PLUGIN_ID.tpk"
  if [ -f "$TPK_FILE" ]; then
    SIZE=$(stat -c%s "$TPK_FILE" 2>/dev/null || stat -f%z "$TPK_FILE" 2>/dev/null || echo 0)
  else
    SIZE=0
  fi

  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "    ," >> "$DIST_DIR/source.json"
  fi

  cat >> "$DIST_DIR/source.json" <<PLUGIN
    {
      "pluginId": "$PLUGIN_ID",
      "name": "$NAME",
      "version": $VERSION,
      "versionName": "$VERSION_NAME",
      "author": "$AUTHOR",
      "description": "$DESC",
      "category": "$CATEGORY",
      "size": $SIZE,
      "tpkPath": "plugins/$PLUGIN_ID/$PLUGIN_ID.tpk",
      "iconPath": "plugins/$PLUGIN_ID/icon.png",
      "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
PLUGIN
  VISIBLE_COUNT=$((VISIBLE_COUNT + 1))
done

cat >> "$DIST_DIR/source.json" <<EOF
  ]
}
EOF

echo "✅ Generated source.json: $VISIBLE_COUNT visible, $HIDDEN_COUNT hidden"
