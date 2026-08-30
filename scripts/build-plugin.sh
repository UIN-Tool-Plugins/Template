#!/bin/bash
# build-plugin.sh <plugin_dir> <output.tpk>
# 构建单个插件，根据 type 文件决定构建方式
set -e

PLUGIN_DIR=$(cd "$1" && pwd)
OUTPUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
PLUGIN_ID=$(basename "$PLUGIN_DIR")
PLUGIN_JSON="$PLUGIN_DIR/plugin.json"

if [ ! -f "$PLUGIN_JSON" ]; then
  echo "❌ $PLUGIN_ID: plugin.json not found"
  exit 1
fi

BUILD_TYPE=$(cat "$PLUGIN_DIR/type" 2>/dev/null | tr -d '[:space:]')
UI_TYPE=$(jq -r '.uiType // "web"' "$PLUGIN_JSON")

echo "📦 Building $PLUGIN_ID (type=${BUILD_TYPE:-default}, uiType=$UI_TYPE)"

# 校验入口文件
case "$UI_TYPE" in
  native)
    MAIN_CLASS=$(jq -r '.mainClass // empty' "$PLUGIN_JSON")
    if [ -z "$MAIN_CLASS" ]; then
      echo "❌ $PLUGIN_ID: native plugin missing mainClass"
      exit 1
    fi
    ;;
  web|cui)
    ENTRY=$(jq -r '.entry // empty' "$PLUGIN_JSON")
    if [ -z "$ENTRY" ]; then
      echo "❌ $PLUGIN_ID: $UI_TYPE plugin missing entry"
      exit 1
    fi
    if [ ! -f "$PLUGIN_DIR/$ENTRY" ]; then
      echo "❌ $PLUGIN_ID: entry file not found: $ENTRY"
      exit 1
    fi
    ;;
esac

# version 自动递增: version==0 时 CI 递增
CURRENT_VER=$(jq -r '.version' "$PLUGIN_JSON")
if [ "$CURRENT_VER" -eq 0 ] 2>/dev/null; then
  DIST_META="dist/plugins/$PLUGIN_ID/.version"
  if [ -f "$DIST_META" ]; then
    LAST_VER=$(cat "$DIST_META")
  else
    LAST_VER=0
  fi
  NEW_VER=$((LAST_VER + 1))
  jq ".version = $NEW_VER" "$PLUGIN_JSON" > /tmp/plugin_tmp.json && mv /tmp/plugin_tmp.json "$PLUGIN_JSON"
  echo "  📈 Auto-increment version: $NEW_VER"
else
  echo "  📌 Using provided version: $CURRENT_VER"
fi

case "$BUILD_TYPE" in
  native)
    echo "  🔨 Compiling native plugin..."
    SRC_DIR="$PLUGIN_DIR/src"
    if [ ! -d "$SRC_DIR" ]; then
      echo "❌ $PLUGIN_ID: src/ directory not found"
      exit 1
    fi

    BUILD_TMP=$(mktemp -d)
    mkdir -p "$BUILD_TMP/classes"

    find "$SRC_DIR" -name "*.java" > "$BUILD_TMP/sources.txt"
    if [ ! -s "$BUILD_TMP/sources.txt" ]; then
      echo "❌ $PLUGIN_ID: no .java files found in src/"
      rm -rf "$BUILD_TMP"
      exit 1
    fi

    javac -source 11 -target 11 \
      -classpath "$PLUGIN_DIR/libs/*:${ANDROID_HOME:-/usr/local/lib/android/sdk}/platforms/android-34/android.jar" \
      -d "$BUILD_TMP/classes" \
      @"$BUILD_TMP/sources.txt" 2>&1

    d8 --output "$BUILD_TMP" \
      --lib "${ANDROID_HOME:-/usr/local/lib/android/sdk}/platforms/android-34/android.jar" \
      $(find "$BUILD_TMP/classes" -name "*.class") 2>&1

    cp "$BUILD_TMP/classes.dex" "$PLUGIN_DIR/plugin.dex"

    cd "$PLUGIN_DIR"
    zip -r "$OUTPUT" \
      plugin.json icon.png plugin.dex web/ scripts/ \
      -x "type" -x "build.sh" -x "visible" -x "*.DS_Store" -x "src/*" -x "libs/*"
    rm -rf "$BUILD_TMP"
    ;;

  other)
    echo "  🔨 Running custom build.sh..."
    if [ ! -f "$PLUGIN_DIR/build.sh" ]; then
      echo "❌ $PLUGIN_ID: type=other but build.sh not found"
      exit 1
    fi
    bash "$PLUGIN_DIR/build.sh" "$PLUGIN_DIR" "$OUTPUT"
    ;;

  *)
    echo "  📦 Default packaging..."
    cd "$PLUGIN_DIR"
    zip -r "$OUTPUT" . \
      -x "type" -x "build.sh" -x "visible" -x "*.DS_Store" -x "src/*" -x "libs/*"
    ;;
esac

echo "  ✅ Built: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
