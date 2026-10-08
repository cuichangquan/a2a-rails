#!/usr/bin/env python3
"""Ephemeral, no-credentials A2A v1.0 echo for *controlled* Cloud Run testing.

Cloud Run terminates public HTTPS; the container listens on private HTTP.
No Agent Card rewrite, local resolver override, or test CA is used by Rails.
Never deploy this service permanently or with access to production systems.
"""
import os
import re
from urllib.parse import urlsplit

from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route

RPC_PATH = "/python/a2a/jsonrpc"
CARD_PATH = "/.well-known/agent-card.json"
MAX_BODY_BYTES = 16 * 1024
PROBE_PATTERN = re.compile(r"^(direct|task): public-egress-[0-9a-f]{24}$")
RUN_APP_HOST = re.compile(r"^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.run\.app$")


def configured_public_base():
    value = os.environ.get("A2A_PUBLIC_BASE_URL", "")
    if not value:
        return None  # Private bootstrap: /healthz only, NO advertised Agent.
    parsed = urlsplit(value)
    if not (
        parsed.scheme == "https"
        and parsed.hostname
        and RUN_APP_HOST.fullmatch(parsed.hostname)
        and parsed.username is None
        and parsed.password is None
        and parsed.port is None
        and parsed.path == ""
        and parsed.query == ""
        and parsed.fragment == ""
        and value == f"https://{parsed.hostname}"
    ):
        raise RuntimeError("A2A_PUBLIC_BASE_URL must be an exact https://*.run.app origin")
    return value


async def health(_request):
    return PlainTextResponse("ok")


class StrictProbeIngress:
    """Reject unexpected routes/methods and bound actual streamed RPC bytes."""

    def __init__(self, application):
        self.application = application

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.application(scope, receive, send)

        path = scope.get("path")
        method = scope.get("method")
        valid = (
            (path == "/healthz" and method == "GET")
            or (path == CARD_PATH and method == "GET")
            or (path == RPC_PATH and method == "POST")
        )
        if not valid:
            return await self.reject(send, 404)

        if path != RPC_PATH:
            return await self.application(scope, receive, send)

        headers = dict(scope.get("headers", []))
        length = headers.get(b"content-length", b"")
        if length:
            if len(length) > 9 or not length.isascii() or not length.isdigit():
                return await self.reject(send, 400)
            if int(length) > MAX_BODY_BYTES:
                return await self.reject(send, 413)
        if headers.get(b"content-encoding", b"identity").lower() != b"identity":
            return await self.reject(send, 415)
        if headers.get(b"content-type", b"").split(b";", 1)[0].strip().lower() != b"application/json":
            return await self.reject(send, 415)

        chunks = []
        size = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > MAX_BODY_BYTES:
                return await self.reject(send, 413)
            chunks.append(chunk)
            if not message.get("more_body", False):
                break

        emitted = False
        body = b"".join(chunks)

        async def replay_receive():
            nonlocal emitted
            if not emitted:
                emitted = True
                return {"type": "http.request", "body": body, "more_body": False}
            return {"type": "http.disconnect"}

        return await self.application(scope, replay_receive, send)

    @staticmethod
    async def reject(send, status):
        await send({"type": "http.response.start", "status": status,
                    "headers": [(b"content-length", b"0")]})
        await send({"type": "http.response.body", "body": b""})


def build_agent_app(base_url):
    # Delay SDK imports until AFTER a real Cloud Run URL is configured.
    # A private bootstrap instance is health-only, not a public Agent.
    from a2a.helpers import (
        new_task_from_user_message,
        new_text_artifact_update_event,
        new_text_message,
        new_text_status_update_event,
    )
    from a2a.server.agent_execution import AgentExecutor, RequestContext
    from a2a.server.events import EventQueue
    from a2a.server.request_handlers import DefaultRequestHandler
    from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
    from a2a.server.tasks import InMemoryTaskStore
    from a2a.types import (
        AgentCapabilities, AgentCard, AgentInterface, AgentSkill, Role, TaskState
    )

    class ControlledEchoExecutor(AgentExecutor):
        async def execute(self, context: RequestContext, event_queue: EventQueue):
            message = context.message
            text = " ".join(part.text for part in message.parts if part.text)
            if not PROBE_PATTERN.fullmatch(text):
                await event_queue.enqueue_event(
                    new_text_message("Unsupported controlled probe", role=Role.ROLE_AGENT)
                )
                return
            if text.startswith("direct:"):
                await event_queue.enqueue_event(
                    new_text_message("Python: " + text, role=Role.ROLE_AGENT)
                )
                return

            task = context.current_task or new_task_from_user_message(message)
            await event_queue.enqueue_event(task)
            await event_queue.enqueue_event(
                new_text_artifact_update_event(
                    task_id=task.id, context_id=task.context_id,
                    name="controlled-echo", text="Python: " + text
                )
            )
            await event_queue.enqueue_event(
                new_text_status_update_event(
                    task_id=task.id, context_id=task.context_id,
                    state=TaskState.TASK_STATE_COMPLETED, text="Done"
                )
            )

        async def cancel(self, context: RequestContext, event_queue: EventQueue):
            raise RuntimeError("Cancellation disabled on ephemeral public Echo Agent")

    card = AgentCard(
        name="Controlled Python SDK Echo",
        description="Temporary outbound Rails Client HTTPS interoperability probe",
        version="1.0.0",
        supported_interfaces=[
            AgentInterface(
                protocol_binding="JSONRPC",
                protocol_version="1.0",
                url=base_url + RPC_PATH,
            )
        ],
        capabilities=AgentCapabilities(streaming=False),
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain"],
        skills=[
            AgentSkill(
                id="controlled_echo", name="Controlled Echo",
                description="Direct Message and completed Task echo for approved tests",
                tags=["echo", "interop"],
            )
        ],
    )
    handler = DefaultRequestHandler(
        agent_executor=ControlledEchoExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=card,
    )
    application = Starlette(routes=[
        Route("/healthz", health),
        *create_agent_card_routes(card),
        *create_jsonrpc_routes(handler, rpc_url=RPC_PATH),
    ])
    return StrictProbeIngress(application)


base = configured_public_base()
app = build_agent_app(base) if base else StrictProbeIngress(
    Starlette(routes=[Route("/healthz", health)])
)
