#!/usr/bin/env bash
# build-plugin.sh <插件目录> <输出.tpk> [上次发布版本] [--force]
#
# 一次构建的完整流程：
#   1. 复制到 build/work/<id>，不污染源码目录
#   2. 校验 plugin.json / 图标 / 入口
#   3. 计算生效版本（version=0 时在 dist 版本上 +1）
#   4. 按 type 编译（native）或执行 build.sh（other）
#   5. 打包确定性 TPK
#   6. 用 PLUGIN_KEYSTORE* 签名（没有密钥时按 REQUIRE_SIGNING 决定是否失败）
#   7. 校验包结构与签名，写 build/meta/<id>.json
#
# 环境变量：
#   REQUIRE_SIGNING=1      没有签名密钥时直接失败（官方仓库 CI 用）
#   PLUGIN_KEYSTORE_BASE64 / PLUGIN_KEYSTORE / PLUGIN_STORE_PASSWORD /
#   PLUGIN_KEY_PASSWORD / PLUGIN_KEY_ALIAS / PLUGIN_CERT_SHA256
#   KEEP_WORK=1            构建成功后保留 build/work/<id>
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

PLUGIN_DIR_IN=${1:-}
OUTPUT_IN=${2:-}
PREV_VERSION=${3:-0}
FORCE=0
for arg in "$@"; do
    [ "$arg" = "--force" ] && FORCE=1
done

[ -n "$PLUGIN_DIR_IN" ] || die "用法: build-plugin.sh <插件目录> <输出.tpk> [上次版本] [--force]"
[ -n "$OUTPUT_IN" ] || die "缺少输出路径"

PLUGIN_DIR_IN=$(cd "$PLUGIN_DIR_IN" && pwd)
PLUGIN_ID=$(basename "$PLUGIN_DIR_IN")
OUTPUT_DIR=$(cd "$(dirname "$OUTPUT_IN")" 2>/dev/null && pwd || (mkdir -p "$(dirname "$OUTPUT_IN")" && cd "$(dirname "$OUTPUT_IN")" && pwd))
OUTPUT="$OUTPUT_DIR/$(basename "$OUTPUT_IN")"

case "$PLUGIN_ID" in
    *[!a-z0-9_.]*|.*) die "目录名不合法: $PLUGIN_ID（只用小写字母、数字、下划线、点）" ;;
esac

STAGE="$BUILD_DIR/work/$PLUGIN_ID"
META_DIR="$BUILD_DIR/meta"
mkdir -p "$BUILD_DIR" "$META_DIR" "$BUILD_DIR/tmp"
rm -rf "$STAGE"
mkdir -p "$STAGE"

log "📦 $PLUGIN_ID (上次发布: $PREV_VERSION)"

# ---------- 1. 暂存 ----------
tpk stage --source "$PLUGIN_DIR_IN" --target "$STAGE"

PLUGIN_JSON="$STAGE/plugin.json"
[ -f "$PLUGIN_JSON" ] || die "$PLUGIN_ID: plugin.json 不存在"

SOURCE_VERSION=$(tpk get --plugin-json "$PLUGIN_JSON" --field version --default 0)
case "$SOURCE_VERSION" in
    ''|*[!0-9]*) die "$PLUGIN_ID: version 必须是整数，当前为 $SOURCE_VERSION" ;;
esac

UI_TYPE=$(tpk get --plugin-json "$PLUGIN_JSON" --field uiType --default "")
case "$UI_TYPE" in
    web|cui|native) ;;
    *) die "$PLUGIN_ID: uiType 必须是 web / cui / native，当前为 '$UI_TYPE'" ;;
esac

# ---------- 2. 版本 ----------
VERSION_ARGS=(--source "$SOURCE_VERSION" --prev "$PREV_VERSION")
[ "$FORCE" = 1 ] && VERSION_ARGS+=(--force)
EFFECTIVE_VERSION=$(tpk version "${VERSION_ARGS[@]}")
tpk set-version --plugin-json "$PLUGIN_JSON" --version "$EFFECTIVE_VERSION"

# ---------- 3. 按 type 构建 ----------
TYPE=""
[ -f "$STAGE/type" ] && TYPE=$(tr -d '[:space:]' < "$STAGE/type")
case "$TYPE" in
    ""|native|other) ;;
    *) die "$PLUGIN_ID: type 只能是空 / native / other，当前为 '$TYPE'" ;;
