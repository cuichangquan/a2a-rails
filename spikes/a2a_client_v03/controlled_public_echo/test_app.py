#!/usr/bin/env python3
"""Local-only contract checks. Never contacts a public deployment."""
import importlib
import os
import unittest
from unittest.mock import patch

from starlette.testclient import TestClient

import app as cloud_agent


class ControlledCloudEchoTest(unittest.TestCase):
    def configured_app(self, base):
        with patch.dict(os.environ, {"A2A_PUBLIC_BASE_URL": base} if base else {},
                        clear=False):
            if not base:
                os.environ.pop("A2A_PUBLIC_BASE_URL", None)
            module = importlib.reload(cloud_agent)
        return module.app

    def test_bootstrap_exposes_only_health(self):
        with TestClient(self.configured_app(None)) as client:
            self.assertEqual(200, client.get("/healthz").status_code)
            self.assertEqual(404, client.get("/.well-known/agent-card.json").status_code)
            self.assertEqual(404, client.post("/python/a2a/jsonrpc", json={}).status_code)

    def test_rejects_non_public_or_ambiguous_advertised_origins(self):
        for url in [
            "http://fake.a.run.app", "https://localhost",
            "https://fake.a.run.app:8443", "https://fake.a.run.app/path",
            "https://user:pass@fake.a.run.app",
            "https://fake.a.run.app?token=secret",
            "https://not-runapp.example",
        ]:
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                self.configured_app(url)

    def test_original_card_and_both_rpc_responses(self):
        origin = "https://approved-echo.a.run.app"
        with TestClient(self.configured_app(origin)) as client:
            card_response = client.get("/.well-known/agent-card.json")
            self.assertEqual(200, card_response.status_code)
            card = card_response.json()
            interfaces = card["supportedInterfaces"]
            self.assertEqual(
                origin + "/python/a2a/jsonrpc",
                interfaces[0]["url"],
            )
            self.assertEqual("JSONRPC", interfaces[0]["protocolBinding"])
            self.assertEqual("1.0", interfaces[0]["protocolVersion"])
            nonce = "0123456789abcdef01234567"
            def request(request_id, text, method="SendMessage"):
                return {
                    "jsonrpc": "2.0", "id": request_id, "method": method,
                    "params": {
                        "message": {
                            "messageId": request_id,
                            "role": "ROLE_USER",
                            "parts": [{"text": text}],
                        }
                    },
                }
            direct = client.post(
                "/python/a2a/jsonrpc",
                json=request("direct-1", "direct: public-egress-" + nonce),
                headers={"A2A-Version": "1.0"},
            )
            self.assertEqual(200, direct.status_code)
            result = direct.json()["result"]
            self.assertIn(nonce, result["message"]["parts"][0]["text"])
            self.assertNotIn("task", result)

            task_response = client.post(
                "/python/a2a/jsonrpc",
                json=request("task-1", "task: public-egress-" + nonce),
                headers={"A2A-Version": "1.0"},
            )
            self.assertEqual(200, task_response.status_code)
            task = task_response.json()["result"]["task"]
            self.assertEqual("TASK_STATE_COMPLETED", task["status"]["state"])
            self.assertIn(nonce, task["artifacts"][0]["parts"][0]["text"])

            fetched = client.post(
                "/python/a2a/jsonrpc",
                json={"jsonrpc": "2.0", "id": "get-1",
                      "method": "GetTask", "params": {"id": task["id"]}},
                headers={"A2A-Version": "1.0"},
            )
            self.assertEqual(200, fetched.status_code)
            self.assertEqual(task["id"], fetched.json()["result"]["id"])

            self.assertEqual(404, client.get("/unexpected").status_code)
            self.assertEqual(
                413,
                client.post("/python/a2a/jsonrpc",
                            content=b"x" * 16385,
                            headers={"Content-Type": "application/json"}).status_code,
            )
            self.assertEqual(
                415,
                client.post("/python/a2a/jsonrpc", content=b"{}",
                            headers={"Content-Type": "application/json",
                                     "Content-Encoding": "gzip"}).status_code,
            )


if __name__ == "__main__":
    unittest.main()
