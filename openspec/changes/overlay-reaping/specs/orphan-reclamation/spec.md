# orphan-reclamation

New capability. Report-only default (D4), implicit report pass (D5), `hash8` scoping (D6), stop-then-remove (D8): `../../proposal.md`. Legacy blind spot: proposal T1. Report-path port benefit: proposal T2 and T3. Worktree-liveness evidence: proposal Q2. Stop-versus-remove reasoning: proposal Q1.

Ownership proof, the label set, and the sidecar are specified in `../overlay-ownership/spec.md`; this capability consumes them and never re-derives them.

## ADDED Requirements

### Requirement: Liveness is decided against the worktree list, and unknown is never orphaned

An overlay's worktree path comes from its `stackgraft.worktree` label or its sidecar entry, and MUST be compared against `git worktree list --porcelain`. A path still listed means the worktree is live and the overlay MUST NOT be acted on under any flag; neither archiving nor sleeping a workspace removes the directory, so both leave the worktree listed. A path absent from the list makes the overlay an orphan *candidate*, nothing more. Every other state — the command failing, the repository being unreadable, an entry the porcelain output marks prunable — MUST classify as unknown, MUST be reported, and MUST NOT be a mutation target: prunable is neither proof the worktree is live nor proof it is gone, and the permissive reading of an unproven state is the one this project rejects. Comparison MUST be on the whole recorded path value, never on a word-split of it.
(Verify: file review of the liveness procedure in `references/reaping.md`; scenarios run against a real `git worktree list --porcelain`.)

#### Scenario: Worktree still listed

- GIVEN a labelled overlay whose worktree path appears in `git worktree list --porcelain`
- WHEN classification runs with both mutation flags passed
- THEN the overlay is reported as live and nothing is stopped, removed, or signalled

#### Scenario: Worktree archived or slept

- GIVEN the editor has archived or put the workspace to sleep, leaving the directory and the worktree registration in place
- WHEN classification runs
- THEN the worktree is still listed, so the overlay is live and is not a candidate

#### Scenario: Worktree deleted

- GIVEN the worktree was removed and its path no longer appears in the porcelain list
- WHEN classification runs
- THEN the overlay is an orphan candidate and is reported with its service, port, and the worktree path that no longer exists

#### Scenario: Worktree list unavailable

- GIVEN `git worktree list --porcelain` fails or cannot be run
- WHEN classification runs
- THEN no overlay is classified as an orphan, the report states that liveness could not be established, and no mutation occurs under any flag

#### Scenario: Prunable entry

- GIVEN the porcelain output lists the worktree and marks it prunable
- WHEN classification runs
- THEN the overlay is classified unknown, is reported with that reason, and is not a mutation target

### Requirement: The report pass runs on every invocation and never mutates

Every invocation MUST perform the report pass: one container query scoped by `hash8` and one `git worktree list --porcelain`, the same auto-healing shape the fingerprint check already has. Under every flag and every flag combination, including both mutation flags, the report pass MUST stop no container, remove nothing, signal no process, and write no file — not the manifest, not the sidecar. It MUST acquire no lock and MUST complete while another process holds one. Mutation, when requested, MUST occur only in the explicit reap step that runs after classification, so every change is attributable to that step and never to the report.
(Verify: run the report with every flag combination and diff the container list, the process table, and the mtimes of both cache files; file review that no write call sits on the report path.)

#### Scenario: Report with no flags

- GIVEN one live overlay and one orphan candidate
- WHEN the skill is invoked with no reaping flag
- THEN both are reported
- AND the container list, the process table, and both cache files are unchanged afterwards

#### Scenario: Report with mutation flags set

- GIVEN both mutation flags are passed
- WHEN the report pass runs
- THEN it changes nothing by itself, and every subsequent change is attributable to the reap step that follows classification

#### Scenario: A writer holds the lock

