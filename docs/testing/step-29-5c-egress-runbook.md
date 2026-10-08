# Step 29-5c — controlled public egress execution runbook

**Controlled Echo server deployment:** [Cloud Run private-first deploy / temporary public access / teardown](step-29-5c-cloud-run-echo-deployment.md). A private Cloud Run Echo has been deployed and its authenticated Rails Client interoperability smoke passed (2026-10-08, documented on [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90)); **the public unauthenticated test has not been performed**. Follow the [Step 29-5e readiness gate](step-29-5e-public-window-readiness.md) before any change to public access.

This is a **manual, protected** probe. Merging its workflow does not establish passing public HTTPS evidence. The release gate remains **NO-GO** until the documented run succeeds and the remaining security checks are reviewed.

## Operator prerequisites

1. Provision an A2A JSON-RPC v1.0 **echo Agent owned or expressly approved** by the project. Use a public IPv4 A record and genuine publicly trusted CA certificate at the original, unmodified Agent Card and advertised interface HTTPS URLs. The Agent must support **both** direct response to a text Part prefixed `direct:` and a completed Task with text Artifact for a Part prefixed `task:`; both replies must contain the unique input nonce. The Python/Go servers under `spikes/a2a_client_v03/` are **loopback-only CI fixtures with hard-coded `.test` hostnames**, not public deployment examples; do not expose them unchanged. Do not choose an arbitrary third-party Agent.
2. Provision a dedicated GitHub Actions **self-hosted** runner with both `self-hosted` and `a2a-public-egress` labels. Enforce a network egress firewall permitting only explicitly approved DNS resolution and target IPs/ports. Isolate runner execution and remove all unrelated credentials.
3. Configure a protected GitHub Actions environment named `a2a-public-egress`, restricted to the `main` branch with required reviewer approval. Configure these **environment variables**, not user-provided dispatch inputs:
   - `A2A_PUBLIC_EGRESS_APPROVED` = `controlled-endpoint-no-auth`
   - `A2A_PUBLIC_CARD_URL` = exact owned Card HTTPS URL
   - `A2A_PUBLIC_EXPECTED_RPC_URL` = exact original Card-advertised JSON-RPC HTTPS URL
   - `A2A_PUBLIC_ALLOWED_ORIGINS` = comma-separated exact HTTPS Card/RPC origins
4. The positive probe intentionally sends **no tokens**. If authentication is required, deploy a restricted no-auth echo test Agent rather than storing production tokens or weakening the probe.
5. Dispatch [the protected workflow](../../.github/workflows/a2a-outbound-public-egress.yml) on **main**, after the PR is reviewed and merged. Do not enable automatic PR/push public egress execution.

## Observable evidence and limitations

- The workflow first executes `spikes/a2a_client_v03/public_https_preflight.rb`: normal exact-origin policy and real public DNS resolve, an IPv4 socket pinned to the approved resolved address, TLS SNI and peer hostname check with **system public CA trust**. It prints only approved origin, connected IP, sanitized certificate issuer, expiry and certificate SHA256 fingerprint. This preflight is **a distinct socket**, not evidence of which socket address the Rails Client subsequently dialed.
- The smoke then invokes the unchanged `A2A::Rails::Client.new` without any test seam, proxy, custom test CA, DNS override or Card rewrite. It checks the original JSON-RPC interface URL and requires **both** direct Message echo and Task + GetTask + Artifact echo of a unique nonce. A partial response is a failed test, not PASS.
- Collect a dated GitHub Actions run link, commit SHA, **actual DNS answers**, publicly trusted TLS issuer/fingerprint/expiry, configured Card/RPC URLs and PASS/FAIL lines. Collect the **actual Rails Client dialed IP** separately from the dedicated runner's network trace or egress firewall logs. The preflight prints only its own independently connected IP; do not conflate the two. **Do not** log tokens, private keys, request Parts, nonce values or untrusted remote responses.
- The workflow's syntax job runs on pull requests; its real public egress job requires a deliberate dispatch on `main`, environment approval, and a self-hosted runner.
- This smoke validates only the configured no-auth server's basic operations. It does **not** by itself fulfill SSRF/TLS failure injection, auth callback isolation, concurrency, bounded I/O, full Python/Go Task semantics, or package compatibility matrices.

## Gate disposition

If no approved endpoint, public CA, protected environment, dedicated egress-filtered runner and evidence are available: **NOT RUN / NO-GO**. Never substitute a loopback/self-signed result and label it a public egress PASS.

The total-deadline / DNS credential callback and exception-cause corrections were merged under [PR #92](https://github.com/cuichangquan/a2a-rails/pull/92), with 29/29 CI PASS. This does **not** clear all Issue #90 gates or authorize a v0.3.x RubyGems release.

### Current action / ownership boundary

A controlled IAM-protected Cloud Run HTTPS Echo Agent now exists for private authenticated tests, but the required no-auth public endpoint, protected workflow environment and dedicated egress-filtered runner are **not yet validated** for the public test. The repository cannot itself register DNS, acquire the domain certificate, set protected GitHub Environment values or register an isolated self-hosted runner. Those need to exist before a manual public-egress execution can return meaningful evidence. Do not put a placeholder or unapproved third-party URL into the environment to force a green result.

After provisioning, start the workflow from **Actions → Step 29-5c controlled public HTTPS outbound Client egress → Run workflow** on `main`, approve the protected environment, and attach sanitized evidence to [Issue #90](https://github.com/cuichangquan/a2a-rails/issues/90).
