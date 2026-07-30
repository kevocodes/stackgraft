# Tasks: portable-multi-stack

Phase: `sdd-tasks` · Input: `proposal.md` + 4 delta specs + `design.md` · Next: `sdd-apply`

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~790 total — PR1 ~155, PR2 ~270, PR3a ~175, PR3b ~200 |
| 400-line budget risk | High (chain total); Low per slice |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3a → PR 3b |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain (tracker `feat/portable-multi-stack`, D4) |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

**What needs deciding** (three deviations from the proposal/design PR columns, all with stated reasons):
1. **PR 3 splits into 3a/3b — yes.** The proposal priced PR 3 at ~290, before the design added `stateReview` (DS15) and the three-part `serviceFingerprint` recipe (DS16). Realistic ~375 leaves no margin under a 400 budget.
2. **3a/3b content is inverted vs. the proposal's contingency** (proposal: doc first, then schema). Doc-first breaks verification V3 at the 3a boundary — `shared-state.md` would name `backingStores`, `writes`, `competesOn`, `acceptedRisks` before the schema declares them. Schema-first keeps V3 green at both boundaries and puts each half on one verification method (3a = V2, 3b = V1+V3+V4).
3. **Two file-to-PR reassignments**: README status moves from PR 1 → 3b (PR 1's README would claim a gate that is not in the tree); `traps.md:29` reconciliation moves from PR 1/3 → PR 2 (it only becomes true once the `--no-interpolate` resolver exists).

### Verification legend

`openspec/config.yaml` `available_verification` lists exactly four methods:
**V1** SKILL.md style-guide review (incl. the DS3 `awk` body word count) · **V2** JSON well-formedness + JSON Schema validity of `assets/*.json` · **V3** cross-file: every field named in SKILL.md/`references/` exists in the schema · **V4** portability grep.
**V5** = `dash -n` on both scripts. **Flag: V5 is NOT in the config list** — task 1.1 adds it.
**Flag:** V2 and V3 name methods with no committed tool (both are manual). **Flag:** no listed method covers non-shipped files, so `openspec/config.yaml` and `README.md` units verify by file review only.

### Suggested Work Units

| Unit | Goal | PR (base) | Focused check | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Portable runtime, XDG cache, `fingerprint`, example repaired | PR 1 (base: tracker) | V5 + V1 + V4 + V2 | `sh scripts/*.sh` on macOS and `docker run --rm -v "$PWD":/w -w /w alpine/git` | `skills/stackgraft/scripts/` + SKILL.md/assets diff; revert leaves v1 skill intact |
| 2 | Discovery restructure, `portGroup`/`runnable`, field removals | PR 2 (base: PR 1) | V2 + V3 + V1 | N/A — declarative schema + reference prose, no executable surface | `discovery.md` + schema/example diff; PR 1 unaffected |
| 3a | Shared-state schema fields | PR 3a (base: PR 2) | V2 | N/A — schema only | `backingStores`/classification/`acceptedRisks` blocks; no doc references them yet |
| 3b | The gate itself: reference, sealed body rule, traps, README | PR 3b (base: PR 3a) | V3 + V1 + V4 | `git` fixture matrix for `serviceFingerprint` (DS16) on macOS + `alpine/git` | `references/shared-state.md` + SKILL.md rule/row; schema from 3a survives unused |

**Body word ceilings** — re-derived against a **direct measure of 496 words** (≈694 tok at the design's 1.4 proxy), not the design's 559. **The 1.4 tokens/word proxy is itself unverified.** Final ≤500 words. PR 3b adds 53 (41-word rule + 12-word row) ⇒ enter 3b ≤447. PR 2 nets +12 ⇒ enter 2 ≤435. **PR 1 must exit ≤435, a net cut of ≥61** — not the design's 109. Donor subset suffices: CodeGraph clause (−11), the `lsof -a -p` string (−9), Hard Rule 2 `lsof` rewrite (−8), Hard Rule 5 compression (−6), References descriptions (−14), Execution Steps 3–8 trim (−20). Activation Contract, Output Contract, and Decision Gates rows stay intact.

---

## Phase 1: Portable runtime (PR 1 — base `feat/portable-multi-stack`)

- [x] 1.1 In `openspec/config.yaml`: set `open_decisions.scripts-runtime` to resolved with DS19 (POSIX `sh` + `git` + POSIX `awk`, invoked `sh <path>`); append `dash -n` and `command -v git awk` on macOS + minimal Linux to `available_verification`. *Verify: file review (no listed method covers config.yaml — see flag).*
- [x] 1.2 **[RED]** Write the threat-matrix fixture for git repository selection (design row 2): run from a linked worktree, a subdirectory, and a symlinked path; assert one manifest path. Record that it currently resolves to three paths under `~/.claude/stackgraft/<slug>.json`. *Verify: file review of recorded results.*
- [x] 1.3 Create `skills/stackgraft/scripts/fingerprint.sh` and `scripts/pick-port.sh` per the design's contract blocks — `while IFS= read -r p` + `git hash-object --no-filters`, `-\t<path>` on failure; DS7 offset start `lo + (hash8(worktree) mod span)`, candidate-only output, exit 3 on exhaustion. No JSON, no file writes, no `stat`/`readlink -f`/bash-4. *Verify: V5; `command -v git awk` on macOS and `alpine/git`; `git hash-object --no-filters` on a sample file.*
- [x] 1.4 In `SKILL.md`: add frontmatter `compatibility` (≤500 chars, one line, POSIX-only, git + POSIX sh unconditional, container tooling conditional); rewrite Execution Steps 1–2 to `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json` with `hash8` from the git common dir; add DS20 (unwritable ⇒ manifest-less run; `repoRoot` mismatch ⇒ discard); add `scripts/` to References. *Verify: V4 (no `~/.claude`); V1; fixture 1.2 now yields one path.*
- [ ] 1.5 In `SKILL.md` + `references/traps.md`: drop the CodeGraph clause from Hard Rule 4 and `traps.md:25`, leaving the `/tmp`/`/var/tmp` prohibition as its own bullet justified without naming a vendor tool; demote `lsof` to a heuristic in Hard Rules 2–3; compact to **≤435 words** using the donor subset above. *Verify: V1 incl. the DS3 `awk` count; V4.*
- [ ] 1.6 In `assets/manifest.schema.json` + `manifest.example.json`: `schemaVersion` `const: 2`; rename `sources[].sha256` → `fingerprint` (opaque string, **no `pattern`** — DS11); add top-level `fingerprintTool`. *Verify: V2; V3.*
- [ ] 1.7 Fix the two pre-existing example defects (own work unit, D3): remove the root `_comment` and move its caveat into `references/traps.md`; rewrite `catalog-api.overlayCommand` to drop `--service-ports`, add `--no-deps`, and rewrite `SEARCH_URL` to the base stack's `localhost:8090`. *Verify: V2 with `additionalProperties: false` in force; file review of the launch command.*

## Phase 2: Discovery restructure (PR 2 — base PR 1)

- [ ] 2.1 Schema + example: `kind` → open `type: "string"` with `examples`; add `portGroup` (string, **required when `runnable` is true**); re-key `portPolicy.ranges` to `compose` / `node-dev`. Missing `ranges` key ⇒ existing stop-and-ask rule. *Verify: V2 (a novel `kind` with a known `portGroup` validates at `schemaVersion: 2`).*
- [ ] 2.2 Schema + example: add `runnable` (default `true`); draft-2020-12 `if/then` forbidding `basePort`, `portGroup`, `overlayCommand`, `verifyRequest`, `peerEnv` and requiring `paths` + `consumers` when false; convert `backend-shared` from `kind: "static"`. **Blocks PR 3a** — `backingStores` cannot split out of `services` until `static` is retired (D4 forced ordering). *Verify: V2 (`kind: "static"` now fails).*
- [ ] 2.3 Schema + example + `references/discovery.md` §2: remove `healthPath`, `dockerfile`, `sharedDirsIncluded`; make `consumers` the single direction of truth per DS13, and state in `discovery.md` that each service's Dockerfile is read once and only the *result* is recorded as `consumers` membership. *Verify: V2 (all three now rejected); V3.*
- [ ] 2.4 Schema + example: `verifiedOverlays` array → object keyed by service, latest record only (DS14). *Verify: V2 — one entry per service.*
- [ ] 2.5 Schema: add `sources[].revalidate` (`fingerprint` | `always`, default `fingerprint`), `confidence` (`declared`|`inferred`|`user`), `resolverStatus`; constrain `covers` with `not: {pattern: "^(verifiedOverlays|acceptedRisks)"}` — the regex names `acceptedRisks` one slice early, which is inert and avoids re-editing the line in 3a. *Verify: V2.*
- [ ] 2.6 Rewrite `references/discovery.md`: split §(a) path→unit from §(b) unit→launch and tag every source with the question it answers; add the R1/R2/R3 resolver ladder led by `docker compose config --no-interpolate --format json`, the never-execute-repo-code rule, and degradation that never hard-fails; add the DS17 `covers` rule (dotted paths, subsumption normalisation, coarse-wins, evidence keys invalid, evidence invalidation); add `revalidate: always`. Add both `covers` granularities to the example. *Verify: V1-style file review; V3.*
- [ ] 2.7 Reconcile `references/traps.md:29` with the R1 resolver: `--no-interpolate` does not print secrets, so it is exempt from the permission-blocked-config trap. Travels with 2.6 because it is only true once R1 exists. *Verify: file review against `discovery.md` §(b).*

## Phase 3a: Shared-state schema (PR 3a — base PR 2)

- [ ] 3a.1 Schema + example: add top-level `backingStores` (DS8) with `substrate`, `notes`, and `isolation { mechanism, applyVia, command, teardownCommand, env, discoveredFrom, confidence, approval }`; record in the descriptions the collision rule (a name MUST NOT appear in both maps; `dependsOn`/`writes` resolve `backingStores` first; a name in neither is unknown ⇒ fail closed) and that `mechanism: "none"` is legal and meaningful. Add a `postgres` store to the example. *Verify: V2.*
- [ ] 3a.2 Schema + example: add per-service `writes`, `competesOn` (`{store, identity}`), `migrates`, and `stateReview { at, method }`; require `stateReview` whenever any of the three is present (DS15), and state `[] = checked-none` vs `absent = unknown` in the descriptions. *Verify: V2 — a service with `writes` and no `stateReview` fails.*
- [ ] 3a.3 Schema + example: add `acceptedRisks` as an object keyed `^[^:]+::[^:]+$`, requiring `at` + `serviceFingerprint` (plus `reason`, `acceptedBy`), latest-only by construction. **Reconcile spec ↔ design**: the spec's verify note names `service`, `store`, `at`, `fingerprint`; DS14 carries `service`/`store` structurally in the key and names the hash `serviceFingerprint`. Adopt DS14 and record the mapping in the field description. *Verify: V2; file review of the recorded reconciliation.*

## Phase 3b: The gate (PR 3b — base PR 3a)

- [ ] 3b.1 **[RED]** In `references/shared-state.md`, write the rejected-template fixture table first (threat row 1): one rejected example per DS5 rule — unknown `{{…}}`, each deny-listed character, a pipeline, a repo-supplied `{{isolationName}}`, and each destructive verb. *Verify: file review — every DS5 rule has exactly one rejected example.*
- [ ] 3b.2 **[RED]** Record the `serviceFingerprint` fixture matrix (threat row 3): stage-only edit, unstaged-only edit, untracked-only file, unstaged **binary** edit — each MUST move the hash. *Verify: run the DS16 three-part composition on macOS and `alpine/git`; DS16 is marked unverified and this task is where it gets checked.*
- [ ] 3b.3 Complete `references/shared-state.md`: W/X/N verdict table, unknown ⇒ `W=yes,X=yes,N=no` ⇒ REFUSE, escalation triggers that override recorded claims, competitive attachment refused independently of `writes`, the four-rung isolation ladder, the DS5 template contract, the DS18 interlock (`inferred`/`user` confidence MUST NOT satisfy the gate), the per-substrate table, named refuse-cases, and the DS16 recipe. *Verify: V3 — every field it names exists in the 3a schema.*
- [ ] 3b.4 In `SKILL.md`: add the sealed Hard Rule verbatim (41 words, design DS2) and the Decision Gates row (12 words), plus the `references/shared-state.md` References entry. Body ≤500 words. *Verify: V1 incl. the DS2 P1 check — the body contains no `REUSE`, `ISOLATE`, or W/X/N condition; DS3 `awk` count.*
- [ ] 3b.5 Add the shared-state traps to `references/traps.md`: the disarmed-gate shape (all-`[]` classification with `method: user-asserted`), base-namespace reuse by a writer, and a migration in the diff. *Verify: file review — each trap is checkable against a manifest.*
- [ ] 3b.6 Update the `README.md` Status section to describe the shipped skill. Lands last so no intermediate slice claims a gate absent from its tree. *Verify: file review.*

## Phase 4: Chain close

- [ ] 4.1 Re-run every success criterion from `proposal.md` against the tracker branch: example validates, body ≤700 tokens with style-guide order, portability grep clean, V3 clean, `schemaVersion` transitions exactly once across the chain, both scripts pass V5 on both platforms, `open_decisions.scripts-runtime` closed, no `mechanism: "none"` launch without a recorded `acceptedRisks` entry. *Verify: V1 + V2 + V3 + V4 + V5.*
- [ ] 4.2 Confirm the D2 chain rule held: `git log -p feat/portable-multi-stack` shows `schemaVersion` touched only in task 1.6. Merge the tracker only after all four children land (RESOLVED question 2). *Verify: file review of the tracker diff.*
