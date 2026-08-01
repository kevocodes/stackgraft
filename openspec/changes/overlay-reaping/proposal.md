# Proposal: overlay-reaping

Phase: `sdd-propose` · Input: none (originating) · Next: `sdd-spec` + `sdd-design`
Depends on: `portable-multi-stack` merged (needs `hash8` filename derivation, the XDG cache path, and `fingerprint`)

## Intent

An overlay outlives the worktree that created it. Editors built around parallel worktrees make deleting one a single click and expose no destroy hook, so the gap is routine rather than theoretical.

Three consequences, all reachable from the current files:

1. **It produces a false green.** A survivor keeps listening on a port that is already in `constraints[].cors-allowlist`, serving a branch that no longer exists. The next overlay either collides — loud, tolerable — or a request lands on the squatter and reads as a pass. `traps.md` exists to catch exactly this class and does not catch this instance.
2. **The ownership proof does not hold in the orphan case.** The Hard Rule confirms ownership by comparing a process working directory against the worktree. When the worktree is gone the check has no referent, and it fails toward the dangerous side: pids are reused, so a recorded pid may now be the user's editor.
3. **`verifiedOverlays` cannot be the ledger.** The skill's own Hard Rule declares the manifest a cache, and `portable-multi-stack` accepted that a cleaner may wipe it. Overlays outlive the record of themselves; wiping the cache makes them invisible rather than absent.

Success: overlay ownership is recorded on an object that outlives the cache, and an overlay whose worktree is gone is either reported or removed — never silently holding a port.

## Contract surfaces touched

`SKILL.md` (Hard Rules, Decision Gates, Execution Steps), `references/` (1 modified, 1 new), `scripts/` (1 new). `assets/` schema **untouched** except one description — see D1.

## Decisions

### D1 — Ownership record: container labels, plus a sidecar for host kinds. No schema change.

Every overlay container carries:

```
stackgraft.labels=1
stackgraft.repo=<hash8>
stackgraft.worktree=<absolute path>
stackgraft.service=<service key>
stackgraft.port=<published host port>
```

`docker ps --filter label=stackgraft.repo=<hash8>` then reconstructs live overlay state with no manifest at all. Host-run kinds have nowhere to hang a label, so they get a sidecar at `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.processes.json`.

Separate file, not a manifest field, and that is the point: `schemaVersion` stays at 2, no cache is invalidated, and the single-bump rule from `portable-multi-stack` is not reopened by a change with no business touching topology. `stackgraft.labels` versions the label contract independently.

**Accepted cost:** two ownership stores that can disagree. Reconciliation direction is fixed — the runtime wins, the sidecar is rewritten.

### D2 — Labels are applied by the skill at launch, not baked into `overlayCommand`

`overlayCommand` is discovered from the repo and cached. Synthesising `--label` flags into it puts the label contract in every user's cache, where it drifts the moment the contract changes. Appending at launch keeps it in the skill body, next to the version constant.

**Accepted cost:** `overlayCommand` for container kinds must accept appended flags. Templates that pipe or wrap the command break. Discovery already prefers `docker compose config`-derived commands, so the exposure is narrow, but it is a real constraint on hand-written entries and belongs in the schema description.

### D3 — Ownership proof: composite `(pid, lstart)`, string-compared

Record `ps -o lstart= -p <pid>` at launch; compare verbatim before acting. A mismatch means the pid was recycled and the process is not ours — refuse.

No parsing. The format differs between BSD and procps `ps` and it does not matter: the same binary on the same host produced both strings, so equality is the only operation needed. This replaces the cwd check for the orphan case and supplements it elsewhere.

**Accepted cost:** busybox `ps` has no `lstart`. Where it is absent, host-kind overlays are permanently unproven and degrade to report-only. Declared in `compatibility`.

### D4 — Default is report-only; mutation requires an explicit flag

`portable-multi-stack` was written against a supervised agent. Editors that pre-fill a permission-bypass flag mean the confirmation steps several Hard Rules depend on do not block. A reaper that guesses wrong under bypass kills the user's work.

Report-only is also sufficient for the main win — see T2.

