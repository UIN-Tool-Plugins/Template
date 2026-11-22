#!/usr/bin/env bash
# build.sh <stage_dir> <output.tpk>
#
# type=other 的构建脚本。约定：
#   - 构建产物写到 <stage_dir> 内（这里只生成 sysinfo_server）
#   - 不要自己打包 TPK；构建脚本随后会统一打包、签名
#   - 旧脚本如果仍然生成了 <output.tpk>，构建脚本会直接使用它
#
# Android 真机需要 Android NDK 交叉编译。CI 会设置 ANDROID_NDK_HOME；
# 本地没有 NDK 时可以显式用主机 gcc 做语法/逻辑测试，但产物不能在 Android 上运行。
set -euo pipefail

STAGE_DIR=${1:-}
OUTPUT_TPK=${2:-}
[ -n "$STAGE_DIR" ] || { echo "用法: build.sh <stage_dir> <output.tpk>" >&2; exit 1; }
STAGE_DIR=$(cd "$STAGE_DIR" && pwd)
PLUGIN_ID=$(basename "$STAGE_DIR")

SRC_FILE="$STAGE_DIR/src/sysinfo_server.c"
[ -f "$SRC_FILE" ] || { echo "❌ $PLUGIN_ID: src/sysinfo_server.c 不存在" >&2; exit 1; }

echo "  🔨 编译 sysinfo_server"

CC_BIN=""
if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    CC_BIN=$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" \
        -type f -name 'aarch64-linux-android*-clang' 2>/dev/null | sort -V | tail -1)
    if [ -z "$CC_BIN" ]; then
        echo "❌ NDK 里找不到 aarch64-linux-android*-clang" >&2
        exit 1
    fi
    echo "  📱 NDK: $CC_BIN"
elif [ "${REQUIRE_ANDROID_BINARY:-0}" = "1" ]; then
    echo "❌ CI 需要 Android NDK（ANDROID_NDK_HOME），拒绝把主机二进制发布出去" >&2
    exit 1
else
    CC_BIN=${CC:-gcc}
    echo "  ⚠️  未设置 ANDROID_NDK_HOME，使用主机编译器 $CC_BIN；产物不能在 Android 上运行" >&2
fi

"$CC_BIN" -O2 -Wall -Wextra -o "$STAGE_DIR/sysinfo_server" "$SRC_FILE" -lm
chmod +x "$STAGE_DIR/sysinfo_server"

# 防止误把主机二进制当成 Android 产物发布
if command -v file >/dev/null 2>&1; then
    file "$STAGE_DIR/sysinfo_server"
fi

echo "  ✅ 已生成 sysinfo_server（打包由构建脚本统一处理）"
