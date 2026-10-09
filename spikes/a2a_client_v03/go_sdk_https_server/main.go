package main

// Step 29-5b: independent OFFICIAL a2a-go/v2 JSON-RPC server over native
// loopback HTTPS, with an unmodified Agent Card advertising that HTTPS URL.
// Never bind outside loopback or deploy as a public agent.
import (
    "context"
    "flag"
    "fmt"
    "iter"
    "log"
    "net/http"
    "strings"

    "github.com/a2aproject/a2a-go/v2/a2a"
    "github.com/a2aproject/a2a-go/v2/a2asrv"
)

const rpcPath = "/go/agent/jsonrpc"

// Test-only authentication through the official a2asrv CallInterceptor API.
// The SDK's *default* Task Store uses CallContext.User.Name as its owner;
// ListTasks intentionally returns -31401 when no authenticated user is set.
// No authentication bypass or modified JSON-RPC/Task Store handler is used.
type testBearerInterceptor struct {
    a2asrv.PassthroughCallInterceptor
}

func (testBearerInterceptor) Before(ctx context.Context, callCtx *a2asrv.CallContext, _ *a2asrv.Request) (context.Context, any, error) {
    values, ok := callCtx.ServiceParams().Get("authorization")
    if !ok || len(values) != 1 {
        return ctx, nil, a2a.ErrUnauthenticated
    }
    var user string
    switch values[0] {
    case "Bearer go-test-tenant-a-token":
        user = "go-test-tenant-a"
    case "Bearer go-test-tenant-b-token":
        user = "go-test-tenant-b"
    default:
        return ctx, nil, a2a.ErrUnauthenticated
    }
    callCtx.User = a2asrv.NewAuthenticatedUser(user, nil)
    return ctx, nil, nil
}

type echoExecutor struct {}

func (e *echoExecutor) Execute(_ context.Context, ec *a2asrv.ExecutorContext) iter.Seq2[a2a.Event, error] {
    return func(yield func(a2a.Event, error) bool) {
        text := ""
        if ec.Message != nil && len(ec.Message.Parts) > 0 {
            text = ec.Message.Parts[0].Text()
        }

        if strings.HasPrefix(text, "rich:") {
            richData := a2a.NewDataPart(map[string]any{
                "businessId": "go-123",
                "nested": map[string]any{"keepCamelCase": []any{true, float64(0), nil}},
            })
            richData.SetMeta("caseSensitive", "go")
            message := a2a.NewMessage(a2a.MessageRoleAgent,
                a2a.NewTextPart("Go: rich official SDK reply"),
                richData,
                a2a.NewRawPart([]byte("go-bytes")),
                a2a.NewFileURLPart(a2a.URL("https://files.example/go.pdf"), "application/pdf"),
            )
            message.SetMeta("interopTest", "go")
            yield(message, nil)
            return
        }

        if strings.HasPrefix(text, "task:") || strings.HasPrefix(text, "rich-task:") ||
            strings.HasPrefix(text, "input-required:") {
            if !yield(a2a.NewSubmittedTask(ec, ec.Message), nil) {
                return
            }
            if strings.HasPrefix(text, "input-required:") {
                yield(a2a.NewStatusUpdateEvent(ec, a2a.TaskStateInputRequired,
                    a2a.NewMessageForTask(a2a.MessageRoleAgent, ec, a2a.NewTextPart("Go needs more input"))), nil)
                return
            }
            if !yield(a2a.NewArtifactEvent(ec,
                a2a.NewTextPart("Go: official task artifact"),
                a2a.NewDataPart(map[string]any{"businessId": "go-task-123",
                    "nested": map[string]any{"keepCamelCase": true}}),
                a2a.NewRawPart([]byte("go-task-bytes"))), nil) {
                return
            }
            yield(a2a.NewStatusUpdateEvent(ec, a2a.TaskStateCompleted, nil), nil)
            return
        }

        yield(a2a.NewMessage(a2a.MessageRoleAgent, a2a.NewTextPart("Go: hello from official SDK")), nil)
    }
}

func (e *echoExecutor) Cancel(_ context.Context, ec *a2asrv.ExecutorContext) iter.Seq2[a2a.Event, error] {
    return func(yield func(a2a.Event, error) bool) {
        yield(a2a.NewStatusUpdateEvent(ec, a2a.TaskStateCanceled, nil), nil)
    }
}

func main() {
    cert := flag.String("certificate", "", "test-only TLS certificate")
    key := flag.String("key", "", "test-only TLS key")
    port := flag.Int("port", 3445, "loopback TLS port")
    flag.Parse()
    if *cert == "" || *key == "" {
        log.Fatal("a short-lived local test TLS cert/key is required")
    }
    endpoint := fmt.Sprintf("https://go-agent.test:%d%s", *port, rpcPath)
    card := &a2a.AgentCard{
        Name: "Official Go SDK Echo",
        Description: "Outbound Rails Client official Go A2A SDK v1 smoke",
        Version: "1.0.0",
        SupportedInterfaces: []*a2a.AgentInterface{
            a2a.NewAgentInterface(endpoint, a2a.TransportProtocolJSONRPC),
        },
        Capabilities: a2a.AgentCapabilities{Streaming: false},
        SecuritySchemes: a2a.NamedSecuritySchemes{
            "interopBearer": a2a.HTTPAuthSecurityScheme{
                Scheme: "Bearer", BearerFormat: "opaque",
                Description: "Test-only scoped bearer for official SDK interop",
            },
        },
        SecurityRequirements: a2a.SecurityRequirementsOptions{
            a2a.SecurityRequirements{"interopBearer": a2a.SecuritySchemeScopes{}},
        },
        DefaultInputModes: []string{"text/plain"},
        DefaultOutputModes: []string{"text/plain"},
        Skills: []a2a.AgentSkill{
            {ID: "go_echo", Name: "Go Echo", Description: "Return a direct A2A Message", Tags: []string{"echo", "interop"}},
        },
    }
    // The official default InMemory Task Store uses
    // a2asrv.NewTaskStoreAuthenticator() to scope tasks by CallContext.User.
    handler := a2asrv.NewHandler(&echoExecutor{},
        a2asrv.WithCallInterceptors(testBearerInterceptor{}))
    mux := http.NewServeMux()
    mux.Handle(a2asrv.WellKnownAgentCardPath, a2asrv.NewStaticAgentCardHandler(card))
    mux.Handle(rpcPath, a2asrv.NewJSONRPCHandler(handler))
    server := &http.Server{
        Addr: fmt.Sprintf("127.0.0.1:%d", *port),
        Handler: mux,
        ReadHeaderTimeout: 5 * 1000000000, // nanoseconds, 5 sec
    }
    log.Fatal(server.ListenAndServeTLS(*cert, *key))
}
