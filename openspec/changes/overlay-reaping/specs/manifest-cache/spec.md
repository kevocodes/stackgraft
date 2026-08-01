# manifest-cache

Modified capability. The manifest requirements this capability extends were introduced by `portable-multi-stack` under the directory name `manifest-contract` (`../../../portable-multi-stack/specs/manifest-contract/spec.md`); `../../proposal.md` names the capability `manifest-cache` and that name is carried here. The two names MUST be reconciled to one capability directory before either change is archived, so that `openspec/specs/` gains one manifest capability rather than two covering the same file. Nothing stated in the earlier requirements is replaced.

Write discipline (D9) and the three obligations it creates: `../../proposal.md` D9 and Q4. The discipline is stated once here and applies to both cache files; `../overlay-ownership/spec.md` names the sidecar as subject to it.

## ADDED Requirements

### Requirement: Cache-file writes are serialized and atomic

Every write to a file under `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/` — the manifest and the host-overlay sidecar alike — MUST use one discipline: acquire a lock by creating a directory with `mkdir`, write a temporary file in the destination directory, and `rename` it into place while the lock is held. `mkdir` is atomic, fails when the directory already exists, and is in POSIX; `rename` within one directory is atomic on every supported platform. One discipline MUST serve both files, and a second mechanism MUST NOT be introduced for either — two divergent disciplines is the outcome this requirement exists to prevent. `flock` MUST NOT be used: util-linux ships it and stock macOS does not. A concurrent reader MUST observe either the previous complete file or the new complete file, never a partial or truncated one. This retrofits the existing manifest write, which today has no protection at all while a per-worktree port offset exists precisely because concurrent worktrees are the expected case.
(Verify: two concurrent writers exercised against one manifest; file review that the sidecar write and the manifest write call the same shipped script; command list of `scripts/with-lock.sh` contains no `flock`; the existing manifest suite runs unchanged.)

#### Scenario: Two concurrent worktrees write one manifest

- GIVEN two worktrees of one repository each complete an overlay and rewrite the manifest at the same time
- WHEN both writes finish
- THEN both `verifiedOverlays` entries are present in the resulting file
- AND neither writer's entry was lost to the other

#### Scenario: Reader during a write

- GIVEN a writer holds the lock and is replacing the manifest
- WHEN another run loads the manifest
- THEN it parses successfully, reading either the previous complete file or the new one

#### Scenario: Writer crashes mid-write

- GIVEN a writer is interrupted after composing its temporary file and before the rename
- WHEN the cache directory is inspected
- THEN the destination file is still the previous complete file, and the temporary file never occupied the destination name

### Requirement: A lock is bounded in wait and reclaimable when abandoned

Acquisition MUST wait at most a declared bound and MUST NOT wait indefinitely. A lock older than a declared staleness bound MUST be reclaimed, so a holder that crashed cannot wedge every later run: a permanent outage is a worse failure than the occasional clobber the lock exists to prevent, which makes the staleness policy a requirement rather than a refinement. Both bounds MUST be stated as values in a shipped file, not left to be inferred from the script's control flow. Reclaiming a stale lock MUST be reported. The wait MUST NOT be implemented with `timeout`, which is absent from at least one supported platform.
(Verify: abandoned-lock case exercised — create the lock directory, leave no holder, and run a write; file review that both bounds are stated; command list of `scripts/with-lock.sh`.)

#### Scenario: Abandoned lock

- GIVEN a lock directory left behind by a crashed holder, older than the staleness bound
- WHEN the next write runs
- THEN the lock is reclaimed within the declared bound, the reclamation is reported, and the write completes

#### Scenario: Live holder inside the bound

- GIVEN a lock held by a running writer and younger than the staleness bound
- WHEN another write runs
- THEN the lock is not reclaimed and the waiter waits, up to the declared wait bound

#### Scenario: Bounds are discoverable

- GIVEN a reader of the shipped files
- WHEN the write discipline is looked up
- THEN the wait bound and the staleness bound are both stated as values

### Requirement: Failure to acquire is a reported failure, never a skipped write

A write that could not take the lock MUST be reported as a failed write, naming the file that was not written. No path MAY report success, "manifest written", or a recorded overlay for a write that did not happen — a silently skipped write is the same silent loss the discipline exists to prevent, arriving by another route. No path MAY fall back to an unlocked write.
(Verify: hold the lock from another process past the wait bound while keeping it fresh, then run a write; grep the write paths for any unlocked fallback.)

#### Scenario: Lock unavailable past the wait bound

- GIVEN a live holder keeps the lock past the wait bound
- WHEN a write is attempted
- THEN the write is reported as failed, the file is named, and the run's output does not claim the record was stored

#### Scenario: Lock directory cannot be created

- GIVEN the cache directory is not writable
- WHEN a write is attempted
- THEN the failure is reported the same way as any other acquisition failure, and the run continues manifest-less and says so

#### Scenario: No unlocked fallback exists

- GIVEN every path that writes a file under the stackgraft cache directory
- WHEN they are reviewed
- THEN each goes through the shared discipline and none writes the destination directly

### Requirement: Read paths take no lock

Loading the manifest, checking fingerprint freshness, reading the sidecar, and the whole report pass MUST NOT acquire the lock and MUST NOT be blockable by a holder. A read that observes a lock MUST proceed rather than wait. The report pass is read-only by construction, so a writer MUST NOT be able to prevent a user from seeing what is running.
(Verify: hold the lock and run the report pass and a manifest load; file review that no read path calls the lock script.)

#### Scenario: Report pass during a write

- GIVEN a writer holds the cache lock
- WHEN the report pass runs
- THEN it completes without acquiring or waiting for the lock

#### Scenario: Manifest load during a write

- GIVEN a writer holds the cache lock
- WHEN another run loads the manifest
- THEN it completes, reading the previous complete file

#### Scenario: Stale lock present

- GIVEN a lock directory older than the staleness bound
- WHEN any read path runs
- THEN it ignores the lock entirely and does not reclaim it

### Requirement: The ownership record owes no schema change

The label contract and the sidecar MUST NOT add, rename, or remove any manifest field. `schemaVersion` MUST remain `2` across both slices, no cached manifest MAY be invalidated or rediscovered because of this change, and `stackgraft.labels` MUST version the label contract independently of `schemaVersion`. The only permitted `assets/` edit is the `overlayCommand` description required by `../topology-discovery/spec.md`. The single-bump rule established by `portable-multi-stack` is therefore not reopened by a change with no business touching topology.
(Verify: schema diff reviewed — description text only; `schemaVersion` compared before and after each slice; a manifest written before the change loaded after it.)

#### Scenario: Pre-change manifest still valid

- GIVEN a manifest written before this change landed
- WHEN it is loaded after both slices
- THEN it validates, is reused, and no rediscovery is forced by this change

#### Scenario: Version unchanged across both slices

- GIVEN `schemaVersion` before the change and after each slice
- WHEN the values are compared
- THEN all three are `2` and no transition occurred

#### Scenario: Schema diff reviewed

- GIVEN the diff of `assets/manifest.schema.json` across both slices
- WHEN it is read
- THEN it changes the `overlayCommand` description only, adding no property and removing none

#### Scenario: Label contract versioned separately

- GIVEN the label contract version is raised
- WHEN the manifest is loaded afterwards
- THEN `schemaVersion` is unaffected and no cache is discarded