### D5 — Implicit report pass on every invocation; explicit command only for mutation

One `docker ps --filter` and one `git worktree list --porcelain`. The same auto-healing shape the fingerprint check already has: the user does nothing and the skill notices. A standalone reap command is for when something is stuck.

### D6 — Scope by `hash8`, local host only

Every query filters on `stackgraft.repo=<hash8>`. Multi-repo project groups put sibling repos one directory apart; an unscoped `docker ps` reaps a neighbour's overlays, which are not ours to kill. Remote hosts are out of scope.

### D8 — Mutation stops; removal is a second, separate flag

`docker stop` on the mutation path. `rm -f` only when a further flag is passed. An orphan is evidence of something that went wrong, and its logs are the only account of it. Freeing the port is the urgent part; freeing disk is not. Corollary carried into spec: an already-exited container is a target **only** under the removal flag.

### D9 — One write discipline, applied to the sidecar and to the manifest

`mkdir` lock plus temp-file-and-rename inside it, for both files. `flock(1)` is absent on macOS and is out under the assume-nothing rule. This retrofits the manifest write, which today has no protection at all while DS7 establishes concurrent worktrees as the expected case.

**Accepted cost:** shipped behavior changes in a change whose subject is reaping. Taken deliberately — the alternative is two divergent disciplines, which is the outcome the decision exists to avoid. Read paths take no lock; failure to acquire is reported, never silently skipped; and a crashed holder must not wedge the tool, so a staleness policy is mandatory rather than a refinement.

### D7 — Slicing: two PRs, instrument before reap

| # | Slice | Content | Forecast |
|---|-------|---------|----------|
| 1 | Instrumentation | Label emission at launch; `stackgraft.labels` constant; sidecar registry write; `(pid, lstart)` capture; `scripts/with-lock.sh` and the manifest-write retrofit (D9); Hard Rule swap; three new traps; `compatibility` note | ~200 |
| 2 | Reap surface | `scripts/reap.sh`; implicit report pass; Decision Gate rows; mutation flag; `references/reaping.md`; legacy reporting | ~200 |

Ordering is not stylistic. Slice 2 can only find overlays that slice 1 labelled, so reap is inert until instrumentation has run for at least one overlay cycle. Shipping them together would present a feature that does nothing on first run and looks broken.

## Scope

### In scope

- Label emission on every container-kind overlay launch, and sidecar registration for host kinds.
- Liveness test: worktree path from label or sidecar, checked against `git worktree list --porcelain`.
- Report pass on every invocation; a reap command for mutation behind an explicit flag.
- Composite `(pid, lstart)` ownership proof replacing the cwd check for orphans.
- Legacy unlabeled containers reported as requiring manual cleanup, never acted on.
- Feeding known-held ports back into port selection.

### Out of scope (explicit non-goals)

- **Reaping anything in `baseStack`**, under any flag.
- **Stale-but-live overlays.** A worktree that still exists but whose overlay runs old code is a different problem with a different fix.
- **Remote reaping.** SSH worktrees put the overlay on a machine the local `docker ps` cannot see. Report the gap; do not reach across.
- **Volume and network GC.** Volumes may hold data the user wants; networks are cheap. Neither is worth the blast radius.
- **Killing by port occupancy.** Ownership is never inferred from who holds a port.
- **Cache eviction** of the stackgraft cache directory — already a non-goal, unchanged.
- **Windows-native.** POSIX shells only, consistent with the existing declaration.

## Tensions the locked decisions create

**T1 — The label contract has a cold-start hole.** Every container launched before slice 1 is unlabeled and permanently unreapable. Silently skipping them means the user believes the port map is complete when it is not. Unlabeled containers matching no known overlay must be *reported* as legacy with a manual command, and the report must state that the list is incomplete by construction. A reaper that is quietly partial is worse than one that is loudly partial.

**T2 — Report-only default versus the stated goal.** If nobody ever passes the mutation flag, orphans still accumulate. That does not defeat the change, because the two failure modes separate cleanly: the false green is fixed by *knowing* the squatter exists, which the report delivers; only disk and port exhaustion need the kill. The port-selection benefit must land in the report path, not the mutation path.

