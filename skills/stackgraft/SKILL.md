---
name: stackgraft
description: "Trigger: git worktree, run only the changed service on another port, test branches in parallel. Overlay modified services onto an already-running base stack."
compatibility: "Needs a POSIX shell: macOS, Linux, WSL, and Git Bash on Windows, all CI-tested. PowerShell and cmd are out of scope. Required unconditionally: git 2.5+ (worktree, --git-common-dir) and a POSIX shell with awk. Stock macOS, mainstream Linux and Git for Windows carry both; minimal images do not — alpine, debian-slim and distroless ship no git, distroless no shell. Install git where a package manager exists (apk add git). Container tooling (docker compose) is needed only for container repos."
license: Apache-2.0
metadata:
  author: kevocodes
  version: "1.0"
---

## Activation Contract

Load when a worktree or second checkout must run locally and duplicating the stack is wasteful.

Skip when the repo has one service, `up` is cheap, or the user wants an isolated full stack.

## Hard Rules

- Start only services the worktree changed; point unchanged dependencies at the base stack.
- Port probes are heuristics, never proof: bind strict-port, honor `portPolicy.reserved`.
- Never kill a process you did not start.
- Never place a worktree under `/tmp` or `/var/tmp`: both are reaped.
- `/health` returning 200 is not proof: verify a real request's headers.
- The manifest is a cache, not truth: refresh drifted entries; the repo wins, rewrite it.
- Substitute placeholders as quoted words: host paths hold whitespace.
- Every overlay is REFUSED until `references/shared-state.md` has been read and every verdict it demands is recorded. Emptiness is a claim, never a verdict — that file says what evidences it. Nothing else — manifest, user, or inference — produces one. An overlay whose verdict is a refusal does not launch.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Manifest missing | Discover fully, write it |
| All fingerprints match | Reuse it; still re-derive every `revalidate: "always"` source |
| Some source drifted | Re-discover only that slice; rewrite its entries and hashes |
| Changed paths map to nothing | No overlay; run tests only, say so |
| Shared/common dir changed | Overlay every service in that entry's `consumers` |
| Port needed outside the range | Stop and ask before binding |
| Any overlay | Gate it — `references/shared-state.md` |

## Execution Steps

1. At the worktree top, `gitCommonDir` = `CDPATH= cd -- "$(git rev-parse --git-common-dir)" && pwd -P`. Derive `repoRoot` — the **main** worktree, never this checkout — per `references/discovery.md` §0.
2. Load `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, `hash8` being `printf '%s' "$gitCommonDir" | git hash-object --stdin`, cut to 8. Discard on validation failure or `repoRoot` mismatch; if unwritable, run manifest-less and say so. Fingerprint `sources[].path` with `sh scripts/fingerprint.sh -C "$repoRoot"`.
3. Discover or refresh per Decision Gates (`references/discovery.md`).
4. Diff the worktree against its base branch; map changed paths through `paths` globs.
5. Confirm base-stack health; start what is missing.
6. Before launching, read `references/shared-state.md`; record every verdict it demands.
7. `sh scripts/pick-port.sh <lo> <hi> <worktree> [excluded-port ...]` — `portGroup` range, one port per argument: reserved, base ports, taken this run. Bind strictly.
8. Launch each mapped service, rewiring unchanged dependencies to the base stack.
9. Verify with a real request, record `verifiedOverlays`, then rewrite the manifest through `scripts/with-lock.sh`.

## Output Contract

- Manifest path; created, reused, or refreshed — name refreshed entries.
- Changed paths and their mapped services.
- Per overlay: service, port, launch command, verification result.
- Base-stack services reused, not duplicated.
- The exact teardown command, any isolated namespace left behind, and how to remove it.

## References

- `assets/manifest.schema.json`, `assets/manifest.example.json`, `references/discovery.md`, `references/traps.md`, `scripts/fingerprint.sh`, `scripts/pick-port.sh`, `scripts/with-lock.sh`.
- `references/shared-state.md` — the only verdict procedure.
