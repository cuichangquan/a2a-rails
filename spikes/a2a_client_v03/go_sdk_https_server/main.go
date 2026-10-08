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

    "github.com/a2aproject/a2a-go/v2/a2a"
    "github.com/a2aproject/a2a-go/v2/a2asrv"
)

const rpcPath = "/go/agent/jsonrpc"

type echoExecutor struct {}

func (e *echoExecutor) Execute(_ context.Context, _ *a2asrv.ExecutorContext) iter.Seq2[a2a.Event, error] {
    return func(yield func(a2a.Event, error) bool) {
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
        DefaultInputModes: []string{"text/plain"},
        DefaultOutputModes: []string{"text/plain"},
        Skills: []a2a.AgentSkill{
            {ID: "go_echo", Name: "Go Echo", Description: "Return a direct A2A Message", Tags: []string{"echo", "interop"}},
        },
    }
    handler := a2asrv.NewHandler(&echoExecutor{})
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