**T3 — This shrinks the unknowable set in `portable-multi-stack` without closing it.** That tension conceded `pick-port.sh` can only return a candidate because availability is not portably checkable. Labels make the stackgraft-held portion of the range knowable without `lsof` or `ss`. What remains unknowable is "ports held by something that is not stackgraft" — smaller, and no longer the common case. The output contract still says *candidate*; strict-bind is still authoritative.

**T4 — Body budget.** The body is at 497 of 500 words. This change adds a Hard Rule, two Decision Gate rows and one Execution Step. Slice 1 must be net ≤ +0 by rewriting the cwd Hard Rule rather than adding alongside it; slice 2 ceiling +40. Gate detail lives in `references/reaping.md`, and the Hard Rule must be self-sufficient in the refusal direction: unproven ownership means refuse, whether or not the reference was loaded.

## Capabilities

### New

- `overlay-ownership`: label contract, sidecar registry, composite pid identity, reconciliation direction.
- `orphan-reclamation`: liveness test, report contract, mutation gate, legacy reporting.

### Modified

- `portable-runtime`: adds `scripts/reap.sh` and `scripts/with-lock.sh`; `compatibility` gains the `lstart` note.
- `manifest-contract`: the manifest write becomes serialized (D9). Behavior change to shipped code, admitted deliberately. The capability `portable-multi-stack` created under that name is extended, not duplicated.
- `topology-discovery`: `overlayCommand` gains a label-anchor constraint (D2, as amended by A2 and A5).

## Affected areas

| Area | Impact | Change |
|---|---|---|
| `skills/stackgraft/SKILL.md` | Modified | Hard Rule: cwd check → composite identity; two Decision Gate rows; a report step; `compatibility` note |
| `skills/stackgraft/references/traps.md` | Modified | Pid reuse; the cwd proof has no referent once the worktree is gone; the unlabeled-legacy blind spot; last-writer-wins on a concurrently rewritten manifest |
| `skills/stackgraft/references/reaping.md` | New | Label contract, sidecar shape, liveness procedure, reconciliation, refusal cases |
| `skills/stackgraft/scripts/reap.sh` | New | POSIX `sh`; report and mutation paths |
| `skills/stackgraft/scripts/with-lock.sh` | New | `mkdir` lock, bounded wait, staleness policy, temp-and-rename. A script rather than body prose so the discipline costs the body one word, not a paragraph |
| `skills/stackgraft/assets/manifest.schema.json` | Modified | `overlayCommand` description only — the label anchor. No new fields, no version bump |
| `README.md` | Modified | Status |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Reap kills a live overlay of a worktree the editor has archived or slept | **Resolved** | See the question round: neither archive nor sleep removes the directory |
| Sidecar wiped; host overlays unreapable and invisible | Med | Report the sidecar as missing rather than reporting zero host overlays; the two are not the same claim |
| `overlayCommand` templates that cannot take appended flags | Low | Schema description states the constraint; discovery-generated commands comply; hand-written ones fail loudly at launch |
| Label scoping bug reaps a sibling repo in a multi-repo group | Low | The `hash8` filter is mandatory in every query path; verification includes a two-repo case |
| Slice 2 lands and appears to do nothing | High | Expected by construction (D7); README and report output both state that reap only sees overlays launched after instrumentation |
| `ps -o lstart=` unverified across platforms | Med | Verification runs on macOS and a minimal Linux container; busybox absence is declared, not worked around |
| A crashed lock holder wedges every later run — a permanent outage traded for an occasional clobber | Med | Bounded wait plus a declared staleness policy is a spec requirement, not a design refinement; verification includes an abandoned-lock case |
| The manifest retrofit breaks a working write path in a change nobody expects to touch it | Low | Slice 1 verification runs the existing manifest suite unchanged; the lock wraps the write rather than rewriting it |

## Rollback

Revert the merge. Labels already written to running containers become inert metadata; the sidecar is orphaned, small, and ignored by a reader that does not know it. No manifest migration, because there is no manifest change. Containers launched while the change was live remain labelled and are reapable again if it is reinstated.

