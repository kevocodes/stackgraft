---
name: stackgraft
description: "Trigger: git worktree, run only the changed service on another port, test branches in parallel. Overlay modified services onto an already-running base stack."
compatibility: "POSIX systems only: macOS, Linux, WSL. Windows-native is out of scope. git and a POSIX shell with awk are required unconditionally and ship with a stock macOS and a minimal Linux image. Container tooling such as docker compose is required only for container-based repositories."
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
- Port probes are a heuristic, never proof: bind with strict-port and honor `portPolicy.reserved`.
- Never kill a process you did not start.
- Never place a worktree under `/tmp` or `/var/tmp`; both are reaped without warning.
- `/health` returning 200 is not proof; verify a real request and read its headers.
- The manifest is a cache, never truth: refresh drifted entries; on conflict the repo wins and the entry is rewritten.
- Every overlay is REFUSED until `references/shared-state.md` has been read and a verdict is recorded for it. An empty dependency set is not a verdict. Nothing else — not the manifest, not the user, not inference — produces one.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Manifest missing | Full discovery, then write it |
| All fingerprints match | Reuse manifest, skip discovery |
| Some source drifted | Re-discover only that slice, rewrite those entries and hashes |
| Changed paths map to no service | No overlay; run tests only and say so |
| Change touches a shared/common dir | Overlay every service listed in that entry's `consumers` |
| Only the client/frontend changed | Overlay the dev server on a candidate port; reuse all backends |
| Overlay needs a port outside the range | Stop and ask before binding |
| Overlay service has a base-stack dependency | Gate it — `references/shared-state.md` |

## Execution Steps

1. Resolve `repoRoot`: `git rev-parse --path-format=absolute --git-common-dir` minus `/.git`.
2. Load `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, `hash8` being `git hash-object --stdin` over that common dir, truncated to 8. Discard on validation failure or `repoRoot` mismatch; when unwritable, run manifest-less and say so. Fingerprint `sources[].path` with `scripts/fingerprint.sh`.
3. Discover or refresh per the Decision Gates (`references/discovery.md`).
4. Diff the worktree against its base branch; map changed paths through `paths` globs.
5. Confirm the base stack is healthy; start what is missing.
6. `scripts/pick-port.sh <portGroup range lo> <hi> <worktree> <reserved, basePorts, ports taken this run>`; bind strictly.
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
