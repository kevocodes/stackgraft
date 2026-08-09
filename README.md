<p align="center">
  <img src="assets/logo.svg" width="620" alt="stackgraft — run only what you changed">
</p>

<p align="center">
  <strong>Run only the services your git worktree changed</strong><br>
  <em>Agent-agnostic. No runtime to install. Refuses before it corrupts.</em>
</p>

<p align="center">
  <a href="docs/INSTALLATION.md">Installation</a> &bull;
  <a href="docs/HOW-IT-WORKS.md">How it works</a> &bull;
  <a href="docs/SHARED-STATE.md">Shared state</a> &bull;
  <a href="SECURITY.md">Security</a> &bull;
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

**Scope, stated up front.** Local development: one host, one already-running base stack, N worktrees of one repository in parallel. CI, shared hosts, remote hosts and multi-developer stacks are declared non-goals — a boundary, not a preference, and not a list of things that merely have not been tried. If your base stack does not run on the machine you are sitting at, stackgraft is the wrong tool, and you should learn that here rather than from a refusal several minutes in.

## Why this is not just `docker compose up`

Because the naive version of this **silently corrupts your data**.

Reuse the stack and your overlay reaches the same Postgres everyone else is testing against. Run a migration, insert a row, and you have changed the data under your colleague's feet. It does not error. It works, and it poisons.

There is a nastier variant. A service that only *reads* can still break the base stack by **attaching** to something competitive — a Kafka consumer group, a queue subscriber, an advisory lock, a scheduler singleton. It takes work away from a service you never modified, so the symptom appears where you are not looking.

stackgraft classifies every `(service, store)` pair before anything launches and produces one verdict: reuse the store, isolate inside the instance already running, or refuse. **Unknown resolves to refusal.** An empty answer is a claim that needs evidence, never an omission.

→ [How the gate works](docs/SHARED-STATE.md)

## What it looks like in practice

Four runs, every number below measured, against a base stack of nineteen containers.

**A fix scoped to one service.** One overlay on an alternate port and two data copies behind it: **three new containers against the nineteen** a second full stack would have cost. The proof that it was serving was a request carrying the headers the service actually requires — not `/health`, which answers `200` whether or not the thing behind it works — and it came back `200`.

**A migration run against a copy instead of against everyone.** `ALTER TABLE ADD COLUMN`, `CREATE INDEX`, `CREATE TABLE` and `INSERT`, all applied inside the worktree's own copy. The base database finished the run with **zero new columns and zero new tables**, and a real service started against the copy without a schema error. What it started against was the whole database, not an approximation of it: 124 tables, 1404 columns, 390 indexes, 971 constraints, and the extensions the original declared. Making it moved 640MB in one to two seconds; the Redis copy alongside it was 8KB and took none.

**Isolated data and shared dependencies, in the same run.** The overlay read and wrote its own database copy while calling an unmodified service in the base stack over the network, and got `200` back. This is the case the whole design exists for — the data you might corrupt is yours, and everything you did not change is still the process that was already running, not a second copy of it.

**Two worktrees at once, each with its own copies.** Tearing the first one down left the second one's data untouched, and said so in the run's own words: *an instance labelled for another worktree was left alone*. The label is the mechanism, not the courtesy.

**The margin narrows as a change reaches further.** A change touching a widely-shared module pulled in 25 registered consumers, of which 10 were actually running — ten overlays against nineteen containers. Still cheaper than a second stack, by much less.

## Quick start

