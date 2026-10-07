// Official a2a-go/v2 v2.6.0, real client-side interoperability smoke.
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "net/http"
    "os"
    "time"

    "github.com/a2aproject/a2a-go/v2/a2a"
    "github.com/a2aproject/a2a-go/v2/a2aclient"
    "github.com/a2aproject/a2a-go/v2/a2aclient/agentcard"
)

func check(ok bool, label string) {
    if !ok { panic("FAIL Go: " + label) }
    fmt.Println("PASS Go:", label)
}

type versionTransport struct {
    base http.RoundTripper
    count int
}

func (v *versionTransport) RoundTrip(req *http.Request) (*http.Response, error) {
    if req.URL.Path == "/a2a" {
        if req.Header.Get("A2A-Version") != "1.0" {
            return nil, fmt.Errorf("official SDK did not send A2A-Version: 1.0")
        }
        v.count++
    }
    return v.base.RoundTrip(req)
}

func run() error {
    url := os.Getenv("INTEROP_SUT_URL")
    if url == "" { url = "http://127.0.0.1:9998" }
    ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
    defer cancel()

    card, err := agentcard.DefaultResolver.Resolve(ctx, url)
    if err != nil { return fmt.Errorf("card: %w", err) }
    check(card.Name == "a2a-rails Interop Echo", "Agent Card discovery")
    check(len(card.SupportedInterfaces) == 1 &&
        card.SupportedInterfaces[0].ProtocolBinding == a2a.TransportProtocolJSONRPC &&
        string(card.SupportedInterfaces[0].ProtocolVersion) == "1.0", "JSONRPC A2A 1.0")
    check(!card.Capabilities.Streaming, "Non-streaming Agent Card")

    tracked := &versionTransport{base: http.DefaultTransport}
    httpClient := &http.Client{Timeout: 20 * time.Second, Transport: tracked}
    client, err := a2aclient.NewFromCard(ctx, card, a2aclient.WithJSONRPCTransport(httpClient))
    if err != nil { return fmt.Errorf("create client: %w", err) }
    defer func() { _ = client.Destroy() }()

    contextID := "go-step18-context"
    outgoing := a2a.NewMessage(a2a.MessageRoleUser, a2a.NewTextPart("Hello Go"))
    outgoing.ContextID = contextID
    result, err := client.SendMessage(ctx, &a2a.SendMessageRequest{Message: outgoing})
    if err != nil { return fmt.Errorf("send: %w", err) }
    task, ok := result.(*a2a.Task)
    check(ok, "SendMessage returned Task")
    check(task.Status.State == a2a.TaskStateCompleted, "Completed Task")
    check(len(task.Artifacts) == 1 && len(task.Artifacts[0].Parts) == 1 &&
        task.Artifacts[0].Parts[0].Text() == "Interop echo: Hello Go", "Text Artifact")

    fetched, err := client.GetTask(ctx, &a2a.GetTaskRequest{ID: task.ID})
    if err != nil { return fmt.Errorf("get task: %w", err) }
    check(fetched.ID == task.ID, "GetTask")
    listed, err := client.ListTasks(ctx, &a2a.ListTasksRequest{
        ContextID: contextID, IncludeArtifacts: true,
    })
    if err != nil { return fmt.Errorf("list tasks: %w", err) }
    check(listed.TotalSize == 1 && len(listed.Tasks) == 1 &&
        listed.Tasks[0].ID == task.ID, "Context-scoped ListTasks")
    check(len(listed.Tasks[0].Artifacts) == 1 &&
        listed.Tasks[0].Artifacts[0].Parts[0].Text() == "Interop echo: Hello Go",
        "ListTasks with Artifacts")

    direct := a2a.NewMessage(a2a.MessageRoleUser, a2a.NewTextPart("Hello direct Go"))
    direct.ID = "interop-direct-" + direct.ID
    direct.ContextID = contextID
    directResult, err := client.SendMessage(ctx, &a2a.SendMessageRequest{Message: direct})
    if err != nil { return fmt.Errorf("direct: %w", err) }
    reply, ok := directResult.(*a2a.Message)
    check(ok, "SendMessage returned direct Message")
    check(reply.Role == a2a.MessageRoleAgent && reply.ID != "", "Direct Message identity")
    check(len(reply.Parts) == 1 &&
        reply.Parts[0].Text() == "Interop echo: Hello direct Go", "Direct Message TextPart")
    after, err := client.ListTasks(ctx, &a2a.ListTasksRequest{ContextID: contextID})
    if err != nil { return fmt.Errorf("list after direct: %w", err) }
    check(after.TotalSize == 1, "Direct reply creates no Task")

    _, err = client.CancelTask(ctx, &a2a.CancelTaskRequest{ID: task.ID})
    check(errors.Is(err, a2a.ErrTaskNotCancelable), "Terminal CancelTask error (-32002)")
    check(tracked.count >= 6, "Official Go SDK sends A2A-Version: 1.0")

    // Raw negative-version check, distinct from the official SDK positive path.
    req, err := http.NewRequestWithContext(ctx, http.MethodPost, url+"/a2a",
        bytes.NewBufferString("{\"jsonrpc\":\"2.0\",\"id\":\"v\",\"method\":\"ListTasks\",\"params\":{}}"))
    if err != nil { return err }
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("A2A-Version", "0.3")
    response, err := http.DefaultClient.Do(req)
    if err != nil { return err }
    defer func() { _ = response.Body.Close() }()
    var raw map[string]json.RawMessage
    if err := json.NewDecoder(response.Body).Decode(&raw); err != nil { return err }
    var rpcErr struct { Code int }
    if err := json.Unmarshal(raw["error"], &rpcErr); err != nil { return err }
    check(response.StatusCode == 200 && rpcErr.Code == -32009, "A2A-Version 0.3 rejected (-32009)")
    fmt.Println("Go SDK v2.6.0 interoperability PASS")
    return nil
}

func main() {
    if err := run(); err != nil { panic(err) }
}
