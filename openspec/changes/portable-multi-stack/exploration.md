# Exploration: portable-multi-stack

Phase: `sdd-explore` · Status: complete · Next: `sdd-propose`

The baseline under `skills/stackgraft/` is a rename of a Claude-Code-local skill (`worktree-overlay`) promoted to a portable one without a portability pass. That origin explains the leaked conventions found below.

## Verification status

| Claim class | How verified |
|---|---|
| Repo contents, draft baseline, predecessor skill | Read directly |
| Agent Skills spec (frontmatter, `scripts/`, `compatibility`) | agentskills.io/specification |
| XDG defaults, cache-vs-state wording | freedesktop basedir spec |
| `docker compose config` flags, `run` dependency behavior, `include` | Docker docs |
| `git hash-object` semantics | git-scm docs |
| macOS `python3` stub, Perl/Ruby status, bash 3.2 | Web search, consistent secondary sources |
| Redis pub/sub crosses logical DBs; Kafka group semantics | redis.io + Kafka docs |
| `git hash-object --no-filters` on this machine | **Verified by orchestrator** — hashes multiple paths in one call, including a file outside the work tree |
| `manifest.example.json` violates its own schema | **Verified by orchestrator** — root `_comment` under `additionalProperties: false` |
| `/tmp` cleanup retention values per distro | **NOT verified** — treat as directional, not numeric |

## Pre-existing defects (independent of the five questions)

1. **`manifest.example.json` does not validate against `manifest.schema.json`.** Root-level `_comment` under `additionalProperties: false`. `openspec/config.yaml` already lists example-validates-against-schema as a verification method.
2. **The example's `overlayCommand` contradicts the skill's premise.** `docker compose run` starts dependencies unless `--no-deps` is passed, and deliberately does not publish ports unless `--service-ports` re-enables them. The line therefore (a) starts its own `postgres` and peers instead of reusing the base stack, and (b) tries to bind base port `8080` that the base container already holds. The project name also derives from the directory, so the worktree becomes a separate compose project with its own network — peer DNS resolves to the duplicate, not the base. Direct evidence that the draft has **no enforcement mechanism** connecting `dependsOn` to actual reuse.
3. **`healthPath` contradicts a Hard Rule.** `SKILL.md:22` and `traps.md:13` both say a `200` on `/health` is not proof, yet the schema ships the field — inviting the mistake the skill forbids.

---

## Q1 — Shared mutable state

Worse than the draft implies. There are **two** hazards, not one:

- **H1 — Contamination.** The overlay writes state the base stack reads. Migrations, inserts, deletes, cache writes. Damage lands on the base stack's **data**.
- **H2 — Theft.** The overlay *attaches* to a coordination primitive and takes work away from the base stack: consumer group members, queue subscribers, advisory/leader locks, replication slots, cron singletons. Damage lands on the base stack's **behavior**, in a service the user never modified. H2 is nastier for exactly that reason.

The draft models neither. `dependsOn: ["postgres"]` records that a dependency exists and nothing about what happens when two writers share it.

### The decision rule

For every pair `(overlay service S, dependency D)` where D resolves to the base stack, evaluate three booleans:

- **W** — does S *mutate* D? (INSERT/UPDATE/DDL/migration, PUBLISH, PUT, SET, enqueue)
- **X** — is attaching to D *competitive or exclusive*? (consumer group, queue subscriber, advisory/leader lock, replication slot, uniquely-named durable resource, scheduler singleton)
- **N** — does a namespace isolation mechanism exist **inside D's already-running instance**? (separate database, schema, vhost, index prefix, bucket, key prefix, topic prefix, distinct group id, distinct durable name)

| W | X | N | Verdict |
|:-:|:-:|:-:|---|
| no | no | — | **REUSE** the base D. The only unconditionally safe case. |
| no | **yes** | — | **REFUSE** plain attach. Read-only is not sufficient when the read protocol is competitive — a Kafka consumer joining the base `group.id` steals partitions even if it only logs. Require a distinct consumer identity, then re-evaluate. |
| **yes** | — | yes | **ISOLATE** inside the base instance. Reuse the *server process*, never the *namespace*. |
| **yes** | — | no | **REFUSE**, or start a dedicated D. Never reuse. |
| unknown | unknown | unknown | Treat as `W=yes, X=yes, N=no` → **REFUSE**. Fail closed. |

