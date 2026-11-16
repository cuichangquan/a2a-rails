# SDK boundary (required review policy)

Use the agent2agent SDK's existing protocol/schema/transport capabilities; do not
reimplement the protocol merely to remove a dependency. Concentrate SDK-specific
Request/Response/Schema classes, exceptions and internal APIs at Protocol Adapter
(and existing Client codec/transport) boundaries. Do not introduce SDK dependence
into Dispatcher, Lifecycle, Store, Job or application Handlers.

Public Rails APIs use Ruby values or Gem-owned types. Users must not construct,
subclass or directly rescue SDK classes. Persistence and Job arguments contain no
SDK objects. Convert values and exceptions at the boundary. Lifecycle/Store own
Task state; applications own business permissions, validation and input merging.

Do not casually add SDK private APIs or global monkey patches. Any unavoidable
boundary-local workaround records its reason, alternatives, affected SDK version,
regression test and removal condition. This is not a mandate to rewrite unrelated
legacy code. Protocol fields (`taskId`) and states (`TASK_STATE_INPUT_REQUIRED`)
are standard vocabulary, not SDK dependence; preserve existing Client DTO shapes.

Every PR records PASS / FAIL / N/A (with reason) and concrete evidence:

| ID | Review obligation | Evidence |
| --- | --- | --- |
| SDK-1 | Public API/Handlers require no SDK types | Usage/API tests |
| SDK-2 | New SDK dependencies confined to boundaries | Dependency diff/review |
| SDK-3 | State, persistence, Jobs use owned/plain types | Core/Store/Job contracts |
| SDK-4 | Conversion and exceptions tested with real SDK | Adapter tests |
| SDK-5 | Reuse SDK, no needless abstraction/reimplementation | Reuse/supplement rationale |
| SDK-6 | Preserve 0.4.0 public API/use cases | Regression/upgrade tests |

Independent review must verify these claims; unverified/FAIL items block candidate
completion. Core tests need no SDK objects. Adapter tests use the actual SDK, not
an invented replacement SDK. No paid audit or public SDK-selection feature needed.
