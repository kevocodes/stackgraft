# shared-state-safety

Modified capability. The requirements under `## MODIFIED Requirements` replace the same-named requirements introduced by `portable-multi-stack` (`../../../archive/2026-08-01-portable-multi-stack/specs/shared-state-safety/spec.md`); each is restated in full, carrying its still-valid clauses forward. Scope (D1), change-scoped gating (D2 and T1), per-store determinacy (D3), two hazards and two mechanisms (D4), seeded copies (D5, D6), the generated lifecycle target (Q5): `../../proposal.md`.

The data hazard's mechanism is specified in `../isolation-providers/spec.md` and the coordination hazard's in `../coordination-identity/spec.md`. This capability decides which mechanism a pair needs and consumes both; it never re-derives either. `Per-service acceptance, invalidated by fingerprint drift` is unchanged by this delta and is deliberately not restated.

Scope is a term of every requirement below: local development, one host, one already-running base stack, N worktrees of one repository in parallel. A pair outside that scope is not a harder pair — it is not in scope, and it refuses by name.

## ADDED Requirements

### Requirement: Change-scoped pair selection is one-directional and evidence-bound

The gate's subject MUST be the pairs the change can reach. The worktree diff that already selects which units to overlay MUST also select which pairs enter the gate, and a unit that reaches no store MUST contribute no pairs at all. The narrowing MUST be one-directional: it MAY only **remove** a pair whose store a per-`(unit, store)` determinacy record states the changed code does not reach, it MUST NOT add confidence to any pair that survives, and no surviving pair's W or X MAY be read as better evidenced because the diff was small. The relieving record MUST expire on the same `serviceFingerprint` as every other classification, so relief granted for code that has since changed is withdrawn without anyone acting.

**This MUST NOT be read as repealing the rule that `dependsOn` cannot narrow a pair set, and the shipped files MUST say so in those words.** `dependsOn` is a declaration: saying less would gate less, and the laziest manifest would be the least refused. A per-store determinacy record is evidence: it names what was looked at, records how, and expires. What changes is only where the claim is written, not whether a claim is needed. Absence of a record is undetermined, which refuses; absence is never relief. The run MUST report every pair the narrowing removed and the record that removed it, so a narrowing is visible rather than inferred.
(Verify: file review that the narrowing rule and its evidence obligation are stated together in `references/shared-state.md`, and that the `dependsOn` prohibition is restated beside it; a frontend-only diff run end to end against a multi-store repository; a run whose relieving record has drifted.)

#### Scenario: Change touches no store

- GIVEN the diff changes only paths belonging to a unit's frontend, and that unit's determinacy records state the changed code reaches no store
- WHEN the gate builds its subject
- THEN zero pairs are gated, zero copies are provisioned, and the overlay launches
- AND the run names the pairs it removed and the records that removed them

#### Scenario: Declaration still narrows nothing

- GIVEN a unit records `dependsOn: []`
- WHEN the gate builds its subject
- THEN every entry in `backingStores` still yields a pair for that unit
- AND each of those pairs is undetermined until its own record answers W and X

#### Scenario: Narrowing without a record

- GIVEN the diff touches no path that obviously reaches store D, and no determinacy record exists for `(U, D)`
- WHEN the gate classifies `(U, D)`
- THEN the pair is undetermined and REFUSES
- AND the small diff is not read as evidence of anything

#### Scenario: Relief expires with the code it was granted for

- GIVEN `(U, D)` was removed from the subject on a record whose `serviceFingerprint` no longer matches U's source
- WHEN the gate runs again
- THEN the record is treated as absent, the pair re-enters the subject, and it refuses until reclassified

#### Scenario: Narrowing does not strengthen a survivor

- GIVEN `(U, postgres)` survives the narrowing on a record of `inferred` confidence
- WHEN the gate classifies it
- THEN the verdict is the same as it would have been with no narrowing at all, and the degraded record still does not count

### Requirement: The two hazards resolve by two mechanisms, and neither substitutes for the other

