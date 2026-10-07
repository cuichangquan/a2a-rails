"""Independent A2A Python SDK v1.2.2 client smoke against a Rails test SUT."""
import asyncio
import os
from uuid import uuid4

import httpx
from a2a.client import A2ACardResolver, ClientConfig, create_client
from a2a.types import (
    CancelTaskRequest, GetTaskRequest, ListTasksRequest,
    Message, Part, Role, SendMessageRequest, TaskState,
)

URL = os.environ.get("INTEROP_SUT_URL", "http://127.0.0.1:9998")


def check(condition, label):
    assert condition, label
    print(f"PASS Python: {label}")


async def run():
    async with httpx.AsyncClient(timeout=20) as http:
        card = await A2ACardResolver(http, URL).get_agent_card()
        check(card.name == "a2a-rails Interop Echo", "Agent Card discovery")
        check(any(i.protocol_binding == "JSONRPC" and i.protocol_version == "1.0"
                  for i in card.supported_interfaces), "JSONRPC A2A protocol 1.0 advertised")
        check(not card.capabilities.streaming, "Non-streaming declaration")

        client = await create_client(
            card,
            client_config=ClientConfig(
                streaming=False, httpx_client=http,
                supported_protocol_bindings=["JSONRPC"],
            ),
        )
        try:
            ctx = "python-step18-context"
            outgoing = Message(
                role=Role.ROLE_USER,
                message_id=str(uuid4()),
                context_id=ctx,
                parts=[Part(text="Hello Python")],
            )
            events = [ev async for ev in client.send_message(SendMessageRequest(message=outgoing))]
            check(len(events) == 1 and events[0].HasField("task"), "SendMessage returned Task")
            task = events[0].task
            check(task.status.state == TaskState.TASK_STATE_COMPLETED, "Completed Task")
            check(task.artifacts[0].parts[0].text == "Interop echo: Hello Python", "Text Artifact")

            fetched = await client.get_task(GetTaskRequest(id=task.id))
            check(fetched.id == task.id, "GetTask")
            listing = await client.list_tasks(ListTasksRequest(
                context_id=ctx, include_artifacts=True
            ))
            check(listing.total_size == 1 and len(listing.tasks) == 1
                  and listing.tasks[0].id == task.id, "Context-scoped ListTasks")
            check(listing.tasks[0].artifacts[0].parts[0].text == "Interop echo: Hello Python",
                  "ListTasks with Artifacts")

            direct = Message(
                role=Role.ROLE_USER,
                message_id="interop-direct-" + str(uuid4()),
                context_id=ctx,
                parts=[Part(text="Hello direct Python")],
            )
            replies = [ev async for ev in client.send_message(SendMessageRequest(message=direct))]
            check(len(replies) == 1 and replies[0].HasField("message"), "SendMessage direct Message")
            reply = replies[0].message
            check(reply.role == Role.ROLE_AGENT and bool(reply.message_id), "Direct Message identity")
            check(reply.parts[0].text == "Interop echo: Hello direct Python", "Direct Message TextPart")
            remaining = await client.list_tasks(ListTasksRequest(context_id=ctx))
            check(remaining.total_size == 1, "Direct reply creates no Task")

            # Synchronous completion makes CancelTask correctly reject a terminal Task.
            try:
                await client.cancel_task(CancelTaskRequest(id=task.id))
            except Exception as exc:
                check("not cancelable" in str(exc).lower() or "-32002" in str(exc),
                      "Terminal CancelTask expected protocol error")
            else:
                raise AssertionError("CancelTask unexpectedly succeeded for completed Task")

            # Negative version check complements official SDK positive calls.
            response = await http.post(
                URL + "/a2a",
                json={"jsonrpc": "2.0", "id": "v", "method": "ListTasks", "params": {}},
                headers={"A2A-Version": "0.3", "Content-Type": "application/json"},
            )
            check(response.status_code == 200 and response.json().get("error", {}).get("code") == -32009,
                  "A2A-Version 0.3 rejected (-32009)")
            print("Python SDK 1.2.2 interoperability PASS")
        finally:
            await client.close()


if __name__ == "__main__":
    asyncio.run(run())
