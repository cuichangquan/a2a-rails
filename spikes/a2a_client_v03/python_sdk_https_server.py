#!/usr/bin/env python3
"""Independent official Python A2A SDK v1.0 server for outbound Rails Client CI.

Native local HTTPS, with ORIGINAL Agent Card advertising that very HTTPS
endpoint. No Rails Gem, TLS bridge or modified Agent Card is involved.
Loopback-only and NEVER intended for public deployment.
"""
import argparse

import uvicorn
from google.protobuf.json_format import ParseDict
from google.protobuf.struct_pb2 import Value
from starlette.applications import Starlette

from a2a.helpers import (
    new_artifact,
    new_message,
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
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
    Part,
    TaskArtifactUpdateEvent,
    Role,
    TaskState,
)

RPC_PATH = "/python/a2a/jsonrpc"
AGENT_HOST = "python-agent.test"


class PythonEchoExecutor(AgentExecutor):
    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        message = context.message
        text = " ".join(part.text for part in message.parts if part.text)
        if text.startswith("rich:"):
            # Construct genuine SDK/Protobuf Parts. Opaque nested Data and
            # Message metadata are not constructed by the Rails Client.
            parts = [
                Part(text="Python: rich official SDK reply"),
                Part(data=ParseDict({
                    "businessId": "python-123",
                    "nested": {"keepCamelCase": [True, 0, None]},
                }, Value())),
                Part(raw=b"python-bytes", media_type="text/plain", filename="python.txt"),
                Part(url="https://files.example/python.pdf",
                     media_type="application/pdf", filename="python.pdf"),
            ]
            reply = new_message(parts=parts, role=Role.ROLE_AGENT)
            reply.metadata.update({"interopTest": "python", "nestedValue": {
                "keepCamelCase": True
            }})
            await event_queue.enqueue_event(reply)
            return

        if text.startswith("direct:"):
            await event_queue.enqueue_event(
                new_text_message("Python: " + text, role=Role.ROLE_AGENT)
            )
            return

        task = context.current_task or new_task_from_user_message(message)
        await event_queue.enqueue_event(task)
        if text.startswith("input-required:"):
            await event_queue.enqueue_event(
                new_text_status_update_event(
                    task_id=task.id,
                    context_id=task.context_id,
                    state=TaskState.TASK_STATE_INPUT_REQUIRED,
                    text="Python needs more input",
                )
            )
            return

        if text.startswith("rich-task:"):
            artifact = new_artifact(
                parts=[
                    Part(text="Python: rich task artifact"),
                    Part(data=ParseDict({
                        "businessId": "python-task-123",
                        "nested": {"keepCamelCase": True},
                    }, Value())),
                    Part(raw=b"task-bytes", media_type="text/plain", filename="task.txt"),
                ],
                name="python-rich",
            )
            await event_queue.enqueue_event(
                TaskArtifactUpdateEvent(
                    task_id=task.id, context_id=task.context_id, artifact=artifact
                )
            )
        else:
            await event_queue.enqueue_event(
                new_text_artifact_update_event(
                task_id=task.id,
                context_id=task.context_id,
                name="python-echo",
                    text="Python: " + text,
                )
            )
        await event_queue.enqueue_event(
            new_text_status_update_event(
                task_id=task.id,
                context_id=task.context_id,
                state=TaskState.TASK_STATE_COMPLETED,
                text="Done",
            )
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        task = context.current_task
        if task is None:
            raise RuntimeError("No current task for cancellation")
        await event_queue.enqueue_event(
            new_text_status_update_event(
                task_id=task.id,
                context_id=task.context_id,
                state=TaskState.TASK_STATE_CANCELED,
                text="Canceled by official Python SDK",
            )
        )


def build_app(port: int):
    card = AgentCard(
        name="Official Python SDK Echo",
        description="Outbound Rails Client official Python A2A SDK v1 smoke",
        version="1.0.0",
        supported_interfaces=[
            AgentInterface(
                protocol_binding="JSONRPC",
                protocol_version="1.0",
                url=f"https://{AGENT_HOST}:{port}{RPC_PATH}",
            )
        ],
        capabilities=AgentCapabilities(streaming=False),
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain"],
        skills=[
            AgentSkill(
                id="python_echo",
                name="Python Echo",
                description="Echo a text request",
                tags=["echo", "interop"],
            )
        ],
    )
    request_handler = DefaultRequestHandler(
        agent_executor=PythonEchoExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=card,
    )
    return Starlette(
        routes=[
            *create_agent_card_routes(card),
            *create_jsonrpc_routes(request_handler, rpc_url=RPC_PATH),
        ]
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--certificate", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--port", type=int, default=3444)
    args = parser.parse_args()
    uvicorn.run(
        build_app(args.port),
        host="127.0.0.1",
        port=args.port,
        ssl_certfile=args.certificate,
        ssl_keyfile=args.key,
        access_log=False,
        log_level="warning",
    )


if __name__ == "__main__":
    main()
