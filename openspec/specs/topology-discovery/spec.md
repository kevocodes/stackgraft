# topology-discovery

Capability introduced by `portable-multi-stack` and substantially extended by `parallel-feature-isolation`. Per-store classification (D3), the pair-set derivation (C4), provider eligibility (D5, D7), identity-knob discovery (D4): `../../proposal.md`.

Discovery supplies the gate's inputs and never produces a verdict. The verdict procedure is `../shared-state-safety/spec.md`; the two mechanisms are `../isolation-providers/spec.md` and `../coordination-identity/spec.md`.

**A credential channel for `verifyRequest` is deliberately absent from this delta.** It is the one correction in the proposal that is not about isolation, it is separable, and Q7 places it outside `2.0`. Nothing here MAY be read as authorising a credential source, a token placeholder, or a secret written to a cache file.

## ADDED Requirements (from parallel-feature-isolation)

### Requirement: Discovery writes one determinacy record per `(unit, store)`

In the same pass that populates `backingStores`, discovery MUST classify **every runnable unit against every entry in that map**, not merely the stores the unit declares, and MUST write one record per pair carrying W, X, how it looked, and that unit's `serviceFingerprint`.

A record MUST be written only for a pair the pass actually examined. Where the pass could not determine a pair, it MUST **omit** that record rather than write a guess, and an omitted record MUST NOT be written as, or later read as, checked-and-none. Where the pass ran degraded — the ecosystem resolver unavailable and a static parse standing in for it — the records it writes MUST carry the degraded confidence, so the gate declines to count them without discovery having to lie about what it did. Discovery MUST NOT write a record for a pair it inferred from another pair of the same unit.
(Verify: file review of the classification step in `references/discovery.md`; a repository exercised with one store determinable and one not, and the resulting manifest inspected; a run with the resolver down, and its records inspected for the degraded confidence.)

#### Scenario: One store determined, one not

- GIVEN a pass that establishes a unit's behaviour against postgres and cannot establish it against redis
- WHEN the records are written
- THEN one record exists for postgres and none for redis

#### Scenario: Undeclared store still classified

- GIVEN a unit whose `dependsOn` names one of four `backingStores` entries
- WHEN the classification pass runs
- THEN it attempts all four pairs, and the three undeclared stores are classified or omitted on their own evidence

#### Scenario: Degraded pass

- GIVEN the ecosystem resolver is unavailable and a static parse stands in for it
- WHEN records are written
- THEN they carry the degraded confidence and the gate does not count them

#### Scenario: No inference across stores

- GIVEN a unit determined to write postgres
- WHEN records are written for its other stores
- THEN none is derived from the postgres record

### Requirement: The pair set's derivation is recorded and reproducible

The run MUST report the counts its pair set is derived from: the runnable units it selected, the entries in `backingStores`, and the resulting pair count. A unit with `runnable: false` MUST contribute no pairs, which is why a repository of 43 services and four stores yields 156 pairs from 39 runnable units rather than 172 — a figure that is only a usable regression baseline if the derivation behind it is stated rather than inferred.

Two runs against the same repository at the same commit, with the same manifest state, MUST report the same three counts. A run that narrows the pair set (`../shared-state-safety/spec.md`) MUST report the narrowed count **beside** the derived one, never in place of it, so a narrowing cannot be mistaken for a smaller repository.
(Verify: the 43-service repository run and its three counts compared against the recorded baseline; the same run repeated and the counts compared; a run with a narrowing applied, inspected for both counts.)

#### Scenario: Counts reported

- GIVEN a repository of 43 units of which 39 are runnable, and four `backingStores` entries
- WHEN discovery completes
- THEN the run reports 39, 4, and 156

#### Scenario: Non-runnable unit contributes nothing

- GIVEN a `runnable: false` entry
- WHEN the pair set is derived
- THEN it yields no pairs and is excluded from the unit count

#### Scenario: Narrowed count reported beside the derived one

- GIVEN a change classification that removes 100 of 156 pairs
- WHEN the run reports
- THEN both 156 and 56 appear, labelled, and the derived count is not overwritten

#### Scenario: Reproducible

- GIVEN two runs against the same commit with the same manifest state
- WHEN their counts are compared
- THEN all three counts match

### Requirement: Discovery records each store's provider eligibility

For every entry in `backingStores`, discovery MUST record whether the store's state is **local to this host and reachable by a shipped provider**, or **managed, remote, or host-native**. The determination MUST be derived from the discovered address and the store's discovered lifecycle — where its state actually lives and who operates it — and MUST NOT be assumed from the store's name, image, or engine.

Where eligibility cannot be determined, discovery MUST record it as undetermined, which the gate reads as remote and refuses (`../isolation-providers/spec.md`). The recorded reason MUST survive into the refusal message, so the developer is told which fact was missing rather than that isolation was unavailable.
(Verify: file review of the eligibility step; a compose-declared store with a local volume, a store whose address resolves off-host, and a store with no resolvable address each exercised and their records inspected; a refusal message compared against the recorded reason.)

#### Scenario: Local store

- GIVEN a store declared in the base stack whose state lives in a local volume
- WHEN discovery records it
- THEN it is eligible for the shipped provider

#### Scenario: Remote store

- GIVEN a store whose address resolves to a host other than this one
- WHEN discovery records it
- THEN it is recorded as remote with the resolved address as the reason

#### Scenario: Eligibility undetermined

- GIVEN a store whose address or lifecycle cannot be established
- WHEN discovery records it
- THEN it is recorded as undetermined, and the gate treats it as remote

#### Scenario: Reason reaches the refusal

- GIVEN a pair refused for provider ineligibility
- WHEN the refusal is read
- THEN it names the store and the recorded reason, not a generic unavailability

### Requirement: Discovery records the identity knob and the route that delivers it

For every `competesOn` entry, discovery MUST record three things: the substrate's **identity knob** for that coordination primitive; the **value the base stack attaches under**, read from the base stack's own configuration rather than assumed; and the **environment variable the service itself takes that identity from**, read from the service's own configuration. The variable MUST NOT be invented, guessed from a convention, or defaulted from another service.

Discovery MUST also record whether the launch method has a **route** that sets that variable in the overlay's environment — which for a container-run overlay is not the launching shell's. Where no route exists, or where the base stack's current value cannot be read, discovery MUST record that fact, which leaves X undetermined and refuses before anything launches (`../coordination-identity/spec.md`).
(Verify: file review of the identity-discovery step; a broker-backed repository exercised and the recorded knob, base value, variable and route inspected; a service whose configuration names no such variable, exercised; a launch method with no delivery route, exercised.)

#### Scenario: Knob, value, variable and route all discovered

- GIVEN a service configured with a consumer-group key and a base stack whose value is readable
- WHEN discovery records the entry
- THEN the knob, the base value, the service's own variable, and the delivery route are all recorded

#### Scenario: Variable not present in the service's configuration

- GIVEN a service whose configuration names no variable for the identity key
- WHEN discovery records the entry
- THEN no variable is invented, the absence is recorded, and X is undetermined

#### Scenario: Base value unreadable

- GIVEN a base stack whose current identity value cannot be read
- WHEN discovery records the entry
- THEN the unreadability is recorded and distinctness cannot be proven

#### Scenario: No delivery route

- GIVEN a launch method that carries no route for setting that variable in the overlay's environment
- WHEN discovery records the entry
- THEN the absence of a route is recorded, and the pair refuses before anything launches

## ADDED Requirements (from portable-multi-stack)

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
