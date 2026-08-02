---
name: stackgraft
description: "Trigger: git worktree, run only the changed service on another port, test branches in parallel. Overlay modified services onto an already-running base stack."
compatibility: "Needs a POSIX shell: macOS, Linux, WSL, and Git Bash on Windows, all CI-tested. PowerShell and cmd are out of scope. Required unconditionally: git 2.5+ (worktree, --git-common-dir) and a POSIX shell with awk. Minimal images often lack both — install git where a package manager exists (apk add git). Host-overlay ownership needs ps -o lstart=; busybox and MSYS lack it, so those overlays are report-only. Container tooling (docker compose) is needed only for container repos."
license: Apache-2.0
version: "1.0.0"
metadata:
  author: kevocodes
  version: "1.0.0"
---

## Activation Contract

Load when a worktree or checkout must run locally and duplicating the stack is wasteful.

Skip for single-service repos, cheap `up`, or full isolation.

## Hard Rules

- Start only services the worktree changed; point unchanged dependencies at the base stack.
- Port probes are heuristics, never proof: bind strict-port, honor `portPolicy.reserved`.
- Never stop a process without proof it is yours: a recorded `(pid, lstart)` that still matches, per `references/reaping.md`. No record, no match, no action; a port, the manifest and the user are not proof.
- Never place a worktree under `/tmp` or `/var/tmp`: both are reaped.
- `/health` returning 200 is not proof: verify a real request's headers.
- The manifest is a cache, not truth: refresh drifted entries; the repo wins, rewrite it.
- Substitute placeholders as quoted words: paths hold whitespace.
- Every overlay is REFUSED until `references/shared-state.md` has been read and every verdict it demands is recorded. Emptiness is a claim, never a verdict — that file says what evidences it. Nothing else — manifest, user, or inference — produces one. An overlay whose verdict is a refusal does not launch.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Manifest missing, matched, or drifted | Discover, reuse, or refresh that slice — see `references/discovery.md` |
| Changed paths map nowhere | No overlay; run tests, say so |
| Shared/common dir changed | Overlay its `consumers` |
| Port outside the range | Stop and ask |
| Any overlay | Gate it — `references/shared-state.md` |
| Overlay outlived its worktree | Report it — `references/reaping.md` |
| Stopping anything | Refuse without a matching identity |

## Execution Steps

1. At the worktree top, derive `gitCommonDir` and `repoRoot` — the **main** worktree, never this checkout — per `references/discovery.md` §0.
2. Load `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`; derive `hash8` and discard per `references/discovery.md` §0 and §5. If unwritable, run manifest-less and say so. Fingerprint `sources[].path` with `sh scripts/fingerprint.sh -C "$repoRoot"`.
3. Report overlays of this repository per `references/reaping.md`; exclude their ports.
4. Discover or refresh per Decision Gates (`references/discovery.md`).
5. Diff the worktree against its base branch; map changes through `paths`.
6. Confirm base-stack health; start what is missing.
7. Before launching, read `references/shared-state.md`; record every verdict it demands.
8. `sh scripts/pick-port.sh <lo> <hi> <worktree> [excluded-port ...]` — `portGroup` range, one per argument: reserved, base ports, taken this run. Bind strictly.
9. Launch each mapped service per `references/reaping.md`, rewiring unchanged dependencies to the base stack.
10. Verify with a real request, record `verifiedOverlays`, then rewrite the manifest through `scripts/with-lock.sh`.

## Output Contract

- Manifest path; created, reused, or refreshed — name refreshed entries.
- Changed paths and their mapped services.
- Per overlay: service, port, launch command, verification result.
- Base-stack services reused, not duplicated.
- The exact teardown command, any isolated namespace left behind, and how to remove it.

## References

- `assets/manifest.schema.json`, `assets/manifest.example.json`, `references/discovery.md`, `references/reaping.md`, `references/traps.md`, `scripts/fingerprint.sh`, `scripts/pick-port.sh`, `scripts/reap.sh`, `scripts/with-lock.sh`.
- `references/shared-state.md` — the only verdict procedure.
