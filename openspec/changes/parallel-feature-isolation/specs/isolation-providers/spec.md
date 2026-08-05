# isolation-providers

New capability. Provider contract (D5), seeded copies (D6), live copy and its residual (Q2), verification before isolation (Q1), copy lifetime and visible ageing (Q3), managed and remote refusals (D7), free-space evidence (Q6), measurement discipline (T5), the copy as a data surface (T2): `../../proposal.md`.

The gate that decides a pair needs a copy is `../shared-state-safety/spec.md`; a coordination hazard never reaches this capability (`../coordination-identity/spec.md`). Ownership labels are specified in `../overlay-ownership/spec.md` and consumed here, never re-derived; reclaiming a copy is `../orphan-reclamation/spec.md`.

Scope: local development, one host, one already-running base stack, N worktrees of one repository. Every requirement below is bounded by it.

## ADDED Requirements

### Requirement: The provider contract is three operations and names no substrate

A provider MUST expose exactly three operations. **`provision`** produces an instance seeded with a copy of the named store's state. **`address`** states how the overlay reaches that instance — host, port, and the environment entries that carry them. **`destroy`** removes the instance and the copy. Nothing else MAY be added to the contract to make one runtime work.

The contract MUST vary by **runtime** and MUST NOT vary by **substrate**. No operation, parameter, return value, or conformance obligation MAY name PostgreSQL, Redis, MongoDB, Kafka, an object store, or any other engine: cloning state is the same operation for all of them, and a contract that enumerates them is the finite prose table this change removes, re-entered by another door. A store engine released after 2.0 MUST be provisionable with no edit to the contract and no edit to the shipped provider's interface.

Exactly one provider ships at 2.0: **Docker**, which is where a local base stack already runs. Kubernetes, host-native and managed runtimes MUST be declared as unbuilt rather than implied. The contract MUST be shown to describe a second runtime on paper — each of the three operations with a named answer for Kubernetes and for host-native — before the shipped provider is implemented, because a contract that cannot describe a second runtime has failed the premise it exists for.
(Verify: file review of `references/isolation-providers.md` — grep the contract section for engine names and find none; the paper description of a second runtime present with all three operations answered; a store engine the shipped files never enumerate exercised through all three operations.)

#### Scenario: Contract carries no engine name

- GIVEN the provider contract as shipped
- WHEN its operations, parameters, and obligations are read
- THEN no store engine is named anywhere in them

#### Scenario: Unenumerated store engine

- GIVEN a base stack running a store engine no shipped file mentions, with local state
- WHEN a writing pair against it resolves to ISOLATE
- THEN `provision`, `address` and `destroy` all complete with no change to the contract or the provider interface

#### Scenario: Second runtime described

- GIVEN the shipped provider documentation
- WHEN the contract is read
- THEN Kubernetes and host-native each have a named answer for `provision`, `address` and `destroy`, and both are marked unbuilt

#### Scenario: Provider runtime unavailable

- GIVEN the container runtime the shipped provider needs is not running
- WHEN a pair requires a seeded copy
- THEN the pair is undetermined and REFUSES, the reason names the unavailable runtime, and no partial isolation is attempted

### Requirement: A copy is not isolated until it has started and answered a real query

A provisioned instance MUST NOT be treated as isolation because it started. The run MUST issue a real query against the copy — one that reads state the copy is supposed to carry — and MUST record its result before the pair counts as isolated. **A start is not proof.** A process that is running, an accepted TCP connection, a health endpoint returning 200, a zero exit status, and a log line announcing readiness MUST NOT stand in for the query, individually or together.

