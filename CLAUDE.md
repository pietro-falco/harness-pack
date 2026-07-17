# harness-pack — agent session guide

## Role in the stack

Execution-layer runtime pack: the pinned constitution
(`CONSTITUTION.md`), the fail-closed PreToolUse guard, the launcher
(`scripts/launch_worker.sh`), and the hash-chained receipt log. This
repo is where the three-repo stack composes — the full picture is in
[`docs/STACK.md`](docs/STACK.md).

## Gate — run before claiming anything is done

```bash
bash tests/run_tests.sh                          # expect: ALL TESTS PASSED
node "$VERITY_CLI" verify .verity/claims.json    # all claims green (privacy-lint)
```

`VERITY_CLI` points at a built verity CLI; an installed `verity` on
`PATH` works too. Both commands must be green. A red gate is a full
stop, not a retry.

## Deploy is operator-only

`just deploy` copies HEAD into the enforced runtime location under
sudo. Never run it from an agent session — deployment is a standalone
operator act by design: the enforced copy must not be writable by the
tree that produced it.

## Constitution

`CONSTITUTION.md` is injected verbatim into every worker run and its
sha256 is pinned into every receipt. Workers never edit it; changes
are operator-gated and re-pin the hash.

## Agent contract

The authoritative execution rules — ADR gate, evidence discipline,
git hygiene, scope and stops — live in
[`docs/STACK.md` § Agent contract](docs/STACK.md#agent-contract).
This file is a thin projection; where they differ, that section wins.
