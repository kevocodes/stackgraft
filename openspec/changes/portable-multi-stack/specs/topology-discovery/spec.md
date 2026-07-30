# topology-discovery

New capability. Scope and decisions: `../../proposal.md`. Source tiering, resolver table, and the `covers` ambiguity: `../../exploration.md` Q2.

## ADDED Requirements

### Requirement: Discovery answers two separate questions

`references/discovery.md` MUST separate (a) path → runnable unit from (b) unit → launch, port, and peers, and MUST record for each supported source which question it answers. A build-graph source MUST be used for (a) only and MUST NOT contribute a port, a peer URL, or a launch command.
(Verify: file review of `references/discovery.md` — both sections exist and every listed source carries its question.)

#### Scenario: Build-graph source present

- GIVEN the repository contains only workspace/build-graph files that map paths to packages
- WHEN discovery runs
- THEN those files populate `paths` fan-out
- AND no `basePort`, `peerEnv`, or `overlayCommand` value is derived from them

#### Scenario: Declarative source answers both

- GIVEN a compose-family source
- WHEN discovery runs
- THEN it populates units, published host ports, dependency edges, and peer env vars

### Requirement: Resolver preference with a defined fallback

Discovery MUST prefer the ecosystem's own resolver when that resolver is read-only, fast, and non-interpolating, leading with `docker compose config --no-interpolate --format json` for compose repositories. Resolvers that execute repository code MUST NOT be invoked. When the preferred resolver is unavailable, discovery MUST fall back to a static parse, and when the static parse cannot answer, MUST ask the user once and cache the answer. Resolver unavailability MUST NOT hard-fail the run.

#### Scenario: Resolver available

- GIVEN the compose resolver runs successfully
- WHEN discovery extracts unit → launch data
- THEN merged, non-interpolated output is the source of ports and peers, and no hand-parse of the file chain is performed

#### Scenario: Resolver unavailable

- GIVEN the container runtime is not running
- WHEN discovery needs unit → launch data
- THEN discovery falls back to a static parse and continues
- AND if the static parse cannot yield a port, discovery asks the user once and caches that answer

#### Scenario: Code-executing resolver

- GIVEN the repository uses a topology source whose resolver would execute repository code
- WHEN discovery runs
- THEN that resolver is not invoked and the source contributes at most path → unit data

### Requirement: `covers` granularity and slice refresh

`sources[].covers` entries are dot-delimited manifest key paths. The refresh set is the union of the `covers` of all drifted sources, expanded to every key beneath each entry. Where two sources cover the same key at different granularities, the finer source is authoritative for that key's value and the coarser source is authoritative only for keys no finer source covers. When a coarse source drifts, every finer source covering a re-derived key MUST be re-fingerprinted in the same pass. When only a finer source drifts, only its keys re-derive and the coarse source's fingerprint and other keys stay untouched.
(Verify: file review — the rule is stated in `references/discovery.md`; cross-file — `covers` values in `assets/manifest.example.json` exercise both granularities.)

#### Scenario: Fine source drifts alone

- GIVEN a source covering `services.frontend` drifted and the source covering `services` did not
- WHEN the slice refresh runs
- THEN only `services.frontend` is re-derived
- AND the other `services.*` entries and the coarse source's fingerprint are unchanged

#### Scenario: Coarse source drifts

- GIVEN a source covering `services` drifted while a source covering `services.frontend` did not
- WHEN the slice refresh runs
- THEN every `services.*` key is re-derived
- AND the `services.frontend` source is re-fingerprinted in the same pass so it does not claim a value it did not produce

#### Scenario: Both cover one key with conflicting values

- GIVEN both sources are authoritative for `services.frontend` and yield different values
- WHEN the refresh writes the entry
- THEN the finer source's value wins

### Requirement: Unenumerable fingerprint sets revalidate always

A source whose content can pull in files not enumerable from the manifest MUST be recorded with `revalidate: always`. Fingerprint equality MUST NOT be accepted as proof of freshness for such a source; it MUST be treated as drifted on every run.

#### Scenario: Source that imports arbitrary files

- GIVEN a source marked `revalidate: always` whose fingerprint matches the stored value
- WHEN the freshness check runs
- THEN the source is still treated as drifted and its `covers` set is re-derived

#### Scenario: Source file disappeared

- GIVEN a recorded `sources[].path` no longer exists
- WHEN the freshness check runs
- THEN the source is dropped and every key in its `covers` set is re-derived from scratch

### Requirement: Non-runnable units fan out through one direction of truth

An entry with `runnable: false` MUST NOT be launched and MUST NOT receive a port allocation; it exists only so that a change under its `paths` fans out to the services listed in its `consumers`. Whether a shared tree reaches a service MUST be expressed in exactly one place, so a service whose build context excludes that tree MUST NOT appear in its `consumers`.
(Verify: schema validation — no `static` kind and no duplicated shared-reach field; cross-file — `assets/manifest.example.json` shows a `runnable: false` entry with no port.)

#### Scenario: Change lands in a shared tree

- GIVEN the diff touches paths belonging to a `runnable: false` entry
- WHEN changed paths are mapped to services
- THEN every service in that entry's `consumers` is selected for overlay
- AND no port is allocated and no launch is attempted for the shared entry itself

#### Scenario: Service excluded from the shared build context

- GIVEN a service whose build context does not include the shared tree
- WHEN discovery writes the shared entry
- THEN that service is absent from `consumers` and no second field contradicts it

#### Scenario: Changed paths map to nothing

- GIVEN no changed path matches any entry's `paths`
- WHEN mapping completes
- THEN no overlay is launched and the run reports that explicitly
