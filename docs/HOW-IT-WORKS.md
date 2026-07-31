# How it works

Four ideas carry the whole design. Everything else follows from them.

## 1. Share compute, isolate state

The original draft had this backwards, and correcting it reshaped the skill.

Application services are **expensive to start and safe to share**. A datastore is **cheap to start and dangerous to share**. So the cheapest correct arrangement is not "duplicate the stack" and not "reuse everything" — it is: reuse the stateless services, and isolate state *inside* the instance already running.

A second Postgres container costs seconds and a few hundred megabytes. A second copy of thirty application services costs minutes and gigabytes. Isolating a database inside the container that is already up costs almost nothing at all.

## 2. Topology is a cache, never truth

Discovering how a repository runs is expensive, so it happens once and is stored in a manifest under `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/`, keyed by the git common directory so every worktree of a repository shares one file.

Two rules keep the cache honest:

- **Invalidation is per slice, not wholesale.** Each source file records the manifest keys it is authoritative for, so a drifted `package.json` re-derives one service rather than the entire topology.
- **On any conflict the repository wins.** The manifest is rewritten, never trusted over what is on disk. A cache that believes it is the truth is worse than no cache.

Fingerprints come from `git hash-object`, which is already a dependency because the skill is about worktrees.

## 3. Discovery answers two questions, not one

- **path → unit** — which changed files belong to which runnable thing
- **unit → launch, port, peers** — how that thing starts, where it binds, how it reaches dependencies

Most ecosystem files answer only the first. `go.work`, Cargo workspaces, Gradle, Maven, Bazel, `nx.json` and `turbo.json` describe a *build graph*: what compiles, never what listens. Treating one as a topology source produces a manifest that is confident and wrong.

Where an ecosystem ships its own resolver, stackgraft prefers it over hand-parsing:

```sh
docker compose config --no-interpolate --format json
```

That merges `-f` chains, override auto-merge, `extends`, recursive `include` and profiles — and `--no-interpolate` leaves variables unexpanded, so it resolves the file set **without printing a single secret**. When a resolver is unavailable, discovery degrades to a marked static parse rather than failing the run, and the marking matters: degraded evidence is not allowed to satisfy the safety gate.

## 4. Nothing launches without a verdict

Every `(service, store)` pair is classified before anything starts. This is the part that makes the tool safe rather than merely convenient, and it has its own document:

→ [Shared state](SHARED-STATE.md)

## The body is sealed on purpose

Skills load by *progressive disclosure*: the agent sees only `name` and `description` at startup, loads `SKILL.md` when a task matches, and reads `references/` **only if it decides to**.

That last part is the hazard. If the body summarised the safety rule, an agent that skipped the reference could still reach a permissive answer from the summary alone — so skipping the reference would become permissive.

So the body states *that* a verdict is required and *where* it comes from, and never a condition under which an overlay is permitted. Body-only knowledge can reach refusal and nothing else. **Not having read the reference is itself a refusing state.**

It is checkable: the body contains no permitting term, and CI greps for them.

## The scripts do bookkeeping, not judgement

Two POSIX `sh` helpers, and the split between them and the agent is deliberate:

| The agent | The scripts |
|---|---|
| Reads the repository, interprets YAML, decides what changed, maps paths to units, wires peers | Hash files, compare, allocate a candidate port, nothing else |

Deterministic bookkeeping is exactly what you do not want re-derived by judgement on every run — each re-derivation is a fresh chance to be wrong differently. And it dissolves a problem: no small script parses YAML without dependencies, but the agent parses it natively and hands the script structured input.

Neither script reads stdin by default. A caller that forgets a redirect would block forever, and for a tool an agent invokes, hanging is worse than failing — a non-zero exit prints a usage line the agent can act on, while a hang produces nothing at all.

`scripts/pick-port.sh` returns a **candidate**, never a guarantee. Port availability is not portably checkable (`lsof` is absent on minimal Linux, `ss` on macOS) and any reading is stale the moment it is taken, so the authoritative test is the launcher's strict-port bind failure. The offset is derived from the worktree path so two worktrees of one repository do not land on the same port by construction.