The last row is what makes this encodable. Discovery will often fail to determine whether a service writes. Silence must mean unsafe, or the gate is decoration.

### Automatic escalation triggers

Force ISOLATE-or-REFUSE regardless of what the manifest claims — observable from the diff and cheap to check:

- The worktree diff touches a migrations directory, or `overlayCommand`/`prepareCommand` contains a migrate step (`db:migrate`, `alembic`, `rake db:`, `prisma migrate`).
- The service's entrypoint is a scheduler, cron, beat, or worker singleton.
- The service sends externally-visible side effects (email, SMS, webhooks, payments).

### Per-substrate isolation, with honest cost

| Substrate | Cheap in-instance isolation | Cost / gotcha |
|---|---|---|
| PostgreSQL | New database (`CREATE DATABASE x TEMPLATE base`) or new schema + `search_path` | `TEMPLATE` requires no active connections to the source; `search_path` fails if code hardcodes schema; roles/extensions must pre-exist |
| MySQL / MariaDB | New schema (= database) | Same class |
| SQLite | Copy the file | Trivially safe — separate file, no shared server |
| MongoDB | New database name in the URI | Trivially safe |
| Redis (keys) | `SELECT <n>` — 16 logical DBs by default | **Redis Cluster has no multiple DBs.** `FLUSHALL` crosses all DBs. Many clients pin db 0 |
| Redis (pub/sub) | **None** | Pub/Sub has no relation to the keyspace — publishing on db 10 is heard by a subscriber on db 1. `SELECT` does not isolate it |
| Kafka | Distinct `group.id` + topic prefix | Same `group.id` → partitions divided, only the assigned member consumes → **steal**. Different `group.id` → overlay also receives everything → **duplicated side effects**. Neither is free |
| RabbitMQ | Separate vhost, or own exchange + distinct queue names | Consuming an existing queue is round-robin **steal**. vhost needs permissions |
| NATS / JetStream | Subject prefix, distinct durable consumer name | Queue groups steal like Kafka |
| Object storage (S3/MinIO) | Separate bucket, or key prefix | Prefix isolation needs app-level config; lifecycle rules may not follow |
| Elasticsearch / OpenSearch | Separate index or index prefix behind an alias | Mapping conflicts if the alias is shared |
| CDC / logical replication | Unique slot + publication name | Duplicate slot name errors, or unbounded WAL retention |
| Cron / scheduler / leader-elected worker | **Do not run it in the overlay** | Double-firing = duplicate emails, duplicate charges. Leader-election libraries actively fight |
| External SaaS (payments, email, SMS) | **None at the infra layer** | Requires app-level sandbox credentials |

### Cases with no safe answer

1. **Schema migration against a shared database too large or slow to clone.** No correct overlay. Accept a dedicated instance and pay the seed cost, or refuse. No middle option.
2. **Redis pub/sub.** Logical DB selection does not isolate channels; channel prefixing is an application change, not an overlay knob.
3. **Externally-visible side effects.** No infrastructure trick isolates a real email or a real charge.
4. **Host singletons.** Fixed unix socket path, fixed lockfile, host bind-mount, port hardcoded in source. Two instances collide by construction.
5. **When the shared state *is* the thing under test.** Verifying a migration against production-like data cannot be done in an isolated copy, nor safely in the shared one.
6. **Exactly-once consumption where the base consumer is under observation.** Any distinct-group workaround changes what is being measured.

### The framing that should drive the design

**Share compute. Isolate state.** The draft has this inverted. Application services are expensive to build and safe to share; datastores are cheap to run and dangerous to share. A second Postgres container costs a few hundred MB and seconds; a second copy of 33 application services costs minutes and gigabytes. Cheapest correct default: reuse the base stack's **stateless services**, and isolate state **inside the already-running datastore instance** (new database / vhost / prefix) so no second container is needed at all.

### Manifest shape sketch

Backing stores are not "services you might overlay" — separate them:

