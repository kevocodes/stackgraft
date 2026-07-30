# Design: portable-multi-stack

Phase: `sdd-design` · Input: `proposal.md` (locked) + `exploration.md` · Next: `sdd-tasks`

> Size note: the sdd-design 800-word guidance is deliberately exceeded. The launch scope requires
> resolving three named tensions, a full schema shape, two script contracts, a `covers` rule, and a
> resolver tier — each justified against an alternative. Density is held by using tables over prose.

## Technical Approach

Three mechanisms carry the whole change:

1. **A sealed default in the body.** The `SKILL.md` body holds *preconditions and refusals only*.
   Every decision procedure lives in `references/`. An agent that reads only the body can reach
   exactly two outcomes: proceed on a stateless overlay, or REFUSE. Safety therefore does not
   depend on a reference being loaded.
2. **Borrowed tooling, never embedded tooling.** The skill ships no substrate client and no JSON
   parser. Hashing borrows `git`; isolation borrows the repo's own task runner or the client already
   inside the running store container; manifest parsing is the agent's job.
3. **Degrade, never hard-fail — except where degrading would launder a guess into a safety verdict.**
   Discovery falls back through resolver tiers; the shared-state gate does not accept fallback-tier
   evidence.

## Architecture Decisions

### T1 — Progressive disclosure vs. the gate

**DS1 — The body states a precondition, never a procedure ("sealed default").**

| | |
|---|---|
| **Choice** | The body's shared-state Hard Rule names *when* a verdict is required, *where the only verdict procedure lives*, and that absence of a verdict is a refusing state. It contains no fragment of the W/X/N table. |
| **Alternative** | Summarise W/X/N in the body (3 rows, ~60 words). |
| **Rationale** | A summary is *actionable*: an agent that skips `references/shared-state.md` would still reach REUSE from the body alone, so skipping the reference becomes permissive. A precondition is not actionable — body-only knowledge can only produce REFUSE. It also removes the second source of truth that would drift against the reference. |

**DS2 — Wording contract (three properties, all observable by reading the file).**

| Property | Requirement | Violated by |
|---|---|---|
| P1 Precondition, not summary | The rule may state *that* a verdict is required and *where* it comes from. It MUST NOT state any condition under which an overlay is permitted. | Any body text containing `REUSE`, `ISOLATE`, or a W/X/N condition. |
| P2 Absence is an enumerated value | "no verdict recorded" is written as a refusing state, not left undefined. | Wording like "classify before launching" with no stated default. |
| P3 Non-delegable source | The manifest, the user's assertion, and the agent's own inference are each explicitly excluded as verdict sources. | Wording like "unless you are confident" or "unless the manifest says otherwise". |

Exact body text for PR 3 (Hard Rules), 41 words:

> An overlay that touches a `backingStores` entry is REFUSED until `references/shared-state.md` has
> been read and a verdict is recorded for every `(service, store)` pair. No verdict, no launch.
> Nothing else — not the manifest, not the user, not inference — produces a verdict.

Exact Decision Gates row for PR 3, 12 words:

> | Overlay service touches a backing store | Gate it — `references/shared-state.md` |

**DS3 — Per-slice body ceilings, measured in words with a conservative token proxy.**

Tokenisers differ across ~40 agents, so a token count is not portably checkable. Use words with a
factor of **1.4 tokens/word** (conservative for markdown carrying tables and code spans; *unverified
per tokeniser* — treat as a proxy, not a fact). Measure with a tool already required:

```sh
awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' skills/stackgraft/SKILL.md
```

| Slice | Body ceiling (words) | ≈ tokens | Net vs. previous | T1 allowance |
|---|---|---|---|---|
| baseline (today) | ~559 (recount at implementation) | ~783 | — | already over 700 |
| PR 1 | **≤ 450** | 630 | −109 | net ≤ +0 ✔ (cut is deeper) |
| PR 2 | **≤ 462** | 647 | +12 words ≈ +17 tok | ≤ +20 ✔ |
| PR 3 | **≤ 500** | 700 | +38 words ≈ +53 tok | ≤ +60 ✔ |

