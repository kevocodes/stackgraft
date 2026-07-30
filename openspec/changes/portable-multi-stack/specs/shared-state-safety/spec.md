# shared-state-safety

New capability. Scope and decisions: `../../proposal.md`. Evidence, verdict table, and substrate matrix: `../../exploration.md` Q1 — normative there, not restated here.

## ADDED Requirements

### Requirement: Dependency pair classification

For every pair `(overlay service S, dependency D)` where D resolves to the base stack, the skill MUST evaluate W (S mutates D), X (attaching to D is competitive or exclusive) and N (an isolation mechanism exists inside D's already-running instance), and MUST emit exactly one verdict — REUSE, ISOLATE, or REFUSE — per the verdict table in `../../exploration.md` Q1. No overlay MAY launch while any of its pairs lacks a verdict.
(Verify: file review of `references/shared-state.md`; cross-file that every field it names exists in `assets/manifest.schema.json`.)

#### Scenario: Read-only, non-competitive dependency

- GIVEN S declares no `writes` and no `competesOn` entry naming D
- WHEN the gate classifies `(S, D)`
- THEN the verdict is REUSE and the overlay is wired to the base stack's D

#### Scenario: Writer with an available mechanism

- GIVEN S writes D and `backingStores[D].isolation.mechanism` is not `none`
- WHEN the gate classifies `(S, D)`
- THEN the verdict is ISOLATE and the overlay is wired to a new namespace inside the running D, never to the base namespace

#### Scenario: Writer with no mechanism

- GIVEN S writes D and `backingStores[D].isolation.mechanism` is `none`
- WHEN the gate classifies `(S, D)`
- THEN the verdict is REFUSE and the output names S, D, and the missing mechanism

### Requirement: Unknown classifies as unsafe

Any pair whose W, X, or N cannot be determined MUST be treated as `W=yes, X=yes, N=no` and MUST resolve to REFUSE. A missing field, an undetermined discovery result, and an unread classification reference are all "unknown". The SKILL.md body MUST carry the refusal direction self-sufficiently: a run that never loads `references/shared-state.md` MUST refuse, not proceed.
(Verify: file review — the refusal rule is readable in the SKILL.md body without following any link.)

#### Scenario: Discovery cannot determine whether the service writes

- GIVEN discovery resolved D but could not establish whether S mutates it
- WHEN the gate classifies `(S, D)`
- THEN the verdict is REFUSE
- AND the output states which of W/X/N was undetermined

#### Scenario: Classification reference never loaded

- GIVEN the run has not loaded `references/shared-state.md`
- WHEN any overlay service has a dependency resolving to the base stack
- THEN every such pair is unclassified and the run refuses to launch
- AND that refusal is derivable from the SKILL.md body alone

#### Scenario: Manifest claim contradicted by the worktree

- GIVEN the manifest records `writes: []` for S
- WHEN an escalation trigger fires for S
- THEN the recorded claim is overridden and the verdict is ISOLATE or REFUSE

### Requirement: Competitive attachment is unsafe without writing

A pair MUST be refused whenever X holds, even when W is false. `competesOn` MUST be evaluated independently of `writes`. Plain attach MUST be refused until a distinct consumer identity is supplied, after which the pair is re-classified — never approved by the substitution alone.

#### Scenario: Read-only consumer joins the base coordination group

- GIVEN S only reads, and `competesOn` names D with an identity key
- WHEN the gate classifies `(S, D)`
- THEN plain attach is REFUSED and a distinct consumer identity is required

#### Scenario: Distinct identity supplied

- GIVEN a distinct identity is recorded for `(S, D)`
- WHEN the pair is re-classified with X false
- THEN the verdict follows W and N
- AND the output states that the overlay now receives deliveries the base stack also receives

### Requirement: Escalation triggers override recorded claims

The triggers listed in `../../exploration.md` Q1 (migration in the diff or in a launch command; scheduler, cron, beat or singleton-worker entrypoint; externally-visible side effects) MUST force ISOLATE-or-REFUSE regardless of what the manifest records.

#### Scenario: Diff touches a migrations directory

- GIVEN the worktree diff changes a migrations path for S
- WHEN the gate classifies S against a base-stack store
- THEN the verdict is ISOLATE if a mechanism exists, otherwise REFUSE

#### Scenario: Scheduler entrypoint

- GIVEN S's entrypoint is a scheduler, cron, or leader-elected worker
- WHEN the gate classifies S
- THEN S is REFUSED as a named refuse-case and MUST NOT be launched as an overlay

### Requirement: Isolation reuses the server, never the namespace

On an ISOLATE verdict the skill MUST apply `backingStores[].isolation` inside the running instance. It MUST NOT assume any substrate client binary is present; the isolation command MUST be a template discovered from the repository. When no such template is discoverable, `mechanism` MUST be recorded as `none`, which resolves to REFUSE or to a dedicated instance.

#### Scenario: Isolation command discovered in the repository

- GIVEN the repository exposes a command that reaches the running store
- WHEN the ISOLATE verdict is applied
- THEN that discovered template is used and the overlay's peer configuration points at the isolated namespace

#### Scenario: No isolation command discoverable

- GIVEN no template can be discovered for D
- WHEN the manifest entry is written
- THEN `mechanism` is `none`
- AND the pair resolves to REFUSE or to a dedicated instance, never to base-namespace reuse

#### Scenario: Named refuse-case

- GIVEN the pair matches a case with no safe answer in `../../exploration.md` Q1
- WHEN the gate classifies it
- THEN it is reported as a refusal with the case named, and no workaround is attempted

### Requirement: Per-service acceptance, invalidated by fingerprint drift

The only bypass MUST be an `acceptedRisks` entry keyed by `(service, store)`. Each entry MUST record the accepting timestamp and the service's source fingerprint at acceptance time, and MUST be kept latest-only per key. An entry MUST be treated as absent once that service's source fingerprint drifts. No global bypass MAY exist.
(Verify: schema validation — `acceptedRisks` requires `service`, `store`, `at`, and `fingerprint`.)

#### Scenario: Explicit acceptance recorded

- GIVEN the gate refused `(S, D)` and the user explicitly accepts that risk
- WHEN the overlay launches
- THEN an `acceptedRisks` entry for `(S, D)` records the timestamp and S's current fingerprint

#### Scenario: Stale acceptance after source drift

- GIVEN an `acceptedRisks` entry for `(S, D)` whose recorded fingerprint differs from S's current fingerprint
- WHEN the gate evaluates `(S, D)`
- THEN the entry is ignored, the original verdict applies, and the overlay is refused until the user accepts again
- AND a new acceptance replaces the stale entry rather than appending to it

#### Scenario: Acceptance does not generalize

- GIVEN an accepted entry for `(catalog-api, postgres)`
- WHEN the gate evaluates `(catalog-api, kafka)` or `(billing-service, postgres)`
- THEN no acceptance applies and each pair is classified on its own
