# overlay-ownership

New capability. Label contract and sidecar (D1), application point (D2), composite identity (D3), scoping (D6): `../../proposal.md`. Sidecar location: proposal Q3. Write-discipline obligations: proposal Q4.

The write discipline itself is normative once, in `../manifest-contract/spec.md`; this capability states only which ownership stores are subject to it.

## ADDED Requirements

### Requirement: Every container-kind overlay carries the full label set

Every container started as an overlay MUST carry all five labels: `stackgraft.labels` (the label-contract version constant), `stackgraft.repo` (`hash8`, derived exactly as the manifest filename derives it), `stackgraft.worktree` (the overlay worktree's absolute physical path), `stackgraft.service` (the manifest service key), and `stackgraft.port` (the published host port). Labels MUST be supplied at container creation, so a container either exists carrying all five or does not exist; there is no post-hoc labelling step. Every value MUST be passed as one shell word, because a worktree path holds whitespace. A container carrying fewer than five MUST NOT be treated as owned by any run.
(Verify: `docker inspect` of a launched overlay lists all five with the expected values; file review of the launch step; a worktree path containing a space is launched and read back.)

#### Scenario: Launch inspected

- GIVEN a container-kind service launched as an overlay
- WHEN the running container is inspected
- THEN all five labels are present, `stackgraft.repo` equals this repository's `hash8`, `stackgraft.port` equals the published host port, and `stackgraft.worktree` equals the absolute physical path of the overlay worktree

#### Scenario: Worktree path contains whitespace

- GIVEN the overlay worktree path contains a space
- WHEN the container is launched and its labels are read back
- THEN `stackgraft.worktree` holds the whole path as one value
- AND it compares equal to the corresponding `git worktree list --porcelain` entry

#### Scenario: Partial label set is not ownership

- GIVEN a container carrying `stackgraft.repo` but missing `stackgraft.worktree`
- WHEN ownership is evaluated
- THEN the container is not owned, is excluded from every candidate set, and is reported as unowned rather than acted on

### Requirement: Live overlay state is reconstructable without the manifest

`docker ps --filter label=stackgraft.repo=<hash8>` MUST yield, for every live container overlay of this repository, its service, published host port, and worktree path, with no manifest present and no sidecar present. Where the runtime and a stored record disagree, the runtime MUST win and the stored record MUST be rewritten. That rewrite is a write and MUST NOT be performed on the report path (`../orphan-reclamation/spec.md`); the report states the discrepancy, a later write path corrects it.
(Verify: delete the manifest, run the report, compare against the launched set; file review that reconciliation is attributed to a write path.)

#### Scenario: Manifest deleted

- GIVEN two labelled container overlays are running and the manifest file has been removed
- WHEN overlay state is reconstructed
- THEN both overlays are reported with their service, port, and worktree
- AND nothing is reported as unknown for lack of the manifest

#### Scenario: Stored record contradicts the runtime

- GIVEN the manifest records a `verifiedOverlays` entry for a service the runtime has no labelled container for
- WHEN state is reconstructed
- THEN the runtime's answer wins, the discrepancy is named in the report, and the stored entry is corrected only on a subsequent write path

#### Scenario: Sidecar contradicts the process table

- GIVEN a sidecar entry whose pid no longer exists
- WHEN state is reconstructed
- THEN the runtime's answer wins, the stale entry is named, and the sidecar is rewritten only under the discipline in `../manifest-contract/spec.md`

### Requirement: The label contract lives in the skill, never in a cached command

Labels MUST be appended by the skill at launch. No `overlayCommand` value written to a manifest MAY contain a `stackgraft.` label, so raising the label-contract version MUST take effect on the next launch without invalidating, rewriting, or rediscovering any cache. `stackgraft.labels` versions the label contract independently of `schemaVersion`. A live container whose `stackgraft.labels` value this run does not recognize MUST be treated as unproven: reported, never acted on.
(Verify: grep any written manifest for `stackgraft.`; file review that the version constant lives in the shipped skill; unrecognized-version case exercised.)

#### Scenario: Cache holds no label text

- GIVEN a manifest written after a labelled overlay launch
- WHEN every `overlayCommand` value is searched
- THEN no `stackgraft.` label appears in any of them

#### Scenario: Contract version raised

- GIVEN the label-contract version constant is raised in the skill
- WHEN the next overlay launches
- THEN it carries the new value
- AND no manifest is discarded and `schemaVersion` is unchanged

#### Scenario: Unrecognized contract version

- GIVEN a live container whose `stackgraft.labels` value this run does not recognize
- WHEN candidates are classified
- THEN it is reported as carrying an unrecognized label contract and is not a mutation target under any flag

### Requirement: Host-kind overlays are registered in a per-repo sidecar

Host-run overlays have nowhere to hang a label and MUST be registered at `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.processes.json`, one file per repository, using the same `hash8` derivation as the manifest. Every worktree of one repository MUST resolve to the same sidecar, and two repositories sharing a basename MUST resolve to different files. Each entry MUST record the service key, the published host port, the worktree's absolute physical path, the pid, and the start-time evidence of the composite-identity requirement below. The file MUST distinguish *checked and none* from *not checked*: a file that exists carrying an empty list is the former; an absent or unreadable file is the latter and MUST NOT be read as zero host overlays. Sidecar writes MUST use the discipline in `../manifest-contract/spec.md`.
(Verify: path resolution from a linked worktree and from the main checkout; two repositories sharing a basename; file review that the sidecar write calls the shared lock script.)

#### Scenario: Two worktrees, one sidecar

- GIVEN two worktrees of one repository each register a host overlay
- WHEN each resolves the sidecar path
- THEN the paths are identical and both entries live in that one file

#### Scenario: Same basename, different repositories

- GIVEN two repositories whose root directories share a basename
- WHEN each resolves its sidecar path
- THEN the `hash8` segments differ and the two sidecars do not collide

#### Scenario: XDG override honored

- GIVEN `XDG_CACHE_HOME` is set
- WHEN the sidecar path is resolved
- THEN it is rooted at that value, not at `$HOME/.cache`

#### Scenario: Empty is a claim, absent is not

- GIVEN the sidecar exists and carries an empty list
- WHEN host-overlay state is read
- THEN the answer is zero host overlays, checked
- AND when the file is instead absent or unreadable, the answer is unknown, the file is named, and no host overlay is acted on

### Requirement: Ownership of a host process is proven by a verbatim `(pid, lstart)` match

At registration the skill MUST record `ps -o lstart= -p <pid>` exactly as emitted. Before any action on that pid the value MUST be re-read and compared as an exact string. The comparison MUST NOT parse, normalize, reformat, tolerate whitespace differences, or match partially: the same `ps` binary on the same host produced both strings, so equality is the only operation the proof needs, and the format difference between BSD and procps `ps` is therefore irrelevant. Any inequality MUST refuse the action, and the refusal MUST name the pid and the identity mismatch. This proof replaces the working-directory check for the orphan case, where the deleted worktree leaves that check with no referent, and supplements it where the worktree still exists.
(Verify: file review of the comparison in `references/reaping.md` and `scripts/reap.sh` — string equality only, no field extraction; recycled-pid case exercised.)

#### Scenario: Identity matches

- GIVEN a sidecar entry whose recorded start-time string equals the value `ps` reports for that pid now
- WHEN ownership is evaluated
- THEN the process is proven to be this run's overlay, and the remaining gates decide whether anything happens to it

#### Scenario: Pid recycled

- GIVEN a sidecar entry whose pid now belongs to a different process, so the reported start time differs from the recorded one
- WHEN ownership is evaluated
- THEN the action is refused, the refusal names the pid and the start-time mismatch, and the run continues with the remaining candidates
- AND no signal is sent to that pid

#### Scenario: Pid no longer exists

- GIVEN a sidecar entry whose pid is absent from the process table
- WHEN ownership is evaluated
- THEN nothing is signalled, the entry is reported as gone, and it is retired from the sidecar only on a locked write path

#### Scenario: Format is never interpreted

- GIVEN a recorded start-time string in this host's `ps` format
- WHEN it is compared with the current value
- THEN only string equality is used, and no field, token, or timestamp is extracted from either value

### Requirement: Missing start-time evidence degrades to report-only

Where `ps -o lstart=` is unavailable or emits nothing — busybox `ps` has no such field — the ownership record MUST record the absence explicitly, and MUST NOT record an empty string that could compare equal to another absent value. Host-kind overlays registered on such a host are permanently unproven and MUST be report-only: no stop, no signal, and no removal under any flag or flag combination. The degradation MUST be reported at registration and in every report, and MUST be declared in `compatibility` (`../portable-runtime/spec.md`). It MUST NOT be worked around by substituting another identity signal — process name, command line, port, or start-time approximation — because each of those admits exactly the mistaken-identity kill the composite proof exists to prevent.
(Verify: run registration in an image whose `ps` lacks `lstart`; confirm the record marks absence and the mutation path refuses; `compatibility` review.)

#### Scenario: `ps` without `lstart`

- GIVEN a host whose `ps` does not support `lstart`
- WHEN a host-kind overlay is registered
- THEN the entry records that start-time evidence is unavailable, distinctly from an empty or missing value
- AND the run tells the user that host overlays on this host are report-only

#### Scenario: Absence never proves identity

- GIVEN two sidecar entries both registered without start-time evidence
- WHEN either is evaluated for mutation
- THEN neither is proven, equality of the absence marker is not accepted as proof, and neither is a target

#### Scenario: Mutation requested on a degraded host

- GIVEN both mutation flags are passed on a host without `lstart`
- WHEN reaping runs
- THEN labelled container overlays are still eligible, host overlays are reported and skipped, and the reason is named per skipped entry

### Requirement: Unproven ownership refuses, from the body alone

The SKILL.md body MUST carry the refusal direction self-sufficiently: a run that never loads `references/reaping.md` MUST refuse to act on anything, not proceed. The body MUST state only *that* ownership proof is required and *where* the procedure lives; it MUST NOT state any condition under which an overlay may be stopped or removed, because a condition in the body makes skipping the reference permissive. Absent, empty, unreadable, degraded, and unrecognized ownership data are all "unproven", and unproven MUST resolve to refuse.
(Verify: file review that the refusal is readable in the body without following any link; body grep for permitting terms, as the shipped verifier already does for the shared-state gate.)

#### Scenario: Reaping reference never loaded

- GIVEN the run has not loaded `references/reaping.md`
- WHEN any overlay is a candidate for mutation
- THEN every candidate is unproven and nothing is stopped, removed, or signalled
- AND that refusal is derivable from the SKILL.md body alone

#### Scenario: Ownership store unreadable

- GIVEN the sidecar cannot be read, or the container runtime cannot be queried
- WHEN candidates are classified
- THEN the state is unproven and reported as such, never reported as "no orphans" and never acted on

#### Scenario: Body reviewed for permitting language

- GIVEN the SKILL.md body after either slice
- WHEN it is read for the ownership rule
- THEN it names the requirement and the reference and contains no sentence stating a condition under which an overlay may be stopped or removed