W and X are separate hazards with separate mechanisms, and the mapping MUST be stated as a rule rather than left to the reader. **W — the overlay writes state the base stack reads — MUST resolve to its own copy of that state**, provisioned per `../isolation-providers/spec.md`. **X — the overlay attaches to a coordination primitive and takes work away from the base stack — MUST resolve to a distinct identity**, per `../coordination-identity/spec.md`.

Crossing them is forbidden in both directions. A pair carrying X and not W MUST NOT cause a store copy to be provisioned: cloning a broker to avoid a consumer-group collision spends the expensive mechanism on a hazard a name ends, and a requirement that permits it invites it. A pair carrying W MUST NOT be resolved by a name: renaming a namespace the overlay then writes into does not stop the write from landing where the base stack reads, unless the state under that name is the overlay's own. A pair carrying both MUST receive both, and satisfying one MUST NOT be recorded as satisfying the other.
(Verify: file review of the mechanism mapping in `references/shared-state.md`; an X-only pair run end to end with the container runtime's volume list compared before and after; a W-and-X pair run end to end and both mechanisms confirmed applied.)

#### Scenario: Coordination hazard alone

- GIVEN `(U, kafka)` carries X and not W
- WHEN the pair is resolved
- THEN a distinct identity is applied, no provider operation is invoked, and no volume or instance is created
- AND the run states that the pair was resolved by identity

#### Scenario: Data hazard alone

- GIVEN `(U, postgres)` carries W and not X
- WHEN the pair is resolved
- THEN a seeded copy is provisioned and the overlay is wired to it
- AND no identity substitution is recorded as having resolved anything

#### Scenario: Both hazards on one pair

- GIVEN `(U, kafka)` carries both W and X
- WHEN the pair is resolved
- THEN a distinct identity resolves X and a seeded copy resolves W
- AND neither is recorded as having resolved the other, so a pair with only one applied is still undetermined

### Requirement: A missing lifecycle target is offered, never invented, and its teardown is inert until its create has succeeded

Where the in-instance optimisation is unavailable **only** because the repository defines no lifecycle target, the run MAY offer to write one. The offer MUST obey three constraints, because a create is harmless and a drop aimed at the wrong database is not. The store name in the generated target MUST come from the discovered `backingStores` key and MUST NOT be invented, inferred from a service name, or defaulted. The generated content MUST be shown in full before anything is written. It MUST be written only on explicit approval, into the repository, so it is versioned, reviewable in a pull request, and thereafter the repository's own — read on later runs as a legitimate `declared` target rather than as something synthesised at run time.

The teardown half MUST be generated together with the create half, since half a lifecycle is still not a mechanism, and it MUST NOT be executed until at least one run has observed that target's create succeed. The offer MUST NOT be a precondition of anything: a declined offer, an unapproved offer, and a repository that cannot be written to all leave the default seeded copy, which asks the repository for nothing. No refusal MAY be issued on the ground that the repository defines no target while the default path is available.
(Verify: file review of the generation rule; a repository with a discoverable store and no target exercised through offer, decline, and approval; the generated file inspected for the discovered store name; a run whose create fails, with the teardown's execution log checked.)

#### Scenario: Offer shown and declined

- GIVEN a writing pair whose store has no discoverable lifecycle target
- WHEN the run offers to generate one and the user declines
- THEN nothing is written to the repository, the seeded copy resolves the pair, and no refusal is issued for the missing target

#### Scenario: Offer approved

- GIVEN the generated create and teardown are shown and approved
- WHEN the run completes
- THEN both are written into the repository, and a later run reads that target as a `declared` repository-defined target

#### Scenario: Store name cannot be taken from discovery

- GIVEN discovery recorded no `backingStores` key for the store in question
- WHEN generation is considered
- THEN no target is generated and no offer is made, because the name would have to be invented

#### Scenario: Teardown stays inert until the create has succeeded

- GIVEN a newly approved target whose create has never run
- WHEN the run tears down
- THEN the generated teardown is not executed, and the run names the namespace and the command a human would run

#### Scenario: Create fails on first use

- GIVEN the approved create runs and fails
- WHEN teardown is considered
- THEN the teardown is still not executed, the pair falls back to the default seeded copy or refuses, and the failure is reported with the command that produced it

## MODIFIED Requirements

### Requirement: Dependency pair classification

For every pair `(overlay unit U, dependency D)` where D resolves to the base stack **and the change can reach D**, the skill MUST evaluate W (U mutates D), X (attaching to D is competitive or exclusive) and N (a data-isolation mechanism is available for this pair), and MUST emit exactly one verdict — REUSE, ISOLATE, or REFUSE. The pair set MUST be derived as every runnable unit selected for overlay against every entry in `backingStores`, plus any name in that unit's own `dependsOn` that resolves to a store; `dependsOn` MAY only add pairs, and only a per-store determinacy record MAY remove one. N is satisfied by two mechanisms and MUST be evaluated in this order: a store `../isolation-providers/spec.md` can provision a seeded copy of, which is the default and asks the repository for nothing; or a complete in-instance lifecycle the repository declares, which is the zero-disk optimisation. A store neither mechanism can serve is N=no. Scope bounds the whole requirement: a pair whose store is managed, remote, or host-native is out of scope and refuses by name, never by silence. No overlay MAY launch while any of its pairs lacks a verdict.
(Verify: file review of `references/shared-state.md`; cross-file that every field it names exists in `assets/manifest.schema.json`; the 43-service repository re-run and its pair count compared against the recorded baseline.)

#### Scenario: Read-only, non-competitive dependency

- GIVEN U's determinacy record for D states W=no and no `competesOn` entry names D
- WHEN the gate classifies `(U, D)`
- THEN the verdict is REUSE and the overlay is wired to the base stack's D

#### Scenario: Writer against a provisionable store

- GIVEN U writes D and D is a local store the shipped provider can provision
- WHEN the gate classifies `(U, D)`
- THEN the verdict is ISOLATE and the overlay is wired to its own seeded copy of D, never to the base stack's D

#### Scenario: Writer against a store no mechanism serves

- GIVEN U writes D, the provider cannot provision D, and the repository declares no complete in-instance lifecycle for it
- WHEN the gate classifies `(U, D)`
- THEN the verdict is REFUSE and the output names U, D, and which mechanism was unavailable and why

#### Scenario: Pair set is not read off the declaration

- GIVEN `backingStores` carries four entries and U's `dependsOn` names one of them
- WHEN the pair set is built for U
- THEN four pairs exist for U, minus only those a determinacy record removed
- AND a store U forgot to declare is still paired and still gated

### Requirement: Unknown classifies as unsafe

Any pair whose W or X cannot be determined MUST be treated as `W=yes, X=yes, N=no` and MUST resolve to REFUSE. A missing per-`(unit, store)` determinacy record, a record whose `serviceFingerprint` has drifted, a record whose confidence is anything other than `declared`, an undetermined discovery result, an unresolvable store locality, and an unread classification reference are all "unknown".

**Determinacy MUST be read at the granularity it was recorded.** A record for one store MUST NOT be read as evidence about another, and the absence of a record for one store MUST NOT make that unit's other stores undetermined. A positive claim about one store is a claim about that store alone: the shipped files MUST NOT restore any field whose presence asserts checked-and-none for every store at once, because that is what made a partially-informed pass record all-or-nothing and over-refuse.

**The SKILL.md body MUST carry the refusal direction self-sufficiently and MUST carry nothing else about the gate.** It MAY state that a verdict is required and where the procedure lives. It MUST NOT state any condition under which an overlay is permitted, any verdict value other than a refusal, any hazard-to-mechanism mapping, or any fragment of the procedure. A run that never loads `references/shared-state.md` MUST refuse, not proceed.
(Verify: file review — the refusal direction is readable in the SKILL.md body without following any link, and no permitting condition appears anywhere in it; a manifest carrying a record for one store and none for another, run end to end.)

#### Scenario: Discovery cannot determine whether the unit writes

- GIVEN discovery resolved D but could not establish whether U mutates it, and wrote no record for `(U, D)`
- WHEN the gate classifies `(U, D)`
- THEN the verdict is REFUSE
- AND the output states which of W or X was undetermined, for that pair by name

#### Scenario: Partial knowledge is expressible

- GIVEN discovery determined `(U, postgres)` and could not determine `(U, redis)`
- WHEN the gate classifies U's pairs
- THEN `(U, postgres)` is classified on its own record and `(U, redis)` refuses
- AND the undetermined store does not force a refusal on the determined one

#### Scenario: Classification reference never loaded

- GIVEN the run has not loaded `references/shared-state.md`
- WHEN any overlay unit has a dependency resolving to the base stack
- THEN every such pair is unclassified and the run refuses to launch
- AND that refusal is derivable from the SKILL.md body alone

#### Scenario: Body carries no permission

- GIVEN the SKILL.md body after this change
- WHEN it is read end to end
- THEN it states that a verdict is required and where the procedure lives, and states no condition under which an overlay is permitted

#### Scenario: Manifest claim contradicted by the worktree

- GIVEN a determinacy record states `(U, D)` is W=no
- WHEN an escalation trigger fires for U
- THEN the recorded claim is overridden and the verdict is ISOLATE or REFUSE

### Requirement: Competitive attachment is unsafe without writing

A pair MUST be refused whenever X holds, even when W is false. `competesOn` MUST be evaluated independently of the determinacy record's W. Plain attach MUST be refused until a distinct consumer identity is supplied and proven per `../coordination-identity/spec.md`, after which the pair is re-classified — never approved by the substitution alone. Resolving X MUST NOT provision, request, or reserve a store copy, and a pair carrying X and not W MUST leave the container runtime's volume and instance inventory unchanged.
(Verify: file review that the X procedure lives in `../coordination-identity/spec.md` and that `references/shared-state.md` links rather than restates it; an X-only pair exercised with the runtime inventory diffed before and after.)

#### Scenario: Read-only consumer joins the base coordination group

- GIVEN U only reads, and `competesOn` names D with an identity key
- WHEN the gate classifies `(U, D)`
- THEN plain attach is REFUSED and a distinct consumer identity is required

#### Scenario: Distinct identity supplied

- GIVEN a distinct identity is recorded and proven for `(U, D)`
- WHEN the pair is re-classified with X false
- THEN the verdict follows W and N
- AND the output states that the overlay now receives deliveries the base stack also receives

#### Scenario: No copy is made for a coordination hazard

- GIVEN `(U, D)` carries X and not W
- WHEN the pair is resolved by identity
- THEN no provider operation runs and the runtime's volume and instance inventory is unchanged

### Requirement: Escalation triggers override recorded claims

The triggers listed in `references/shared-state.md` — a migration in the diff or in a launch command; a scheduler, cron, beat or singleton-worker entrypoint; externally-visible side effects; a unit recorded as migrating on startup — MUST force ISOLATE-or-REFUSE regardless of what the manifest records **and regardless of any narrowing the change classification performed**. They read the launched process's behaviour rather than the diff, which is what makes them the named re-widening.

**Change classification MUST NOT relieve a write the unit's own launch performs.** A change confined to a unit's frontend does not make that unit stateless: overlaying a service whose entrypoint creates schema, applies migrations, or seeds on startup executes that write whatever the diff touched. The narrowing rule MUST state that limit rather than promise the relief, and a unit recorded as migrating MUST keep W=yes for the stores its entrypoint is pointed at even when the diff reaches none of them. Where the pointing is unknown, every store of that unit is undetermined, which refuses.
(Verify: file review that the limit is stated inside the narrowing rule and not only beside it; a frontend-only diff exercised against a unit whose entrypoint migrates.)

#### Scenario: Diff touches a migrations directory

- GIVEN the worktree diff changes a migrations path for U
- WHEN the gate classifies U against a base-stack store
- THEN the verdict is ISOLATE if a mechanism exists, otherwise REFUSE

#### Scenario: Scheduler entrypoint

- GIVEN U's entrypoint is a scheduler, cron, or leader-elected worker
- WHEN the gate classifies U
- THEN U is REFUSED as a named refuse-case and MUST NOT be launched as an overlay

#### Scenario: Frontend-only diff against a unit that migrates at startup

- GIVEN the diff touches only U's frontend paths and U is recorded as applying migrations from its own entrypoint against postgres
- WHEN the gate builds its subject
- THEN `(U, postgres)` is not relieved by the narrowing, W stays yes, and the pair resolves to ISOLATE or REFUSE

#### Scenario: Escalation outranks a narrowing

- GIVEN a determinacy record would remove `(U, D)` from the subject and an escalation trigger fires for U
- WHEN the two are combined
- THEN the escalation wins, the pair is gated, and the run states which trigger re-widened it

## RENAMED Requirements

### Requirement: Isolation reuses the server, never the namespace → ISOLATE means a seeded copy, and in-instance isolation is the optimisation

(Reason: the old name asserts the mechanism the change replaces. ISOLATE now means the overlay gets its own copy of the state by default; reusing the running server is one of two mechanisms rather than the definition.)
(Migration: references to the old name in `references/`, `docs/SHARED-STATE.md` and `docs/HOW-IT-WORKS.md` must point at the new name; the MODIFIED block below is the requirement's new text.)

### Requirement: ISOLATE means a seeded copy, and in-instance isolation is the optimisation

On an ISOLATE verdict the skill MUST give the overlay state it can write without the base stack reading it. **The default MUST be a seeded copy** provisioned through `../isolation-providers/spec.md`: it carries the data the base stack has, it asks the repository for nothing, and it is what makes an overlay testable against loaded data. An empty namespace MUST NOT be presented as isolation for a unit whose behaviour under test depends on existing data; the shipped files MUST state that an empty namespace is a different thing from a copy.

**In-instance isolation MUST remain available as the zero-disk optimisation**, and every rule that governs it MUST survive unchanged: the command is discovered from the repository and never embedded in the skill, no substrate client binary is assumed present, the placeholder set stays closed, the deny-list applies to the template's own grammar, the substituted command is checked structurally and executed as an argument vector with no shell fallback, a program that re-parses its argument is rejected, the destructive-verb class is judged by effect rather than by spelling, and both halves of the lifecycle are approved together before the first run. Where no complete lifecycle pair is discoverable the optimisation MUST record `mechanism: "none"` for that store, which selects the default copy rather than a refusal — a refusal is reached only when no mechanism at all can serve the pair. The named cases with no safe answer MUST still refuse, unchanged in number and in wording, and neither mechanism MAY be attempted against them.
(Verify: file review of `references/shared-state.md` and `../isolation-providers/spec.md` — the in-instance rules are present and **the In-instance isolation column of the per-substrate table is gone while the table and its catch column remain**; a writing pair exercised with and without a declared lifecycle target; the cases-with-no-safe-answer list diffed against `1.1.0`.)

**Correction, recorded rather than applied silently (`design.md`, *Locked decisions this design cannot deliver as written*, item 2).** This clause previously read *the substrate namespace table is gone*, which taken literally deletes the table four of the six cases with no safe answer rest on: Redis pub/sub, Kafka's shared group, RabbitMQ's round-robin and the leader-elected worker are all evidenced by that table's **catch** column, and `../coordination-identity/spec.md` needs its knob rows. What this change deletes is the **In-instance isolation column**, not the table — a reader who deletes the table deletes the evidence for the refuse-cases, which is T1's hazard wearing different clothes.

#### Scenario: Default path, nothing declared

- GIVEN U writes D and the repository declares no isolation command for D
- WHEN the ISOLATE verdict is applied
- THEN a seeded copy of D is provisioned and the overlay's peer configuration points at it
- AND no repository seeding target is hunted for and no refusal is issued for the absence

#### Scenario: Optimisation taken

- GIVEN the repository declares a complete create-and-teardown lifecycle for D, approved and `declared`
- WHEN the ISOLATE verdict is applied
- THEN that discovered template is used, the overlay points at the isolated namespace, and no copy is provisioned

#### Scenario: Half a lifecycle discovered

- GIVEN a create command is discoverable for D and no teardown is
- WHEN the manifest entry is written
- THEN the in-instance `mechanism` is `none`
- AND the pair resolves through the default seeded copy, never through base-namespace reuse

#### Scenario: Named refuse-case

- GIVEN the pair matches one of the cases with no safe answer
- WHEN the gate classifies it
- THEN it is reported as a refusal with the case named, no copy is provisioned, no namespace is created, and no workaround is attempted
