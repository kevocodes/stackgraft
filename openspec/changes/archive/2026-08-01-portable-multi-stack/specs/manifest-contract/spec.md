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
