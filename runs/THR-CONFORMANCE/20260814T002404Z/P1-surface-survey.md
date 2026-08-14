# P1 — existing-surface survey: is there a format that compares an
# execution's exercised surface against its authorized surface?

Date: 2026-08-14. Method: primary sources fetched and read this run (URLs
below); nothing taken from model memory. The one question asked of every
source: does a format exist that compares what an execution ACTUALLY
exercised (tool calls, delegation depth) against a surface AUTHORIZED
beforehand, yielding a machine-checkable verdict? A trace of what happened
does not count: a trace says what happened, not whether it was permitted.

## Verdict

**No such format exists in any surveyed source. The comparison SHAPE exists
once — in-toto layout verification — but its vocabulary is supply-chain
steps and artifacts, not agent tool calls with delegation depth. The new
predicateType is therefore justified as the missing predicate inside an
adopted envelope: this thread is integration at the envelope layer
(in-toto Statement v1, already pinned by ADR-019/ADR-020) and novelty only
at the predicate layer.**

## Per-source findings, with citations

### in-toto Attestation Framework — envelope adopted, no comparison inside
Read: `raw.githubusercontent.com/in-toto/attestation/main/spec/README.md`,
`…/spec/v1/statement.md`.
- Statement schema: `_type` = `https://in-toto.io/Statement/v1`; `subject`
  ("Subject artifacts are matched purely by digest"); `predicateType`
  ("URI identifying the type of the Predicate"); `predicate`.
- The framework carries claims; it does not compare: "The intended
  consumers are automated policy engines, such as in-toto-verify and
  Binary Authorization."
- New predicates are the framework's own extension mechanism: tagged
  releases "indicate updates to predicate specifications … a new
  predicate type."

### in-toto specification (layout/link/verify) — the comparison shape
Read: `raw.githubusercontent.com/in-toto/docs/master/in-toto-spec.md`.
- The a-priori declaration exists: a layout is "a signed file that
  dictates the series of steps that need to be carried out"; per step it
  declares `expected_command`, `expected_materials`/`expected_products`
  (ARTIFACT_RULES), authorized functionary `pubkeys`, and a `threshold`.
- The record of what happened exists: link metadata carries `materials`,
  `products` (hash objects) and "the command and its arguments as executed
  by the functionary".
- The comparison exists and fails closed: "Artifact rules are applied
  against the products and materials reported by each step"; on mismatch
  "return ERROR('Rule failed to verify!')".
- What does NOT exist: any vocabulary for tool calls, tool pools,
  delegation trees, or depth. The unit is a supply-chain step run by a
  keyed functionary over artifacts. Adopting layouts would mean encoding
  tool calls as artifact hashes — a category error, not an integration.

### SLSA Provenance — descriptive, verification external
Read: `slsa.dev/spec/v1.0/provenance`.
- Purpose: "Describe how an artifact or set of artifacts was produced so
  that: Consumers of the provenance can verify that the artifact was built
  according to expectations." `predicateType` = `https://slsa.dev/provenance/v1`;
  fields `buildDefinition`, `runDetails`.
- The predicate records; verification is a separate downstream activity
  ("Verifying Artifacts" is its own document). No authorized-surface
  comparison inside the predicate.

### OpenTelemetry GenAI semantic conventions — carries inputs, no comparison
Read (moved repo): `open-telemetry/semantic-conventions-genai` —
`docs/gen-ai/gen-ai-agent-spans.md`, `gen-ai-spans.md`, `gen-ai-events.md`,
`mcp.md`, and the full attribute registry `docs/registry/attributes/gen-ai.md`.
- Declared side exists as an opt-in attribute: `gen_ai.tool.definitions` —
  "The list of tool definitions available to the GenAI agent or model."
