# Assumption ledger — THR-CONFORMANCE 20260814T002404Z

1. **P1 source boundary.** Every per-source claim in P1-surface-survey.md
   is quoted from documents fetched this run (URLs listed there): in-toto
   attestation README + statement.md, in-toto spec (layout/verify), SLSA
   provenance v1 page, OTel GenAI semconv (moved repo: agent-spans, spans,
   events, mcp, full attribute registry), OpenInference
   semantic_conventions.md, Spec Kit README + spec-driven.md, LangSmith
   observability-concepts, LangGraph interrupts, Agent SDK
   overview/typescript/hooks/subagents at code.claude.com. NOT read (and
   therefore outside the "no such format exists" claim's evidence): OTel
   GenAI metrics/exceptions/provider pages and non-normative docs,
   OpenInference pages beyond the semantic conventions file, LangGraph
   beyond the interrupts page, SLSA verifying-artifacts page, in-toto
   attestation docs beyond the two read, Spec Kit beyond the two read.
   The negative claim is bounded by what was read.
2. **parent_tool_use_id at depth.** Documented: SessionMessage carries it
   from CLI v2.1.202; subagent messages at EVERY nesting depth are
   forwarded from v2.1.219 (before that, depth-1 only) — read in the SDK
   TypeScript reference this run. Measured: chains resolve to depth 2 on
   2.1.231 evidence (arm A3) and on today's synthetic corpus. Below
   v2.1.219 the record builder would see unresolvable parents and refuse —
   behavior asserted by code path, not measured on an old CLI.
3. **Ordinals.** FT-20..FT-27 free (FT-19 was the highest registered) and
   ADR-024 free (ADR-023 highest on disk) — verified by listing, not
   recall.
4. **State line under watch frequency.** The conformance watcher extends
   the gate's contract (one short line, atomic replace, rewrite only on
   change); measured update latency 53–112ms at interval 100ms, inside
   the declared 300ms threshold (FT-27 GREEN at 112ms). NOT measured: a
   statusline consuming BOTH the gate's line and conformance.state
   concurrently; assumed cheap because both are single-line rereads.
5. **CLI drift between evidence and pin.** The three real-arm records were
   built today (pin 2.1.232) over streams captured yesterday (2.1.231).
   Verification recomputes from bytes, so no analysis step depends on
   today's CLI; equivalence of stream semantics across the two patch
   versions is assumed, not measured.
6. **Declared model.** This session's declared model is fable (Fable 5,
   claude-fable-5) and matches the serving model as declared; nothing to
   register as divergence. Arm evidence remains model-tagged sonnet by
   yesterday's explicit choice (ADR-023 OR-5).
