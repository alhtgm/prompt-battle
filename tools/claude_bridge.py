# 開発用：llama-server と同じ形（/health と /v1/chat/completions）で待ち受け、問い合わせを claude コマンド（Claude Code）に渡す中継。
# ゲームの操縦士を Claude で動かして比べるためのもの。本番では使わない（企画は各PCの小さいLLMが前提）。
# 使い方：data/llm.local.json に {"external_server": true, "external_label": "Claude Opus 5.5", "request_timeout_sec": 15} を書き、
#   python tools/claude_bridge.py --model claude-opus-5-5 --effort low
# を起動してからゲームを開く。claude コマンドにログインしていれば APIキーはいらない。
import argparse
import json
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INTENTS = ["charge", "flank", "keep_distance", "retreat", "push_to_pit", "go_repair", "circle", "hold"]
SCHEMA = json.dumps({
    "type": "object", "additionalProperties": False, "required": ["intent", "skill", "say"],
    "properties": {
        "intent": {"type": "string", "enum": INTENTS},
        "skill": {"anyOf": [{"type": "null"}, {"type": "integer", "minimum": 0}]},
        "say": {"type": "string"},
    },
})

args = None


def ask_claude(system: str, user: str) -> tuple[str, str]:
    """答えの JSON 文字列と、ログ用の説明を返す"""
    cmd = ["claude", "-p", user, "--model", args.model, "--effort", args.effort,
           "--system-prompt", system, "--json-schema", SCHEMA, "--output-format", "json",
           "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence"]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=60)
    wall = time.time() - t0
    try:
        out = json.loads(p.stdout)
    except json.JSONDecodeError:
        return "", f"読めない答え（{wall:.1f}秒）：{(p.stdout or p.stderr)[:200]}"
    ans = out.get("structured_output")
    if not isinstance(ans, dict):
        try:
            ans = json.loads(out.get("result", ""))
        except (TypeError, json.JSONDecodeError):
            return "", f"形が違う（{wall:.1f}秒）：{str(out.get('result'))[:200]}"
    return json.dumps(ans, ensure_ascii=False), f"{wall:.1f}秒"


class Handler(BaseHTTPRequestHandler):
    # llama-server と同じく接続を保つ（HTTP/1.0 で毎回切ると、ゲームの HttpJob が「接続が切れた」と扱う）
    protocol_version = "HTTP/1.1"

    def _send(self, code: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        self._send(200 if self.path == "/health" else 404, {"status": "ok"})

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self._send(404, {})
            return
        req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8"))
        msgs = {m["role"]: m["content"] for m in req.get("messages", [])}
        content, note = ask_claude(msgs.get("system", ""), msgs.get("user", ""))
        print(f"[{time.strftime('%H:%M:%S')}] {content or '（失敗）'}  {note}", flush=True)
        self._send(200, {"choices": [{"message": {"role": "assistant", "content": content}}]})

    def log_message(self, *_: object) -> None:
        pass  # 1回ごとのアクセスログは出さない


def main() -> None:
    global args
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="claude-opus-5-5")
    parser.add_argument("--effort", default="low")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8399)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"中継を開始：{args.host}:{args.port} → {args.model}（effort={args.effort}）", flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
