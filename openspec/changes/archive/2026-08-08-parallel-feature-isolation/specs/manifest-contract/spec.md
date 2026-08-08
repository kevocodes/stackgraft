# manifest-contract

Modified capability. The requirements under `## MODIFIED Requirements` replace the same-named requirements introduced by `portable-multi-stack` (`../../../archive/2026-08-01-portable-multi-stack/specs/manifest-contract/spec.md`) and `overlay-reaping` (`../../../archive/2026-08-01-overlay-reaping/specs/manifest-contract/spec.md`); each is restated in full, carrying its still-valid clauses forward. Per-store determinacy (D3), scoped `migrates` (D3), the provider reference and the name family (D5, D8), the breaking bump and its absent migration path (D3 accepted cost, Rollback): `../../proposal.md`.

The write discipline requirements introduced by `overlay-reaping` — the lock, its bounds, its failure reporting, and the read paths — are unchanged by this delta and are deliberately not restated. `The ownership record owes no schema change` is restated for one reason only: its version clause was written for `overlay-reaping`'s slices and would otherwise read as a standing prohibition against the bump this change performs.

## ADDED Requirements

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

## MODIFIED Requirements

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

## RENAMED Requirements

### Requirement: Schema v2 field contract → Schema v3 field contract

(Reason: this change raises `schemaVersion` from `2` to `3`, breaking, and replaces the field contract that version described.)
(Migration: none for stored values — by design. Every field is re-derivable, so an unrecognised `schemaVersion` discards the cache and rediscovers, which is the whole migration. References to "schema v2" in `references/`, `docs/` and `CHANGELOG.md` must point at v3.)

### Requirement: Schema v3 field contract

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
