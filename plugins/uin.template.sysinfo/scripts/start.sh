#!/bin/sh
# 启动 C 后端。
#
# 插件目录在共享存储（/storage/emulated/0）上，该分区通常以 noexec 挂载：
# 即使 chmod +x，直接 exec 也会得到 "Permission denied"。
# 因此先把二进制复制到可执行目录再运行：
#   - 内置 proot：容器内的 /tmp（位于应用私有 /data，允许执行）
#   - 实体 Termux：$TMPDIR（Termux 自己的 tmp，位于 /data，允许执行）
# /tmp 在部分实体 Termux 环境里不存在，所以按 TMPDIR -> /tmp -> $HOME 依次尝试。
set -e

cd "$(dirname "$0")/.."

SRC="./sysinfo_server"
[ -f "$SRC" ] || {
    echo "[start.sh] binary not found: $SRC" >&2
    exit 1
}

TMP_BASE=""
for dir in "${TMPDIR:-}" /tmp "${HOME:-}/.uin_tmp"; do
    [ -n "$dir" ] || continue
    mkdir -p "$dir" 2>/dev/null || continue
    if ( : > "$dir/.uin_start_probe" ) 2>/dev/null; then
        rm -f "$dir/.uin_start_probe"
        TMP_BASE="$dir"
        break
    fi
done
if [ -z "$TMP_BASE" ]; then
    echo "[start.sh] no writable exec dir (TMPDIR/tmp/HOME)" >&2
    exit 1
fi

RUN="$TMP_BASE/uin_sysinfo_server.$$"
cp "$SRC" "$RUN"
chmod +x "$RUN"

echo "[start.sh] starting sysinfo_server on 127.0.0.1:${PORT:-8000}" >&2
exec "$RUN"
