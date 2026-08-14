#!/usr/bin/env node
// harnesswright --agents emitter. Emission target path (operator copy, this
// run cannot write outside harness-pack): harnesswright/scripts/emit_agents.mjs
//
// Reads a spec, emits the JSON object `claude --agents` accepts, or exits
// non-zero on the first static defect. The architectural point: the subset
// check makes the emitted declaration accurate REGARDLESS of runtime
// semantics — even if a future CLI let a child widen its pool, agents
// emitted here stay inside the surface the spec declares. The measured arms
// (RESULT.json) decide only whether a runtime re-check is also needed; on
// 2.1.231 they measured subset semantics at depth 1 and 2, foreground and
// background, so none is.
//
// Preconditions are machine-read, never remembered: --result <RESULT.json>
// must show apparatus_green true and arm A8 CONFORME with both markers.
//
// Usage: emit_agents.mjs --spec <spec.json> --result <RESULT.json> [--explain]
//
// Spec shape:
// {
//   "parent_tools": ["Read","Write","Agent"],   // the pool the parent declares
//   "max_spawn_depth": 1,                       // required if any agent pools Agent
//   "skills_allowlist": [],                     // required if any agent lists skills
//   "memory_declaration": {"scope":"project","path":".claude/agent-memory/"},
//   "agents": { "<name>": { <documented keys only> } }
// }
import { readFileSync } from "node:fs";

const VOCABULARY = new Set([
  "description", "prompt", "tools", "disallowedTools", "model",
  "permissionMode", "mcpServers", "hooks", "maxTurns", "skills",
  "initialPrompt", "memory", "effort", "background", "isolation", "color",
]);

const EXIT = {
  E_USAGE: 64, E_PRECONDITION: 65, E_TOOLS_SUPERSET: 66, E_UNKNOWN_KEY: 67,
  E_AGENT_WITHOUT_DEPTH_BOUND: 68, E_MEMORY_UNDECLARED: 69,
  E_SKILL_NOT_ALLOWLISTED: 70, E_ZERO_TOOLS: 71, E_DENY_FORM: 72,
};

function die(code, msg) {
  process.stderr.write(`${Object.keys(EXIT).find(k => EXIT[k] === code)}: ${msg}\n`);
  process.exit(code);
}

const args = process.argv.slice(2);
function opt(name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}
const specPath = opt("--spec");
const resultPath = opt("--result");
if (!specPath || !resultPath) die(EXIT.E_USAGE, "need --spec and --result");

let result;
try {
  result = JSON.parse(readFileSync(resultPath, "utf8"));
} catch (e) {
  die(EXIT.E_PRECONDITION, `RESULT.json unreadable: ${e.message}`);
}
const a8 = result.arms && result.arms.A8;
if (!result.apparatus_green || !a8 || a8.outcome !== "CONFORME"
    || !a8.alive_marker || !a8.disk_says_child_bash) {
  die(EXIT.E_PRECONDITION,
      "measurement not green: A8 must be CONFORME with both markers");
}

let spec;
try {
  spec = JSON.parse(readFileSync(specPath, "utf8"));
} catch (e) {
  die(EXIT.E_USAGE, `spec unreadable: ${e.message}`);
}
const pool = spec.parent_tools;
if (!Array.isArray(pool) || pool.length === 0)
  die(EXIT.E_USAGE, "spec.parent_tools must be a non-empty array");
const agents = spec.agents || {};

const surfaces = {};
for (const [name, agent] of Object.entries(agents)) {
  for (const key of Object.keys(agent)) {
    if (!VOCABULARY.has(key))
      die(EXIT.E_UNKNOWN_KEY, `agent ${name}: key "${key}" is not one of the sixteen documented keys`);
  }
  const declared = agent.tools;
  const deny = agent.disallowedTools || [];
  for (const d of deny) {
    if (/[()]/.test(d))
      die(EXIT.E_DENY_FORM,
          `agent ${name}: deny rule "${d}" uses the parenthesized form, which` +
          ` leaves the tool in context and denies only matching calls; the` +
          ` bare name form removes it`);
  }
  if (Array.isArray(declared)) {
    const outside = declared.filter(t => !pool.includes(t));
    if (outside.length)
      die(EXIT.E_TOOLS_SUPERSET,
          `agent ${name}: tools [${outside}] not a subset of the declared parent pool [${pool}]`);
  }
  // Resolution order, measured semantics: disallowedTools applies first,
  // tools then selects from the residue. A tool named in both is REMOVED.
  const residue = pool.filter(t => !deny.includes(t));
  const effective = (Array.isArray(declared) ? declared : residue)
    .filter(t => residue.includes(t));
  if (effective.length === 0)
    die(EXIT.E_ZERO_TOOLS,
        `agent ${name}: tools resolve to zero tools; at runtime this is the` +
        ` documented "Agent would be spawned with zero tools" error`);
  if (effective.includes("Agent")
      && !Number.isInteger(spec.max_spawn_depth))
    die(EXIT.E_AGENT_WITHOUT_DEPTH_BOUND,
        `agent ${name}: pools Agent but the spec declares no max_spawn_depth`);
  if (agent.memory !== undefined) {
    const md = spec.memory_declaration;
    if (!md || typeof md.path !== "string" || !md.path.length)
      die(EXIT.E_MEMORY_UNDECLARED,
          `agent ${name}: memory present without an explicit spec` +
          ` memory_declaration carrying a path`);
  }
  if (Array.isArray(agent.skills)) {
    const allow = spec.skills_allowlist;
    if (!Array.isArray(allow))
      die(EXIT.E_SKILL_NOT_ALLOWLISTED,
          `agent ${name}: skills present without a declared skills_allowlist`);
    const rogue = agent.skills.filter(s => !allow.includes(s));
    if (rogue.length)
      die(EXIT.E_SKILL_NOT_ALLOWLISTED,
          `agent ${name}: skills [${rogue}] outside the declared allowlist`);
  }
  surfaces[name] = effective;
}

if (args.includes("--explain"))
  process.stderr.write(`declared surfaces: ${JSON.stringify(surfaces)}\n`);
process.stdout.write(JSON.stringify(agents) + "\n");