The baseline is already above the 700 recommendation, so PR 1 is a **compaction slice**, not a
net-zero one. Named donors for the −109: CodeGraph clause (−11), the `lsof -a -p …` string in Hard
Rule 3 (−9, verbatim in `traps.md:8`), Hard Rule 2 `lsof` demotion rewrite (−8), Hard Rule 5
compression (−6, verbatim in `traps.md:13`), Activation Contract (−8), Execution Steps 3–8 (−20),
Output Contract (−16), References descriptions (−14), Decision Gates rows (−15). **Contingency:**
if PR 1 cannot reach 450, collapse Execution Steps 5–8 to one line each and let
`references/discovery.md` §5 (which already documents the wiring) carry the detail. The Output
Contract stays in the body unconditionally — it defines the return value, and a reference may not load.

### T2 — Automated isolation vs. zero install

**DS4 — `isolation.command` is discovered on a four-rung ladder; the skill embeds no client.**

| Rung | Source | Template shape | Confidence |
|---|---|---|---|
| 1 | Repo task runner: `Makefile` target, `Taskfile.yml`, `justfile`, `package.json` script, `bin/*`, `scripts/*` whose name matches an isolation intent (`db:create`, `createdb`, `db:setup`, `vhost`, `topic`) | `make db-create DB={{isolationName}}` | `declared` |
| 2 | Client **inside the running store container**, when a resolver reports the store service | `docker compose exec -T postgres psql -U {{user}} -d postgres -c 'CREATE DATABASE {{isolationName}} TEMPLATE {{templateName}}'` | `inferred` |
| 3 | No server-side command needed — isolation is an overlay env/URI change (`applyVia: "env"`): Mongo db name, Redis `SELECT n`, S3 key prefix, Kafka `group.id`, index prefix | no `command`; `env` map only | `declared` or `inferred` |
| 4 | Nothing discoverable | `mechanism: "none"` | — |

**Choice**: borrow the client from the substrate container (rung 2), never from the host.
**Alternative**: ship per-substrate SQL/CLI snippets in the skill. **Rationale**: the exploration's
per-substrate table shows the real cost is repo-specific (roles and extensions must pre-exist,
`TEMPLATE` needs no active connections, vhosts need permissions). Shipped snippets encode
credentials and topology the skill cannot know, and reintroduce the host-tool assumption POSIX `sh`
was chosen to avoid. **Alternative rejected**: tell the user to run isolation by hand — that is the
step people skip, and it is exactly how the gate gets routed around (proposal risk R1).

*Unverified*: that official store images ship their client on `PATH` (`psql` in `postgres`,
`rabbitmqctl` in `rabbitmq`). The design does not depend on it — rung 2 is recorded as `inferred`,
and a first-use failure downgrades the store to `mechanism: "none"`, which refuses.

**DS5 — Template contract: one program, no shell grammar.**

