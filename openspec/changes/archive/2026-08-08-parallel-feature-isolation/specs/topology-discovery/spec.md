# topology-discovery

Modified capability. Extends the requirements introduced by `portable-multi-stack` (`../../../archive/2026-08-01-portable-multi-stack/specs/topology-discovery/spec.md`) and `overlay-reaping` (`../../../archive/2026-08-01-overlay-reaping/specs/topology-discovery/spec.md`); nothing already stated there is replaced. Per-store classification (D3), the pair-set derivation (C4), provider eligibility (D5, D7), identity-knob discovery (D4): `../../proposal.md`.

Discovery supplies the gate's inputs and never produces a verdict. The verdict procedure is `../shared-state-safety/spec.md`; the two mechanisms are `../isolation-providers/spec.md` and `../coordination-identity/spec.md`.

**A credential channel for `verifyRequest` is deliberately absent from this delta.** It is the one correction in the proposal that is not about isolation, it is separable, and Q7 places it outside `2.0`. Nothing here MAY be read as authorising a credential source, a token placeholder, or a secret written to a cache file.

## ADDED Requirements

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