## Dependencies

- `portable-multi-stack` merged — `hash8` derivation and the XDG path are load-bearing.
- `git` (already required), POSIX `sh` + `awk` (already), `ps` with `lstart`.
- `docker` only for container-kind repos, consistent with the existing conditional dependency.
- No new package, build step, or runtime.

## Success criteria

- [ ] Every container-kind overlay launch emits all five labels; verified by `docker inspect`.
- [ ] `docker ps --filter label=stackgraft.repo=<hash8>` reconstructs overlay state with the manifest deleted.
- [ ] A pid recycled between registration and reap is refused, and the refusal names the identity mismatch.
- [ ] The report pass never mutates, under any flag combination.
- [ ] An unlabeled legacy container is reported, is not acted on, and the report declares itself incomplete.
- [ ] No `baseStack` service is reachable as a reap target in any code path.
- [ ] A two-repo group reaps only the scoped repo.
- [ ] An exited container is reported but not acted on under the stop flag, and is a target under the removal flag.
- [ ] Two concurrent writers against one manifest both survive: neither loses its `verifiedOverlays` entry.
- [ ] An abandoned lock is reclaimed within the declared bound rather than wedging the run.
- [ ] Failure to acquire a lock is reported as a failure; no path reports success on a skipped write.
- [ ] The report pass acquires no lock and completes while a writer holds one.
- [ ] `schemaVersion` unchanged at 2 across both slices.
- [ ] Body ≤500 words; slice 1 net ≤ +0, slice 2 ≤ +40.
- [ ] `reap.sh` and `with-lock.sh` pass `dash -n` and run on macOS and a minimal Linux container.

## Proposal question round

### Amendments after design

Four locked decisions did not survive design contact. Each is corrected here rather than worked around downstream; each correction was verified against the repository, not argued.

**A1 — D9's lock is necessary but not sufficient. `with-lock.sh` needs compare-and-swap.** Serializing the write does not fix last-writer-wins, because the loss happens in the *read-modify-write window*, not in the write. Two agents read the same manifest, both queue on the lock, and the second's write — correctly serialized — still erases the first's `verifiedOverlays` entry. The script therefore takes an expected fingerprint and refuses a stale write, which the caller re-reads and retries. D9 stands; its stated mechanism was half a mechanism.

**A2 — D2's "appending `--label` flags" is wrong, and the counterexample ships in this repository.** `assets/manifest.example.json:98` ends its template at the service operand: `docker compose … run --rm --no-deps --publish {{port}}:8080 catalog-api`. Appending after that makes the label the container's `COMMAND`. Options precede the operand, so the mechanism is anchor insertion. This *shrinks* D2's accepted cost rather than binding it — piped and wrapped templates keep working.

**A3 — T4's "slice 1 net ≤ +0" is insufficient, not merely loose.** The real constraint is `slice1_out + slice2_delta ≤ 500`. Slice 1 landing at 497 leaves slice 2 three words against its own forty-word ceiling — the two stated budgets cannot both hold. Slice 1's target is net **−34**, to 463.

**A4 — D7 mis-slices `references/reaping.md`, and slice 1's CI goes red because of it.** Slice 1's Hard Rule names the file, and `.github/scripts/verify.sh:87-88` resolves every backticked `references/…` link and fails on a dangling one. The file is created in slice 1 with the instrumentation half and extended in slice 2. `references/discovery.md` joins slice 1 for the same structural reason and was missing from the affected-areas table.

**A5 — the spec's refusal test is over-broad; DS24's anchor test replaces it.** `specs/topology-discovery/spec.md` refuses any command that "pipes, wraps, redirects, or otherwise terminates the argument list"; DS24 refuses on *anchor absence*. They disagree on the piped case, and DS24 is right: insertion lands immediately after the `run` token, before the pipe, so the labels reach the launcher and the container starts correctly labelled. The spec's test refuses launches that would have succeeded.

