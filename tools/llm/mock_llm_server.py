#!/usr/bin/env python3
"""A tiny OpenAI-compatible chat server for tests (M12). Standard library only.

Streams a bartender reply as SSE, the way llama-server / Ollama / OpenRouter do,
so the game's real HTTP path (HTTPClient polling, chunked SSE, UTF-8 split across
chunks) is exercised in CI with no model.

  python3 tools/llm/mock_llm_server.py --port 8765

Behaviour by path prefix (so one server can play several providers):
  /good/v1/...   streams a valid reply in small, deliberately awkward chunks
  /hang/v1/...   accepts the request and never answers (timeout + fallback)
  /err/v1/...    answers 500
  /garbage/v1/...  streams text that is not JSON (parser repair path)
  /health or /<mode>/health  200 except for /hang and /err
The reply echoes the last player line it received, which proves the player's
words actually reached the model.
"""
import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def reply_for(body):
    msgs = body.get("messages", [])
    last = ""
    for m in reversed(msgs):
        if m.get("role") == "user":
            last = m.get("content", "")
            break
    said = re.sub(r"</?player_says>", "", last).strip()
    briefing = "\n".join(m.get("content", "") for m in msgs if m.get("role") == "system")
    rumor = re.search(r"\[(r_[a-z_]+)\]", briefing)
    actions = [{"type": "share_rumor", "id": rumor.group(1)}] if rumor else []
    actions.append({"type": "trust", "delta": 1, "why": "polite"})
    return {
        "say": "You said “%s”. Café talk costs extra, friend." % said[:60],
        "tone": "amused",
        "then": actions,
    }


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _mode(self):
        p = self.path.strip("/").split("/")
        return p[0] if p and p[0] in ("good", "hang", "err", "garbage") else "good"

    def do_GET(self):
        mode = self._mode()
        code = 200 if mode in ("good", "garbage") else 503
        data = b'{"status":"ok"}'
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        mode = self._mode()
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n) or b"{}")
        if mode == "hang":
            time.sleep(30)
            return
        if mode == "err":
            data = b'{"error":{"message":"boom"}}'
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        if mode == "garbage":
            text = "Sure! Here's my answer: the gate is closed tonight."
        else:
            text = json.dumps(reply_for(body), ensure_ascii=False)
        time.sleep(0.05)
        # Build the SSE stream, then cut it at awkward byte offsets (mid-line,
        # mid-UTF-8 character) to prove the client reassembles it.
        sse = b""
        step = 7
        for i in range(0, len(text), step):
            ev = {"choices": [{"index": 0, "delta": {"content": text[i:i + step]}}]}
            sse += b"data: " + json.dumps(ev, ensure_ascii=False).encode("utf-8") + b"\n\n"
        sse += b'data: {"choices":[],"usage":{"prompt_tokens":321,"completion_tokens":42}}\n\n'
        sse += b"data: [DONE]\n\n"
        cut = 0
        sizes = [5, 13, 3, 29, 11, 2, 17]
        k = 0
        while cut < len(sse):
            piece = sse[cut:cut + sizes[k % len(sizes)]]
            cut += len(piece)
            k += 1
            self.wfile.write(b"%x\r\n%s\r\n" % (len(piece), piece))
            self.wfile.flush()
            time.sleep(0.004)
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    print("mock llm on", a.port, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
