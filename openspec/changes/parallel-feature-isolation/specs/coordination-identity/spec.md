# coordination-identity

New capability. The coordination hazard's mechanism (D4), the name family (D8 as amended by Q4), and the deletion of the integer allocator (Q4): `../../proposal.md`. Split out of `shared-state-safety` so the two hazards have two homes.

The gate that decides a pair carries X is `../shared-state-safety/spec.md`; the data hazard's mechanism is `../isolation-providers/spec.md`. Discovery of the knob, the base stack's current value, and the delivery route is `../topology-discovery/spec.md`; this capability consumes those records and never re-derives them.

Scope: local development, one host, one already-running base stack, N worktrees of one repository.

## ADDED Requirements

### Requirement: A coordination hazard resolves by a distinct identity, never by a copy

X is the overlay attaching to a coordination primitive and taking work away from the base stack: a consumer group, a queue subscriber, an advisory or leader lock, a replication slot, a scheduler singleton. Its damage lands on the base stack's **behaviour**, inside a service nobody modified. The answer MUST be a **distinct identity** — a name — and MUST NOT be a copy of the store. Provisioning a broker to avoid a consumer-group collision spends gigabytes and minutes on a hazard one string ends; no requirement, reference, or script MAY offer a copy as a remedy for X alone, because a mechanism that is permitted will be reached for.

A pair carrying X and not W MUST leave the container runtime's volume and instance inventory unchanged. A pair carrying X and W MUST receive both mechanisms, and the copy MUST NOT be recorded as having resolved X: a private copy of a broker's storage does not stop the overlay from joining the base stack's group on the base stack's broker, and an overlay attached to its own copy is not exercising the coordination the base stack runs.
(Verify: file review of `references/coordination-identity.md` — no copy or provider operation appears as a remedy for X; an X-only pair run end to end with the runtime inventory diffed; a W-and-X pair inspected for both mechanisms recorded separately.)

#### Scenario: Coordination hazard alone

- GIVEN `(U, kafka)` carries X and not W
- WHEN the pair is resolved
- THEN a distinct identity is applied and no volume, instance, or provider operation is created or invoked

#### Scenario: Both hazards

- GIVEN `(U, kafka)` carries X and W
- WHEN the pair is resolved
- THEN a distinct identity resolves X and a seeded copy resolves W, recorded separately
- AND the copy alone leaves X undetermined, which refuses

#### Scenario: No identity available

- GIVEN `(U, D)` carries X and no distinct identity can be proven
- WHEN the pair is resolved
- THEN it REFUSES, and no copy is provisioned as a substitute

### Requirement: The substrate table answers one question — what is this substrate's identity knob

The per-substrate table MUST answer only **"what is this substrate's identity knob"**: `group.id`, a durable name, a queue name, a subject prefix, an advisory-lock key, a replication-slot name. It MUST NOT answer "how do you create a namespace inside this substrate" — that open-ended question is what turned a finite prose table into the gate for an unbounded set of stores, and it belongs to `../isolation-providers/spec.md`, which answers it once per runtime rather than once per engine.

A substrate absent from the table is undetermined, which refuses. **A substrate whose competition no name ends MUST refuse and MUST NOT be given a name anyway**: a second consumer on one RabbitMQ queue still round-robins, and a lock, a replication slot, or a scheduler singleton admits one holder however it is spelled. The cases with no safe answer MUST survive this change identical in number and in wording, and none of them MAY be reclassified as solvable by an identity.
(Verify: file review of the knob table — every row names a knob and no row names a namespace-creation procedure; the cases-with-no-safe-answer list diffed against `1.1.0`; a shared-queue pair and an absent-substrate pair each exercised.)

#### Scenario: Substrate with a knob

- GIVEN a pair against a broker whose table row names its consumer-group key
- WHEN the identity is chosen
- THEN the knob named in that row is what the overlay attaches under

#### Scenario: Substrate whose competition no name ends

- GIVEN a pair whose overlay would consume from a queue the base stack consumes from
- WHEN the identity is considered
- THEN the pair REFUSES, and no distinct name is applied as though it helped

#### Scenario: Substrate absent from the table

- GIVEN a coordination primitive the table does not cover
- WHEN the identity is considered
- THEN X is undetermined and the pair REFUSES

#### Scenario: Refuse-cases preserved

- GIVEN the cases with no safe answer before and after this change
- WHEN the two lists are compared
- THEN they are identical, and none has been moved into the knob table

### Requirement: An identity counts only when it is distinct, delivered, and substrate-confirmed

Recording an identity MUST NOT re-classify a pair. X is no only when three things are proven, and any one unproven leaves X **undetermined**, which refuses — so the loop terminates on evidence rather than on repetition.

**(a) Distinct.** The value MUST differ from the value the base stack attaches under, read from the base stack's own configuration rather than assumed. A value that cannot be compared because the base stack's value could not be read is not distinct.

**(b) Delivered.** The value MUST reach the launched process. The environment variable that carries it MUST be the service's own variable for that identity key, discovered from the service's configuration and never invented, and the launch MUST set it in the **overlay's** environment — which is not the launching shell's for a container-run overlay. The value MUST cross by a route the launch already has; where no available route carries it, the pair MUST refuse **before** anything launches rather than after. A value recorded and not applied leaves X undetermined. A store-level environment map MUST NOT serve as the channel: it belongs to the store and is shared by every service paired with it, so one overlay's identity would be handed to all of them.

**(c) Substrate-confirmed.** The table above MUST confirm that a distinct identity ends the competition on that substrate. Where it does not, no name helps.

