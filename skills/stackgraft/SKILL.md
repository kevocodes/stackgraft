---
name: stackgraft
description: "Trigger: git worktree, run only the changed service on another port, test branches in parallel. Overlay modified services onto an already-running base stack."
compatibility: "POSIX systems only: macOS, Linux, WSL. Windows-native is out of scope. git 2.5+ and a POSIX shell with awk are required unconditionally and ship with a stock macOS and a minimal Linux image. Container tooling such as docker compose is required only for container-based repositories."
license: Apache-2.0
metadata:
  author: kevocodes
  version: "1.0"
---

## Activation Contract

Load when a worktree or second checkout must run locally and duplicating the full stack is not worth it.

Skip when the repo has one service, a full `up` is cheap, or the user explicitly wants an isolated full stack.

## Hard Rules

- Start only services the worktree changed; point unchanged dependencies at the base stack.
- Port probes are heuristics, never proof: bind strict-port, honor `portPolicy.reserved`.
- Never kill a process you did not start.
- Never place a worktree under `/tmp` or `/var/tmp`; both are reaped without warning.
- `/health` returning 200 is not proof: verify a real request, read its headers.
- The manifest is a cache, not truth: refresh drifted entries; on conflict the repo wins, rewrite the entry.
- Every overlay is REFUSED until `references/shared-state.md` has been read and every verdict it demands is recorded. Emptiness is a claim, never a verdict — that file says what evidences it. Nothing else — manifest, user, or inference — produces one.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Manifest missing | Full discovery, then write it |
| All fingerprints match | Reuse manifest, skip discovery — but re-derive every `revalidate: "always"` source |
| Some source drifted | Re-discover only that slice, rewrite those entries and hashes |
| Changed paths map to no service | No overlay; run tests only and say so |
| Change touches a shared/common dir | Overlay every service listed in that entry's `consumers` |
| Overlay needs a port outside the range | Stop and ask before binding |
| Any overlay | Gate it — `references/shared-state.md` |

## Execution Steps

1. Resolve `gitCommonDir`: `cd -- "$(git rev-parse --git-common-dir)" && pwd -P`. Derive `repoRoot` — the **main** worktree, never this checkout — per `references/discovery.md` §0.
2. Load `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, `hash8` being `git hash-object --stdin` over `gitCommonDir`, truncated to 8. Discard on validation failure or `repoRoot` mismatch; when unwritable, run manifest-less and say so. Fingerprint `sources[].path` with `scripts/fingerprint.sh`.
3. Discover or refresh per the Decision Gates (`references/discovery.md`).
4. Diff the worktree against its base branch; map changed paths through `paths` globs.
5. Confirm the base stack is healthy; start what is missing.
6. `sh scripts/pick-port.sh <portGroup range lo> <hi> <worktree> <reserved, basePorts, ports taken this run>`; bind strictly.
7. Launch each mapped service, rewiring unchanged dependencies to the base stack.
8. Verify with a real request, record `verifiedOverlays`, rewrite the manifest.

## Output Contract

Return:

- Manifest path, and whether it was created, reused, or refreshed — name the refreshed entries.
- Changed paths and the services they mapped to.
- Per overlay: service, port, launch command, verification result.
- Base-stack services reused, not duplicated.
- The exact teardown command.

## References

- `assets/manifest.schema.json` — field contract.
- `assets/manifest.example.json` — filled example.
- `references/discovery.md` — discovery procedure.
- `references/traps.md` — failure modes.
- `references/shared-state.md` — the only verdict procedure.
- `scripts/fingerprint.sh`, `scripts/pick-port.sh` — POSIX helpers.
