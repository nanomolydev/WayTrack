#!/usr/bin/env python3
"""HTTP-мост между приложением WayTrack и claude-vpn.

Приложение шлёт POST /chat, мост будит сессию Claude Code (через claude-vpn,
то есть с подпиской и kzVPN-прокси) и продолжает её при следующих запросах.
Если запросов нет дольше WAYTRACK_IDLE секунд — сессия засыпает, и следующее
обращение начинает разговор заново.
"""
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ.get("WAYTRACK_TOKEN", "")
IDLE = int(os.environ.get("WAYTRACK_IDLE", "900"))
PORT = int(os.environ.get("WAYTRACK_PORT", "8765"))
CLAUDE = os.environ.get("WAYTRACK_CLAUDE", "/usr/local/bin/claude-vpn")
TIMEOUT = int(os.environ.get("WAYTRACK_TIMEOUT", "170"))

# ponytail: один разговор на сервер — приложение личное, очередь из одного.
lock = threading.Lock()
state = {"session": None, "last": 0.0}


def awake():
    return state["session"] is not None and time.time() - state["last"] < IDLE


def ask(prompt, model, session):
    cmd = [CLAUDE, "-p", prompt, "--output-format", "json"]
    if model:
        cmd += ["--model", model]
    if session:
        cmd += ["--resume", session]
    done = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT,
                          env={**os.environ, "HOME": "/root"})
    if done.returncode != 0:
        raise RuntimeError((done.stderr or done.stdout or "claude failed").strip()[:500])
    payload = json.loads(done.stdout)
    return payload.get("result", ""), payload.get("session_id")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, code, body):
        raw = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def authorized(self):
        return TOKEN and self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def do_GET(self):
        if self.path != "/health":
            return self.reply(404, {"error": "not found"})
        self.reply(200, {"awake": awake(), "idle": IDLE,
                         "quiet_for": int(time.time() - state["last"]) if state["last"] else None})

    def do_POST(self):
        if self.path != "/chat":
            return self.reply(404, {"error": "not found"})
        if not self.authorized():
            return self.reply(401, {"error": "bad token"})

        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self.reply(400, {"error": "bad json"})

        prompt = (body.get("prompt") or "").strip()
        if not prompt:
            return self.reply(400, {"error": "empty prompt"})

        with lock:
            session = body.get("session") or state["session"]
            if not awake():
                session = None          # разговор проспал слишком долго — начинаем заново
            try:
                reply, new_session = ask(prompt, body.get("model"), session)
            except subprocess.TimeoutExpired:
                return self.reply(504, {"error": "claude не ответил вовремя"})
            except Exception as error:  # noqa: BLE001 — наружу отдаём текст как есть
                return self.reply(502, {"error": str(error)})
            state["session"] = new_session
            state["last"] = time.time()

        self.reply(200, {"reply": reply, "session": new_session, "sleeps_in": IDLE})

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    if not TOKEN:
        raise SystemExit("WAYTRACK_TOKEN не задан")
    print(f"waytrack bridge on :{PORT}, сессия засыпает после {IDLE}s", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
