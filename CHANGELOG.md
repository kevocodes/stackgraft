# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-08-07

Run against a real repository for the first time — 43 services, four compose files — the skill resolved the whole topology in under a second and then refused 116 of 156 `(service, store)` pairs. The overlay never launched. This release replaces the isolation half of the skill with the two things that run produced: a scope, and a copy.

**Breaking.** `schemaVersion` moves from `2` to `3` and there is **no migration path**. That is the design and not an omission: every field here is re-derivable from the repository, so a manifest whose version a reader does not recognise is **discarded** whole and rediscovered, which costs one discovery pass and carries nothing forward. Carrying a field forward would be worse than dropping it — the retired service-level `writes` array was one claim about a whole unit, and re-reading it as evidence about one pair is the amplification this version exists to end.

Two things do not revert themselves, and rolling back to `1.1.0` does not undo them. A manifest written at `3` is unrecognised by `1.1.0`, which discards it — the intended fail-safe. And **any store copy or approved lifecycle target created while 2.0 was live stays where it is**: the copy is on your disk, labelled, removable with the command every run prints, and the target is in your repository, where it is now yours. No data of yours is moved or deleted by the rollback itself.

### Added

- **The scope, stated where a reader meets it.** Local development: one host, one running base stack, N worktrees. CI, shared or remote hosts and multi-developer stacks are declared non-goals rather than untested territory. It is a grant as much as a limit — on one laptop, against gigabyte volumes, the skill may copy state instead of naming a corner of it.
- **ISOLATE means a seeded copy.** A second instance of the same image, started on a copy of the state your base stack holds, so it carries the data you have; making it asks your repository for nothing, and the bullet below says what verifying it asks for. `scripts/provider-docker.sh` ships one provider — `provision`, `address`, `destroy` — and names no store engine anywhere in its signature. In-instance isolation stays as the zero-disk optimisation with every rule it ever had intact.
- **A copy is not isolated until it answers a query an empty instance answers differently.** One command, issued through one route against the base store, the copy, and an empty instance of the same image. Matching proves the copy carries the base's state; discrimination proves the command could have said otherwise. `pg_isready`, `redis-cli ping` and `SELECT 1` are all measured to fail that test and are refused as queries. A copy that fails is destroyed and the pair refuses; it is never wired to the base store instead.
- **A missing lifecycle target is offered, never invented.** Where the cheap path is unavailable only because nothing defines a target, the run generates three files per store — create, drop **and read** — shows them in full, and writes them only on explicit approval, as new executable files in your existing script directory. It never appends to `Makefile`, `Taskfile.yml`, `justfile` or `package.json`, never edits a file it did not author, and never stages, commits or pushes. What it wrote is recorded `inferred` until a run has observed all three succeed, and the approval is fingerprinted over the files as you approved them.
- **Two hazards, two mechanisms.** A data hazard buys a copy; a coordination hazard buys a distinct identity. `references/coordination-identity.md` holds the identity knob per substrate and the three-part proof a recorded value passes before the competition is over. Cloning a broker to avoid a consumer-group collision is not the answer and is no longer offered.
- **A name family instead of one shape.** One branch hash, one separator-free slug, two projections: an SQL identifier and a DNS or object-store label. The separator belongs to the projection, which makes "no underscore in a label" true by construction — every bucket `1.1.0` could name was rejected by the substrate itself.
- **The rules for reclaiming a store copy, written down and deliberately not implemented.** `references/reaping.md` section 9a specifies candidacy by the complete label set, liveness against git's worktree list, and a removal flag **in addition to** the mutation flag, because a copy removed by accident is state nothing on the host can reproduce. **None of it is in `scripts/reap.sh`**, which accepts containers and processes and nothing else, so an orphaned copy is not detected and not reclaimed. What ships is `provider-docker.sh destroy`, which removes a copy for a worktree you can still name and takes no flags, plus the copy's name and removal command printed on every launch. The section says so at the top, and so does `README.md` under *Honest limits*.

### Changed

- **Determinacy is recorded per `(unit, store)`.** The single `writes` array is gone: it was a positive claim that asserted checked-and-none for every other store at once, so a pass that determined one store and could not determine the next had to say nothing about any of them. `migrates` now names only the stores an entrypoint is pointed at.
- **The gate's subject is the pairs the change can reach.** The worktree diff that already selects which units to overlay now selects which pairs enter the gate — one-directional, evidence-bound, and reported with the narrowed count beside the derived one. `dependsOn` still narrows nothing.
- **Managed, remote, host-native and undeterminable-locality stores refuse by name**, with the fact discovery recorded carried into the message. A refusal does not cascade.
- **The integer allocator is deleted.** Sixteen host-global slots that nothing owns are a pool two worktrees draw the same value from and never detect. An index-addressed store gets a copy like every other store.

### Fixed

- **`{{isolationName}}` could not name an S3 or MinIO bucket at all** — its underscores are mandatory and those grammars forbid them. Measured against a real object store: every bucket `1.1.0` could name is rejected by `make_bucket`, and every one the label form names is created.
- **A startup migration made W = yes against every store in the map**, whatever the change touched. It is now scoped, and an unscoped one leaves every store of that unit undetermined rather than relieved.
- **A volume copy leaked one anonymous volume per provision.** A store image commonly declares a volume path of its own, and any such path the run does not mount over becomes an unnamed volume that no scoped query can ever find.

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

[2.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v2.0.0
[1.1.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.1.0
[1.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.0.0
