# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-08-02

An overlay used to outlive the worktree that created it, holding a port and serving a branch that no longer existed. This release makes an overlay identifiable after the fact, and reclaimable only with proof.

Backward compatible: `schemaVersion` stays at `2` and a manifest written before this release still loads and is reused, with no forced rediscovery.

### Added

- **Overlay ownership.** Every container-kind overlay now carries five labels, so `docker ps --filter label=stackgraft.repo=<hash8>` reconstructs live overlay state **with the manifest deleted**. Host-run services, which have nowhere to hang a label, register in a per-repository sidecar beside the manifest.
- **Ownership proof by `(pid, lstart)`**, compared as verbatim strings — the same `ps` on the same host produced both, so equality is the only operation needed and nothing is parsed. A pid recycled between registration and reap is refused, and the refusal names the mismatch. Where `ps` has no `lstart`, host overlays degrade to report-only rather than being silently unproven.
- **A report pass on every invocation**, which never mutates under any flag combination and completes while another run holds the lock.
- **`scripts/reap.sh`.** Reclaiming requires an explicit flag and **stops** the container; removal is a second flag, so an orphan's logs survive the reap that frees its port. A target whose ownership cannot be proven is refused by name and the proven targets beside it are still acted on.
- **`scripts/with-lock.sh`** and `references/reaping.md`.

### Fixed

- **The manifest's last-writer-wins window.** `SKILL.md` said *rewrite the manifest*, with no lock and no atomic replace, while the design already treats concurrent worktrees as the expected case — two runs would reach that step against one file and the loser's `verifiedOverlays` entry vanished with no error. Writes are now serialized **and** compare-and-swap: serializing alone does not fix it, because the loss happens in the read-modify-write window, not in the write.
- A reclaim that could not delete what it set aside used to exit `0` reporting success over the debris. It now fails loudly and names what it left.

### Changed

- **Two limits are stated rather than covered.** Overlays launched before the label contract carry no label, so nothing distinguishes them from any other container on the machine — the report names the category and declares itself incomplete instead of pretending to enumerate them. And the base-stack port exclusion is **caller-supplied and caller-defeatable**: the helpers parse no JSON, so nothing can check a passed port against the manifest it came from. What holds unconditionally is the positive allowlist.
- Installation leads with the Agent Skills package managers — `npx skills add kevocodes/stackgraft` — instead of asking the reader to know where their agent keeps skills.
- The skill frontmatter gained a top-level semver `version`, which `paks` requires. One release is now one number in four places, and CI rejects a partial bump.

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

[1.1.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.1.0
[1.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.0.0