esac

if [ "$TYPE" = "native" ] && [ "$UI_TYPE" != "native" ]; then
    die "$PLUGIN_ID: type=native 时 plugin.json 的 uiType 必须是 native"
fi

if [ "$TYPE" = "native" ]; then
    if ! find "$STAGE/src" -name '*.java' -print -quit 2>/dev/null | grep -q .; then
        # 没有源码时允许直接提供预编译 plugin.dex
        if [ ! -f "$STAGE/plugin.dex" ]; then
            die "$PLUGIN_ID: native 插件需要 src/*.java 或预编译的 plugin.dex"
        fi
        log "  📦 使用预编译 plugin.dex"
    fi
    compile_native "$STAGE" "$PLUGIN_ID"
fi

LEGACY_TPK=0
if [ "$TYPE" = "other" ]; then
    [ -f "$STAGE/build.sh" ] || die "$PLUGIN_ID: type=other 但缺少 build.sh"
    rm -f "$OUTPUT"
    log "  🔨 build.sh"
    (
        cd "$STAGE"
        PLUGIN_ID="$PLUGIN_ID" \
        PLUGIN_DIR="$STAGE" \
        OUTPUT_TPK="$OUTPUT" \
        REQUIRE_ANDROID_BINARY="${REQUIRE_ANDROID_BINARY:-0}" \
        ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-}" \
        bash "$STAGE/build.sh" "$STAGE" "$OUTPUT"
    ) || die "$PLUGIN_ID: build.sh 失败"
    if [ -f "$OUTPUT" ] && [ -s "$OUTPUT" ]; then
        LEGACY_TPK=1
        log "  📦 build.sh 已产出 TPK，跳过内置打包"
    fi
fi

if [ "$LEGACY_TPK" = 0 ]; then
    tpk package --dir "$STAGE" --output "$OUTPUT"
fi

# ---------- 4. 签名 ----------
SIGNER=""
set +e
SIGNER=$(bash "$SCRIPT_DIR/sign-tpk.sh" "$OUTPUT")
SIGN_RC=$?
set -e

if [ "$SIGN_RC" -eq 10 ]; then
    if [ "${REQUIRE_SIGNING:-0}" = "1" ]; then
        die "$PLUGIN_ID: 未配置签名密钥（REQUIRE_SIGNING=1）。请设置 PLUGIN_KEYSTORE_BASE64 / PLUGIN_KEYSTORE 等"
    fi
    log "  ⚠️  未签名（本地构建）。发布前请配置密钥，否则客户端会显示「未知签名」"
    SIGNER=""
elif [ "$SIGN_RC" -ne 0 ]; then
    die "$PLUGIN_ID: 签名失败"
fi

# ---------- 5. 校验 ----------
VERIFY_ARGS=(--tpk "$OUTPUT" --plugin-id "$PLUGIN_ID")
if [ -n "$SIGNER" ]; then
    VERIFY_ARGS+=(--require-signature)
fi
if [ -n "${PLUGIN_CERT_SHA256:-}" ]; then
    [ -n "$SIGNER" ] || die "$PLUGIN_ID: 配置了 PLUGIN_CERT_SHA256 但产物未签名"
    VERIFY_ARGS+=(--expected-signer "$PLUGIN_CERT_SHA256")
fi
tpk verify "${VERIFY_ARGS[@]}"

# ---------- 6. 元数据 ----------
SIGNER_FILE=""
if [ -n "$SIGNER" ]; then
    SIGNER_FILE="$BUILD_DIR/$PLUGIN_ID.signer"
    printf '%s\n' "$SIGNER" > "$SIGNER_FILE"
fi
tpk meta \
    --tpk "$OUTPUT" \
    --plugin-json "$PLUGIN_JSON" \
    --signer-file "$SIGNER_FILE" \
    --output "$META_DIR/$PLUGIN_ID.json"

if [ "${KEEP_WORK:-0}" != "1" ]; then
    rm -rf "$STAGE" "$BUILD_DIR/tmp/$PLUGIN_ID"
fi

log "✅ $PLUGIN_ID version=$EFFECTIVE_VERSION -> $OUTPUT"
