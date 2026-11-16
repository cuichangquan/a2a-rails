"""Independent A2A Python SDK v1.2.2 client smoke against a Rails test SUT."""
import asyncio
import os
from uuid import uuid4

import httpx
from google.protobuf.json_format import MessageToDict, ParseDict
from a2a.client import A2ACardResolver, ClientConfig, create_client
from a2a.utils.errors import InvalidParamsError, UnsupportedOperationError
from a2a.types import (
    CancelTaskRequest, GetTaskRequest, ListTasksRequest,
    Message, Part, Role, SendMessageRequest, SendMessageConfiguration, TaskState,
)

URL = os.environ.get("INTEROP_SUT_URL", "http://127.0.0.1:9998")


def check(condition, label):
    assert condition, label
    print(f"PASS Python: {label}")


async def continuation_checks(client):
    async def send(parts, task_id=None, context_id=None, message_id=None):
        args = dict(role=Role.ROLE_USER, message_id=message_id or str(uuid4()), parts=parts)
        if task_id is not None:
            args["task_id"] = task_id
        if context_id is not None:
            args["context_id"] = context_id
        events = [ev async for ev in client.send_message(SendMessageRequest(
            message=Message(**args),
            configuration=SendMessageConfiguration(history_length=0),
        ))]
        check(len(events) == 1 and events[0].HasField("task"), "Continuation returns Task")
        task = events[0].task
        check(len(task.history) == 0, "historyLength zero omits response history")
        return task

    initial = ParseDict({"data": {"interop_continuation": True, "year": 2026, "month": 10}}, Part())
    waiting = await send([initial])
    check(waiting.status.state == TaskState.TASK_STATE_INPUT_REQUIRED,
          "Data request pauses in INPUT_REQUIRED")
    question = waiting.status.message
    check(question.role == Role.ROLE_AGENT and bool(question.message_id)
          and question.task_id == waiting.id and question.context_id == waiting.context_id,
          "Question has agent Message identity and original task/context")
    check(any(part.text == "Which department?" for part in question.parts), "Question text decoded")
    question_data = next(MessageToDict(p)["data"] for p in question.parts if p.HasField("data"))
    check(question_data == {"required": "department_id", "flag": False, "nil": None,
                            "messageId": "business-camel", "message_id": "business-snake",
                            "empty": {}, "nested": [[False, None], {}]},
          "Question Data preserves keys, false, null, empty object and nested arrays")
    fetched = await client.get_task(GetTaskRequest(id=waiting.id, history_length=0))
    check(fetched.status.state == TaskState.TASK_STATE_INPUT_REQUIRED and not fetched.history,
          "GetTask returns waiting state without history")
    listing = await client.list_tasks(ListTasksRequest(context_id=waiting.context_id))
    check(any(t.id == waiting.id and t.status.state == TaskState.TASK_STATE_INPUT_REQUIRED
              for t in listing.tasks), "ListTasks includes waiting Task")

    try:
        await send([ParseDict({"data": {"department_id": 123}}, Part())],
                   task_id=waiting.id, context_id="different-context")
    except InvalidParamsError:
        check(True, "Mismatching context rejected by official SDK error type")
    else:
        raise AssertionError("Mismatching context unexpectedly accepted")

    # taskId alone is the protocol-defined continuation, not a new Task request.
    incomplete_id = str(uuid4())
    again = await send([ParseDict({"data": {}}, Part())], task_id=waiting.id, message_id=incomplete_id)
    check(again.id == waiting.id and again.context_id == waiting.context_id
          and again.status.state == TaskState.TASK_STATE_INPUT_REQUIRED,
          "Incomplete taskId-only answer asks again on same Task")
    completed = await send([ParseDict({"data": {"department_id": 123}}, Part())], task_id=waiting.id)
    check(completed.id == waiting.id and completed.context_id == waiting.context_id
          and completed.status.state == TaskState.TASK_STATE_COMPLETED,
          "Data answer completes same Task with inferred context")
    result = MessageToDict(completed.artifacts[0].parts[0])["data"]
    check(result == {"year": 2026, "month": 10, "department_id": 123, "count": 3, "total": 35000},
          "Application combines original and current inputs despite omitted response history")
    retained = await client.get_task(GetTaskRequest(id=waiting.id))
    check(len(retained.history) == 5, "Original request, two questions and two answers retained")

    replay = await send([ParseDict({"data": {}}, Part())], task_id=waiting.id, message_id=incomplete_id)
    check(replay.id == waiting.id and replay.status.state == TaskState.TASK_STATE_COMPLETED,
          "Earlier accepted messageId replay returns current Task without restarting")
    unchanged = await client.get_task(GetTaskRequest(id=waiting.id))
    check(len(unchanged.history) == len(retained.history), "Replay does not duplicate history")
    try:
        await send([ParseDict({"data": {"department_id": 123}}, Part())], task_id=waiting.id)
    except UnsupportedOperationError:
        check(True, "New answer to completed Task rejected as UnsupportedOperationError")
    else:
        raise AssertionError("New answer to completed Task unexpectedly accepted")

    text_wait = await send([Part(text="interop-question")])
    check(text_wait.status.state == TaskState.TASK_STATE_INPUT_REQUIRED, "Text request asks question")
    text_done = await send([Part(text="Ada")], task_id=text_wait.id, context_id=text_wait.context_id)
    check(text_done.id == text_wait.id and text_done.status.state == TaskState.TASK_STATE_COMPLETED
          and text_done.artifacts[0].parts[0].text == "Hello Ada", "Text answer completes original Task")
    cancel_wait = await send([Part(text="interop-question")])
    canceled = await client.cancel_task(CancelTaskRequest(id=cancel_wait.id))
    check(canceled.id == cancel_wait.id and canceled.status.state == TaskState.TASK_STATE_CANCELED,
          "Input-required Task can be canceled with official SDK")


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
            await continuation_checks(client)
            print("Python SDK 1.2.2 interoperability PASS")
        finally:
            await client.close()


if __name__ == "__main__":
    asyncio.run(run())
