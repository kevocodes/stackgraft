# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-07-31

First public release.

### Added

- **The skill.** An [Agent Skills](https://agentskills.io) folder read by roughly forty agents: `SKILL.md` plus `references/`, `assets/` and `scripts/`. No per-agent adapters.
- **Selective overlay.** Starts only the services a git worktree changed, on candidate ports, wiring every unchanged dependency back to the base stack already running.
- **A cached topology manifest** under `XDG_CACHE_HOME`, keyed by the git common directory so every worktree of a repository shares one. Invalidation is per slice: a drifted source re-derives only the manifest keys it owns.
- **Discovery that prefers each ecosystem's own resolver** over hand-parsing — leading with `docker compose config --no-interpolate`, which resolves overrides, `extends` and `include` without expanding a secret — and degrades to a marked static parse rather than failing.
- **The shared-state gate.** Every `(service, store)` pair receives a verdict before anything launches: reuse, isolate inside the running instance, or refuse. Unknown resolves to refusal, and emptiness is a claim requiring evidence at every level.
- **A discovered-template contract.** Isolation commands come from the repository and are therefore untrusted: closed placeholder set, a deny-list on the template's own grammar, argv execution with no shell fallback, and rejection of any program that would re-parse an argument as code.
- **Two POSIX `sh` helpers** needing only `git` and `awk`. Neither reads stdin by default, because for a tool an agent invokes, hanging is worse than failing.
- **A Claude Code plugin** wrapping the same folder, for one-command install.
- **A verification suite** run in CI on every push, including a job that exercises the helpers on Alpine with nothing but `git`, `dash` and busybox `awk`.

### Notes on how this arrived

Three adversarial review lineages — six correction rounds and six blind dual re-judgments — closed roughly seventy findings before this release. The ones worth recording:

- **A gate satisfiable by declaring nothing.** The trigger rested on data that could be absent and reopened one level up four times: an optional map, then an optional list, then an empty list, then a second optional map. Each fix was correct for the case in front of it. What closed it was making emptiness cost something at every level rather than moving the trigger again.
- **A perverse incentive.** With optional classification, declaring one field forced a refusal while declaring none forced nothing — the laziest manifest was the least restricted, the exact inverse of failing closed.
- **A guard wrong in the safe direction, replaced by one wrong in the unsafe direction.** A deny-list applied after placeholder substitution rejected any host path containing `&`; the structural rule that replaced it silently admitted `sh -c '… {{path}} …'`, where the value becomes shell grammar again inside a nested interpreter.
- **A verifier that could not fail.** A cross-file check collected field names from the schema and verified them against the schema, so it passed for several rounds while proving nothing. Its replacement is proven by breaking it.

[1.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.0.0
