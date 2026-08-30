#!/bin/bash
# CUI 入口脚本 - 显示系统信息
echo "=========================================="
echo "  UIN Tool SysInfo (C Backend + CUI)"
echo "=========================================="
echo ""

# 后端由宿主自动启动，这里等待端口就绪
PORT="${PORT:-8000}"
echo "Waiting for backend on port $PORT..."

for i in $(seq 1 10); do
  if curl -s "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
    echo "Backend ready!"
    break
  fi
  sleep 1
done

echo ""

while true; do
  echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
  echo ""

  # 从 C 后端获取系统信息
  if INFO=$(curl -s "http://127.0.0.1:$PORT/info" 2>/dev/null); then
    echo "[System Info from C Backend]"
    echo "  $INFO" | sed 's/[{}",]/\n/g' | grep -v '^$' | sed 's/^  //'
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