- GIVEN another worktree holds the cache lock and is rewriting the manifest
- WHEN the report pass runs
- THEN it completes without waiting for or acquiring the lock

#### Scenario: Reconciliation is deferred, not performed

- GIVEN a stored record contradicts the runtime
- WHEN the report pass runs
- THEN the discrepancy is named in the report and the stored record is left untouched

### Requirement: The report distinguishes checked-and-none from not-checked

Emptiness is a claim that needs evidence, never an omission. The report MUST render separately: container overlays found, host overlays found from a sidecar that was actually read, and every ownership store that could not be read. A missing sidecar MUST be reported as a missing sidecar and MUST NOT be rendered as zero host overlays — the two are different claims and only one of them is evidence. The same distinction applies when the container runtime is absent or not running.
(Verify: run the report with the sidecar deleted, with an empty sidecar, with a malformed sidecar, and with the container runtime stopped; compare the four outputs.)

#### Scenario: Sidecar exists and is empty

- GIVEN the sidecar exists and carries an empty list
- WHEN the report is produced
- THEN it states zero host overlays, checked

#### Scenario: Sidecar absent

- GIVEN the sidecar file does not exist
- WHEN the report is produced
- THEN it names the missing file and states that host-overlay state is unknown
- AND it does not state zero host overlays

#### Scenario: Sidecar malformed

- GIVEN the sidecar exists but cannot be parsed
- WHEN the report is produced
- THEN host-overlay state is unknown, the file is named, and no host overlay is acted on under any flag

#### Scenario: Container runtime unavailable

- GIVEN the container runtime is not running
- WHEN the report is produced
- THEN container-overlay state is reported as unknown with the reason
- AND the run does not fail and does not report zero container overlays

### Requirement: The report declares itself incomplete by construction

