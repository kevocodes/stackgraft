# stackgraft

Run only the services your git worktree changed — grafted onto the stack you already have running.

A graft joins a living branch to an established rootstock. The roots keep working; only the grafted part is new. That is what this does: your worktree's modified service runs on its own port, and every unchanged dependency resolves to the stack that is already up.

## The problem

You have a repository with many services. You open a git worktree to work on a branch in parallel. To test it, you would have to bring up the whole stack a second time — most of it byte-identical to what is already running.

## The approach

Start only the services whose files the worktree changed. Point everything else at the base stack. Cache the discovered topology per repository so the second run does not rediscover it, and invalidate that cache by fingerprint when the source files drift.

## Status

Early. The skill body, manifest schema, and reference material are drafted; the deterministic helper and the multi-stack discovery surface are in progress.

## Install

This is an [Agent Skill](https://agentskills.io) — one folder, read by ~40 agents including Claude Code, Codex, Cursor, Gemini CLI, Copilot, OpenCode, and Goose.

Copy `skills/stackgraft/` into your agent's skills directory (`~/.claude/skills/`, `~/.copilot/skills/`, …).

Claude Code users can install it as a plugin instead:

```
/plugin marketplace add kevocodes/stackgraft
```

## License

Apache-2.0
