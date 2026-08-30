#!/usr/bin/env python3
"""计算器后端 - 提供 /calc 和 /health 接口"""
import os
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get('PORT', 8000))

class CalcHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/calc':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            data = json.loads(body)
            expr = data.get('expr', '')

            try:
                result = eval(expr, {"__builtins__": {}}, {})
                response = {"result": str(result)}
            except Exception as e:
                response = {"error": str(e), "result": "Error"}

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 静默日志

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', PORT), CalcHandler)
    print(f'Calculator backend running on port {PORT}')
    server.serve_forever()