What the spec was protecting — **never launch an unlabeled container** — is preserved unchanged, and the criterion becomes: refuse when no anchor exists after a recognised launcher token, and refuse `up`-shaped templates outright. Interpreter templates (`sh -c …`) stay refused by the existing deny-list in `references/shared-state.md`, which is where that rule already lives; anchor matching MUST NOT reach inside a quoted string, or `echo "docker run x" | sh` would be "labelled" into a string and launch bare.

Rewrite the requirement and its second scenario accordingly. The requirement's name — *MUST tolerate appended arguments* — is part of the error and changes with it.

**A6 — the `with-lock.sh` carve-out is one file too narrow.** The spec permits the lock directory and a rename. DS22 also needs `: > "$destination.wait.$$"` as the `find -newer` reference, and it cannot live inside the lock directory because that directory belongs to whoever holds it. Widen the carve to name a staleness-reference file adjacent to the destination, created and removed by the script. The two properties the rule protects — scripts parse no JSON, the agent owns the content — are untouched: the reference file is empty by construction.

**A7 — T1's legacy detection has no mechanism, and the blind spot is the deliverable.** A container launched before instrumentation carries no label, so nothing distinguishes it from any other container on the machine. An unfiltered listing does not detect legacy overlays; it lists everything and cannot say which is which. Widening the query buys noise, not coverage, and the spec is right to forbid it. So the report names the category, states that overlays launched before `stackgraft.labels` are invisible by construction, and gives the manual command — which is what T1 asked for. Accepted as a real coverage loss, stated loudly.

**A8 — `verify.sh`'s `compatibility` guard is vacuously satisfiable, and it ships today.** `[ "${compat:-0}" -lt 500 ]` reads `0` when awk prints nothing, so **deleting the field entirely passes the check**. It also enforces `< 500` where the requirement says *at most* 500. Same failure this project has now hit five times: a gate keyed on an optional field is no gate. Fix in slice 1, alongside the `compatibility` edit that first depends on the counter being honest — and pair it with a negative fixture, since a check that cannot fail is the thing being fixed.

**A9 — `-B` is removed. Container mutation requires at least one real base port, and the unbuildable half of the base-stack clause becomes a declared limit.**

The C3 fix replaced an optional-flag gate with a flag that lets the caller *assert* there is nothing to exclude. Executed, `-B -m stop` stops a hand-labelled base-stack container: `acted 1`, exit 0. Nothing validates the claim, `references/reaping.md:191`'s "the only way past that refusal is to supply the information the exclusion is made of" is false because `-B` supplies zero ports, and `scripts/reap.sh:508`'s refusal message hands the reader the bypass.

That is the project's own forbidden shape wearing a new hat: **emptiness is a claim that needs evidence.** An empty `backingStores` must carry a `stateReview` recording who looked and how; `-B` carries nothing a script can check. Worse, its semantics are undefined precisely where they matter — `-B` is checked-and-none about *the manifest*, while the decision is about *the base stack's actual ports*, and those diverge in the manifest-less mode `SKILL.md:43` explicitly supports. A truthful `-B` can still reap a base-stack container.

**Decision: remove the flag.** Container mutation requires at least one `-b <port>`. A run that cannot name a single base port refuses, and that refusal has no override. The cost is real and gets declared: a repository whose manifest records no `basePort` cannot mutate container targets until one is supplied. It is a small cost — this skill exists to overlay onto a running base stack whose ports the overlay must avoid, so `pick-port.sh` already needs those ports; a repository with none is degenerate. And the refusal message must state what is missing **without naming a way around it**, because there no longer is one.

**The genuinely unbuildable half becomes a declared limit, with an amendment rather than a quiet skill-file note.** `specs/orphan-reclamation/spec.md:177` says "or one identified as a base-stack service" — unbuildable under the locked *scripts parse no JSON* constraint: `stackgraft.service` holds a manifest service key and the base stack runs those same services, so refusing on the name would refuse every overlay this skill exists to reclaim. Exclusion is by port, from ports the caller supplies. The residual is one shape and must be written into the spec, not only into `reaping.md`: a container carrying this repository's complete label set, whose worktree is unlisted, whose published port is none of those passed.

