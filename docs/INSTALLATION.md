# Installation

stackgraft is a folder. Copying it into the place your agent reads skills from is the whole install.

## Requirements

| | |
|---|---|
| Platform | macOS, Linux, WSL, and **Git Bash on Windows** — the shell that ships with Git for Windows. PowerShell and cmd are out of scope. |
| Required | `git` 2.5+, a POSIX shell, POSIX `awk` |
| Conditional | `docker` / `docker compose`, only for container-based repositories |

There is nothing to compile and no package to add. The two helper scripts deliberately avoid `python3`, `node`, `jq` and `sha256sum` — each is missing from at least one supported platform.

> `git` ships with a stock macOS and with most developer images, but **not** with alpine, debian-slim or distroless. Install it there before using the skill.

## Any agent

Skills are an [open standard](https://agentskills.io) — the same folder is read by roughly forty agents. Only the destination differs.

```bash
git clone https://github.com/kevocodes/stackgraft /tmp/stackgraft
cp -R /tmp/stackgraft/skills/stackgraft <your-agent-skills-dir>/
```

| Agent | Skills directory |
|---|---|
| Claude Code | `~/.claude/skills/` |
| GitHub Copilot | `~/.copilot/skills/` |
| Codex, Cursor, Gemini CLI, OpenCode, Goose, Amp, Kiro, … | see your agent's skills documentation |

Project-scoped installs work too — put the folder in the repository's own skills directory instead of your home one, and it travels with the checkout.

## Claude Code, as a plugin

The plugin wraps the same folder and keeps it updated.

```
/plugin marketplace add kevocodes/stackgraft
/plugin install stackgraft@stackgraft
```

There is no central registry to submit to: the repository *is* the marketplace. Updates arrive when the version in `.claude-plugin/plugin.json` changes, not on every commit.

```
/plugin marketplace update stackgraft
```

## Verify it took

Ask your agent something in the skill's territory — *"run this worktree against the stack that's already up"* — and confirm it names `stackgraft`. If nothing happens:

1. **Check the folder landed intact.** `SKILL.md` at the top, plus `references/`, `assets/` and `scripts/`.
2. **Check for a duplicate.** Two skills with overlapping trigger text confuse discovery. Remove the older copy.
3. **Restart the agent.** Most read the skills directory at startup.

## First run

Point it at a worktree of a repository whose stack is already running. The first run costs a discovery pass and writes a manifest to `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/`. Later runs read that manifest and re-derive only what drifted.

If the topology it discovers does not match your repository, that is the thing worth reporting — the manifest is a cache of a guess, and a wrong guess is cheap to correct and expensive to leave.

## Uninstall

Delete the folder. For the plugin, `/plugin uninstall stackgraft@stackgraft`.

The manifest cache is separate and safe to remove at any time:

```bash
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft"
```

Nothing there is authoritative — every field is re-derivable from the repository.
