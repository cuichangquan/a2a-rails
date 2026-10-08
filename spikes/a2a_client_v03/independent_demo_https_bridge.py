#!/usr/bin/env python3
"""TEST-ONLY HTTPS adapter in front of the independent published-Gem Rails Demo.

The demo intentionally advertises http://127.0.0.1:3000/a2a because it is
local-only. This harness terminates TLS on loopback and rewrites ONLY the
Agent Card interface URL to its TLS address. It does not change the Demo's
JSON-RPC implementation or the production Client's SSRF policy.
"""
import argparse
import http.client
import http.server
import json
import ssl
from urllib.parse import urlsplit

MAX_REQUEST_BYTES = 1_048_576
DEMO_HOST = "127.0.0.1"
DEMO_PORT = 3000


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        # No payload, credential or proxy headers in CI logs.
        pass

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        if urlsplit(self.path).path not in {"/.well-known/agent-card.json", "/a2a"}:
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if length < 0 or length > MAX_REQUEST_BYTES:
            self.send_error(413)
            return
        body = self.rfile.read(length) if length else b""
        headers = {"Host": f"{DEMO_HOST}:{DEMO_PORT}"}
        for name in ("Content-Type", "A2A-Version"):
            if self.headers.get(name):
                headers[name] = self.headers[name]

        connection = http.client.HTTPConnection(DEMO_HOST, DEMO_PORT, timeout=8)
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            upstream = connection.getresponse()
            payload = upstream.read(MAX_REQUEST_BYTES + 1)
            if len(payload) > MAX_REQUEST_BYTES:
                self.send_error(502)
                return

            if self.command == "GET" and self.path == "/.well-known/agent-card.json" and upstream.status == 200:
                card = json.loads(payload)
                for interface in card.get("supportedInterfaces", []):
                    if interface.get("protocolBinding") == "JSONRPC" and interface.get("protocolVersion") == "1.0":
                        interface["url"] = f"https://echo-agent.test:{self.server.server_port}/a2a"
                payload = json.dumps(card, separators=(",", ":")).encode("utf-8")

            self.send_response(upstream.status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, ValueError, json.JSONDecodeError):
            self.send_error(502)
        finally:
            connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--certificate", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--port", type=int, default=3443)
    args = parser.parse_args()

    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=args.certificate, keyfile=args.key)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    try:
        httpd.serve_forever(poll_interval=0.1)
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