**The process failure is the part worth naming.** Pass 1 rejected C2 for being a contract change without an amendment, and C2 was then fixed by changing code to match the spec. C3's second clause took the opposite route — a skill file was changed and the spec was never told — leaving `spec.md:177` saying MUST while `reaping.md:193` says unbuildable. A limit that A7 was required to declare with a numbered amendment and absorbing spec text cannot be declared for C3 with a narrative bullet in `tasks.md`.

**A10 — the absolute base-stack guarantee is not buildable. Narrow the contract to what is true, and stop pretending three fixes closed it.**

A9 removed `-B` and the hole moved into the value: `-b 0` — a decimal, so it passes validation, sets `base_given`, and enters a list where it can never match — stops a hand-labelled base-stack container. `acted 1`, exit 0, verbatim the C3-R CRITICAL with a different spelling. `-b 1` does it too, and **`1` is a valid TCP port**, so a range check does not close this. Nothing does.

**The reason is structural, and three rounds of code fixes were the wrong instrument.** `scripts parse no JSON` is locked, so `reap.sh` cannot read the manifest. It knows only what the caller passes. A caller that passes a wrong port — by typo, by a stale manifest, by malice — defeats the port exclusion, always. `specs/orphan-reclamation/spec.md:177`'s *"No flag, flag combination, or code path MAY reach a base-stack service"* is a promise this architecture cannot keep, and the spec now contradicts itself: `:202` demands every shape supplying no base port refuse, while `:208` says a container whose port is none of those passed is an orphan and not a defect. `-b 0` satisfies both, and the code takes the permissive branch — inverting the change's own central principle.

**Decision: no fourth attempt at the guarantee. Make the contract true.**

- The **non-defeatable** protection is the positive allowlist, and it is genuinely structural: a container is a candidate only if it carries the complete five-label set with this repository's `hash8`. A base-stack container does not carry those labels unless a human put them there.
- The **port exclusion is caller-supplied and caller-defeatable**, and the spec must say so in those words. Narrow `:177` and `:202` to what holds: a run supplying **no** `-b` argument refuses.
- The residual is one named shape: a container hand-labelled with this repository's complete label set, whose worktree is unlisted, and whose published port is not among the values passed. Write it into the contract, not only into `references/reaping.md`.
- `README.md:93` ("one narrow case") and `reaping.md:195` ("not a second way in") are **false as shipped** and must be corrected rather than softened.
- `tasks.md` task 3.1 carries the falsified criterion as a success condition; it cannot be closed as written and must be restated against the allowlist.

**Port-range validation still lands, and must not be sold as the fix.** `-b 0`, `-b 99999999` and `-b 018103` are not valid ports, and the last one — a manifest value typed with a leading zero — silently loses all protection today. `scripts/pick-port.sh` already validates 1–65535 with a leading-zero strip in `port_arg()`; `reap.sh` should reuse that shape for consistency. It removes footguns. It closes nothing, and no document may imply otherwise.

**The verification must assert the true behaviour.** `verify.sh:1143`'s A9 negative control never pairs a wrong port with the base-stack container, which is precisely why the suite stayed green through this. The new row must execute the declared residual and assert that the container **is** stopped — a row that documents the limit instead of one that wishes it away. A suite that only tests the shapes we hoped were safe is how three rounds shipped green with a hole in each.

**Resolved, not amended:** the design flagged one blocking unknown — whether `docker compose run` accepts `--label`, the premise the whole D2 mechanism rests on. It does: `-l, --label stringArray  Add or override a label`. Verified against the installed binary.

### Q1 — RESOLVED: stop by default, remove behind a second explicit flag

An orphan is a symptom. The worktree was deleted mid-work, or a background sweep took it — either way the logs are the only account of what the overlay was doing when its worktree vanished, and destroying them is destroying the evidence at the exact moment someone wants to read it. Stopping frees the port, which is the damage; removal frees disk, which is not urgent.

Two flags, then: one to mutate at all (D4), one to escalate from stop to remove. Consequence to carry into spec: **an already-exited container is a reap target only under the removal flag.** Under stop it is already stopped, so acting on it would be a no-op that reports as work done.