**Any agent that reads the [Agent Skills](https://agentskills.io) standard** — Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode, Goose, Amp, Kiro and ~30 more:

```bash
npx skills add kevocodes/stackgraft
```

That is the whole install, and knowing where each agent keeps its skills is now its job rather than yours. One canonical copy lands in `.agents/skills/stackgraft/`; every agent directory it finds gets a **relative symlink** to that one copy, so there is nothing to keep in sync. `skills-lock.json` pins exactly what you installed by sha256 content hash, and `npx skills update` / `npx skills remove` cover the rest of the lifecycle.

Or with **paks**, pointed straight at the skill folder:

```bash
paks install https://github.com/kevocodes/stackgraft/tree/main/skills/stackgraft
```

**Claude Code**, as a plugin that stays updated:

```
/plugin marketplace add kevocodes/stackgraft
/plugin install stackgraft@stackgraft
```

Then just ask, in whatever words you use:

> *run this worktree against the stack that's already up*

→ [Copying it by hand, per-agent paths and troubleshooting](docs/INSTALLATION.md)

## What the first run asks of you

A copy that started is not proof that it holds your data, so **a copy is verified before it counts as isolated**: the run issues a single read command three times — against the base store, against the copy, and against an **empty instance of the same image** — and accepts the copy only where its answer matches the base store's byte for byte *and* the empty instance answers something else. Where that query fails or cannot be derived, the copy is destroyed and the pair refuses; it is never quietly wired to the base store instead.

**That command has to come from your repository.** The skill will not invent one, because a query it wrote itself is a claim about a database it has never seen. And the healthchecks your stores already declare mostly cannot serve as it: `CMD-SHELL` healthchecks are shell source rather than argument vectors, `redis-cli ping` answers `PONG` on an instance holding nothing, and a health endpoint answers the same whether the database behind it is full or empty. On the repository this was built for, **zero of four stores supplied a usable candidate.**

So the likely shape of a first run is that the copy is provisioned and then every writing pair refuses until a read command exists to query it with. Where nothing defines one, the run offers to write three files — `db-create-<store>`, `db-drop-<store>` and `db-read-<store>`, the third being exactly that query — shown in full, written only on your approval, into your own script directory, never into a file it did not author, and **nothing staged, committed or pushed**. What it writes is `inferred` until a run has watched all three succeed, and your approval is fingerprinted over the files as you approved them, so any later edit — the skill's own included — shows them to you again.

## What ships

```
skills/stackgraft/
├── SKILL.md          the body — the only file loaded whole
├── references/       shared-state.md · discovery.md · traps.md · reaping.md
├── assets/           manifest schema + a worked example
└── scripts/          four POSIX sh helpers
```

**No runtime to install.** The helpers need `git`, a POSIX shell and `awk` — nothing else. `python3` is a stub on a stock macOS, so it was disqualified; hashing rides on `git hash-object`, which the skill already depends on. macOS, Linux, WSL and Git Bash on Windows are each exercised in CI; **PowerShell and cmd are out of scope**, and `git` itself is absent from minimal container images — alpine, debian-slim and distroless ship none.

**Topology is cached, not re-derived.** A per-repository manifest under `XDG_CACHE_HOME`, keyed by the git common dir so every worktree shares one. Each source records the manifest keys it owns, so a drifted file re-derives only its slice. The manifest is a cache, never truth — on conflict the repository wins.

**Discovery prefers your ecosystem's own resolver** over hand-parsing, and degrades to a marked static parse instead of failing when the resolver is unavailable.

**Cleanup reports by default and acts only on request.** Every run names which of this repository's overlays and copies outlived their worktree — and a runtime that will not answer reports *unknown*, never zero. Stopping one takes an explicit flag; removing it takes a second flag on top of that; and nothing is stopped, removed or signalled without **both** an orphan classification and a matching recorded identity. A data copy takes the removal verb on top of the mutation flag before anything removes it for you — a `v:` target under `stop` is refused by name, because the copy is the one thing here that nothing on your host can reproduce.

## Creating the worktree is a different job

stackgraft does not create worktrees and does not install dependencies. It starts where that work ends.

[`using-git-worktrees`](https://www.skills.sh/obra/superpowers/using-git-worktrees) covers the creating half — where the worktree should live, gitignore safety, installing dependencies for npm, cargo, pip or go, and a baseline test run — and says so itself: it *"does not start services, manage ports, or handle databases."* That is the half stackgraft does. **The two compose**: use it to create the worktree, then stackgraft to run only what you changed in it.

They meet on one question, where a worktree should live, which is why stackgraft carries a hard rule against placing one under `/tmp` or `/var/tmp` — both are reaped.

## Honest limits

- **A copy is a duplicate of your base stack's data, sitting on your disk.** It is made once per worktree and store, reused on every later launch and refreshed only when you ask, so **what every run reports is the age of the copy** — not how far the base store has moved since, because the run never compares the two. The free-space check that precedes making one is **a candidate and not a guarantee**: it measures the runtime's data root and the host filesystem behind it, names which of the two bound the decision, and prints what it could not see. `SECURITY.md` states the surface; `references/isolation-providers.md` states the mechanism.
- **The base stack is outside the candidate set by construction, but the port test on top of that is only as good as what the caller passes.** Only an overlay launch writes the ownership label, so a base-stack container is never a candidate to begin with — that half is structural and holds under every flag. The shape that gets past it, a container hand-labelled with this repository's id, is tested against the base-stack ports the run passes in, and **that test is caller-supplied and caller-defeatable**: the helpers parse no JSON, so nothing can check a passed port against the manifest it came from, and a run that passes the wrong one reaps the container. A mutation given no port refuses rather than guessing, and no flag stands in for one. So the limit is stated rather than covered, here as in `references/reaping.md` and in the requirement itself: a hand-labelled container whose worktree is unlisted and whose published port is not among the values passed **is reaped**. Nothing else on a running container tells a base-stack service apart from an overlay.
- **It sees only overlays launched after the labels shipped**, so the first run legitimately reports nothing to act on. A container started before that carries no ownership label, which means nothing distinguishes it from any other container on the machine — there is no query that finds it, so the report names the category, says the gap is structural, and prints the command to look by hand rather than widening a query into a neighbouring repository. An accepted coverage loss, stated out loud.
- **The verification is scripts driving the mechanism rather than an agent reading the skill.** Until recently this entry said the gate had never been exercised against a production-shaped repository at all, and the two defects that admission was hiding are in `2.1.1`: the empty instance every copy is compared against was launched with no environment and never booted, so no copy could be certified however faithful it was. Five layers now run every build — **848** prose and schema checks, then **75** behavioural ones that boot real stores under their own entrypoints and drive the copy road, the overlay run, the manifest discovery produces, and the generated lifecycle family with both of its falsifiers. Blindness to the substrate is **demonstrated rather than argued**: the same procedure runs over `postgres` and `redis`, which differ in every way it is supposed to be blind to — one refuses to boot without environment and the other needs none, one declares a `CMD-SHELL` healthcheck the argv rule excludes before anything else is asked and the other declares an exec-form vector that *is* a rung-1 candidate and is refused by the discriminator instead. What changes between them is the read command **the repository supplies**; nothing in the procedure changes at all. What remains is stated rather than implied: **the runs are driven by test scripts**, which proves the primitives compose and the mechanism holds. It does not prove that an agent reading `SKILL.md` and its references arrives at the same place, which is a different claim needing a different instrument and has none yet.

## The name

**stack** + **graft**.

Grafting joins a living shoot to a rootstock that is already established. The roots keep working; only the grafted part is new.

Your running stack is the rootstock. The service you changed is the shoot. The alternate port and the rewired dependencies are the join.

## License

[Apache-2.0](LICENSE)