- Exercised side exists: `execute_tool` spans ("`gen_ai.operation.name`
  SHOULD be `execute_tool`"), `gen_ai.tool.name`, `gen_ai.tool.call.id`,
  `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`.
- A grep of all five documents for allow/authoriz/policy/permission/
  conform/verdict/violat/deny returned zero authorization-semantics hits.
  No comparison, no verdict, no delegation-depth attribute (nesting is
  implicit span parentage only).

### OpenInference — tracing only
Read: `raw.githubusercontent.com/Arize-ai/openinference/main/spec/semantic_conventions.md`.
- Declared side: `llm.tools` — "List of tools that are advertised to the
  LLM to be able to call." Exercised side: `tool_call.function.name`,
  `tool_call.id`, TOOL span kind. Structure: `graph.node.id` /
  `graph.node.parent_id` ("used to visualize the execution graph").
- Only policy-adjacent concept is the GUARDRAIL span kind (content
  moderation calls). No authorized-surface comparison, no verdict.

### GitHub Spec Kit — artifact-to-artifact, never artifact-to-execution
Read: `raw.githubusercontent.com/github/spec-kit/main/README.md`, `…/spec-driven.md`.
- "Define what to build before building it"; `/speckit.analyze` runs
  "after /speckit.tasks, before /speckit.implement"; `/speckit.converge`
  assesses "the codebase against spec/plan/tasks". All checks compare
  documents and code — none compares an execution trace against an
  authorized surface. No runtime conformance verdict.

### LangSmith / LangGraph — logs and gates, no record of conformity
Read: `docs.langchain.com/langsmith/observability-concepts`,
`docs.langchain.com/oss/python/langgraph/interrupts`.
- LangSmith: "A *run* represents a single unit of work executed by an
  agent"; "you can think of a run as a span" — a trace, i.e. what
  happened. Page contains no allowed/authorized/conformance concept.
- LangGraph interrupts "pause graph execution … and wait for external
  input" — pre-action human approval, which gates the future; it produces
  no artifact about what the past execution was permitted to do.

### Anthropic Agent SDK — the substrate, and confirmation of the gap
Read: `code.claude.com/docs/en/agent-sdk/overview.md`, `…/typescript.md`,
`…/hooks.md`, `…/subagents.md` (the docs.claude.com address 301-redirects;
content read at code.claude.com).
- The stream carries attribution: `SessionMessage.parent_tool_use_id` —
  "For subagent messages, the `tool_use_id` of the spawning `Agent` tool
  call. `null` for main-session messages" (requires ≥ v2.1.202);
  `forwardSubagentText`: "Messages from subagents at every nesting depth
  are forwarded on Claude Code v2.1.219 and later". Depth is never a
  field; it is recomputed by chaining parent ids (matches yesterday's
  measurement: SubagentStart/SubagentStop carry `agent_id`/`agent_type`
  but no depth).
- The SDK documents its own non-binding: "`allowedTools` … Tools to
  auto-approve without prompting. This does not restrict Claude to only
  these tools" — the documentation of the exact gap ADR-022 named.
- Naming caveat for any declaration parser: "Current SDK releases emit
  `\"Agent\"` in `tool_use` blocks but still use `\"Task\"` in the
  `system:init` tools list and in `result.permission_denials[].tool_name`."
- No built-in comparison: nearest primitives are per-call gating
  (PreToolUse / canUseTool) and the result message's `permission_denials[]`
  (a partial event log). "Log and audit every tool call" is listed as a
  use case the consumer must implement.

## Consequence for P2

Adopt: the in-toto Statement v1 envelope (ADR-019 D1 subject discipline,
ADR-020 allowlist writer, ADR-018 canonical form) — unchanged.
Define: a new versioned predicateType carrying the resolved declared
surface, the delegation tree recomputed from `parent_tool_use_id`, every
exercised capability with its depth and paired-result reading (ADR-023
D6), the unused authorizations, and the comparison rule by id+digest.
That predicate exists in no surveyed convention; where a neighbour has a
name for one of its inputs, the neighbour's name is recorded here
(OTel `gen_ai.tool.definitions` / `gen_ai.tool.name`) so a future exporter
can map fields without redesign.
