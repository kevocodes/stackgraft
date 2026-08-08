# manifest-contract

New capability. Location decision (D1), version decision (D2), and example fixes (D3): `../../proposal.md`. Field-level evidence: `../../exploration.md` Q2 and Q4.

## ADDED Requirements

### Requirement: The manifest is a cache, never truth

On any conflict between a manifest value and what the repository yields, the repository MUST win and the conflicting entry MUST be rewritten in the same run. A manifest whose `schemaVersion` is unrecognized MUST be discarded whole and rediscovered; no migration of stored values MAY be attempted. A missing, unreadable, or malformed cache MUST trigger full discovery and MUST NOT fail the run.
(Verify: file review — the rule is a SKILL.md Hard Rule and is restated in `references/discovery.md`.)

#### Scenario: Stored value contradicts the repository

- GIVEN the manifest records a `basePort` that differs from the port the repository resolves to
- WHEN the overlay is prepared
- THEN the repository's value is used and the manifest entry is rewritten before the run reports

#### Scenario: Unrecognized schema version

- GIVEN a cached manifest whose `schemaVersion` the reader does not recognize
- WHEN the manifest is loaded
- THEN it is discarded in full and discovery runs from scratch
- AND no field is carried over from the discarded file

#### Scenario: Cache absent or wiped

- GIVEN the cache file does not exist or cannot be parsed
- WHEN the run starts
- THEN full discovery runs and the manifest is written back
- AND the run does not report an error for the missing cache

### Requirement: Agent-neutral cache location

The manifest MUST live at `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.json`, where `hash8` is derived from the repository's git common directory. It MUST NOT be written under `.git/`, under any agent-specific directory, or under a raw path slug. Every worktree of one repository MUST resolve to the same file, and two repositories sharing a basename MUST resolve to different files. Cache eviction is out of scope.
(Verify: file review of SKILL.md Execution Steps; portability grep — no agent-specific path in shipped files.)

#### Scenario: Worktree and main checkout agree

- GIVEN the run starts inside a linked worktree
- WHEN the manifest path is resolved
- THEN it is identical to the path resolved from the main checkout

#### Scenario: Same basename, different repositories

- GIVEN two repositories whose root directories share a basename
- WHEN each resolves its manifest path
- THEN the `hash8` segments differ and the two manifests do not collide

#### Scenario: XDG override honored

- GIVEN `XDG_CACHE_HOME` is set
- WHEN the manifest path is resolved
- THEN it is rooted at that value, not at `$HOME/.cache`

### Requirement: Schema v2 field contract

`assets/manifest.schema.json` MUST declare `schemaVersion` as `2`. `sha256` MUST be replaced by `fingerprint`, accompanied by `fingerprintTool`. `kind` MUST accept unknown strings and MUST NOT key port ranges; `portPolicy.ranges` MUST be keyed by an explicit `portGroup`. `runnable`, `backingStores`, per-service `writes`, `competesOn`, `migrates`, and `acceptedRisks` MUST exist. `healthPath`, `dockerfile`, and the `static` kind MUST NOT exist. `additionalProperties: false` MUST be retained.
(Verify: schema validation of `assets/*.json`; cross-file that every field named in SKILL.md or `references/` exists here.)

#### Scenario: New stack type needs no version bump

- GIVEN a manifest using a `kind` value the schema never enumerated, with a `portGroup` present in `portPolicy.ranges`
- WHEN the manifest is validated
- THEN it validates and `schemaVersion` remains `2`

#### Scenario: Retired field rejected

- GIVEN a manifest containing `healthPath`, `dockerfile`, or `kind: "static"`
- WHEN the manifest is validated
- THEN validation fails

#### Scenario: Version bumped exactly once

- GIVEN the full change is applied
- WHEN `schemaVersion` values are compared before and after
- THEN exactly one transition occurred, from `1` to `2`

### Requirement: Log fields stay bounded

