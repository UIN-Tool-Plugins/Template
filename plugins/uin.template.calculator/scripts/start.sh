#!/bin/sh
# 启动脚本 - 安装依赖并启动后端
pip install flask 2>/dev/null
python scripts/backend/server.py
