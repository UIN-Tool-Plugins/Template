#!/bin/bash
# 系统监控脚本 - CUI 插件示例
echo "=========================================="
echo "  UIN Tool System Monitor (CUI Plugin)"
echo "=========================================="
echo ""

while true; do
  echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
  echo ""

  # 内存信息
  echo "[Memory]"
  if [ -f /proc/meminfo ]; then
    TOTAL=$(awk '/MemTotal/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
    FREE=$(awk '/MemAvailable/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
    echo "  Total: $TOTAL"
    echo "  Available: $FREE"
  else
    echo "  N/A"
  fi
  echo ""

  # 磁盘信息
  echo "[Disk]"
  df -h / 2>/dev/null | tail -1 | awk '{printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
  echo ""

  # CPU 信息
  echo "[CPU]"
  if [ -f /proc/stat ]; then
    LOAD=$(awk '/^cpu / {printf "%.1f%% %.1f%% %.1f%%", $2/$5*100, $3/$5*100, $4/$5*100}' /proc/stat 2>/dev/null)
    echo "  Load: $LOAD"
  else
    echo "  N/A"
  fi
  echo ""

  # 进程数
  echo "[Processes]"
  echo "  Total: $(ls /proc | grep -c '^[0-9]' 2>/dev/null || echo 'N/A')"
  echo ""

  echo "=========================================="
  echo "  Refreshing in 3 seconds... (Ctrl+C to stop)"
  echo "=========================================="
  echo ""

  sleep 3
done
