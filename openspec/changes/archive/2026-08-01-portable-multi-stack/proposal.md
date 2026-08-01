# Proposal: portable-multi-stack

Phase: `sdd-propose` · Input: `exploration.md` (complete) · Next: `sdd-spec` + `sdd-design`

## Intent

`skills/stackgraft/` is a rename of a Claude-Code-local skill promoted to a portable one without a portability pass. Three consequences, all evidenced in the files:

1. **It is unsafe.** The manifest records `dependsOn` but nothing about *what happens when two writers share a datastore*. The shipped example proves the gap: `catalog-api.overlayCommand` starts its own `postgres` and re-binds base port `8080`, the exact behavior the skill exists to avoid.
2. **It is not portable.** `~/.claude/stackgraft/…` (SKILL.md:41) and the CodeGraph clause (SKILL.md:21) are single-agent conventions in a skill targeting ~40 agents.
3. **It has no runtime.** `scripts/` does not exist; `openspec/config.yaml` → `open_decisions.scripts-runtime` is open, so nothing deterministic can be specified.

Success: the folder can be copied into any of ~40 agents and refuse an unsafe overlay by construction rather than by warning.

## Contract surfaces touched

All four: `SKILL.md` (body + frontmatter), `assets/` (schema + example), `references/` (2 modified, 1 new), `scripts/` (new).

## Decisions

### D1 — Manifest location: **Option B, XDG cache**