```jsonc
"backingStores": {
  "postgres": {
    "substrate": "postgres",
    "isolation": { "mechanism": "database", "template": "...", "cost": "seconds" }
    // mechanism: "none" is a legal, meaningful value
  }
},
"services": {
  "catalog-api": {
    "reads":  ["postgres"],
    "writes": ["postgres"],                                   // default when unknown
    "competesOn": [{ "store": "kafka", "identity": "group.id" }],
    "migrates": true
  }
}
```

Gate: refuse to launch any overlay whose `writes` or `competesOn` resolves to a base-stack store with `isolation.mechanism: "none"`, unless the user explicitly accepts — and record that acceptance in `verifiedOverlays` so it is auditable rather than forgotten.

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| A. Refuse all stateful overlays | Trivially correct | Kills most real use cases | Low |
| B. Warn, let the user decide | Cheap, flexible | Warnings become noise and get accepted by reflex; the failure is silent so the warning is the only signal | Low |
| **C. Classify + isolate-in-place, fail closed** | Correct by construction; reuses the base server so cost stays near zero; encodable as a gate | New manifest fields, per-substrate knowledge, real discovery work | Medium-High |
| D. Always duplicate every stateful dep | Simple, safe | Loses the seed data; many services fail on empty state | Medium |

**Recommend C**, with D as the documented fallback when `isolation.mechanism: "none"`.

---

## Q2 — Multi-stack topology discovery

### Structural findings

**`kind` conflates three orthogonal things:** launch mechanism, port-allocation family (`portPolicy.ranges` is keyed by it, so the enum is load-bearing), and runnability. `"kind": "static"` on `backend-shared` is the smell — it is not a kind of thing to run, it means *not runnable, exists only for path fan-out*. Replace with `runnable: false` and `static` disappears on its own.

**Discovery is two problems the current `discovery.md` treats as one:**

- **(a) path → unit** — which changed files belong to which runnable unit
- **(b) unit → launch / port / peers** — how to start it, where it binds, how it finds dependencies

`go.work`, Cargo workspaces, Gradle `settings.gradle`, Maven `<modules>`, Bazel, `pnpm-workspace.yaml`, `nx.json`, `turbo.json` describe a **build graph** and say nothing about ports or runtime peers. Treating them as topology sources produces confident, wrong manifests.

### Prefer the ecosystem's own resolver over hand-parsing

Highest-leverage finding for Q2. Compose alone has `-f` chains, `COMPOSE_FILE`, `compose.override.yaml` auto-merge, `extends`, `include` (recursive), profiles, and `!reset`/`!override` merge directives. Hand-parsing that is a losing game.

```
docker compose config --no-interpolate --format json
```

`config` merges the files, resolves variables, and expands short notation into canonical form; `--no-interpolate` disables variable expansion, so include/extends/override/profiles resolve **without expanding secrets** — which answers the concern `traps.md:29` raises about config dumps. `--no-env-resolution` exists too.

| Stack | Resolver | Read-only? | Verified |
|---|---|---|---|
| Compose | `docker compose config --no-interpolate --format json` | Yes | docs |
| Cargo | `cargo metadata --format-version 1 --no-deps` | Yes | no |
| Go | `go list -m -json all` | Yes | no |
| Nx | `nx show projects --json` | Yes | no |
| Kustomize | `kubectl kustomize <dir>` | Yes | no |
| Gradle | `./gradlew -q projects` | **Runs a build** | no |
| Bazel | `bazel query` | Starts a server | no |
| Tilt | `tilt dump api` | **Executes Starlark** | no |
| .NET Aspire | `dotnet run --publisher manifest ...` | **Builds and runs the AppHost** | docs |

Rule: **use the resolver when it is read-only, fast, and non-interpolating; otherwise fall back to static parse; otherwise ask the user once and cache the answer.**

### Recommended tiering

**Tier 1 — declarative, statically resolvable, answers both (a) and (b). Ship support.**

