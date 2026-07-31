# stackgraft

Run only the services your git worktree changed — grafted onto the stack you already have running.

A graft joins a living branch to an established rootstock. The roots keep working; only the grafted part is new. That is what this does: your worktree's modified service runs on its own port, and every unchanged dependency resolves to the stack that is already up.

## The problem

You have a repository with many services. You open a git worktree to work on a branch in parallel. To test it, you would have to bring up the whole stack a second time — most of it byte-identical to what is already running.

## The approach

Start only the services whose files the worktree changed. Point everything else at the base stack. Cache the discovered topology per repository so the second run does not rediscover it, and invalidate that cache by fingerprint when the source files drift.

## Status

Usable, and honest about its edges.

What ships: an agent-neutral manifest cached under `XDG_CACHE_HOME`, invalidated per source by fingerprint rather than wholesale. Two POSIX `sh` helpers that need only `git` and `awk` — no Python, no Node, no `jq`. Discovery that separates "which unit owns this path" from "how does that unit start", prefers each ecosystem's own resolver over hand-parsing, and degrades instead of failing when a resolver is unavailable. And a shared-state gate that refuses an overlay until every `(service, store)` pair has a verdict, treating unknown as unsafe.

The gate is the part worth knowing about. Running a second copy of one service against the database everyone else is testing on does not fail — it works, and quietly corrupts. So the skill classifies what each service writes and what it competes for, isolates inside the store already running where that is possible, and refuses where it is not. The only bypass is an explicit acceptance recorded per service and store, which expires the moment that service's source changes.

Not done: verification is manual. Two of the four checks the project relies on have no committed tooling, so "passes" currently means a human ran them.

## Install

This is an [Agent Skill](https://agentskills.io) — one folder, read by ~40 agents including Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode, and Goose.

Copy `skills/stackgraft/` into your agent's skills directory (`~/.claude/skills/`, `~/.copilot/skills/`, …).

Claude Code users can install it as a plugin instead:

```
/plugin marketplace add kevocodes/stackgraft
```

## License

Apache-2.0
