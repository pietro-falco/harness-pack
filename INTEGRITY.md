# INTEGRITY

The record of every declared transformation applied to a tracked blob in this
repository. A re-pinned blob digest is evidence of a declared transformation
only when it appears here, enumerated by path, against a rule file whose own
sha256 matches the one this record cites. A re-pin absent from this file is
undeclared content drift and must be treated as tampering, not as maintenance.

## Path transformation

**Rule:** `scripts/path_transform_rule_v2.json`  
**Rule sha256:** `0c73a6820a614cd6cc1e92ecf9318fad87df1e430114a44037a48389082023be`  
**Applied in merge:** `30361485ec1031ebf3596683f5e11f1dad49ec6c` (ours) x `f1e2f473983c7040a9b9ad7bfd7d3588e766b957` (theirs)

`path-transform/v2` replaces the operator home path with `<LOCAL_ROOT>` in two
encodings — the filesystem form and the dash-flattened form used by Claude Code
project-state directory names. Both patterns are stored in the rule file as JSON
`\u00XX` escapes, so the rule file is a fixed point of its own rule and does not
itself carry the substring `privacy-lint-user-paths` refuses.

### Superseded draft, never landed

`path-transform/v1` declared the filesystem form only. The remote side of this
merge carries 396 occurrences of the dash form and zero of the filesystem form,
so v1 reproduced the local blob on 0 of 40 paths. It is recorded here by digest
as a superseded draft and is not tracked in this repository.

**v1 draft sha256:** `556e0ad43aad7a06513aca9ace6243e25260f89aebc46757ce2d8ef12d3615ad` — superseded, never landed.

### Verification gates

| Gate | Question | Result |
| --- | --- | --- |
| G-A reproduction | v2 applied to the remote blob reproduces the local blob | 40/40 |
| G-A control (v1) | v1 applied to the remote blob reproduces the local blob | 0/40 |
| G-B idempotence | v2 applied twice equals v2 applied once | 40/40 |
| G-C anti-vacuity | remote blobs whose bytes v2 actually changes | 40 |

### Declared paths (40)

Each row is a path this transformation covers and the sha256 of the resulting
blob, which is the blob committed at this merge.