`verifiedOverlays` MUST be keyed by service and `acceptedRisks` by `(service, store)`, each keeping only the latest entry. Neither MAY be append-only.
(Verify: schema validation — uniqueness is expressed in the schema; file review of the field descriptions.)

#### Scenario: Repeated verification of one service

- GIVEN a service has been verified several times
- WHEN the manifest is written back
- THEN exactly one `verifiedOverlays` entry exists for that service, carrying the latest timestamp

### Requirement: The shipped example validates and demonstrates the premise

`assets/manifest.example.json` MUST validate against `assets/manifest.schema.json`, so it MUST carry no root-level comment key; explanatory caveats MUST live in `references/`. Every `overlayCommand` in the example MUST start no dependency of its own, MUST NOT re-bind any `basePort`, and MUST rewrite unchanged peers to the base stack.
(Verify: schema validation; file review of the example's launch commands.)

#### Scenario: Example validated

- GIVEN the shipped example and schema
- WHEN the example is validated against the schema
- THEN validation passes with `additionalProperties: false` in force

#### Scenario: Example overlay command reviewed

- GIVEN a compose-based service entry in the example
- WHEN its `overlayCommand` is read
- THEN it suppresses dependency startup, publishes only the overlay port, and leaves the base stack's published port untouched

#### Scenario: Documented field missing from the schema

- GIVEN SKILL.md or a `references/` file names a manifest field
- WHEN the cross-file consistency check runs
- THEN that field exists in the schema, otherwise the check fails

## ADDED Requirements (from parallel-feature-isolation)

### Requirement: Determinacy is recorded per `(unit, store)`

The manifest MUST carry one determinacy record per `(unit, store)` pair, each recording W, X, the evidence for each, and its own `serviceFingerprint`. The single service-level `writes` array MUST NOT exist, and no field MAY be reintroduced whose **presence** asserts checked-and-none for every store at once.

That reading is the defect being repaired, and the shipped files MUST state it in these terms: `writes: ["postgres"]` was a *positive* claim that simultaneously asserted checked-and-none for every other store, so a pass that determined one store and could not determine another had to omit the field entirely, making all of them undetermined. The missing capability was **granularity**, not the ability to write a negative. A per-store record MUST therefore be able to say checked-and-none for one store while saying nothing at all about the next.

An absent record MUST be undetermined, which refuses; the fail-closed direction is unchanged. A record MUST be about exactly one pair: it MUST NOT be readable as evidence about another store, another unit, or a set. A record whose `serviceFingerprint` no longer matches its unit's source MUST be treated as absent.
(Verify: schema validation — `writes` is absent from the schema and a manifest carrying it is rejected; a manifest carrying a record for one store and none for another validates; cross-file that every field named in `references/` exists here.)

#### Scenario: Partially-informed pass

- GIVEN discovery determined `(catalog-api, postgres)` and could not determine `(catalog-api, redis)`
- WHEN the manifest is written
- THEN one record exists for postgres, none for redis, and the manifest validates

#### Scenario: The all-or-nothing field is gone

- GIVEN a manifest carrying a service-level `writes` array
- WHEN it is validated
- THEN validation fails

#### Scenario: A record is about one pair only

- GIVEN a record stating `(catalog-api, postgres)` is W=no
- WHEN `(catalog-api, kafka)` and `(billing, postgres)` are classified
- THEN neither reads that record as evidence, and each needs its own

#### Scenario: Record expires with its unit's source

- GIVEN a record whose `serviceFingerprint` differs from its unit's current fingerprint
- WHEN the gate reads it
- THEN it is treated as absent and the pair is undetermined

### Requirement: `migrates` names the stores the entrypoint is pointed at

`migrates` MUST be expressed as the stores a unit's entrypoint is **pointed at**, which the per-store record names, and MUST NOT be a unit-level boolean read as W=yes against every entry in `backingStores`. Nearly every service in a real repository applies schema on startup, so the unscoped reading made one true fact amplify into a write claim against every store the repository has, which is where the bulk of the over-refusals came from.

Scoping it MUST NOT weaken the reason the field exists. A unit that migrates on startup still writes, and that write MUST survive any narrowing the change classification performs (`../shared-state-safety/spec.md`). **Where the pointing is unknown, every store of that unit MUST be undetermined, which refuses** — an unscoped `migrates` becomes a scoped one only where the scope is evidenced, never by default.
(Verify: schema validation that the field carries store names rather than a bare boolean; the 43-service repository re-run and its refusal count compared against the recorded baseline; a unit whose pointing is unknown exercised.)

#### Scenario: Entrypoint pointed at one store

- GIVEN a unit that applies schema on startup against postgres, with the pointing recorded
- WHEN its pairs are classified
- THEN `(unit, postgres)` is W=yes and the unit's other stores are classified on their own records

#### Scenario: Pointing unknown

- GIVEN a unit recorded as migrating on startup with no record of which stores it reaches
- WHEN its pairs are classified
- THEN every store of that unit is undetermined and refuses

#### Scenario: F5 regression

- GIVEN a repository whose services create schema at startup and whose `backingStores` carries four entries
- WHEN the pairs are classified
- THEN a unit pointed at one store no longer yields W=yes against the other three

### Requirement: `isolation` carries a provider reference, and the placeholder set carries the name family

`backingStores[].isolation` MUST be able to carry a **provider reference** for the data hazard — the runtime that will provision, address and destroy a seeded copy — and MUST remain able to carry an in-instance record for the zero-disk optimisation. Both MUST be expressible in one entry, and a store with neither MUST be expressible too.

`{{isolationName}}` MUST be replaced by the members of the name family (`../coordination-identity/spec.md`), each a distinct placeholder with a defined source. The placeholder set MUST stay **closed**: any other `{{…}}` invalidates the template. No placeholder MAY yield an allocated value, and no schema field MAY describe a bounded pool, an exhaustion case, or a release obligation for a namespace name.
(Verify: schema validation of a store carrying a provider reference, a store carrying an in-instance record, and a store carrying neither; a template using an unknown placeholder confirmed to invalidate; grep of the schema for an allocated-value placeholder, finding none.)

#### Scenario: Provider reference recorded

- GIVEN a store whose data hazard resolves through the shipped provider
- WHEN the manifest is validated
- THEN the provider reference validates and no in-instance command is required beside it

#### Scenario: In-instance record retained

- GIVEN a store with a complete, approved create-and-teardown lifecycle
- WHEN the manifest is validated
- THEN the in-instance record validates and the store may still carry a provider reference

#### Scenario: Name family placeholders

- GIVEN a template using the SQL-identifier form and another using the label form
- WHEN both are validated
- THEN both are inside the closed set, and a template using any other `{{…}}` is invalid

#### Scenario: No allocated placeholder exists

- GIVEN the closed placeholder set
- WHEN each member's source is read
- THEN every one is derived, and none is drawn from a pool

## MODIFIED Requirements (from overlay-reaping and parallel-feature-isolation)

### Requirement: Schema v3 field contract (renamed from Schema v2 field contract)

`assets/manifest.schema.json` MUST declare `schemaVersion` as `3`. The per-`(unit, store)` determinacy records MUST exist and the service-level `writes` array MUST NOT. `migrates` MUST name the stores an entrypoint is pointed at. `backingStores[].isolation` MUST admit a provider reference. The name family MUST replace `{{isolationName}}` in the closed placeholder set. `fingerprint` and `fingerprintTool` MUST be retained, and `sha256` MUST NOT exist. `kind` MUST accept unknown strings and MUST NOT key port ranges; `portPolicy.ranges` MUST be keyed by an explicit `portGroup`. `runnable`, `backingStores`, `competesOn` and `acceptedRisks` MUST exist. `healthPath`, `dockerfile`, and the `static` kind MUST NOT exist. `additionalProperties: false` MUST be retained.

**No migration path MAY be written, and its absence is the design.** Everything the manifest holds is re-derivable from the repository, so a manifest whose `schemaVersion` a reader does not recognise MUST be discarded whole and rediscovered — which is how a `2` manifest reaches `3` and how a `3` manifest reaches `1.1.0` after a rollback. The bump MUST happen exactly once across this change's slices, and no slice MAY publish on its own.
(Verify: schema validation of `assets/*.json`; a schema-2 manifest loaded under this version and confirmed discarded with nothing carried over; a schema-3 manifest loaded under `1.1.0` and confirmed discarded; `schemaVersion` compared before and after each slice; cross-file that every field named in SKILL.md or `references/` exists here.)

#### Scenario: New stack type needs no version bump

- GIVEN a manifest using a `kind` value the schema never enumerated, with a `portGroup` present in `portPolicy.ranges`
- WHEN the manifest is validated
- THEN it validates and `schemaVersion` remains `3`

#### Scenario: Retired field rejected

- GIVEN a manifest containing `writes`, `healthPath`, `dockerfile`, or `kind: "static"`
- WHEN the manifest is validated
- THEN validation fails

#### Scenario: Version bumped exactly once

- GIVEN the full change is applied across its slices
- WHEN `schemaVersion` values are compared before and after each slice
- THEN exactly one transition occurred, from `2` to `3`

#### Scenario: Cached manifest from the previous version

- GIVEN a manifest written at `schemaVersion` 2
- WHEN it is loaded under this version
- THEN it is discarded whole, discovery runs from scratch, and no field is carried over

#### Scenario: Rollback to the previous release

- GIVEN a manifest written at `schemaVersion` 3 and the skill folder reverted to `1.1.0`
- WHEN the manifest is loaded
- THEN it is unrecognised, discarded, and rediscovered, and the run does not fail for it

### Requirement: The ownership record owes no schema change

The label contract and the sidecar MUST NOT add, rename, or remove any manifest field. Across `overlay-reaping`'s two slices `schemaVersion` MUST remain `2`, no cached manifest MAY be invalidated or rediscovered because of **that** change, and `stackgraft.labels` MUST version the label contract independently of `schemaVersion`. The only `assets/` edit that change permits is the `overlayCommand` description required by `../topology-discovery/spec.md`. The single-bump rule established by `portable-multi-stack` is therefore not reopened by a change with no business touching topology.

**This requirement constrains `overlay-reaping` and MUST NOT be read as a standing prohibition on a later version bump.** It says that an ownership change owes no schema change; it does not say the schema is frozen. The requirement that owns the current version is `Schema v3 field contract`, and the independence of `stackgraft.labels` from `schemaVersion` is what lets the two move separately.
(Verify: schema diff of `overlay-reaping` reviewed — description text only; `schemaVersion` compared before and after each of that change's slices; a manifest written before that change loaded after it; file review that this requirement names the requirement owning the current version.)

#### Scenario: Pre-change manifest still valid

- GIVEN a manifest written before `overlay-reaping` landed
- WHEN it is loaded after both of that change's slices
- THEN it validates, is reused, and no rediscovery is forced by that change

#### Scenario: Version unchanged across both slices

- GIVEN `schemaVersion` before `overlay-reaping` and after each of its slices
- WHEN the values are compared
- THEN all three are `2` and no transition occurred within that change

#### Scenario: Schema diff reviewed

- GIVEN the diff of `assets/manifest.schema.json` across `overlay-reaping`'s two slices
- WHEN it is read
- THEN it changes the `overlayCommand` description only, adding no property and removing none

#### Scenario: Label contract versioned separately

- GIVEN the label contract version is raised
- WHEN the manifest is loaded afterwards
- THEN `schemaVersion` is unaffected and no cache is discarded

#### Scenario: Read as a standing rule

- GIVEN a reader asking whether a later change may raise `schemaVersion`
- WHEN this requirement is read
- THEN it scopes itself to `overlay-reaping` and names the requirement that owns the current version

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