| Source | Gives |
|---|---|
| Compose family via `config --no-interpolate` | services, published ports, `depends_on`, env, build context |
| `package.json` scripts + workspace globs | dev servers, `--port` flags |
| `Procfile` / `Procfile.dev` | process list + commands |
| `.env.example` / `.env.sample` | peer URLs, constraints (never hash the real `.env`) |
| `devcontainer.json` | `forwardPorts`, `appPort`, `dockerComposeFile`, `service`, `runServices`, `portsAttributes` |
| `launchSettings.json` (.NET) | `applicationUrl` per profile = the ports |
| `Makefile` / `Taskfile.yml` / `justfile` | launch commands only, not ports |

**Tier 2 — declarative but k8s-indirect. Support if effort allows.**

- `skaffold.yaml` → `portForward:` with `localPort`. Caveat: auto-forward picks a random open port when the requested one is taken, so base ports are not predictable from the file alone.
- kustomize / plain k8s `Service` manifests → container ports; a local port only exists via `port-forward`.
- `Tiltfile` → `k8s_resource(port_forwards=...)`. Starlark *code*; static extraction is a heuristic and must be marked low-confidence.

**Tier 3 — build graph only. Use for path→unit fan-out. Never infer ports.**

`go.work`, Cargo `members`, Gradle `settings.gradle(.kts)`, Maven `<modules>`, Bazel, `nx.json`, `turbo.json` (its `persistent: true` tasks do flag dev servers — a useful hint), `pnpm-workspace.yaml`, `lerna.json`.

**Framework specifics, cheap to add:** Laravel Sail (generated compose + `APP_PORT`/`FORWARD_DB_PORT`/`VITE_PORT`), Rails (`Procfile.dev` via `bin/dev`, `config/puma.rb`), Django (`manage.py runserver`, plus `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` — those two belong in `constraints`, being exactly the silent-failure class `traps.md` documents).

### `kind`: open, not closed

- Extending a closed enum requires bumping `schemaVersion`, and the draft's own rule is to discard and rediscover any manifest with an unrecognized version. Adding one stack type would invalidate every user's cache.
- The enum's only load-bearing use is keying `portPolicy.ranges`. Decouple: add an explicit `portGroup`, key ranges by it, and let `kind` be purely descriptive.
- JSON Schema can still document the expected set via `examples` while accepting unknown strings.

### Minimum viable descriptor set

