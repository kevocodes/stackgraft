# Apply progress: portable-multi-stack

Slice: **PR 1 — portable runtime**. Branch `feat/portable-multi-stack-1-runtime`, base `feat/portable-multi-stack`.
Mode: standard. `openspec/config.yaml` sets `strict_tdd: false` (no test runner, no language runtime, no CI), so every check below is one of the methods listed under `testing.available_verification`.

## RED fixture — git repository selection (task 1.2, design threat row 2)

Scratch repo, a linked worktree, a subdirectory, and a symlinked path; the manifest path resolved from all four.

- **The task's premise needed correcting.** The vantage-point axis is already stable: `git rev-parse --path-format=absolute --git-common-dir` normalises worktree, subdirectory, and symlink alike, so all four vantage points resolve to one repo root. The three-path defect is real, but it sits on a different axis.
- **The real RED.** `SKILL.md:41` said `~/.claude/stackgraft/<slugified-repo-root>.json` and never defined the slug. Three plausible readings of "slugified" produced **3 distinct manifest paths for one repository**: `tr -c alnum '-'`, `tr '/' '_'`, and `<parent>-<basename>`.
- **Same-basename collision.** Under the `<parent>-<basename>` reading, `orgA/api` and `orgB/api` both resolve to `api.json`.
- **GREEN after task 1.4.** `<repo-basename>-<hash8>` yields one path from all four vantage points (`repo-e618519d.json`), and `api-d2bd9622.json` vs `api-205ebc6d.json` for the two same-basename repositories.

## Work unit evidence (tasks 1.1-1.7, all done)

| Check | How | Result |
|---|---|---|
| V5 POSIX syntax | `dash -n` on both scripts; `sh -n` under `alpine/git` | both parse on both platforms |
| Runtime harness | both scripts run on macOS and in `docker run --rm -v "$PWD":/w -w /w alpine/git`; one `command -v` per name for `git` and `awk` | identical output on both (`18538`, `5196`, exclusion to `5198`, exhaustion exit 3); both tools present. Gotcha: busybox `command -v` reports only its first argument |
| V2 schema/example | `jsonschema` Draft202012 `check_schema` plus `iter_errors` | schema valid; example validates with `additionalProperties: false`; `schemaVersion: 1`, absent `fingerprintTool`, and `sha256` all rejected; a 64-char fingerprint accepted |
| V3 cross-file | every manifest field `SKILL.md` names, resolved against the schema | 17/17 present |
| V1 body budget | the DS3 `awk` word count | 496 to **434** words, under the 435 ceiling; style-guide section order and the 157-char `description` intact |
| V4 portability | `rg` for `~/.claude`, vendor index names, `python3`, `jq`, `sha256sum` | clean |

Rollback: revert this branch. `skills/stackgraft/scripts/` disappears and the v1 skill returns intact; no later slice depends on it yet.
