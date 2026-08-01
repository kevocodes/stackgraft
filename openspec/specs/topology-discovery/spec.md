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

### Requirement: A container-kind `overlayCommand` MUST expose a label anchor

The label set is inserted by the skill at launch, at an anchor inside the discovered command, and is never stored in a discovered command, so every container-kind `overlayCommand` MUST expose that anchor: a `run` or `create` token following a recognised launcher token, ahead of the service operand. Insertion MUST add the label elements at the anchor and change nothing else. Anchor matching MUST NOT match a token inside a quoted string — otherwise `echo "docker run x" | sh` would be "labelled" inside a string literal and the container would still launch bare. `assets/manifest.schema.json` MUST state this constraint in the `overlayCommand` description; it MUST NOT be expressed as a new field, MUST NOT add a placeholder to the closed set, and MUST NOT change `schemaVersion`. Discovery-generated commands MUST comply, which the preferred `docker compose config`-derived form already does, so the exposure is confined to hand-written entries. An entry carrying a recognised launcher with no anchor token after it, and an `up`-shaped template — `up` takes no label flag, so it exposes no anchor — MUST fail loudly at launch, naming the service and the entry. A pipe, wrapper, or redirect *after* the anchor is NOT grounds for refusal: insertion lands ahead of it and the labels reach the launcher. Templates that hand the command to an interpreter stay refused by the deny-list in `references/shared-state.md`, where that rule already lives, and are not restated here. The overlay MUST NOT be launched unlabeled instead: an unlabeled container is unreapable and invisible to every later run, which is the exact failure this change exists to close. Host-kind entries are unaffected — they carry no labels and register in the sidecar instead.
(Verify: schema review of the `overlayCommand` description; file review of the launch step; an anchorless hand-written command, an `up`-shaped template, and a quoted-launcher template each exercised at launch; a piped template with an intact anchor exercised at launch and its container inspected for labels; `schemaVersion` compared before and after.)

#### Scenario: Discovery-generated command

- GIVEN an `overlayCommand` derived from `docker compose config --no-interpolate`
- WHEN the overlay launches
- THEN the label arguments are inserted at the anchor and the container starts carrying all five labels

#### Scenario: Hand-written command with no anchor

- GIVEN a container-kind `overlayCommand` whose recognised launcher token is followed by no `run` or `create` token
- WHEN the overlay is launched
- THEN the launch fails, names the service and the offending entry, and no container is left running unlabeled
- AND a whole-stack `up` form is refused the same way, because `up` takes no label flag

#### Scenario: Piped template whose anchor is intact

- GIVEN an `overlayCommand` that pipes or wraps the launcher — `cd X && docker compose run … | tee log` — with its `run` token still following a recognised launcher
- WHEN the overlay launches
- THEN the labels are inserted at that anchor, ahead of the pipe, and the container starts carrying all five labels
- AND the launch is not refused for piping

#### Scenario: Launcher text inside a quoted string

- GIVEN an `overlayCommand` whose only `docker run` text sits inside a quoted string, as in `echo "docker run x" | sh`
- WHEN an anchor is sought
- THEN no anchor is found, nothing is inserted into the string literal, and the launch is refused rather than run bare

#### Scenario: Constraint is discoverable where the command is written

- GIVEN a user writing an `overlayCommand` by hand
- WHEN the schema's description for that field is read
- THEN the anchor constraint is stated there
- AND no new property was added and `schemaVersion` is still `2`

#### Scenario: Host-kind entry

- GIVEN a `kind` whose overlay runs directly on the host
- WHEN it is launched
- THEN no anchor constraint applies to its command, and ownership is recorded in the sidecar instead of in labels

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
