<p align="center">
  <img src="assets/logo.svg" width="620" alt="stackgraft — run only what you changed">
</p>

<p align="center">
  <strong>Run only the services your git worktree changed</strong><br>
  <em>Agent-agnostic. No install step. Refuses before it corrupts.</em>
</p>

<p align="center">
  <a href="docs/INSTALLATION.md">Installation</a> &bull;
  <a href="docs/HOW-IT-WORKS.md">How it works</a> &bull;
  <a href="docs/SHARED-STATE.md">Shared state</a> &bull;
  <a href="CONTRIBUTING.md">Contributing</a> &bull;
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

> **graft** `/ɡrɑːft/` — *horticulture*: joining a living shoot to an established rootstock so the two grow as one. The roots keep working. Only the grafted part is new.

You open a git worktree to work on a branch in parallel. To test it you would have to bring the whole stack up a second time — most of it byte-identical to what is already running.

**stackgraft starts only what you changed**, on its own port, and wires every unchanged dependency back to the stack you already have up.

```
  base stack — already running                    your worktree
  ┌───────────────────────────────┐
  │  catalog-api      :8080       │ ◄──────────────┐
  │  search-indexer   :8090       │ ◄────┐         │  only this one changed
  │  postgres         :5432       │      │         │
  │  storefront       :5173       │      │         │
  └───────────────────────────────┘      │  ┌──────┴───────────────┐
                                         └──┤  catalog-api  :18042 │ ← the graft
                                            └──────────────────────┘
```

One service starts. Three are reused. Nothing is duplicated.

## Why this is not just `docker compose up`

Because the naive version of this **silently corrupts your data**.

Reuse the stack and your overlay reaches the same Postgres everyone else is testing against. Run a migration, insert a row, and you have changed the data under your colleague's feet. It does not error. It works, and it poisons.

There is a nastier variant. A service that only *reads* can still break the base stack by **attaching** to something competitive — a Kafka consumer group, a queue subscriber, an advisory lock, a scheduler singleton. It takes work away from a service you never modified, so the symptom appears where you are not looking.

stackgraft classifies every `(service, store)` pair before anything launches and produces one verdict: reuse the store, isolate inside the instance already running, or refuse. **Unknown resolves to refusal.** An empty answer is a claim that needs evidence, never an omission.

→ [How the gate works](docs/SHARED-STATE.md)

## Quick start

**Any agent that reads the [Agent Skills](https://agentskills.io) standard** — Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode, Goose, Amp, Kiro and ~30 more:

```bash
git clone https://github.com/kevocodes/stackgraft
cp -R stackgraft/skills/stackgraft ~/.claude/skills/     # or ~/.copilot/skills/, etc.
```

**Claude Code**, as a plugin that stays updated:

```
/plugin marketplace add kevocodes/stackgraft
/plugin install stackgraft@stackgraft
```

Then just ask, in whatever words you use:

> *run this worktree against the stack that's already up*

→ [Per-agent paths and troubleshooting](docs/INSTALLATION.md)

## What ships

```
skills/stackgraft/
├── SKILL.md          the body — the only file loaded whole
├── references/       shared-state.md · discovery.md · traps.md
├── assets/           manifest schema + a worked example
└── scripts/          two POSIX sh helpers
```

**No runtime to install.** The helpers need `git`, a POSIX shell and `awk` — nothing else. `python3` is a stub on a stock macOS, so it was disqualified; hashing rides on `git hash-object`, which the skill already depends on.

**Topology is cached, not re-derived.** A per-repository manifest under `XDG_CACHE_HOME`, keyed by the git common dir so every worktree shares one. Each source records the manifest keys it owns, so a drifted file re-derives only its slice. The manifest is a cache, never truth — on conflict the repository wins.

**Discovery prefers your ecosystem's own resolver** over hand-parsing, and degrades to a marked static parse instead of failing when the resolver is unavailable.

## Honest limits

- **The verification is real but young.** Schema negatives, script runs and body budgets are checked in CI; the shared-state gate has never been exercised against a production-shaped repository.
- **POSIX only.** macOS, Linux and WSL. Windows-native is out of scope.
- **`git` is required and is not present in minimal container images** — alpine, debian-slim and distroless ship none.

## The name

**stack** + **graft**.

Grafting joins a living shoot to a rootstock that is already established. The roots keep working; only the grafted part is new.

Your running stack is the rootstock. The service you changed is the shoot. The alternate port and the rewired dependencies are the join.

## License

[Apache-2.0](LICENSE)