The proven value and its channel MUST both be recorded, or the re-classification does not persist and the pair is back at REFUSE on the next run. The run MUST state what the distinct identity changes: an overlay with its own consumer group receives every message the base stack receives, so any externally visible side effect it performs is now duplicated, which the escalation triggers refuse on their own terms.
(Verify: file review of the three-part proof; a pair exercised with each of the three failing in turn; the launched container's environment inspected for the delivered variable; a run repeated to confirm the recorded proof persists.)

#### Scenario: All three proven

- GIVEN a value distinct from the base stack's, an env channel the launch can use, and a substrate the table confirms
- WHEN the pair is re-classified
- THEN X is no and the verdict follows W
- AND the run states that the overlay now receives deliveries the base stack also receives

#### Scenario: Value equals the base stack's

- GIVEN the recorded identity matches the value read from the base stack's configuration
- WHEN the pair is re-classified
- THEN X is undetermined and the pair REFUSES

#### Scenario: Base stack's value unreadable

- GIVEN the base stack's current identity value cannot be read
- WHEN distinctness is evaluated
- THEN it is unproven, X is undetermined, and the pair REFUSES

#### Scenario: No delivery route

- GIVEN a value and a variable name are recorded but the launch method carries no route that sets it in the overlay's environment
- WHEN the pair is evaluated
- THEN it REFUSES before anything launches, and the reason names the missing route

#### Scenario: Recorded but not applied

- GIVEN the launch completed without setting the recorded variable in the overlay's environment
- WHEN the pair is evaluated
- THEN X is undetermined and the pair REFUSES

#### Scenario: Proof persists across runs

- GIVEN a pair whose identity value and channel were recorded and applied
- WHEN the next run classifies the same pair
- THEN the recorded proof is re-checked and, still valid, X is no without asking again

### Requirement: Namespace names are derived, never allocated

No name this skill uses for an identity or for a copy MAY be **allocated** from a bounded, host-global pool. An allocation is state the derivation does not need: it can be exhausted, it must be released, and a pool nothing owns is a pool two worktrees can draw the same value from and never detect. Sixteen host-global logical-database indexes, shared across every repository on the machine, are exactly that shape: two worktrees pick the same index and collide silently, and the collision is undetectable by construction.

The integer member of the name family MUST NOT exist. An index-addressed store MUST be given a seeded copy like every other store — the measured cost of copying such a store's state was effectively zero — rather than a slot inside the running instance. No shipped file MAY describe an allocation, an exhaustion case, or a release obligation for a namespace name, and no placeholder MAY yield an allocated value.
(Verify: portability grep of shipped files for an allocator, a slot table, an exhaustion case, or a release step, finding none; a writing pair against an index-addressed store exercised end to end and confirmed to receive a copy; two worktrees run concurrently against the same store and their derived names compared.)

#### Scenario: Index-addressed store gets a copy

- GIVEN a writing pair against a store whose in-instance isolation would be a numeric index
- WHEN the pair resolves to ISOLATE
- THEN a seeded copy is provisioned and verified, and no index is selected

#### Scenario: No allocator ships

- GIVEN every shipped file
- WHEN they are searched for an allocation, an exhaustion case, or a release obligation for a namespace name
- THEN there are none

#### Scenario: Two worktrees, one store

- GIVEN two worktrees of one repository resolve a pair against the same store at the same time
- WHEN their names are compared
- THEN the names differ, and neither run consulted or wrote any shared pool

### Requirement: The name family derives every form from one branch hash

A single generated shape cannot name every substrate's namespace: the SQL-identifier form's underscores are forbidden in DNS labels and object-store bucket names, so every bucket the skill could name was rejected by the substrate. `{{isolationName}}` MUST therefore be replaced by a **family** whose members all derive from the same branch hash, so they remain one logical namespace:

- an **SQL-identifier form**, `sg_<slug>_<hash8>`, generated by the existing rule unchanged — lowercase, non-alphanumeric runs collapsed to `_`, slug truncated, `hash8` taken over the full untruncated branch name;
- a **DNS- and object-store-safe label form**, `sg-<slug>-<hash8>`, carrying no underscore, no uppercase, no leading or trailing hyphen, and at most 63 characters.

Each consumer MUST request the form its substrate accepts, and a form MUST NOT be substituted for another. Every member MUST be a pure derivation of the branch name — no member MAY be allocated, and none MAY be read from the repository. A substrate that accepts neither form is undetermined, which refuses, rather than being given the nearest form and allowed to fail at the substrate.
(Verify: file review of the generation rule; a bucket created under the label form against a real object store; the SQL form compared against `1.1.0`'s output for the same branch; two branches whose slugs truncate identically compared in both forms; a label form measured for length and scanned for underscores.)

#### Scenario: Object-store bucket named (F1 regression)

- GIVEN a writing pair against an object store on a branch whose slug contains several words
- WHEN a namespace name is requested for it
- THEN the label form is used, the substrate accepts it, and the name carries no underscore

#### Scenario: SQL form unchanged

- GIVEN a branch name and the same skill inputs used against `1.1.0`
- WHEN the SQL-identifier form is generated
- THEN it is byte-identical to what `1.1.0` generated

#### Scenario: Truncated slugs stay distinct

- GIVEN two branch names whose slugs truncate to the same 28 characters
- WHEN both forms are generated for each
- THEN the two branches differ in both forms, because `hash8` is taken over the full branch name

#### Scenario: Label form bounds

- GIVEN a branch name long enough to overflow the label form
- WHEN the label form is generated
- THEN it is at most 63 characters, is entirely lowercase and hyphen-separated, and neither begins nor ends with a hyphen

#### Scenario: Substrate accepts neither form

- GIVEN a substrate whose namespace grammar accepts neither member of the family
- WHEN a name is requested
- THEN the pair is undetermined and REFUSES, and no nearest-fit name is offered to the substrate
