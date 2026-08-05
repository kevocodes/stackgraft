# orphan-reclamation

Modified capability. Extends the requirements introduced by `overlay-reaping` (`../../../archive/2026-08-01-overlay-reaping/specs/orphan-reclamation/spec.md`); nothing already stated there is replaced. The reopened volume non-goal (T3) and the copy as a reaping obligation (T2): `../../proposal.md`.

Liveness, the report pass, the scoped query, the allowlist, the flag discipline and the ownership proof are specified there and consumed here unchanged. Store copies are created by `../isolation-providers/spec.md` and carry the label set specified in `../overlay-ownership/spec.md`.

## ADDED Requirements

### Requirement: A store copy this skill created is a reclamation candidate; nothing else is

`overlay-reaping` excluded volumes from reclamation because *"volumes may hold data the user wants"*. That is correct for a volume this skill did not create and wrong for one it did, and the label contract is what tells them apart. **The non-goal is reopened for exactly the labelled subset and no wider.**

A store copy carrying this repository's **complete** ownership label set MUST be a reclamation candidate under the same liveness rule an overlay is judged by: its worktree path compared against `git worktree list --porcelain`, a listed path meaning live and untouchable, an absent path making it a candidate and nothing more, and every other state — the command failing, an entry marked prunable — classifying as unknown, reported, and never a mutation target.

A volume or instance carrying **no** stackgraft label set, or one whose label-contract version this run does not recognise, MUST NOT be removed, emptied, or renamed under any flag, MUST NOT be enumerated by an unscoped query, and MUST be reported for manual cleanup only where the scoped query already made it visible. Candidacy MUST stay positive and closed: nothing but this skill's own provisioning writes that label set, so no flag, flag combination, or code path reaches a volume of the user's unless a human hand-labelled it with this repository's complete set.

Removal MUST require the removal flag in addition to the mutation flag, exactly as removing a container does — a copy is the more expensive thing to have destroyed by accident, not the less. The report MUST distinguish copies found from copy state that could not be read: a runtime that cannot be queried MUST be reported as unknown and MUST NOT be rendered as zero copies.
(Verify: file review of `references/reaping.md` — candidacy is an allowlist and the copy path carries the same flag discipline; a copy of a deleted worktree exercised through all four flag combinations; an unlabelled volume holding data confirmed to survive both flags; the container runtime stopped and the report inspected; grep of every volume query in shipped scripts for the `stackgraft.repo` filter.)

#### Scenario: Copy of a deleted worktree

- GIVEN a labelled store copy whose worktree path no longer appears in `git worktree list --porcelain`
- WHEN classification runs
- THEN the copy is reported as an orphan candidate, named with its store and the worktree that no longer exists

#### Scenario: Copy of a live worktree

- GIVEN a labelled store copy whose worktree is still listed
- WHEN classification runs with both mutation flags passed
- THEN it is reported as live and nothing is removed

#### Scenario: Removal requires the second flag

- GIVEN an orphaned labelled copy
- WHEN only the mutation flag is passed
- THEN the copy is reported and still exists
- AND with the removal flag added, it is removed

#### Scenario: Unlabelled volume holding the user's data

- GIVEN a volume this skill did not create
- WHEN a reap runs with both mutation flags
- THEN it is never a target, is never emptied, and exists unchanged afterwards

#### Scenario: Unrecognised label-contract version

- GIVEN a copy whose `stackgraft.labels` value this run does not recognise
- WHEN classification runs
- THEN it is treated exactly as legacy: reported, never acted on

#### Scenario: Copy state unreadable

- GIVEN the container runtime is not running
- WHEN the report is produced
- THEN copy state is reported as unknown with the reason, and the report does not state zero copies