### Q2 — RESOLVED: sleep and archive keep the directory

Answered against the editor's own source rather than by argument, because the question could not be settled any other way.

| Action | The worktree directory | Evidence |
|---|---|---|
| **sleep** | **Kept.** Only PTY processes and browsers are released; the code states the operation is reversible and that tab records and layouts persist | `sleep-worktree-flow.ts` |
| **archive** | **Kept.** `isArchived` is a boolean on the workspace, consumed by cleanup classification; nothing in that path removes a directory | `workspace-cleanup.ts` |
| **delete** | **Removed**, along with the branch | editor docs, `delete-worktree-flow.ts` |

A repository-wide search puts `git worktree remove` only in the delete path. Liveness by directory existence therefore stands as proposed, and the highest-consequence risk in the table is closed.

**A finding that strengthens the change:** the editor ships a workspace-cleanup module that classifies archived-and-idle workspaces as cleanup candidates. Worktrees can therefore disappear on a background sweep, not only on an explicit click — so orphans can appear while nobody is watching, and the report pass matters more than the original framing suggested.

**Residual, non-blocking:** whether that sweep deletes the directory itself or only surfaces a suggestion. It does not block the design, because either way the directory is gone by the time the reaper looks — but it constrains what the report may claim about *why* a worktree vanished.

### Q3 — RESOLVED: sidecar is per-repo, alongside the manifest

`${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.processes.json`, as D1 proposed. Scoping stays uniform with everything else in the project, and a repository that goes away takes its registry with it instead of leaving a row in a file nobody owns.

The cost is accepted and must be stated where it bites: answering *"is this port already held?"* requires reading N sidecars, one per repository. D6 scopes every reap query to one `hash8`, so the reaper itself only ever reads one — but the port-selection benefit in T2 is deliberately **repo-local**. Ports held by a sibling repository's host overlays remain in the unknowable set of T3. Strict-bind stays authoritative; that has not changed.

### Q4 — RESOLVED, on a corrected premise: one write discipline, applied to both files

**The premise of the original question was wrong and is corrected here.** It asked whether the sidecar needed *the same* treatment as the manifest. The manifest has no treatment: `SKILL.md` step 9 says *rewrite the manifest*, and there is no lock, no atomic replace, and no mention of a second writer anywhere in the skill or the schema.

The intent behind the answer — one mechanism, not two — therefore resolves to **define the discipline in this change and apply it to both files**. Protecting only the sidecar would create precisely the second, divergent surface the answer rejected.

**The manifest's exposure is not hypothetical.** `portable-multi-stack` DS7 chose a per-worktree port offset because *"lowest-first makes two concurrent worktrees collide by construction"* — the offset exists because concurrent worktrees are the expected case. Two of them reach step 9 against one manifest file; last writer wins and the loser's `verifiedOverlays` entry is gone with no error. The sidecar would inherit that bug rather than introduce it.

**Mechanism: a `mkdir` lock plus temp-file-and-rename inside it.** `flock(1)` is out — util-linux ships it, macOS does not, and the project's rule is to assume nothing. `mkdir` is atomic, fails when the directory exists, and is in POSIX; `rename` within one directory is atomic on every supported platform. No new dependency, consistent with the existing script constraints.

Three obligations this creates for `sdd-design`, none of them optional:

1. **A crashed holder must not wedge the tool forever.** A lock with no staleness rule converts a crash into a permanent outage, which is worse than the clobber it replaces. Bounded wait, then a declared staleness policy.
2. **Failure to acquire is reported, never silently skipped.** A skipped manifest write that reports success is the same silent-loss failure by another route.
3. **Read paths take no lock.** The report pass is read-only by D4 and must not be blockable by a writer.

**Scope note.** Retrofitting the manifest write is a change to already-shipped behavior and is admitted deliberately, because the alternative is two disciplines. It lands in slice 1 with the sidecar, and slice 1's `≤ +0` body budget is now harder — the lock is a script-level concern and must not consume body words beyond the existing step 9 wording.