- **Required:** `paths`, `launch`, port binding (`basePort` + override mechanism), `peers` (env var → URL)
- **From Q1:** `writes` / `competesOn` / `migrates`
- **Demote or drop:** `healthPath` (contradicts a Hard Rule); `dockerfile` (only an input to computing `sharedDirsIncluded` — keep the derived answer, drop the input); `sharedDirsIncluded` (redundant with the shared entry's `consumers` list and able to drift out of sync — pick one direction of truth)

### Cache-invalidation gap

Fingerprinting `sources[].path` assumes topology lives in enumerable files. A `Tiltfile` or an Aspire `AppHost/Program.cs` can import arbitrary other files, so the fingerprint set is provably incomplete and the cache can go stale silently. Honest options: fingerprint the whole subtree, or mark such entries `revalidate: always`.

Separately, `sources[].covers` mixes granularities — `["services", "baseStack", "constraints"]` on one entry and `["services.frontend"]` on another. The refresh algorithm ("union their `covers` values") never defines how a coarse `services` interacts with a fine `services.frontend`. Needs a stated rule.

---

## Q3 — Zero-install runtime for `scripts/`

### Verified

**`python3` is not usable on a stock macOS.** `/usr/bin/python3` is a stub that triggers the Command Line Tools installer prompt. Python 3 ships with the Xcode CLT, not with macOS. Apple removed bundled Python 2.7 in macOS 12.3 and stated future versions will not include scripting runtimes by default. **This disqualifies Python outright** — the constraint is "no install step."

Perl 5.34 does still ship; Ruby is effectively gone. Both are under the same deprecation notice and neither is guaranteed on minimal Linux. Neither is a safe foundation. Alpine's base is BusyBox + musl — `python3` requires `apk add`. Debian-minimal likewise.

**Common to both platforms:** a POSIX shell (`/bin/sh`), a POSIX `awk`, and — decisively — **`git`**.

### The insight that dissolves the problem

`git` is a hard dependency by definition; the skill is *about* git worktrees. And `git hash-object` is a complete hashing solution: works on any file including untracked ones and files outside the work tree, accepts multiple paths at once, and writes nothing without `-w`.

```
git hash-object --no-filters -- <paths>
```

**Verified on this machine.** `--no-filters` matters: without it, gitattributes clean filters and EOL conversion apply, masking real content changes.

No `sha256sum` (absent on macOS), no `shasum` (a Perl script, absent on minimal Linux), no `openssl`.

Two consequences:
- Output is a SHA-1 object id (SHA-256 in a repo with `extensions.objectFormat=sha256`). **Rename the schema field `sha256` → `fingerprint`** and add `fingerprintTool`. Only equality is needed; a repo migrating hash format makes every hash mismatch and triggers full rediscovery — failing in the safe direction.
- SHA-1 collision resistance is irrelevant. This is change detection, not a security boundary.

### Recommendation

**POSIX `sh` + `git` + POSIX `awk`. The script parses neither JSON nor YAML.**

Push the existing split one step further: **the agent owns the manifest file**. Every agent has a file-write tool, so the script's I/O contract is plain lines (`<hash>\t<path>`) and the JSON-parser problem disappears rather than being solved in awk.

Two single-purpose scripts, ~40–80 lines total:

- `scripts/fingerprint.sh` — paths on stdin → `<hash>\t<path>` lines
- `scripts/pick-port.sh <lo> <hi> <exclude-list>` → one port

### The real cost

| Constraint | Consequence |
|---|---|
| macOS ships **bash 3.2.57**; zsh is the default login shell | No bash-4 idioms — no associative arrays, no `mapfile`, no `${var^^}`. Write POSIX `sh` |
| `awk` differs (BWK on macOS; mawk/gawk/BusyBox on Linux) | POSIX awk only — no `gensub`, no `asort` |
| No `lsof` on minimal Linux; no `ss` on macOS | **Port availability is not portably checkable.** Treat as heuristic; the authoritative test is the launcher's `--strictPort` failure, which `traps.md:9` already mandates |
| `stat` flags incompatible (`-c` GNU vs `-f` BSD); `readlink -f` unreliable on older macOS | Avoid both; use `cd … && pwd -P` |
| `sed -i` differs GNU vs BSD | Never edit files in place in the script |
| `date -u +%Y-%m-%dT%H:%M:%SZ` works on both | Safe for `discoveredAt` |
| Absent by default on both | `jq`, `node`, `python3`, `sha256sum` |

**Declare it in the spec-sanctioned place.** The Agent Skills spec defines an optional `compatibility` field (max 500 chars) for exactly this. The draft frontmatter does not use it:

```yaml
compatibility: "POSIX systems (macOS, Linux). Requires git and a POSIX shell; docker/compose only for compose-based repos."
```

The spec also notes supported script languages depend on the agent implementation — a second independent argument for the most boring runtime.

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| Python 3 | Real JSON, real hashing | **Disqualified** — stub on macOS, absent on minimal Linux | — |
| Node | Real JSON | Not preinstalled on either | — |
| **POSIX sh + git + awk, no JSON in script** | Runs everywhere; hashing solved by an already-required dependency; ~60 lines | POSIX discipline easy to violate; port check stays heuristic | Low-Medium |
| **No `scripts/` at all** — inline commands in `references/` | Maximum portability; nothing to maintain | No encapsulation, so agent-to-agent variance rises; lengthens a token-budgeted body | Low |

**Recommend POSIX sh + git + awk**, and evaluate "no `scripts/`" seriously during proposal — it is defensible here, not a cop-out.

---

## Q4 — Agent-neutral state location

`~/.claude/stackgraft/<slug>.json` is wrong for a skill running under ~40 agents.

**Option A — git common dir.** `$(git rev-parse --path-format=absolute --git-common-dir)/stackgraft/manifest.json`. The skill already computes this path in Execution Step 1.

- Eliminates slugification entirely and a whole bug class with it (same-basename repos, moved/renamed repos, symlinked paths, case-insensitive APFS). Shared by all worktrees **by construction** — that is what the common dir is. GC'd with the repo. Not carried by `git clone`, which is correct for a machine-local cache.
- **Cons: many agents refuse writes under `.git/`.** For a ~40-agent target this is material adoption risk. Per-agent policies unverified.

**Option B — XDG cache.** `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<name>-<hash8>.json`

`XDG_CACHE_HOME` defaults to `$HOME/.cache` and is for "user-specific non-essential data files." `XDG_STATE_HOME` (`$HOME/.local/state`) is for data that persists between restarts but is not important or portable enough for `$XDG_DATA_HOME`. The manifest is explicitly a cache by the draft's own Hard Rule — *"Treat the manifest as a cache, never as truth"* — and every field is re-derivable. **`XDG_CACHE_HOME` is semantically correct** and fails safe: if a cleaner removes it, the skill rediscovers.

Filename — avoid a raw path slug, derive it with an already-required tool:

```
hash8 = first 8 chars of: printf '%s' "<git-common-dir>" | git hash-object --stdin
name  = basename of the repo root
→ bookshop-3f9a1c7d.json
```

**macOS:** honor `XDG_CACHE_HOME` if set, else `~/.cache`. Do not special-case `~/Library/Caches` — it doubles lookup paths for no benefit, cross-platform CLI tools overwhelmingly use `~/.cache` on macOS, and the system may reclaim `~/Library/Caches`.

**Windows / WSL:** WSL is Linux, XDG applies. Native Windows would want `%LOCALAPPDATA%`, but the skill already ships POSIX-only commands. The honest move is to declare POSIX-only via `compatibility` rather than half-support Windows.

**Recommend Option B.** Spec-backed, portable, semantically correct, no agent-permission risk. Option A is the alternative that trades permission risk for removing the slug problem entirely — proposal decides.

Also flag: `verifiedOverlays` is documented append-only in a file living in a cache directory. Unbounded growth. Cap it, or key by service and keep only the latest.

---

## Q5 — The leaked CodeGraph convention

**Recommend: remove it from `SKILL.md` outright. Do not generalize it.**

1. **Vendor-specific.** CodeGraph is one third-party tool. Naming it violates this project's own guideline in `openspec/config.yaml`: *"Ship no path, env var, or tool name that only one agent provides."* Traceable to the Claude-Code-local predecessor — inherited, not designed.
2. **Off-topic.** stackgraft's job is running services on alternate ports. A code-intelligence index has no bearing on whether a service starts, binds, or reaches peers.
3. **A Hard Rule must be testable and in-scope.** This is neither for the ~39 agents that never heard of CodeGraph.
4. **The general class is already covered.** "Per-checkout tool caches must not be shared between worktrees" is already expressed usefully in `traps.md:27` for `node_modules`.

**Keep the `/tmp` rule, but split and re-justify it.** `SKILL.md:21` crams two unrelated rules into one bullet and must be split regardless. The `/tmp` hazard is genuinely tool-neutral: on many Linux distributions `/tmp` is tmpfs — RAM-backed, wiped on reboot — and subject to automatic aging cleanup; macOS `/tmp` → `/private/tmp` is subject to periodic cleanup; tmpfs size limits break `node_modules`-scale trees, which this skill explicitly clones into worktrees. Retention windows unverified — state the hazard qualitatively.

> Never place a worktree under `/tmp` or `/var/tmp` — those paths are subject to automatic cleanup and are often RAM-backed. Use `<repo-parent>/<repo-name>-worktrees/<name>`.

---

## Consolidated recommendation

| # | Question | Recommendation | Confidence |
|---|---|---|---|
| 1 | Shared mutable state | Add `backingStores` + per-service `writes`/`competesOn`/`migrates`. Encode the W/X/N gate. **Fail closed on unknown.** Adopt "share compute, isolate state" — isolate *inside* the running instance, not by duplicating the server | High |
| 2 | Discovery | Make `kind` **open**; add `portGroup` for range keying; add `runnable: false` and retire `static`. **Prefer resolver commands over hand-parsing**, leading with `docker compose config --no-interpolate --format json`. Tier sources by which question they answer. Drop `healthPath`; deduplicate `sharedDirsIncluded` against `consumers` | High |
| 3 | Runtime | **POSIX sh + git + POSIX awk.** Hash via `git hash-object --no-filters`. Script handles no JSON and no YAML — the agent owns the manifest. Add `compatibility:` to frontmatter. Evaluate "no `scripts/`" as the serious alternative | High |
| 4 | State location | `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<name>-<hash8>.json`. Cache, not state. Git-common-dir is the alternative if `.git` writes are acceptable | High |
| 5 | CodeGraph | **Remove.** Split the bullet, keep `/tmp` on tool-neutral grounds, invent no generalized successor | High |

## Affected areas

- `skills/stackgraft/SKILL.md` — Hard Rules (line 19 `lsof`, line 21 split, line 22), Execution Steps 1–2 (manifest path), frontmatter (`compatibility`). **Token-budgeted** (180–450 target, 1000 hard max): Q1's gate cannot fully fit in the body — it needs a new `references/` file with a one-line pointer from a Decision Gate.
- `skills/stackgraft/assets/manifest.schema.json` — `kind` enum, `portPolicy.ranges` keying, `sha256`→`fingerprint`, new `backingStores`, `runnable`, `writes`/`competesOn`, remove `healthPath`, resolve `sharedDirsIncluded`/`consumers` duplication, bound `verifiedOverlays`
- `skills/stackgraft/assets/manifest.example.json` — root `_comment` breaks validation; `catalog-api.overlayCommand` is wrong
- `skills/stackgraft/references/discovery.md` — split (a)/(b), add tiering and resolver preference, define `covers` granularity rule
- `skills/stackgraft/references/traps.md` — line 25 removal; add shared-state traps; reconcile line 29 with the resolver recommendation
- **New:** `skills/stackgraft/references/shared-state.md`, `skills/stackgraft/scripts/`
- `openspec/config.yaml` — closes `open_decisions.scripts-runtime`
- `README.md` — Status section
- `~/.claude/skills/worktree-overlay/**` — the predecessor carries every defect. Retire-or-sync decision needed; **out of scope for this repo's change**, but must be named

## Risks

1. **Scope.** Q1 alone is design-sized. All five together blow the 400-line review budget. Natural slicing for chained PRs: (1) portability Q3+Q4+Q5 + the two example bugs, (2) Q2 schema restructure, (3) Q1 shared-state gate.
2. **`schemaVersion` churn.** Q1 and Q2 both change the schema. Batch into a single `schemaVersion: 2` bump or every cache invalidates twice.
3. **Discovery cost inflation.** Every field added for Q1 is a field discovery must populate. If it cannot, fail-closed refuses overlays and the skill becomes useless. **The `unknown → refuse` default needs a usable escape hatch** or the gate gets routed around.
4. **Platform claims need one real check.** On a stock macOS and a minimal Linux container: `command -v python3 awk git`, `git hash-object --no-filters` on a sample file, and a POSIX-sh syntax check under `dash`.
5. **Resolver commands are not free.** `docker compose config` requires Docker running; Aspire and Tilt resolvers execute code. The tiering must state what happens when the resolver is unavailable, or discovery hard-fails whenever the base stack is down.

## Ready for proposal

Yes. The proposal phase should decide: (a) slicing across chained PRs, (b) Option A vs B for state location, (c) `scripts/` vs no `scripts/`, (d) whether the pre-existing example bugs ride along or become a separate fix.

## Sources

[Agent Skills specification](https://agentskills.io/specification) · [XDG Base Directory spec](http://specifications.freedesktop.org/basedir/latest/) · [docker compose config](https://docs.docker.com/reference/cli/docker/compose/config/) · [docker compose run](https://docs.docker.com/reference/cli/docker/compose/run/) · [Compose include](https://docs.docker.com/reference/compose-file/include/) · [git hash-object](https://git-scm.com/docs/git-hash-object) · [devcontainer.json reference](https://containers.dev/implementors/json_reference/) · [Redis Pub/Sub](https://redis.io/docs/latest/develop/pubsub/) · [Skaffold port forwarding](https://skaffold.dev/docs/port-forwarding/) · [Tiltfile API](https://docs.tilt.dev/api.html) · [Aspire manifest spec](https://github.com/dotnet/aspire/blob/main/docs/specs/manifest-spec.md)
