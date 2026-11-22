#!/bin/sh
# CUI 入口脚本 - 显示系统信息
#
# 宿主注入：PORT（后端实际端口）、PLUGIN_ID、PLUGIN_DIR、WORK_DIR。
# Debian 最小 rootfs 没有 curl/wget，这里用 Python 3 发 HTTP 请求。

PORT="${PORT:-8000}"
BASE="http://127.0.0.1:$PORT"

http_get() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys
import urllib.request

try:
    with urllib.request.urlopen(sys.argv[1], timeout=2) as resp:
        sys.stdout.write(resp.read().decode("utf-8", "replace"))
except Exception:
    sys.exit(1)
PY
}

echo "=========================================="
echo "  UIN Tool SysInfo (C Backend + CUI)"
echo "=========================================="
echo ""

echo "Waiting for backend on port $PORT..."
i=0
while [ "$i" -lt 10 ]; do
    if http_get "$BASE/health" >/dev/null; then
        echo "Backend ready!"
        break
    fi
    i=$((i + 1))
    sleep 1
done
echo ""

while true; do
    echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
    echo ""

    if INFO=$(http_get "$BASE/info"); then
        echo "[System Info from C Backend]"
        printf '%s' "$INFO" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for key, value in data.items():
    print("  %s: %s" % (key, value))
' || printf '  %s\n' "$INFO"
    else
        echo "[System Info]"
        echo "  Backend not available, showing local info:"
        uname -a 2>/dev/null || echo "  N/A"
    fi
    echo ""

    # 本地补充信息
    echo "[Local Info]"
    if [ -f /proc/meminfo ]; then
        TOTAL=$(awk '/MemTotal/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
        FREE=$(awk '/MemAvailable/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
        echo "  Memory: $FREE / $TOTAL"
    fi

    df -h / 2>/dev/null | tail -1 | awk '{printf "  Disk: %s / %s (%s)\n", $3, $2, $5}'
    echo ""

    echo "=========================================="
    echo "  Refreshing in 3 seconds..."
    echo "=========================================="
    echo ""

    sleep 3
done
