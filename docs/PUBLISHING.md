# Publishing path

Phase 0 (now): private GitHub repo, CI green on every push. The repo
gates itself: the guard, the chain, and the lint are tested by the
same deterministic machinery they implement.

Phase 1 (public template repo):
- LICENSE: Apache-2.0 (patent grant matters for infra tooling).
- Enable: branch protection/rulesets with required status check `ci`,
  CODEOWNERS, Dependabot, secret scanning + push protection, gitleaks
  in CI, OpenSSF Scorecard action.
- SSH commit signing with the hardware-gated key (already on the
  roadmap) before flipping public.
- README badge row: ci, scorecard.

Phase 2 (versioned artifact, only if adoption justifies it):
- npm publish as a template pack with OIDC trusted publishing and
  SLSA provenance, same pipeline as harnesswright. Consumers scaffold
  via harnesswright rather than copying files.
- GitHub artifact attestations on release tarballs.

Naming: working name harness-pack. A brand pass (e.g. "charter") is a
Phase 2 decision; renaming a template repo is cheap, renaming an npm
package is not.
