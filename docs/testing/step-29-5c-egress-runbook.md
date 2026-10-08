# Step 29-5c — controlled public egress execution runbook

This is a **manual, protected** probe. Merging its workflow does not establish passing public HTTPS evidence. The release gate remains **NO-GO** until the documented run succeeds and the remaining security checks are reviewed.

## Operator prerequisites

1. Provision an A2A JSON-RPC v1.0 echo Agent **owned or expressly approved** by the project. The Agent must publish its **original unmodified** Agent Card and selected HTTPS interface, using a public IPv4 A record and a real public CA certificate. Do not choose an arbitrary reachable third-party Agent.
2. Provision a dedicated GitHub Actions **self-hosted** runner with both `self-hosted` and `a2a-public-egress` labels. Enforce a network egress firewall permitting only explicitly approved DNS resolution and target IPs/ports. Isolate runner execution and remove all unrelated credentials.
3. Configure a protected GitHub Actions environment named `a2a-public-egress`, restricted to the `main` branch with required reviewer approval. Configure these **environment variables**, not user-provided dispatch inputs:
   - `A2A_PUBLIC_EGRESS_APPROVED` = `controlled-endpoint-no-auth`
   - `A2A_PUBLIC_CARD_URL` = exact owned Card HTTPS URL
   - `A2A_PUBLIC_EXPECTED_RPC_URL` = exact original Card-advertised JSON-RPC HTTPS URL
   - `A2A_PUBLIC_ALLOWED_ORIGINS` = comma-separated exact HTTPS Card/RPC origins
4. The positive probe intentionally sends **no tokens**. If authentication is required, deploy a restricted no-auth echo test Agent rather than storing production tokens or weakening the probe.
5. Dispatch [the protected workflow](../../.github/workflows/a2a-outbound-public-egress.yml) on **main**, after the PR is reviewed and merged. Do not enable automatic PR/push public egress execution.

## Observable evidence and limitations

- The test script invokes `A2A::Rails::Client.new` without any internal test seam, proxy, test CA, DNS override, or Agent Card rewrite. It reads the Card, validates the original selected JSON-RPC interface against the configured expected endpoint, and sends a distinct Message ID. Direct Message or Task + GetTask must succeed.
- Collect a dated run link, commit SHA, **real DNS answers**, IP selected at socket connect (from trusted network diagnostics/packet capture), validated certificate chain + SNI, declared Card/RPC URLs and application output. **Do not** include tokens, private keys, request Parts or untrusted response bodies in logs or issue comments.
- The workflow's syntax job runs on pull requests; its real public egress job requires a deliberate dispatch on `main`, environment approval, and a self-hosted runner.
- This smoke validates only the configured no-auth server's basic operations. It does **not** by itself fulfill SSRF/TLS failure injection, auth callback isolation, concurrency, bounded I/O, full Python/Go Task semantics, or package compatibility matrices.

## Gate disposition

If no approved endpoint, public CA, protected environment, dedicated egress-filtered runner and evidence are available: **NOT RUN / NO-GO**. Never substitute a loopback/self-signed result and label it a public egress PASS.

The separately identified total-deadline gap (DNS lookup and credential callback occur before the current transport deadline) must be fixed and regression-tested before release.