Where the query fails, cannot be issued, or cannot be derived at all, the copy MUST be destroyed and the pair MUST REFUSE. The overlay MUST NOT be launched against an unverified copy and MUST NOT be wired to the base store instead — an unverified copy the overlay then writes into is a false green with the loss already committed, and a silent fall back to the base store is the contamination the gate exists to prevent. The absence of a derivable verification query is a refusal, not a waiver.
(Verify: file review that the verification step is stated as blocking; a copy provisioned from a deliberately truncated volume and confirmed destroyed with the pair refused; a store for which no verification query is derivable, confirmed to refuse; the overlay's peer configuration inspected after a failed verification.)

#### Scenario: Copy starts and answers

- GIVEN a provisioned copy of a store the pair writes
- WHEN the verification query runs and returns the state the copy was seeded with
- THEN the pair counts as isolated, the result is recorded, and the overlay is wired to the copy

#### Scenario: Copy starts and cannot answer

- GIVEN a provisioned copy whose engine starts but fails the verification query
- WHEN the run evaluates it
- THEN the copy is destroyed, the pair REFUSES, and the overlay is not launched

#### Scenario: No verification query derivable

- GIVEN a store for which the run can derive no query that reads seeded state
- WHEN the copy is evaluated
- THEN it is treated exactly as a failed verification: destroyed, pair refuses, nothing launched

#### Scenario: Port accepts before the engine is ready

- GIVEN the copy's port accepts a connection while the engine is still recovering
- WHEN the run evaluates readiness
- THEN the accepted connection does not count and the pair stays unisolated until the query answers

#### Scenario: No fallback to the base store

- GIVEN verification failed for `(U, D)`
- WHEN the run finishes
- THEN U is not launched wired to the base stack's D, and the output names the refusal rather than reporting a launched overlay

### Requirement: Copies are taken live, and the residual is stated rather than covered

Provisioning MUST NOT stop, pause, quiesce, freeze, or otherwise disturb the base stack's store. Not disturbing the base stack is the property the whole tool exists for, and surrendering it to obtain a cleaner copy trades the premise for the detail. The copy is therefore **crash-consistent**: a file-level copy of a live engine is what a power cut looks like, and engines are built to recover from that.

The shipped files MUST state that residual in the same place they state the copy is taken live: an engine with an fsync-ordering dependency may not recover from it. The residual MUST NOT be described as covered, mitigated, handled, or unlikely, and no shipped file MAY assert that a live copy is safe for every engine. Verification is what catches the cases where crash consistency was not enough, which is why verification is mandatory rather than advisory.
(Verify: file review that the live-copy statement and the residual statement sit together, and that no shipped file claims the residual is covered; the base store's container inspected before and after a copy for restart count, uptime, and dropped connections.)

#### Scenario: Base store undisturbed

- GIVEN a copy is taken of a running store with live connections
- WHEN the copy completes
- THEN the base store was not stopped or paused, its uptime is continuous, and its existing connections were not dropped

#### Scenario: Crash-consistent copy that does not recover

- GIVEN an engine whose copied state does not survive crash-consistent recovery
- WHEN the copy is started and verified
- THEN the verification fails, the copy is destroyed, and the pair refuses

#### Scenario: Residual stated, not covered

- GIVEN the shipped files describing the copy
- WHEN they are read
- THEN they state that the copy is crash-consistent and that an fsync-ordering-dependent engine may not survive it
- AND no file claims the residual is covered, mitigated, or unlikely

### Requirement: A copy's lifetime is the worktree, and its age is reported every run

A copy MUST be provisioned once per `(worktree, store)` and reused on every later launch from that worktree, so the first start pays the measured cost and every later one pays none. A copy MUST NOT be re-provisioned on a later run except on an **explicit** refresh request; no elapsed time, no size, and no staleness heuristic MAY trigger a refresh on its own, and none MAY refuse a launch on age alone. A refresh MUST destroy the old copy and MUST verify the new one before it is used, exactly as a first provision does.

**Every run that uses a copy MUST report that copy's age**, whether or not anything else about the copy is reported and whether or not the run considers it stale. Data ages, that is the accepted cost of reuse, and ageing has to be visible rather than discovered: a developer must be able to read how old the state is without asking for it.
(Verify: file review of the output contract — the age is unconditional; two consecutive launches from one worktree with the runtime's instance identity compared; a refresh exercised end to end; a launch that touches nothing else about the copy inspected for the age line.)

#### Scenario: First launch from a worktree

- GIVEN a worktree with no copy of store D
- WHEN a writing pair against D resolves to ISOLATE
- THEN a copy is provisioned, verified, and reported with its size and elapsed time

#### Scenario: Later launch from the same worktree

- GIVEN a verified copy of D already exists for this worktree
- WHEN the overlay is launched again
- THEN the same copy is reused, nothing is re-provisioned, and the run reports the copy's age

#### Scenario: Age reported on an otherwise quiet run

- GIVEN a run that provisions nothing, refreshes nothing, and destroys nothing
- WHEN it uses an existing copy
- THEN the output still states that copy's age

#### Scenario: Explicit refresh

- GIVEN the user explicitly requests a refresh of D's copy
- WHEN the run executes it
- THEN the old copy is destroyed, a new one is provisioned and verified, and the age resets

#### Scenario: Age does not decide anything by itself

- GIVEN a copy older than any threshold a shipped file mentions
- WHEN the overlay is launched with no refresh requested
- THEN the copy is reused, the age is reported, and nothing is refreshed or refused on that basis

### Requirement: Managed, remote and host-native stores refuse by name

A store the shipped provider cannot provision locally MUST refuse, naming the store, the reason, and the fact that no isolation was attempted. **Managed and remote stores** — a store whose address resolves off this host, or whose lifecycle belongs to a provider this skill does not operate — MUST be refused: there is no local state to copy, and isolating inside the remote instance would need credentials and substrate knowledge the skill has neither of. The skill MUST NOT request such credentials and MUST NOT attempt in-place isolation against them. **Host-native stores** MUST be refused as a runtime for which this change builds no provider, stated as unbuilt rather than as impossible.

A store whose locality cannot be determined MUST be treated as remote and refused: an unknown is not a permission. No partial isolation, no approximation, and no fall back to the base store MAY be attempted for any of these, and the refusal MUST NOT cascade — the unit's other pairs are still classified on their own.
(Verify: file review of the refusal cases; a compose stack pointed at a managed endpoint exercised end to end; a store with an undeterminable address exercised; a unit with one refused store and one provisionable store exercised.)

#### Scenario: Managed store

- GIVEN a writing pair whose store is a managed endpoint outside this host
- WHEN the gate resolves it
- THEN the pair refuses with the store and the reason named, no copy is attempted, and no credential is requested

#### Scenario: Host-native store

- GIVEN a writing pair whose store runs directly on the host rather than in the container runtime
- WHEN the gate resolves it
- THEN the pair refuses and the output states that no provider for that runtime ships in this version

#### Scenario: Locality undetermined

- GIVEN discovery could not establish whether the store's state is local
- WHEN the gate resolves the pair
- THEN the store is treated as remote and refuses

#### Scenario: A refusal does not cascade

- GIVEN a unit paired with one remote store and one local store, both written
- WHEN the gate classifies both
- THEN the remote pair refuses by name and the local pair still resolves to a verified seeded copy

### Requirement: Free space is proven on the filesystem the copy will occupy, before the copy

Before provisioning, the run MUST establish the free space of the filesystem the copy will **actually** occupy. On a virtualised container runtime that is not the filesystem the working directory reports, and the runtime's data disk is a sparse image that grows into the host — so the binding constraint is the host's free space, and a check made against the wrong filesystem is a check that reports comfort it cannot deliver.

A copy that would not fit MUST be refused **before** it starts rather than failed during it, and a refusal MUST leave no partial copy behind. Where free space cannot be established, the copy MUST be refused: an unknown is not a permission. The run MUST state which filesystem it measured, so the number is checkable rather than trusted.
(Verify: file review of the space check — it names the runtime's data root, not the working directory; a copy attempted against a filled filesystem; a run whose space probe fails; the filesystem the run reports compared against the one the runtime writes to.)

#### Scenario: Space sufficient

- GIVEN the measured filesystem has room for the copy
- WHEN provisioning starts
- THEN the copy proceeds and the run states which filesystem it measured

#### Scenario: Space insufficient

- GIVEN the measured filesystem does not have room
- WHEN provisioning is considered
- THEN the copy is refused before any bytes are written, the pair refuses, and no partial copy is left behind

#### Scenario: Free space undetermined

- GIVEN the space probe cannot answer for the filesystem the copy would land on
- WHEN provisioning is considered
- THEN the copy is refused and the reason names what could not be established

#### Scenario: The measured filesystem is the runtime's

- GIVEN a virtualised container runtime whose data root is not on the working directory's filesystem
- WHEN the space check runs
- THEN it interrogates the runtime's data root and the host disk backing it, not the working directory's filesystem

### Requirement: The run reports what it copied and predicts nothing

For every copy, the run MUST report the store, the bytes copied, and the elapsed time **measured on this run**. The run MUST NOT predict, estimate, extrapolate, or promise a duration — not from a byte count, not from another store's observed rate, and not from a previous run of the same store. The measured spread on one host, one SSD, one run — 244 MB/s for a store of few large files against 72 MB/s for a store of many small ones — is evidence that rate tracks file profile rather than size, so any figure derived from a size is derived from the wrong variable. No shipped file MAY state an expected duration, a typical duration, or a worst case as a guarantee; a measurement MAY be cited as evidence that the approach is viable, labelled as one sample.
(Verify: file review — no shipped file states an expected duration; a two-store run inspected for one report per store; the output before a copy inspected for any predicted figure.)

#### Scenario: Copy reported

- GIVEN a copy completes
- WHEN the run reports
- THEN it names the store, the bytes copied, and the elapsed time it measured

#### Scenario: No prediction before a copy

- GIVEN a copy is about to start
- WHEN the run announces it
- THEN it states no expected or estimated duration

#### Scenario: Two stores in one run

- GIVEN two stores are copied in one run
- WHEN the run reports
- THEN each is reported separately and neither figure is derived from the other

#### Scenario: Shipped files reviewed

- GIVEN every shipped file
- WHEN they are searched for a stated duration
- THEN any measurement present is labelled as one sample and none is stated as an expectation

### Requirement: Every copy is owned, labelled, named in the output, and removable

A copy is a duplicate of whatever data the developer's base stack holds, sitting on the same disk under a name this skill chose. That is a surface the shipped files MUST describe rather than leave implicit. Every copy MUST carry the same ownership label set an overlay carries, scoped to this repository's `hash8`, so that it is distinguishable from a volume this skill did not create. Every copy MUST be named in the run's output together with the exact command that removes it, and the output MUST state that a copy of the base stack's data now exists on this host.

The naming MUST also happen when the copy was **not** removed — the overlay is still up, or a destroy failed — because the only thing that will remove it otherwise is a person who was told it exists. No unlabelled volume MAY ever be a target of anything this capability does (`../orphan-reclamation/spec.md`).
(Verify: file review of the output contract and of `SECURITY.md`; a copy inspected for the full label set with this repository's `hash8`; a run left with the overlay up and its output inspected for the copy and its removal command.)

#### Scenario: Copy carries the ownership labels

- GIVEN a provisioned copy
- WHEN its labels are inspected
- THEN it carries the complete stackgraft label set with this repository's `hash8`

#### Scenario: Output names the copy

- GIVEN a run that provisioned a copy
- WHEN the output is read
- THEN it names the copy, states that it holds a duplicate of the base stack's data, and gives the exact removal command

#### Scenario: Teardown did not run

- GIVEN the overlay is still up, or a destroy failed
- WHEN the run reports
- THEN the copy is still named with its removal command rather than assumed to be someone else's problem

#### Scenario: Unlabelled volume

- GIVEN a volume this skill did not create
- WHEN any operation of this capability runs
- THEN it is never provisioned over, never destroyed, and never named as a copy