| # | Path | Resulting blob sha256 |
| --- | --- | --- |
| 1 | `runs/THR-SUBAGENT/20260813T194853Z/RESULT.json` | `be3d1aa8aca5a79efd586d249aab0c4affc48eeb940c47db65f88d8fb5721b50` |
| 2 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/detect.json` | `2f12d677e43396065750748fe63aba928506314f25ddeeca99563e60e0a78d00` |
| 3 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/invocation.txt` | `b0dd3a968f7cb260c8732639426b681b251b0184e7cc389e6be1acf6f74dcfa8` |
| 4 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/stream.jsonl` | `4cc85d3179f0a415416d069f85644193843da9165e48f902f4b98019c87c34ad` |
| 5 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1fg/invocation.txt` | `e64f2589cff820d0a4520396b0758813129cf298523d833e0b4b9c2e41abe28a` |
| 6 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1fg/stream.jsonl` | `d1c390d07b5a250622ea37d500d9bd9b4e4e33bac4ae737eaebd8a2b964032bd` |
| 7 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/detect.json` | `6779792d4092b6687973f1ddd1183e9a72957a601784bf964aaef304dabe5901` |
| 8 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/invocation.txt` | `a8cf6cc8773af7eb1ac8e39e04fbb40d2b94652856b27f1c745ee066c90aa907` |
| 9 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/stream.jsonl` | `e2cd4d4734071d61924b45e7468052968e5e57e22a190ea9aa5c6179dfeb9831` |
| 10 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/detect.json` | `576a2b6f49c0c2b333cb6bdce2bc1b3ce4293a4a745f598cac9e45ee012cba07` |
| 11 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/invocation.txt` | `aab83549ac5d580c5bc01b88adadebec656d8e134df6f42be67bfbbbc2c3a3c5` |
| 12 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/stream.jsonl` | `7e245e9bf34f382867a2bcda6f71dacc2916393b047fada7f9e12b5d2eed38e1` |
| 13 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/detect.json` | `7029eb3f7c44d8083f7c704f07c9093bba59e2459d4ce4263d8bfb63ce56e2cd` |
| 14 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/invocation.txt` | `f10e15aaee4e4c91aff1786d20be577af6b22e61ac4089f19e94085c62d8944b` |
| 15 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/stream.jsonl` | `afdccf2991c09cd134a2468f42715c00fb6d980f6ef5e30fd0cf9ef9dba94eaa` |
| 16 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4-tools-empty-string/invocation.txt` | `47624d70b23c5c3733856eabd8cb812044913996b35182d00167a0d25238604a` |
| 17 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4-tools-empty-string/stream.jsonl` | `731be7d0022785466f879e29a43780d879f6f067500920a1aecdb8961d1ecfb0` |
| 18 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/detect.json` | `be0e54190d13621bdffc6fc7b5c1e4a868b82bbd9d1bb8b25191e506112645ea` |
| 19 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/invocation.txt` | `8b068b3320691f8e76110c13741e016af2320e5054bf874c0ad7c149ee9587aa` |
| 20 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/stream.jsonl` | `c2ae65ba0b14912cdd7758c41df10866c4cc0cc075bfb6a6256c7c3f57fb9fe1` |
| 21 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/detect.json` | `1934a9d771e3c678a72e33df982f3454040e707a422d144999c21bb37b90c2cf` |
| 22 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/invocation.txt` | `3d3dfc17bb217df819b899c019a0440504d4d90c754ed41d2223fb8b9e632893` |
| 23 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/stream.jsonl` | `fc0aa806803d4240bbe38cd1a1a9e188cf76fc9d725acd1f31ba708e41538110` |
| 24 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/invocation.txt` | `a02cfc79203976be9c019f7f4e15020c3b318e22e2a0f36bf67aa42a655cb917` |
| 25 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/memory-after.txt` | `1e94295f5ff4768514ad7be7298827de264153a065c6db3b51234a1815ca6a27` |
| 26 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/stream.jsonl` | `6a62b6f9bdbf33951c878963019cc6f7bc5aa1b425fa1b4fa43235b7048bc63b` |
| 27 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A7/invocation.txt` | `843d787d2c54a2d691d5bc1f3eadded5210cabd57529d76c810d03ee4b0e11a4` |
| 28 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A7/stream.jsonl` | `5b3f349fd843186afe0381e40bd8102368d851233cd823eab4475e90b9510e71` |
| 29 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/detect.json` | `5105eb9873af6cebd5aafb826293ff46ff95d00d25b87aaae86774f5a1045291` |
| 30 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/invocation.txt` | `1bb03e0f38e64f5a5e6e6b6875aa9fe2b1f48a341e2cc3dcb924e16d3544510d` |
| 31 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/stream.jsonl` | `f71998846bd7541431d21de5a1c82bc4d95b2383e56b29a7d878a8374f9cf6a6` |
| 32 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/evidence.txt` | `f1f35803754ffb5c8e688c6e211f45cdfc785db11ee371a47d7d411636e5cfb8` |
| 33 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/invocation.txt` | `32cd246f467f228095b66ebe983369f356bd4c48436196c8db18564834e5bf23` |
| 34 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/ledger/pretooluse.jsonl` | `577889355426c9ba91df04eaf65e6d5e113b2d55c6870ab31e967fbb2b1321d3` |
| 35 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/ledger/spawn.jsonl` | `bf8ff5b0d403f0af9ef78e99595dcb959948165321d0642c99a3bf713dd3fde8` |
| 36 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/stream.jsonl` | `ca0ce085cfc070165466b29d9acbb53b882249e8823942db38eb9a526354fb53` |
| 37 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2neg/invocation.txt` | `5c3ef58063ade02340a023c1276f8b14137874da6e8368bcfbdfb8979a9e34e9` |
| 38 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2neg/stream.jsonl` | `f9a5cb793d4b955f33dbb1ec0824f6b4bd9ce54fd8e4934ada7c9cc7e84074d4` |
| 39 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2pos/invocation.txt` | `d756f0b82df68c31c3510b51829867911821d0fbd24dc2054c9fd97b9db6e6e9` |
| 40 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2pos/stream.jsonl` | `cdd2f7f912842be3b8886bf57a00a718114739742ccd6e4cbf13d67a152fe64f` |
