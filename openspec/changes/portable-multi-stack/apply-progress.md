# Apply progress: portable-multi-stack

Slice: **PR 1 — portable runtime**. Branch `feat/portable-multi-stack-1-runtime`, base `feat/portable-multi-stack`.
Mode: standard. `openspec/config.yaml` sets `strict_tdd: false` (no test runner, no language runtime, no CI), so every check below is one of the methods listed under `testing.available_verification`.

## RED fixture — git repository selection (task 1.2, design threat row 2)

Scratch repo, a linked worktree, a subdirectory, and a symlinked path; the manifest path resolved from all four.

- **The task's premise needed correcting.** The vantage-point axis is already stable: `git rev-parse --path-format=absolute --git-common-dir` normalises worktree, subdirectory, and symlink alike, so all four vantage points resolve to one repo root. The three-path defect is real, but it sits on a different axis.
- **The real RED.** `SKILL.md:41` said `~/.claude/stackgraft/<slugified-repo-root>.json` and never defined the slug. Three plausible readings of "slugified" produced **3 distinct manifest paths for one repository**: `tr -c alnum '-'`, `tr '/' '_'`, and `<parent>-<basename>`.
- **Same-basename collision.** Under the `<parent>-<basename>` reading, `orgA/api` and `orgB/api` both resolve to `api.json`.
- **GREEN after task 1.4.** `<repo-basename>-<hash8>` yields one path from all four vantage points (`repo-e618519d.json`), and `api-d2bd9622.json` vs `api-205ebc6d.json` for the two same-basename repositories.
