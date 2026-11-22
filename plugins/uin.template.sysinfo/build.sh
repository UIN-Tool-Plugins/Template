#!/usr/bin/env bash
# build.sh <stage_dir> <output.tpk>
#
# type=other 的构建脚本。约定：
#   - 构建产物写到 <stage_dir> 内（这里只生成 sysinfo_server）
#   - 不要自己打包 TPK；构建脚本随后会统一打包、签名
#   - 旧脚本如果仍然生成了 <output.tpk>，构建脚本会直接使用它
#
# 目标环境是插件后端**实际运行的地方**：
#   - 内置 proot：Debian (glibc)
#   - 实体 Termux 本机：Android (bionic)
# 同时兼容两者的形态是「静态链接的 Linux aarch64 可执行文件」。
# Android NDK 产出的是 bionic 动态可执行文件，缺少 /system/bin/linker64 时
# 在 Debian 容器里根本起不来，所以这里不用 NDK。
set -euo pipefail

STAGE_DIR=${1:-}
OUTPUT_TPK=${2:-}
[ -n "$STAGE_DIR" ] || { echo "用法: build.sh <stage_dir> <output.tpk>" >&2; exit 1; }
STAGE_DIR=$(cd "$STAGE_DIR" && pwd)
PLUGIN_ID=$(basename "$STAGE_DIR")

SRC_FILE="$STAGE_DIR/src/sysinfo_server.c"
[ -f "$SRC_FILE" ] || { echo "❌ $PLUGIN_ID: src/sysinfo_server.c 不存在" >&2; exit 1; }

echo "  🔨 编译 sysinfo_server（静态 aarch64 Linux）"

# 优先交叉编译器；在 aarch64 Linux 上直接用本机 gcc。
CC_BIN="${CROSS_CC:-aarch64-linux-gnu-gcc}"
if command -v "$CC_BIN" >/dev/null 2>&1; then
    :
elif [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "aarch64" ] && command -v gcc >/dev/null 2>&1; then
    CC_BIN=gcc
else
    echo "❌ 找不到 aarch64 编译器。" >&2
    echo "   Ubuntu/Debian: sudo apt-get install -y gcc-aarch64-linux-gnu" >&2
    echo "   或设置 CROSS_CC 指向 aarch64 交叉编译器。" >&2
    exit 1
fi

echo "  🛠️  编译器: $CC_BIN"
"$CC_BIN" -O2 -static -Wall -Wextra -o "$STAGE_DIR/sysinfo_server" "$SRC_FILE" -lm
chmod +x "$STAGE_DIR/sysinfo_server"

# 防止把主机架构或动态链接的二进制发布出去
if command -v file >/dev/null 2>&1; then
    file "$STAGE_DIR/sysinfo_server"
    if ! file "$STAGE_DIR/sysinfo_server" | grep -q 'ARM aarch64'; then
        echo "❌ 产物不是 aarch64，拒绝发布" >&2
        exit 1
    fi
    if ! file "$STAGE_DIR/sysinfo_server" | grep -qi 'statically linked'; then
        echo "❌ 产物不是静态链接，在 proot 容器里可能找不到解释器" >&2
        exit 1
    fi
else
    echo "  ⚠️  没有 file 命令，跳过产物架构检查" >&2
fi

echo "  ✅ 已生成 sysinfo_server（打包由构建脚本统一处理）"
