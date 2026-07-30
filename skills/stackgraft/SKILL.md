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

- Start only services whose files the worktree changed. Point every unchanged dependency at the base stack already running.
- A port free in `lsof` is not a port that is available. Honor `portPolicy.reserved` and ask before taking a port outside the overlay range.
- Never kill a process you did not start. Confirm ownership with `lsof -a -p <pid> -d cwd -Fn` first.
- Never place a worktree under `/tmp` or `/var/tmp`. Each worktree needs its own `.codegraph/`; never reuse another checkout's index.
- A `200` on `/health` is not proof. Verify a real request carrying the overlay's `Origin`/host and read the response headers back.
- Never act on a manifest entry whose source fingerprint drifted. Refresh it first.
- Treat the manifest as a cache, never as truth. On any conflict, the repo wins and the manifest gets rewritten.

## Decision Gates

| Situation | Action |
|-----------|--------|
| Manifest missing | Full discovery, then write it |
| All fingerprints match | Reuse manifest, skip discovery |
| Some source drifted | Re-discover only that slice, rewrite those entries and hashes |
| Changed paths map to no service | No overlay; run tests only and say so |
| Change touches a shared/common dir | Overlay every service listed in that entry's `consumers` |
| Only the client/frontend changed | Overlay the dev server on a free port; reuse all backends |
| Overlay needs a port outside the range | Stop and ask before binding |

## Execution Steps

1. Resolve `repoRoot`: `git rev-parse --path-format=absolute --git-common-dir` minus `/.git`.
2. Load `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, `hash8` being `git hash-object --stdin` over that common dir, truncated to 8. Discard on `schemaVersion`/`repoRoot` mismatch; when unwritable, run manifest-less and say so. Fingerprint `sources[].path` with `scripts/fingerprint.sh`.
3. Discover or refresh per the Decision Gates — follow `references/discovery.md`.
4. Diff the worktree against its base branch and map changed paths to services via each entry's `paths` globs.
5. Confirm the base stack is up and healthy; start only what is missing.
6. Allocate ports from `portPolicy`.
7. Launch the mapped services with env overrides so every unchanged dependency resolves to the base stack.
8. Verify each overlay with a real request, record it in `verifiedOverlays`, and write the manifest back.

## Output Contract

Return:

- Manifest path, and whether it was created, reused, or refreshed — name the refreshed entries.
- Changed paths and the services they mapped to.
- Per overlay: service, port, launch command, verification result.
- Base-stack services reused, not duplicated.
- The exact teardown command.

## References

- `assets/manifest.schema.json` — manifest field contract.
- `assets/manifest.example.json` — filled multi-service example.
- `references/discovery.md` — discovery and slice-refresh procedure per stack type.
- `references/traps.md` — verified failure modes to check every run.
- `scripts/fingerprint.sh`, `scripts/pick-port.sh` — POSIX helpers.