| Rule | Detail |
|---|---|
| Placeholders | Closed set: `{{isolationName}}`, `{{templateName}}`, `{{store}}`, `{{worktree}}`, `{{repoRoot}}`, `{{port}}`. Any other `{{…}}` ⇒ template invalid ⇒ `mechanism: "none"`. |
| Character deny-list | `` ` `` `$` `;` `&` `|` `>` `<` and newline are forbidden anywhere in the raw template. |
| One program | The template invokes a single program with arguments. Pipelines, chains, and redirection are not expressible — a repo needing them must wrap them in its own task target (rung 1), which the developer already runs. |
| Name generation | `{{isolationName}}` is generated by stackgraft, never read from the repo: `sg_<branch-slug>_<hash8>` matching `^[a-z][a-z0-9_]{0,39}$`. |
| Destructive verbs | Reject a template containing `DROP DATABASE`/`DROP SCHEMA` of a name not derived from `{{isolationName}}`, `FLUSHALL`, `FLUSHDB`, `compose down`, `-v`, `--volumes`, `rm -rf`. |
| Execution | Prefer argv execution. When the agent has only a shell tool, the deny-list plus the name regex are what make `sh -c` safe. |
| Approval | Show the substituted command and its target store before the first run per `(repo, store)`. Record `isolation.approval {at, sourceFingerprint}`. Re-prompt when `discoveredFrom`'s source fingerprint drifts — same invalidation semantics as the locked escape hatch. |

**Rationale**: the template is discovered from repository data, so it travels with any branch a user
checks out. Without the deny-list, discovery becomes an arbitrary-execution path on the developer's
machine. Allowing a repo's own task runner as the single program keeps expressiveness without
synthesising a shell pipeline from untrusted data.

### T3 — `pick-port.sh` emits a candidate, not a guarantee

**DS6 — Candidate contract + caller reconciliation.**

The script never probes. `lsof`/`ss`/`nc` are absent on one platform or the other, and a "free"
reading is stale the moment it is taken. The authoritative test is the launcher's strict-bind
failure, which `traps.md:9` already mandates.

Caller protocol on a taken candidate:

1. Launch with a strict-bind flag (`--strictPort`, `--host-port`, `--publish`). A taken port must
   fail loudly. A launcher with no strict flag ⇒ read the actually-bound port from its own output
   before recording anything.
2. On bind failure: append the candidate to the in-memory exclude list, re-run `pick-port.sh` with
   the same range, retry. **Maximum 3 attempts**, then stop and ask the user.
3. Transient exclusions are **never** persisted to `portPolicy.reserved`. `reserved` is user-owned;
   writing failures into it erodes the range permanently.
4. An agent that happens to have `lsof` may pre-check, but a "free" result never authorises skipping
   the strict-bind check.

**DS7 — Deterministic-per-worktree start offset instead of lowest-first.**

**Choice**: `start = lo + (hash8(worktree path) mod (hi − lo + 1))`, scan upward with wraparound,
skipping excludes. **Alternative**: always the lowest non-excluded port. **Rationale**: lowest-first
makes two concurrent worktrees collide by construction, because neither can know the other's ports.
An offset derived from the worktree path spreads them, and is still deterministic — the same branch
gets the same port across runs, so a CORS allowlist entry or a bookmark keeps working. Cost is three
lines and `git hash-object --stdin`, already a required tool. **Alternative rejected**: random pick
— loses run-to-run stability, which is the property the CORS constraint class depends on.

### Schema v2

**DS8 — `backingStores` is a top-level sibling of `services`.**
**Alternative**: a `role: "store"` discriminator inside `services`. **Rationale**: the gate must
resolve a dependency *name* to a store record without first proving it is not an app service; and a
single namespace forces `additionalProperties: false` to accept the union of both field sets, losing
the schema's ability to reject `overlayCommand` on a store. **Collision rule**: a name MUST NOT
appear in both maps; `dependsOn`/`writes` resolve `backingStores` first; a name in neither is
**unknown ⇒ fail closed**.

**DS9 — `kind` open, `portGroup` load-bearing.** `kind` becomes `type: "string"` with `examples`;
it is purely descriptive. `portGroup` (string) keys `portPolicy.ranges` and is **required when
`runnable` is true**. A missing `ranges` key ⇒ stop and ask (reuses the existing Hard Rule).
**Alternative rejected**: default `portGroup = kind` — silently reinstates the coupling being
removed, and mis-keys on the first unknown kind.

**DS10 — `runnable: false` retires `kind: "static"`.** Default `true`. When `false`, the schema
forbids `basePort`, `portGroup`, `overlayCommand`, `verifyRequest`, `peerEnv` (draft-2020-12
`if/then` with `"<field>": false`) and requires `paths` + `consumers`.

**DS11 — `fingerprint` + top-level `fingerprintTool`.** `fingerprint` is an opaque string with **no
`pattern`** — a repo with `extensions.objectFormat=sha256` produces a different length, and a
pattern would reject it. `fingerprintTool` is one value per manifest (e.g.
`"git-hash-object-no-filters"`); a mismatch against the current tool marks **every** source drifted,
i.e. full rediscovery — the same fail-safe direction as an unrecognised `schemaVersion`.
**Alternative rejected**: per-source tool — extra surface, no use case. Also add per-source
`revalidate: "fingerprint" | "always"` (default `fingerprint`) for sources whose real input set is
not enumerable (Tiltfile, Aspire AppHost).

**DS12 — `healthPath` removed outright.** No replacement; `verifyRequest` is the only proof. An old
manifest carrying it now fails `additionalProperties: false`, which is harmless because
`schemaVersion: 2` already forces rediscovery.

**DS13 — Duplication resolved toward `consumers`; `sharedDirsIncluded` and `dockerfile` dropped.**
**Rationale**: one shared tree lists N consumers in one place; the inverse encoding needs N booleans
that must all stay in sync with one fact, so the drift surface is N× larger. `consumers` is the
derived answer; `dockerfile` was only an input to computing it. The existing Decision Gates row
already reads `consumers`, so the body needs no change. **Cost named honestly**: if no shared entry
was discovered, no consumer fan-out exists — mitigated by requiring `consumers` on every
`runnable: false` entry, and by `discovery.md` stating "read each service's Dockerfile once, record
the *result* as membership in the shared entry's `consumers`".

**DS14 — `verifiedOverlays` and `acceptedRisks` become keyed maps, not arrays.**
`verifiedOverlays` → object keyed by service name, latest record only. **Alternative**: array with
`maxItems` + trim. **Rationale**: the field's stated purpose is "evidence the entry is still
correct" — only the latest record is evidence. Keying by service gives an O(services) bound with no
trim policy and no tie-break. `acceptedRisks` → object keyed by `"<service>::<store>"`; a JSON
object cannot hold duplicate keys, so the proposal's "keyed by (service, store), latest-only" becomes
structural rather than procedural. *This refines the proposal's `acceptedRisks[]` notation without
changing its semantics.*

**DS15 — Classification fields distinguish "verified none" from "unknown".**
`writes: []` and `competesOn: []` mean *checked, none*; **absent means unknown ⇒ fail closed**. That
`[] ≠ absent` distinction is the entire encoding. Because `[]` alone is unfalsifiable — a lazy pass
could emit it everywhere and permanently disarm the gate — any service carrying `writes`,
`competesOn`, or `migrates` MUST also carry `stateReview { at, method }` with
`method ∈ {code-scan, user-asserted, resolver-declared}`. `traps.md` then gets a checkable
statement: *an all-`[]` manifest with `method: user-asserted` is the shape of a disarmed gate.*

**DS16 — `serviceFingerprint` for escape-hatch invalidation.** The locked rule is that an
`acceptedRisks` entry dies when that service's source drifts, so a value is needed. Definition —
`git hash-object --stdin` over the concatenation of, in order:

1. `git ls-files -s -- <service paths>` (index object ids — one process, no per-file hashing),
2. `git diff --no-color --binary -- <service paths>` (unstaged delta; `--binary` because a binary
   edit otherwise renders as "Binary files differ" and would not move the hash),
3. `git ls-files --others --exclude-standard -- <service paths>` piped through `fingerprint.sh`
   (untracked files, normally few).

**Alternative rejected**: hashing every tracked file — hundreds of `git hash-object` spawns per
service. **Alternative rejected**: `git rev-parse HEAD:<dir>` — misses uncommitted work, which is
exactly the state an overlay runs. *Unverified on this machine*: only
`git hash-object --no-filters` was verified by the orchestrator; this three-part composition must be
checked during PR 3 verification.

### Discovery

**DS17 — `covers` granularity: dotted key paths, normalised by subsumption, over-refresh on tie.**

| Rule | Detail |
|---|---|
| Vocabulary | `services`, `services.<name>`, `backingStores`, `backingStores.<name>`, `baseStack`, `portPolicy`, `constraints`. |
| Refresh set | Union the drifted entries' `covers`, then **remove any token that is a strict descendant of another token in the set**. |
| Coarse wins | Refreshing `services` re-derives the whole `services` object from every source covering any part of it, including entries whose own source did not drift. Over-refresh is cheap; under-refresh is silent staleness. |
| Fine stays fine | `services.frontend` drift refreshes only that key. It may create, update, or delete that one key — never another. |
| Evidence is not derived | `verifiedOverlays` and `acceptedRisks` are invalid `covers` targets (schema-enforced by `not: {pattern: "^(verifiedOverlays\|acceptedRisks)"}`). |
| Evidence invalidation | Refreshing `services.<name>` drops `verifiedOverlays[<name>]` and invalidates every `acceptedRisks["<name>::*"]`. |

**Alternative rejected**: forbid coarse tokens and require one token per service — a compose file
genuinely defines all services, and enumerating them makes the source entry churn on every service
added, defeating slice refresh entirely.

**DS18 — Resolver tiering degrades; the gate does not accept degraded evidence.**

| Tier | Behaviour | Records |
|---|---|---|
| R1 preferred | `docker compose config --no-interpolate --format json` | `confidence: "declared"` |
| R2 fallback | Hand-parse the compose file set, best-effort on `-f` / `COMPOSE_FILE` / override auto-merge | `confidence: "inferred"` |
| R3 last resort | Ask the user once, cache the answer | `confidence: "user"` |
| Never | Resolvers that execute repo code — Tilt Starlark, Aspire AppHost, Gradle (locked non-goal) | — |

Availability: probe `docker compose version` (no daemon needed), then run the config call. **Any**
failure — daemon down, permission denied, timeout — degrades to R2 and records `resolverStatus` on
the source entry. Discovery never hard-fails on an unavailable resolver.

**Safety interlock (the reason tiering and T2 are one design, not two):** entries at
`confidence: "inferred"` or `"user"` MUST NOT satisfy the shared-state gate.
`backingStores[].isolation` and the `writes`/`competesOn` classification require
`confidence: "declared"`. Without this, the fallback path launders guesses into safety verdicts and
the gate becomes decoration.

*Unverified* (exploration marked them so, and they stay so): `cargo metadata`, `go list -m -json`,
`nx show projects --json`, `kubectl kustomize` as read-only resolvers; `/tmp` cleanup retention
windows (state the hazard qualitatively, never numerically).

### Runtime and location

**DS19 — Runtime: POSIX `sh` + `git` + POSIX `awk`; invoked as `sh scripts/<name>.sh`.**
No install step because all three are present on a stock macOS and a minimal Linux, and `git` is a
definitional dependency of a worktree skill. Scripts are invoked via `sh <path>` so neither the
executable bit nor the shebang is load-bearing — several agents copy skill folders without
preserving file modes. Closes `open_decisions.scripts-runtime`.

**DS20 — Unwritable cache ⇒ run manifest-less, never relocate.** If
`${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/` cannot be created or written, perform full discovery
every run and say so. **Alternative rejected**: fall back to a second location — that splits the
cache silently and produces two divergent truths. Additionally, since `hash8` is 32 bits, a loaded
manifest whose `repoRoot` differs from the resolved one is a collision: discard and rediscover.

## Interfaces / Contracts

### `scripts/fingerprint.sh`

```
usage:  sh scripts/fingerprint.sh [repoRoot]
stdin:  one path per line (relative to repoRoot, or absolute)
stdout: one line per input line, in input order:  <fingerprint>\t<path>
        unreadable path, directory, or hash failure  ->  "-\t<path>"
exit:   0 ok · 2 usage / cd failed
```

Body is a `while IFS= read -r p` loop calling `git hash-object --no-filters -- "$p"` — the exact form
verified by the orchestrator. **Alternative rejected**: batching paths per call (which `git` does
support). It saves ~50–100 ms on a 30-entry `sources[]` and costs the per-path error isolation that
makes `-` reporting simple. Revisit only if a repo's `sources[]` exceeds ~200 entries. `-` is a
meaningful value, not an error: a disappeared source is legitimate drift (`discovery.md:40`).

### `scripts/pick-port.sh`

```
usage:  sh scripts/pick-port.sh <lo> <hi> [worktree-path]
stdin:  zero or more excluded ports, one integer per line
stdout: exactly one integer + newline — a CANDIDATE, not a verified-free port
exit:   0 candidate emitted · 2 usage error · 3 range exhausted (stdout empty)
```

Neither script parses JSON or YAML. Both avoid `stat`, `readlink -f`, `sed -i`, and bash-4 idioms
(macOS ships bash 3.2). `date -u +%Y-%m-%dT%H:%M:%SZ` is the only timestamp form used.

### Manifest v2 skeleton (shape only)

```jsonc
{
  "schemaVersion": 2,
  "repoRoot": "…", "discoveredAt": "…", "fingerprintTool": "git-hash-object-no-filters",
  "sources": [{ "path": "…", "fingerprint": "…", "covers": ["services"],
                "revalidate": "fingerprint", "confidence": "declared", "resolverStatus": "ok" }],
  "baseStack": { "startCommand": "…", "statusCommand": "…", "teardownCommand": "…", "bindsTo": "…" },
  "backingStores": {
    "postgres": {
      "substrate": "postgres",
      "isolation": {
        "mechanism": "database",           // open string; "none" is legal and meaningful
        "applyVia": "command",             // command | env | copy | none
        "command": "…{{isolationName}}…", "teardownCommand": "…",
        "env": { "DATABASE_URL": "…{{isolationName}}" },
        "discoveredFrom": "docker-compose.yml#services.postgres",
        "confidence": "inferred",
        "approval": { "at": "…", "sourceFingerprint": "…" }
      },
      "notes": ["TEMPLATE requires no active connections to the source database"]
    }
  },
  "services": {
    "catalog-api": {
      "kind": "docker-compose", "portGroup": "compose", "runnable": true,
      "basePort": 8080, "paths": ["services/catalog/**"], "buildContext": "…",
      "dependsOn": ["postgres"], "reads": ["postgres"], "writes": ["postgres"],
      "competesOn": [{ "store": "kafka", "identity": "group.id" }], "migrates": true,
      "stateReview": { "at": "…", "method": "code-scan" },
      "peerEnv": { "SEARCH_URL": "http://localhost:8090" },
      "verifyRequest": "…", "overlayCommand": "…", "prepareCommand": "…", "notes": []
    },
    "backend-shared": { "runnable": false, "paths": ["packages/contracts/**"],
                        "consumers": ["catalog-api", "search-indexer"] }
  },
  "portPolicy": { "reserved": [3000, 5173], "ranges": { "node-dev": [5174, 5199], "compose": [18000, 18999] } },
  "constraints": [{ "kind": "cors-allowlist", "where": "…", "effect": "…", "remedy": "…" }],
  "verifiedOverlays": { "frontend": { "port": 5174, "at": "…", "worktree": "…", "result": "…" } },
  "acceptedRisks": { "catalog-api::postgres": { "at": "…", "serviceFingerprint": "…",
                                                 "reason": "…", "acceptedBy": "user" } }
}
```

Removed from v1: `sha256`, `healthPath`, `dockerfile`, `sharedDirsIncluded`, `kind` enum,
array-shaped `verifiedOverlays`.

## Data Flow

```
worktree ──git diff──► changed paths ──┐
                                       │
XDG cache manifest ──fingerprint.sh──► drift? ──► refresh set (covers ∪, subsumption)
   │  repoRoot mismatch ──► discard            │
   │  unwritable ──► manifest-less run         ▼
   └───────────────────────────────► paths→unit map (services[].paths, consumers fan-out)
                                               │
                                        overlay set S
                     ┌─────────────────────────┴──────────────────────────┐
                     ▼                                                    ▼
        shared-state gate (references/shared-state.md)          pick-port.sh → CANDIDATE
        per (S, store): W / X / N                                          │
        needs confidence:"declared"                              strict bind ──fail──┐
              │                                                            │        │
     REUSE ───┤ ISOLATE ──► isolation.command|env (approved, deny-listed)  │  exclude + retry ≤3
     REFUSE ──┴──► acceptedRisks[svc::store] or dedicated instance         │        │
                     └──────────────► launch (peerEnv rewritten) ◄─────────┴────────┘
                                               ▼
                              verifyRequest ──► verifiedOverlays[service]
```

## File Changes

| File | Action | PR | Description |
|---|---|---|---|
| `skills/stackgraft/SKILL.md` | Modify | 1,2,3 | Frontmatter `compatibility`; compaction to ≤450 words; XDG path; sealed-default Hard Rule + gate row (PR 3) |
| `skills/stackgraft/assets/manifest.schema.json` | Modify | 1,2,3 | `schemaVersion: 2` + `fingerprint`/`fingerprintTool` (1); `kind`/`portGroup`/`runnable`/`revalidate`/`covers` pattern, drop `healthPath`+`dockerfile`+`sharedDirsIncluded`, keyed `verifiedOverlays` (2); `backingStores`, `writes`/`competesOn`/`migrates`/`stateReview`, `acceptedRisks` (3) |
| `skills/stackgraft/assets/manifest.example.json` | Modify | 1,2,3 | Drop root `_comment`; fix `overlayCommand` (`--no-deps`, no `basePort` re-bind, peers → base stack); v2 shape |
| `skills/stackgraft/references/discovery.md` | Modify | 2 | Split path→unit / unit→launch; source tiering; resolver preference + degradation; `covers` rule; `revalidate: always` |
| `skills/stackgraft/references/traps.md` | Modify | 1,3 | Drop line 25 (CodeGraph); reconcile line 29 with `--no-interpolate`; add shared-state traps incl. the disarmed-gate shape |
| `skills/stackgraft/references/shared-state.md` | Create | 3 | The full W/X/N gate, escalation triggers, per-substrate table, isolation ladder, template deny-list, `serviceFingerprint` recipe |
| `skills/stackgraft/scripts/fingerprint.sh` | Create | 1 | Contract above |
| `skills/stackgraft/scripts/pick-port.sh` | Create | 1 | Contract above |
| `openspec/config.yaml` | Modify | 1 | Close `open_decisions.scripts-runtime` |
| `README.md` | Modify | 1 | Status |

**New files vs. the agentskills.io folder contract**: `references/shared-state.md` is on-demand
detail — the exact category `references/` exists for, and the only way the gate fits the body budget.
`scripts/` is the spec's sanctioned place for deterministic helpers; the spec notes supported script
languages depend on the agent, which is a second argument for POSIX `sh`.

**Portability impact for non-Claude agents**: no agent-specific path, env var, or tool name ships.
`~/.claude/…` → XDG; CodeGraph removed with no generalised successor. Agents without a `scripts/`
execution capability lose nothing structural — both scripts are ~15-line recipes an agent can inline.
Agents that copy folders without file modes are covered by `sh <path>` invocation. POSIX-only is
declared in `compatibility` (≤500 chars) rather than half-supported.

## Verification Strategy

`openspec/config.yaml` records no test runner, no CI, no linter. These are review-time checks, not
automated tests; nothing new is introduced.

| Layer | What | How |
|---|---|---|
| Static | Both scripts are POSIX | `dash -n scripts/*.sh`; `command -v git awk` on macOS and a minimal Linux container |
| Static | Body budget | the `awk` word count in DS3, per slice |
| Static | Schema/example agreement | JSON parse + validate `manifest.example.json` against `manifest.schema.json` |
| Static | Portability grep | no `~/.claude`, no `codegraph`, no single-agent tool name in shipped files |
| Static | Cross-file | every field named in `SKILL.md`/`references/` exists in the schema; every link resolves relative to the skill directory |
| Static | Sealed default | `SKILL.md` body contains no `REUSE`/`ISOLATE`/W/X/N condition (DS2 P1) |
| Behavioural | `git hash-object --no-filters` on a sample file; the three-part `serviceFingerprint` composition | run once on macOS and minimal Linux (PR 1 and PR 3) |
| Fixture | Template deny-list | a fixture table of rejected templates in `references/shared-state.md`, each with the rule it violates |

## Threat Matrix

| Boundary | Applicability | Design response | Planned check |
|---|---|---|---|
| Documentation-like paths | **Applicable** — `Makefile`, `Taskfile.yml`, `justfile`, `package.json` scripts are discovered *and invoked* as isolation templates | DS5: closed placeholder set, character deny-list, one-program rule, destructive-verb rejection, stackgraft-generated `{{isolationName}}`, approval before first run | Deny-list fixture table; one rejected example per rule |
| Git repository selection | **Applicable** — `git rev-parse --path-format=absolute --git-common-dir`, worktree vs. common dir, relative vs. absolute paths | `repoRoot` is the main worktree; manifest keyed by the common dir hash; `repoRoot` mismatch on load ⇒ discard; `fingerprint.sh` resolves paths against a caller-set cwd (`cd … && pwd -P`, never `readlink -f`) | Run from a linked worktree, a subdirectory, and a symlinked path; assert one manifest file |
| Commit state | **Applicable** — `serviceFingerprint` must cover staged, unstaged, and untracked work | DS16 three-part composition, `--binary` on the diff | Fixture: stage-only edit, unstaged-only edit, untracked-only file, unstaged binary edit — each must move the fingerprint |
| Push state | **N/A** — the skill never pushes | — | — |
| PR commands | **N/A** — the skill runs no VCS/PR automation | — | — |

## Migration / Rollout

**No manifest migration.** A v1 reader does not recognise `schemaVersion: 2` and `discovery.md:42`
already discards-and-rediscovers, which fails in the safe direction. Because PR 1 also moves the
cache path, v1 files remain orphaned under the old location — small, inert, and out of scope
(eviction is a locked non-goal). Chain rule from D2 holds: **no child PR after PR 1 touches
`schemaVersion`.** Tracker stays unmerged until all three child PRs land, so `main` never sees
schema 2 without the gate.

**Rollback**: revert the tracker merge, or restore the previous `skills/stackgraft/`.

## Open Questions

- [ ] Non-blocking: does any commonly-used store image lack its client on `PATH`, making rung 2
      systematically `mechanism: "none"` for that substrate? Handled safely either way (refuse), but
      it changes how often the gate refuses in practice. Resolve by observation, not by assumption.
- [ ] Non-blocking: the 1.4 tokens/word proxy is unverified against any specific tokeniser. If PR 1
      verification shows a materially different ratio, adjust the word ceilings in DS3, not the
      700-token target.
- [ ] Non-blocking: `stateReview` (DS15) adds one object per service to discovery's workload. If
      PR 3 verification shows discovery cannot populate it, the fallback is
      `method: "user-asserted"` with an explicit trap entry — not dropping the field, which would
      make `[]` unfalsifiable.