`${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, where `hash8` is the first 8 chars of `printf '%s' "<git-common-dir>" | git hash-object --stdin`.

Adoption risk decides it. Option A (git common dir) writes under `.git/`, which many agents refuse — a cache the agent cannot write is a broken skill for that agent, and portability is this change's entire reason to exist. B is also semantically correct: the skill's own Hard Rule calls the manifest a cache, and `XDG_CACHE_HOME` is the spec's location for re-derivable non-essential data, so a cleaner wiping it degrades to rediscovery. A's real advantage — no slugification, therefore no same-basename / moved-repo / symlink / APFS-case bug class — is kept by deriving the filename from the git-common-dir hash instead of a path slug, using a tool the skill already requires. **Accepted cost:** the cache is not GC'd when the repo is deleted. Eviction is a non-goal.

### D2 — `schemaVersion`: **one bump to `2`, flipped in PR 1, never re-bumped in the chain**

Both restructures change the schema, so a naive slicing invalidates every user's cache twice. Delivered via a Feature Branch Chain (D4): `main` sees exactly one schema transition, at the tracker merge. Chain rule: **no child PR after PR 1 may touch `schemaVersion`.** No migration code is needed — `discovery.md:42` already discards unrecognized versions and rediscovers. Doing *both* restructures under one bump is also why `kind` becomes an open string keyed by a new `portGroup`: after v2, adding a stack type must never force another invalidation.

### D3 — Pre-existing example bugs: **ride along, in PR 1**

Not scope creep — `openspec/config.yaml` → `rules.verify.manual_checks` already requires the example to validate against the schema, so this change's own verification fails while the root `_comment` stands. Fix by removing the comment (keeping `additionalProperties: false`, which is doing real work) and moving the caveat text to `references/`. The `overlayCommand` fix is the demonstration of the change's premise: `--no-deps`, no re-bind of `basePort`, peers rewritten to the base stack. Splitting them out would require a second PR against a file PR 1 edits anyway (the `sha256` → `fingerprint` rename), guaranteeing a conflict. `healthPath` is removed, not redesigned.

### D4 — Slicing: **Feature Branch Chain, tracker `feat/portable-multi-stack`, 3 child PRs**

| # | Slice | Content | Forecast |
|---|---|---|---|
| 1 | Portability + runtime | frontmatter `compatibility`; Hard Rules (drop CodeGraph, split `/tmp`, demote `lsof` to heuristic); Execution Steps 1–2 → XDG path; `sha256`→`fingerprint` + `fingerprintTool`; `schemaVersion: 2`; `scripts/fingerprint.sh` + `scripts/pick-port.sh`; both example bugs; README status; close `open_decisions.scripts-runtime` | ~140 |
| 2 | Discovery restructure | open `kind`; add `portGroup`, `runnable: false` (retires `static`); drop `healthPath`, `dockerfile`; dedupe `sharedDirsIncluded` against `consumers`; bound `verifiedOverlays`; `discovery.md` split into path→unit and unit→launch, resolver preference, source tiering, `covers` granularity rule, `revalidate: always` | ~245 |
| 3 | Shared-state gate | `backingStores`; per-service `writes`/`competesOn`/`migrates`; `acceptedRisks`; new `references/shared-state.md`; SKILL.md gate wiring; shared-state traps | ~290 |

Ordering rationale: PR 1 first because later slices edit shapes it defines (field name, version const, manifest path) and because `sdd-design` needs the runtime decision closed. PR 2 second because `backingStores` can only be split out of `services` once `runnable: false` exists — otherwise it overlaps `kind: static`. PR 3 last: largest, most likely to need splitting, and the only slice whose correctness depends on both predecessors.

**Contingency:** if `references/shared-state.md` pushes PR 3 over 400, split into 3a (reference doc only, no schema) and 3b (schema + SKILL.md wiring + example + traps).

## Scope

### In scope

- W/X/N classification of every `(service, dependency)` pair; fail closed on unknown.
- Automated in-instance isolation (database / schema / vhost / topic prefix / distinct consumer identity) driven by `backingStores[].isolation`.
- Per-service, timestamped, recorded escape hatch in `acceptedRisks[]`, keyed by `(service, store)`, latest-only so it stays bounded.
- Discovery split into path→unit and unit→launch, leading with `docker compose config --no-interpolate --format json`.
- Two POSIX `sh` scripts (~60 lines): fingerprints via `git hash-object --no-filters`, port selection.
- Manifest schema v2, XDG location, both example bugs.

### Out of scope (explicit non-goals)

- **Windows-native support.** POSIX only, declared in `compatibility`.
- **Cache eviction/GC** of `~/.cache/stackgraft/`.
- **Embedded substrate clients.** `psql`, `redis-cli`, `rabbitmqctl`, Kafka CLI are never assumed present (see T2).
- **Resolvers that execute code**: Tilt Starlark, Aspire AppHost, Gradle. Build-graph sources are used for path→unit fan-out only, never for ports.
- **Solving the unsolvable cases.** Redis pub/sub, external SaaS side effects, host singletons, and migrations against uncloneable data are *named as refuse-cases*, not fixed.
- **Data seeding / clone strategy** beyond offering `TEMPLATE`.
- **A global bypass flag.** The escape hatch is per-service only.
- **`healthPath` replacement.** Removed outright.
- **Test runner, CI, or linter.** None exist; none are introduced.
- **`~/.claude/skills/worktree-overlay/`** — the predecessor carries every defect; retire-or-sync is a follow-up outside this repo.

## Tensions the locked decisions create

**T1 — Token budget vs. progressive disclosure (blocking constraint on `sdd-spec`).** The body is the only file loaded whole. The W/X/N gate cannot live there, so its correctness lives in `references/shared-state.md`, which the agent may never load. The Hard Rule must therefore be self-sufficient *in the refusal direction*: not reading the reference must mean "unclassified", and unclassified must mean refuse. Body allocation ceiling: PR 1 net ≤ +0 tokens (removals offset additions), PR 2 ≤ +20, PR 3 ≤ +60; final body ≤ 700.

**T2 — Full-scope isolation vs. the zero-install runtime.** Automating `CREATE DATABASE` / vhost creation / topic prefixing needs substrate-specific clients — precisely the tool assumptions the POSIX-sh decision was made to avoid. Resolution: the skill embeds no client. `backingStores[].isolation.command` is a template **discovered from the repo** (e.g. `docker compose exec postgres psql …`). If none can be discovered, `mechanism` is `none` and the gate refuses or escalates to a dedicated instance.

**T3 — `pick-port.sh` cannot deliver its name.** Port availability is not portably checkable (no `lsof` on minimal Linux, no `ss` on macOS). The script's output contract must say *candidate* port; the authoritative check stays the launcher's `--strictPort` failure.

## Capabilities

### New capabilities

- `shared-state-safety`: W/X/N classification, fail-closed default, escalation triggers, in-instance isolation, recorded per-service acceptance.
- `topology-discovery`: path→unit vs unit→launch, resolver preference and fallback, source tiering, `covers` granularity, fingerprint invalidation.
- `manifest-contract`: schema v2 fields, cache location and filename derivation, bounded log fields.
- `portable-runtime`: `scripts/` runtime contract, `compatibility` declaration, no agent-specific coupling.

### Modified capabilities

None. `openspec/specs/` contains only `.gitkeep`.

## Affected areas

| Area | Impact | Change |
|---|---|---|
| `skills/stackgraft/SKILL.md` | Modified | Frontmatter `compatibility`; Hard Rules 19/21/22; Execution Steps 1–2; gate row + reference link |
| `skills/stackgraft/assets/manifest.schema.json` | Modified | v2: `fingerprint`, `portGroup`, `runnable`, open `kind`, `backingStores`, `writes`/`competesOn`/`migrates`, `acceptedRisks`; remove `healthPath`, `dockerfile` |
| `skills/stackgraft/assets/manifest.example.json` | Modified | Both bugs; v2 shape |
| `skills/stackgraft/references/discovery.md` | Modified | Split (a)/(b), tiering, resolver preference, `covers` rule |
| `skills/stackgraft/references/traps.md` | Modified | Drop line 25; reconcile line 29; add shared-state traps |
| `skills/stackgraft/references/shared-state.md` | New | The full gate |
| `skills/stackgraft/scripts/` | New | `fingerprint.sh`, `pick-port.sh` |
| `openspec/config.yaml` | Modified | Close `open_decisions.scripts-runtime` |
| `README.md` | Modified | Status |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Fail-closed gate refuses everything; users route around it | High | Cheap observable escalation triggers auto-classify the common case; per-service recorded escape hatch (locked D-2 from context) |
| SKILL.md body breaches 700 tokens | Med | Per-slice ceilings (T1); token count is a verify gate on every slice |
| Substrate isolation command unavailable | High | `mechanism: none` → refuse or dedicated instance; never assume a client binary |
| PR 3 exceeds 400 lines | Med | Pre-declared 3a/3b split |
| POSIX claims unverified on minimal Linux | Med | PR 1 verification must include `dash -n` on both scripts and `command -v git awk` on macOS + a minimal Linux container |
| Reviewer sees an intermediate half-migrated schema | Low | Feature Branch Chain; `main` only sees the tracker merge |

## Rollback

The skill is copy-a-folder: revert the tracker merge, or restore the previous `skills/stackgraft/`. **Manifest migration: none.** v2 is unrecognized by a v1 reader, and `discovery.md`'s discard-and-rediscover rule already handles that in the safe direction. After a rollback, orphan files remain in `~/.cache/stackgraft/` because PR 1 also moves the path; they are small and inert.

## Dependencies

- `git` (already a hard dependency — the skill is about worktrees) and a POSIX `sh` + `awk`.
- `docker compose` only for compose-based repos.
- No new package, build step, or runtime.

## Success criteria

- [ ] `manifest.example.json` validates against `manifest.schema.json`.
- [ ] SKILL.md body ≤ 700 tokens; section order matches the style guide.
- [ ] Portability grep: no agent-specific path, env var, or tool name in shipped files.
- [ ] Every field named in SKILL.md or `references/` exists in the schema, and every link resolves relative to the skill directory.
- [ ] `schemaVersion` increments exactly once across the whole chain.
- [ ] Both scripts pass `dash -n` and run on macOS and a minimal Linux container.
- [ ] `open_decisions.scripts-runtime` closed in `openspec/config.yaml`.
- [ ] No overlay can launch against a base-stack store with `isolation.mechanism: "none"` without a recorded `acceptedRisks` entry.

## Proposal question round — RESOLVED

All three confirmed by the user on 2026-07-30. Each assumption held; these are now binding on `sdd-spec` and `sdd-design`.

1. **Escape-hatch lifetime — RESOLVED: invalidated when that service's source fingerprint drifts.** An `acceptedRisks` entry does not survive a change to the service it covers, because the acceptance was granted for code that no longer exists. It is not tied to full-manifest rediscovery, and it is never permanent.
2. **Chain visibility — RESOLVED: the tracker stays unmerged until all three child PRs land.** No intermediate release of PR 1 alone. `main` sees exactly one `schemaVersion` transition, and it never sees a state carrying schema 2 without the shared-state gate that makes it safe.
3. **Predecessor skill — RESOLVED: out of scope.** `~/.claude/skills/worktree-overlay/` is retired separately as a local installation task, not named in this repository's README. It was never distributed from here, so its removal is machine cleanup rather than a documented migration.