Every report MUST state that it can only see overlays launched after instrumentation shipped, whether or not any legacy overlay was found, and MUST name the categories it structurally cannot cover: unlabeled containers predating the label contract, and overlays belonging to worktrees on any host other than this one. The statement MUST NOT be conditional on finding an instance, because a reaper that is quietly partial is worse than one that is loudly partial, and the first run after instrumentation is exactly the run that looks broken without it.
(Verify: file review of the report's output contract; run the report on a repository with no overlays at all.)

#### Scenario: Nothing found

- GIVEN no overlay of any kind is running
- WHEN the report is produced
- THEN it states zero overlays, checked, and still prints the incompleteness statement

#### Scenario: First run after instrumentation

- GIVEN the change has just landed and no overlay has yet been launched under it
- WHEN the report is produced
- THEN it reports nothing to act on and says that overlays launched before instrumentation are invisible to it

#### Scenario: Remote worktree

- GIVEN a worktree that lives on another host
- WHEN the report is produced
- THEN remote overlays are named as outside local scope, are never classified as orphans, and are never acted on

### Requirement: Legacy unlabeled overlays are reported for manual cleanup and never acted on

An overlay carrying no stackgraft label set, or one whose `stackgraft.labels` value is unrecognized, MUST be reported as requiring manual cleanup together with the command the user would run. It MUST NOT be stopped, removed, or signalled under any flag. Detecting such an overlay MUST NOT require listing containers outside `stackgraft.repo=<hash8>`; where seeing one would require an unscoped listing, none MUST be performed and the report MUST record the resulting blind spot rather than widening the query, because an unscoped listing reaches a neighbouring repository's containers, which are not ours to enumerate or to kill.
(Verify: launch a container with no stackgraft labels and confirm it survives both mutation flags; grep every container query in shipped scripts for the `stackgraft.repo` filter.)

#### Scenario: Legacy container present

- GIVEN a container that predates the label contract and carries no stackgraft labels
- WHEN the report runs with both mutation flags
- THEN it is reported as legacy with a manual cleanup command, and it is still running afterwards

#### Scenario: Unrecognized contract version

- GIVEN a container whose `stackgraft.labels` value this run does not recognize
- WHEN classification runs
- THEN it is treated exactly as legacy: reported, never acted on

#### Scenario: Detection would need an unscoped query

- GIVEN a legacy container is only discoverable by listing containers repository-wide
- WHEN the report is produced
- THEN no unscoped listing is issued and the report names the blind spot it therefore has

### Requirement: Every query is scoped to this repository

Every container query, on the report path and the mutation path alike, MUST carry the `stackgraft.repo=<hash8>` filter in the query itself, not as a post-filter over a repository-wide listing. Sidecar reads are scoped by construction, one file per repository. Multi-repo project groups put sibling repositories one directory apart, so an unscoped query reaps a neighbour's overlays.
(Verify: two-repo case run end to end; grep of shipped scripts — every container-listing invocation carries the label filter.)

#### Scenario: Two-repo group

- GIVEN two sibling repositories each with a live labelled overlay of a deleted worktree
- WHEN the reap runs inside one of them with both mutation flags
- THEN only the scoped repository's overlay is reported and stopped
- AND the sibling's overlay is neither named nor touched

#### Scenario: Sibling holds a wanted port

- GIVEN a sibling repository's overlay holds a port this repository would like
- WHEN a port is selected
- THEN the sibling's overlay is not reaped to free it, and the strict-port bind failure handles the collision

#### Scenario: Query paths reviewed

- GIVEN every container query in the shipped scripts and reference procedures
- WHEN they are listed
- THEN each carries the `stackgraft.repo` label filter

### Requirement: The base stack is outside the candidate set by construction, and the port exclusion on top of it is caller-supplied

Candidacy MUST be positive and closed: a container is a candidate only if it carries the full label set with `stackgraft.repo` equal to this repository's `hash8`, so every base-stack container is outside the candidate set by construction rather than by exclusion. **This allowlist is the only unconditional protection this requirement states, and it is the only one that holds structurally**: nothing but an overlay launch writes that label, so no flag, no flag combination, and no code path reaches a base-stack container unless a human has hand-labelled it with this repository's complete label set.

Exclusion beyond that allowlist MUST be **by supplied port**, and the contract MUST describe it as what it is: **caller-supplied and caller-defeatable**. A container publishing a port the run supplied as a base-stack port MUST be excluded even when it carries a matching label set, and the anomaly MUST be reported. Those ports MUST reach the actuator as supplied values, one per port, because the scripts parse no JSON — which is the same reason nothing in the actuator can check a supplied port against the manifest it was read out of. A container mutation MUST therefore refuse while the run **supplies no `-b` argument at all** — absent information is unknown rather than none, and a gate keyed on an optional input is no gate — and no flag, flag combination, or code path MAY stand in for that supply. Nothing stronger MAY be claimed: a run that supplies a *wrong* port, by typo, by a stale manifest, or deliberately, reaches the container the right port would have excluded, and no test available here separates the two. Each supplied value MUST be a decimal port in 1–65535 with leading zeros stripped, so a manifest value typed `018103` excludes the container publishing 18103 instead of silently matching nothing; that validation removes typos and closes nothing, because `1` is a valid port. The refusal MUST NOT name an override, because there MUST NOT be one: an assertion that there is nothing to exclude cannot be checked by a runtime that parses no JSON, and an unverifiable assertion that switches the exclusion off is the same absent gate under another name.

Refusing on the **name** of a service MUST NOT be attempted, and the blind spot that leaves MUST be recorded in this requirement rather than only in a reference file. `stackgraft.service` holds a manifest service key and the base stack runs those same services, so a name test would refuse every overlay this capability exists to reclaim; a compose project name would have to come from the manifest the scripts do not parse. **The residual is therefore exactly one shape, and it is accepted: a container hand-labelled with this repository's complete label set, whose worktree is unlisted, and whose published port is not among the values the run passed — whether the run passed the wrong values or simply not that one.** Nothing narrower is buildable under the zero-JSON constraint, so the limit is part of the contract and not a note beside it, and no shipped document MAY describe the port exclusion as closed, complete, or unbypassable.
(Verify: file review that candidacy is an allowlist; run a reap with the base stack up; hand-label a base-stack container and confirm it is excluded when its port is supplied and that the mutation refuses while no `-b` is supplied; enumerate every shape that supplies no `-b` and confirm each refuses; execute the residual — a valid port that is not that container's — and confirm the container IS stopped; confirm a base-stack container carrying no label set is unreachable at every `-b` value; confirm a `-b` value outside 1–65535 is a usage error.)

#### Scenario: Base stack running

- GIVEN the base stack is up and one orphaned overlay exists
- WHEN a reap runs with both mutation flags and the base-stack ports supplied
- THEN only the orphaned overlay is acted on and every base-stack container is still running

#### Scenario: Base-stack container carrying a matching label

- GIVEN a base-stack container has been hand-labelled with this repository's `stackgraft.repo`
- WHEN candidates are classified with that container's published port supplied as a base-stack port
- THEN it is excluded, the anomaly is reported, and it is not acted on

#### Scenario: Mutation with no base-stack port supplied

- GIVEN a container target under a mutation verb and a run that supplied no base-stack port
- WHEN the target is proven
- THEN the target is refused as unknown rather than decided against an empty port set, the container is untouched, and the refusal names the missing port information without naming a way around it

#### Scenario: No flag stands in for a missing base-port argument

- GIVEN the whole flag surface of the actuator
- WHEN every shape that supplies no `-b` argument at all is exercised against a hand-labelled base-stack container
- THEN every one of them refuses and the container is still running

#### Scenario: The accepted residual

- GIVEN a container hand-labelled with this repository's complete label set, whose worktree is unlisted, and whose published port is not among the values the run passed — the run having passed a wrong value, or simply not that one
- WHEN it is classified
- THEN it is treated as an orphan and is acted on, which is the declared limit of exclusion-by-supplied-port and not a defect to be fixed by widening the test

#### Scenario: A base-stack container carrying no label set

- GIVEN a base-stack container that carries no stackgraft label set
- WHEN a container mutation names it and any base-stack port value is supplied
- THEN it is refused as not a labelled overlay of this repository, whatever value was supplied, because the allowlist is what excludes it and no supplied port can widen the candidate set

#### Scenario: A base-port value that is not a port

- GIVEN a `-b` value outside 1–65535, `0` and `99999999` included
- WHEN the run is parsed
- THEN it is a usage error, the rejected value is named, and nothing is mutated
- AND a value carrying leading zeros is read as the port it spells, so `018103` excludes the container publishing 18103 rather than matching nothing

#### Scenario: Only the base stack is running

- GIVEN no overlay of any kind exists and the base stack is up
- WHEN a reap runs with both mutation flags
- THEN nothing is acted on and the run reports zero targets, checked

### Requirement: Mutation requires one explicit flag; removal requires a second

The default MUST be report-only. Stopping a container requires an explicit mutation flag; removing it requires a further removal flag in addition. The removal flag alone MUST NOT mutate anything, and the run MUST say the mutation flag is required. An already-exited container MUST be reported but MUST NOT be acted on under the mutation flag alone, because stopping something already stopped is a no-op that reports as work done; it IS a target under the removal flag. A stop MUST leave the container's logs readable: an orphan is evidence of something that went wrong, and its logs are the only account of it.
(Verify: exercise all four flag combinations against a running orphan and an exited orphan; read the logs of a stopped orphan afterwards.)

#### Scenario: No flags

- GIVEN a running orphaned overlay
- WHEN the skill is invoked with no flag
- THEN the orphan is reported and is still running

#### Scenario: Mutation flag, running orphan

- GIVEN a running orphaned overlay
- WHEN the mutation flag alone is passed
- THEN the container is stopped, is not removed, and its logs are readable afterwards

#### Scenario: Mutation flag, exited orphan

- GIVEN an orphaned overlay whose container has already exited
- WHEN the mutation flag alone is passed
- THEN it is reported and not acted on, and the run does not count it as work done

#### Scenario: Both flags, exited orphan

- GIVEN an orphaned overlay whose container has already exited
- WHEN both the mutation and the removal flags are passed
- THEN the container is removed

#### Scenario: Removal flag alone

- GIVEN a running orphaned overlay
- WHEN only the removal flag is passed
- THEN nothing is stopped or removed and the run states that the mutation flag is required

### Requirement: No mutation without proven ownership

Before any stop, removal, or signal, the run MUST hold both an orphan classification from the liveness requirement and an ownership proof from `../overlay-ownership/spec.md`: a `hash8`-scoped full label set for container kinds, or a sidecar entry whose `(pid, lstart)` matches verbatim for host kinds. Ownership MUST NOT be inferred from port occupancy, container name, image, compose project, or from a manifest record alone. No process the run did not start MAY be signalled. A refusal MUST name its reason and MUST NOT stop the run from acting on the remaining proven candidates — including a target that fails at the parsing layer rather than at the proof, since a malformed target is one target's problem and refusing the whole invocation for it withholds the reap from the orphans that were named correctly beside it. What is not a target at all — the verb, the repository identifier, the options — MAY still be a usage error, because none of those belongs to a single target.
(Verify: occupy an overlay port with an unlabelled process and confirm it survives both flags; exercise the recycled-pid case; delete the manifest and confirm nothing changes about what is reapable; name a malformed target beside two proven ones and confirm both proven ones are acted on.)

#### Scenario: Port held by something unowned

- GIVEN a process or container holds the port an overlay used to hold, and carries no ownership record
- WHEN a reap runs with both flags
- THEN it is never a target, and the report says the port is held by something stackgraft did not start

#### Scenario: Pid recycled between registration and reap

- GIVEN a sidecar entry whose pid now belongs to another process
- WHEN the reap evaluates it
- THEN the action is refused, the refusal names the identity mismatch, and the reap proceeds with the other candidates

#### Scenario: Manifest record without runtime evidence

- GIVEN the manifest records an overlay for which no labelled container and no sidecar entry exists
- WHEN the reap runs
- THEN nothing is acted on for that service and the discrepancy is reported

#### Scenario: Malformed target beside proven ones

- GIVEN one invocation naming two proven orphans and one target that will not parse
- WHEN the run executes
- THEN the malformed target is refused by name, both proven orphans are acted on, and the run reports how many it acted on before exiting non-zero

### Requirement: The report feeds known-held ports into port selection

The live-overlay set the report produces MUST be supplied to port selection as exclusions, on the report path, with no mutation flag required — the port benefit belongs to the report path, because the report is what every invocation runs. The knowledge is repository-local: ports held by another repository's overlays remain unknown, so the output stays a *candidate* and the launcher's strict-port bind stays authoritative (`../portable-runtime/spec.md`).
(Verify: launch an overlay, then request a port and confirm its port is excluded; run with the ownership stores unreadable and confirm a candidate is still returned.)

#### Scenario: Held port excluded

- GIVEN a labelled live overlay of this repository publishes port P
- WHEN a candidate port is requested for a new overlay
- THEN P is passed as an exclusion and the candidate is not P

#### Scenario: Held-port set incomplete

- GIVEN the sidecar is missing or the container runtime is unavailable
- WHEN a candidate port is requested
- THEN no port is excluded on that basis, a candidate is still returned, and the run states that the held-port set is incomplete

#### Scenario: Another repository's port

- GIVEN a sibling repository's overlay holds port P
- WHEN a candidate port is requested
- THEN P is not excluded, and if it is chosen the strict-port bind failure is what catches it
