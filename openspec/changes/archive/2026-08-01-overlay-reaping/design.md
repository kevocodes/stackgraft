# Design: overlay-reaping

Phase: `sdd-design` · Input: `proposal.md` (locked, D1–D9) · Next: `sdd-spec` + `sdd-tasks`

> Size note: the sdd-design 800-word guidance is deliberately exceeded, on the precedent
> `portable-multi-stack/design.md` set. This change adds a mutual-exclusion primitive, a process-identity
> primitive, a launch-time mutation of repository-supplied command templates, a second ownership store,
> and a pass that runs on every invocation. Each needs its contract stated in full or the implementation
> re-decides it. Density is held by tables. Numbering continues from DS20.

## Technical Approach

Four mechanisms carry the change, and each is built out of a tool the skill already requires.

1. **Ownership is a runtime fact, not a cached one.** Container labels and a sidecar registry both
   record `(worktree, service, port)` plus, for host kinds, `(pid, lstart)`. The manifest is never
   consulted to decide whether something may be stopped.
2. **One identity primitive, two uses.** `(pid, lstart)` proves an overlay process was not recycled
   (D3) *and* proves whether a lock holder crashed (D9). Building the staleness policy out of the
   ownership proof means one probe, one capability test, and one degraded state to reason about.
3. **The report never writes; the write never guesses.** The report pass takes no lock, mutates no
   file, and cannot reach a mutation path. The write path takes a lock and a compare-and-swap guard,
   so a lost update is refused rather than silently taken.
4. **Sealed in the refusal direction.** An agent that never opens `references/reaping.md` launches
   nothing labelled, records nothing, and — because the body's Hard Rule requires a matching recorded
   identity before any stop — can only refuse. Missing instrumentation degrades to *reported as
   incomplete*, never to *acted on unproven*.

## Architecture Decisions

### The write discipline (D9)

**DS21 — `with-lock.sh` takes a payload path, a destination, and a required expected fingerprint. It never wraps a command and never reads stdin.**

```
usage:  sh scripts/with-lock.sh <destination> <payload> <expected>
        <expected>  fingerprint of <destination> as READ by the caller, or "-" when
                    the caller read no file there
stdout: nothing on success
exit:   0 committed  ·  2 usage error  ·  3 lock not acquired (destination untouched)
        4 environment failure (cache dir, copy, or rename)  ·  5 destination changed
        since <expected> — re-read, re-merge, retry (maximum 3 attempts, then ask)
```

| | |
|---|---|
| **Choice** | Payload-and-destination, with a mandatory compare-and-swap argument. `<expected>` is `git hash-object --stdin < <destination>`, and `-` when the file was absent. |
| **Alternative** | Wrap a command (`with-lock.sh <dest> -- <cmd>...`). **Alternative**: read the payload on stdin. **Alternative**: make `<expected>` optional. |
| **Rationale** | The agent composes the manifest JSON with its own file-write tool; forcing that through a shell command would make an agent express a file write as a command line, and would reopen the arbitrary-execution surface `references/shared-state.md` spends a whole table closing. Stdin is rejected because both shipped scripts take arguments and read stdin only on an explicit `-`: a helper that blocks forever leaves nothing to diagnose. **`<expected>` is required, not optional, because serialising the write alone does not fix last-writer-wins.** Two agents each read the manifest, each merge their own `verifiedOverlays` entry, and each write under a perfect lock — the loser's entry is still gone. The guard closes the read-modify-write window, and an *optional* guard is a guard nobody passes, exactly as an absent `confidence` is not `declared`. `-` for "expected absent" reuses `fingerprint.sh`'s existing vocabulary rather than inventing a second one. |

Two details the implementation must not re-decide. The destination is hashed with
`git hash-object --stdin < <path>`, **not** `fingerprint.sh`'s `--no-filters -- <path>` form: the cache
file lives outside any repository, and the stdin form is the one `pick-port.sh` and
`references/discovery.md` §0 already rely on there. And the payload is **copied**, never renamed, so a
caller that must retry after exit 5 still holds its payload.

**DS22 — `mkdir` lock, holder identity inside it, liveness-first staleness with a time-bounded fallback.**

Lock path is `<destination>.lock` — per destination, not per repository, so the lock name is derived
from the one argument the script already has and a manifest writer never excludes a sidecar writer.

| Step | Operation | Note |
|---|---|---|
| 1 | `mkdir "$lock" 2>/dev/null` | POSIX, atomic, fails when it exists. Success arms the cleanup trap. |
| 2 | Write `"$lock/owner"`: three lines — `pid`, `lstart` (or `-`), `uname -n` | The holder's identity, by the DS23 probe. |
| 3 | `cp "$payload" "$lock/tmp"` then `mv "$lock/tmp" "$destination"` | Temp lives *inside* the lock, so its name is unique by construction and cleanup is one `rm -rf`. Same directory ⇒ same filesystem ⇒ `rename(2)`. |
| 4 | `trap 'cleanup' EXIT INT TERM HUP`, guarded on `held=1` | INT/TERM re-exit non-zero; a bare trap in POSIX `sh` would *continue*. A waiter that never acquired removes nothing. |

**Staleness, and the tension the proposal refuses to leave noted.** A lock with no reclamation turns one
crash into a permanent outage; a lock that reclaims on a timer alone steals from a live holder. The
resolution is that the two cases are *distinguishable*, and each gets the answer it deserves:

| Holder state (read from `owner`) | Action | Wait |
|---|---|---|
| `pid` absent from `ps`, or `lstart` differs, and `uname -n` matches | **Reclaim immediately** — the holder is provably dead | none |
| `pid` live and `lstart` matches, host matches | **Never steal.** Exit 3 naming the holder's pid | full bound first |
| `owner` missing, unreadable, `lstart` is `-`, or the host differs | Fall back to the time bound below | full bound |

Time-bounded fallback, with no `stat` and no `flock`: before waiting, `: > "$destination.wait.$$"`;
retry `mkdir` once a second for **10** attempts; then `find "$lock" -prune -newer "$destination.wait.$$"`.
Empty output means the lock predates the reference by the whole bound. Reclaim is
`mv "$lock" "$lock.stale.$$" && rm -rf "$lock.stale.$$"` — the rename is atomic, so exactly one of N
simultaneous waiters wins and the losers fall back into the normal acquisition retry. A lock created
*during* the wait is not stolen; one further cycle, then exit 3.

**Why the fallback is safe to get wrong.** Stealing a lock from a live-but-unprovable holder degrades to
last-writer-wins — which is precisely today's shipped behaviour — while the CAS guard of DS21 still
refuses the loser's stale write. Not stealing degrades to a permanent outage. The asymmetry is the
whole argument: the failure mode of reclaiming is the status quo ante, the failure mode of not
reclaiming is a tool nobody can use again. **`SIGKILL` cannot be trapped**, which is why the policy is
mandatory rather than a refinement, and why the verification plan pairs a `TERM` case (trap removes the
lock) against a `KILL` case (lock survives, staleness reclaims it).

*Declared limitation*: `mkdir` atomicity on a network filesystem is not guaranteed. A cache directory on
NFS is out of scope, stated, not worked around.

### The ownership proof (D3)

**DS23 — One `ps` invocation, a capability probe with a real negative, and three sidecar states.**

Capture and compare: `ps -o lstart= -p <pid>`, compared as a verbatim string. The whole batch is one
process: `ps -o pid=,lstart= -p <comma-separated list>` (POSIX `-p proclist`). No parsing — BSD and
procps disagree on the format and it does not matter, because the same binary on the same host produced
both strings and equality is the only operation.

The probe must reject a `ps` that *ignores* the flags rather than failing on them, which is what busybox
does. Two conditions, and the second is the negative that makes the first a check:

1. `ps -o lstart= -p $$` exits 0 and emits **exactly one** non-blank line.
2. `ps -o lstart= -p 1` also emits **exactly one** line. A `ps` that ignores `-p` prints the whole
   table, which on any host running this probe contains at least the shell and `ps` itself.

| Sidecar `lstart` | Meaning | Consequence |
|---|---|---|
| a string | captured, comparable | mutation permitted once it re-matches |
| `null` | `ps` on this host cannot supply it | **report-only, permanently** — never a mutation target |
| key absent | never captured — an older or truncated record | unproven **and** the sidecar is reported damaged |

Three states, not two, for the same reason `writes: []` is not an absent `writes`: "checked, and this
host cannot" must not read as "nobody looked". **On two of the three CI platforms `lstart` is
unavailable** — alpine's busybox `ps` and Git Bash's MSYS `ps` both fail the probe — so the degraded
path is the common one in CI and must be exercised there, not treated as an edge case. Note also that
`lstart` has one-second resolution: the composite proves *the pid was not recycled since capture*,
which is exactly the claim needed, and nothing stronger.

The probe block is byte-identical in `with-lock.sh` and `reap.sh`. **Alternative rejected**: a third
sourced script — `scripts/` is the folder contract's place for helpers an agent *invokes*, and a
library nobody calls directly does not belong there. CI asserts the two copies match, with a mutated
copy as the negative.

### Label application at launch (D2)

**DS24 — Labels are inserted at a declared anchor inside the template, not appended to it. No anchor, no launch.**

The shipped example's own `overlayCommand` proves suffix-append wrong:
`docker compose --project-directory {{worktree}} run --rm --no-deps --publish {{port}}:8080 catalog-api`
— appending `--label …` after `catalog-api` makes it the container's **COMMAND**, not an option.
Options must precede the service operand.

| Template shape | Anchor | Result |
|---|---|---|
| `… docker [compose] … run …` | immediately after the first `run` token that follows a recognised launcher token | insert `--label k=v` per label |
| `… docker … create …` | after `create` | insert |
| `… docker compose … up …` | **none** — `up` takes no label flag | **refuse the launch** |
| launcher present, no anchor token | none | **refuse the launch** |
| container kind naming no recognised launcher at all | none | **refuse the launch** |
| the only launcher text sits inside a quoted string — `echo "docker run x" \| sh` | none: an anchor is never matched inside a quoted string, or the insertion edits a string literal and the container still launches bare | **refuse the launch** |
| host kind | — | outside this table: no labels, sidecar registration |

Recognised launcher tokens: `docker`, and by CLI compatibility `podman` and `nerdctl`; the report pass
queries each launcher its own templates named, so recognising them costs nothing and avoids a
gratuitous refusal.

**The entry's `kind` selects the rows, not whether a launcher token happens to appear.** A
container-kind entry with no anchor is refused however the anchor went missing — absent launcher,
unrecognised launcher, launcher inside a string, or `up` — and a host-kind entry is outside the rule
entirely. The quoted-string row is amendment A5's and was written after this table; it is also why the
original single row "no recognised launcher token ⇒ host kind" had to be split, because
`echo "docker run x" | sh` on a container-kind entry exposes no recognised launcher and must still be
refused rather than registered in the sidecar. A pipe, wrapper, or redirect *after* the anchor stays
accepted: insertion lands ahead of it.

| | |
|---|---|
| **Choice** | Anchor insertion, with a structural post-condition: the resulting token sequence equals the original with **only** the label elements added at the anchor — program, operand order, and every other element unchanged. Values are placed one per argv element, or single-quoted as one shell word, per `references/discovery.md` §6. |
| **Alternative** | Append at the end (D2's literal wording). **Alternative**: synthesise the labels into `overlayCommand` at discovery time. **Alternative**: fall back to sidecar registration when a container template cannot be labelled. |
| **Rationale** | Suffix-append breaks the discovery-preferred form, which is the form `references/discovery.md` §3 *mandates*. Anchor insertion is also strictly **more permissive** than D2 forecast: a template that pipes or wraps (`cd X && docker compose run … \| tee log`) keeps working, so D2's accepted cost shrinks rather than binds. Refusing an `up`-shaped template introduces no new constraint — §3 already forbids the whole-stack `up` for `overlayCommand`, so the refusal enforces an existing rule and its remedy is the line discovery would have produced anyway. **Silent fallback to the sidecar is the one option that must not exist**: the pid of a `docker compose run` client is not the container, so a container recorded by pid is a false ownership record, and killing it kills the CLI while the container keeps the port. |

Schema `overlayCommand` description gains exactly this, and nothing else (no field, no version bump):

> A container-kind template MUST expose a label anchor — the token `run` (or `create`) following the
> launcher program, before the service operand — because the launch inserts `--label` flags there.
> A whole-stack `up` form, or a launcher this skill does not recognise, has no anchor; an unlabelled
> container cannot be reclaimed, so that launch is refused rather than run untracked. Insertion adds
> the label elements and changes nothing else.

### The sidecar and its reconciliation (D1)

**DS25 — Array of records, all-lowercase keys, `[]` and absent are different claims.**

`${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.processes.json`

```jsonc
{ "version": 1, "repo": "<hash8>", "at": "2026-07-31T12:00:00Z",
  "overlays": [ { "service": "storefront", "worktree": "/abs/physical/path", "port": 5174,
                  "pid": 41234, "lstart": "Wed Jul 30 12:00:00 2026" } ] }
```

| Rule | Detail |
|---|---|
| Keys are all lowercase | **Load-bearing, not cosmetic.** `.github/scripts/check_schema.py` collects every backticked camelCase token in `SKILL.md` and `references/*.md` and requires it to be a field of `manifest.schema.json`. A backticked `` `capturedAt` `` in `references/reaping.md` would fail CI, and widening `FOREIGN` to admit it would weaken a check that file exists to keep able to fail. Lowercase keys make the constraint structural. |
| Array, not a keyed map | The natural key is `(worktree, service)` — two worktrees running one service is the skill's whole purpose — and both halves are unconstrained strings, so a `"a::b"` composite would be a parsing hazard on exactly the Gradle and Bazel unit names `acceptedRisks` already had to accommodate. Uniqueness is an invariant instead: at most one record per `(worktree, service)`, enforced by the rewrite. |
| Growth is bounded | Every write emits only records the reconciliation kept, so the file is bounded by live overlays, never by history. |
| `"overlays": []` ≠ file absent | `[]` is *checked, and none*. An absent file is *unknown*. The report must print `host overlays: unknown (registry missing)` and must never print a zero for it. |

**DS26 — The runtime wins; the report computes the reconciliation and writes nothing.**

| Sidecar record | Runtime evidence | Verdict |
|---|---|---|
| `(pid, lstart)` re-match | worktree in `git worktree list` | live, keep |
| `(pid, lstart)` re-match | worktree **absent** | **orphan** — the only mutation target for a host kind |
| pid absent from `ps` | — | dead; dropped at the next write |
| pid live, `lstart` differs | — | **recycled pid** — drop, never act, and say why |
| `lstart` is `null` | any | unproven; report, never act |
| no record, container labelled | — | container kind; the label is the record |
| file absent or unparseable | — | `unknown`, plus a damaged-registry line |

**Choice**: the report pass persists nothing; the next legitimate write (a launch registration, or a
completed mutation) commits the reconciled set. **Alternative**: rewrite the sidecar on every
invocation. **Rationale**: D4 makes the default report-only and D9 obligation 3 makes read paths
lock-free; a pass that rewrote a file on every run would need the lock on every run and would make
"the report acquires no lock" false. Because every reader re-runs the reconciliation, **a sidecar that
is never rewritten can still never cause a wrong action** — a stale row is re-tested against the
runtime before it means anything.

**DS27 — Path comparison is normalised on both sides, or the reaper kills live work.**

The liveness test compares a stored worktree path against `git worktree list`. On macOS a worktree under
`/tmp` stores as `/private/tmp/…` after `pwd -P` but may be reported the other way; either mismatch reads
as *worktree gone*, and the consequence is stopping a live overlay. So: the label value and the sidecar
`worktree` are written as `CDPATH= cd -- <path> && pwd -P` at launch, the porcelain output is normalised
the same way before comparing, and **a path that cannot be normalised is unproven, never orphaned**.
Read the list as `git -c core.quotePath=false worktree list --porcelain`, parsed
`awk '/^worktree /{print substr($0,10)}'`; `-z` is not used because it postdates the declared git 2.5+
floor. A path git still C-quotes (control characters, embedded quotes) is reported unresolvable — the
same fail-safe direction `fingerprint.sh` takes with `-`.

### The report pass (D5, D6)

**DS28 — Four processes, one file read, and a named degradation when `docker` is absent.**

| # | Command | Cost | Absent ⇒ |
|---|---|---|---|
| 1 | `git -c core.quotePath=false worktree list --porcelain` | 1 process | git is unconditional; no degradation |
| 2 | `docker ps --all --filter label=stackgraft.repo=<hash8> --format <tab-separated>` | 1 process | `degraded<TAB>docker-unavailable` |
| 3 | `docker ps --all --format <tab-separated>` — legacy/port scan, **report-only** | 1 process | same line |
| 4 | `ps -o pid=,lstart= -p <all sidecar pids>` | 1 process, batched | `degraded<TAB>lstart-unsupported` |
| 5 | read the sidecar, no lock | 1 read | `unknown`, per DS25 |

Availability is one `command -v docker` (one argument — busybox `command -v` reports only its first).
When it is absent, or the call exits non-zero, the container half of the report is **unavailable**, which
is not **zero**: the same distinction as a missing sidecar, one rule applied twice. The `--format` string
is built with a literal tab from `tab=$(printf '\t')` rather than relying on the CLI's own `\t`
expansion.

**Why query 3 does not break D6.** D6 requires every *reap* query to filter on `hash8`; query 3 is
unfiltered because unlabelled legacy containers are unfindable by a label filter by construction (T1).
The scoping guarantee is structural, not a promise: **the mutation path takes its target list only from
query 2's output**, so query 3's rows can only ever produce a report line. Its rows are filtered in
`awk` against `portPolicy.ranges` and printed as `legacy<TAB><id><TAB><ports>` with the standing
declaration that the list is incomplete by construction.

*Hazard, stated qualitatively per house rule*: an unresponsive Docker daemon can make query 2 or 3 hang,
and no portable timeout exists (`timeout` is absent from at least one supported platform). Not
worked around; declared.

**DS29 — `reap.sh` is a collector and a guarded actuator. It parses no JSON.**

```
usage:  sh scripts/reap.sh [-C <repoRoot>] report <hash8>
        sh scripts/reap.sh [-C <repoRoot>] stop   <hash8> <target>...
        sh scripts/reap.sh [-C <repoRoot>] remove <hash8> <target>...
target: c:<container-id>          |  p:<pid> <recorded-lstart>   (two arguments)
stdout: tab-separated records — worktree / container / legacy / process / degraded / refused
exit:   0 ok · 2 usage · 3 a target failed its proof (nothing acted on) · 4 environment
```

**Choice**: the agent parses the sidecar and passes the recorded identities as arguments; the script
re-verifies each target **inside itself**, immediately before acting. **Alternative**: let the script
read the sidecar. **Alternative**: let the agent decide and have the script act. **Rationale**: the
script cannot read the sidecar — parsing JSON needs a tool the runtime constraints forbid, and
`openspec/config.yaml` already records that the helpers never touch JSON. And the proof must live in the
actuator, not in the caller: an agent that never opened `references/reaping.md` must still be unable to
kill something unproven.

Two guarantees fall out of the shape:

- **`baseStack` is unreachable as a target, structurally.** A `c:` target is re-verified with
  `docker ps --all --filter label=stackgraft.repo=<hash8> --filter id=<id> --quiet` and must come back;
  base-stack containers carry no `stackgraft.repo` label because only an overlay launch writes one. A
  second condition covers the case of a repository that writes the label itself: a candidate whose
  `stackgraft.worktree` is **present** in `git worktree list` is never a target under any flag.
- **D8's corollary is a filter, not a comment.** Under `stop`, a container whose state is not `running`
  is reported and skipped; under `remove`, it is a target. `stop` uses `docker stop`; `remove` uses
  `docker rm -f`. A `p:` target is `kill` under `stop`; `remove` has no meaning for a process and is a
  usage error.
- A container carrying `stackgraft.repo` with a `stackgraft.labels` value this skill does not recognise
  is **reported, never acted on** — the same fail-safe direction as an unrecognised `schemaVersion`.

### Body and frontmatter budgets (T4)

**DS30 — Slice 1 is net −34, not net ≤ +0, because the binding constraint is the sum.**

Measured with the tool the house design fixed:
`awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' skills/stackgraft/SKILL.md` → **497** today
(recount at implementation; this design's arithmetic was derived by the same rule, section by section).

| Slice 1 change | From | To | Δ |
|---|---:|---:|---:|
| Hard Rule 3 swap: `Never kill a process you did not start.` → the composite-identity rule | 9 | 35 | **+26** |
| Step 9 gains `sh scripts/with-lock.sh` | 11 | 14 | **+3** |
| Step 8 gains `per references/reaping.md` (labels actually get applied) | 12 | 14 | **+2** |
| References bullet 1 gains `references/reaping.md` and `scripts/with-lock.sh` | 7 | 9 | **+2** |
| Activation Contract compaction | 37 | 27 | −10 |
| Step 1 — the `CDPATH=`/`--git-common-dir` recipe is verbatim in `discovery.md` §0 | 29 | 20 | −9 |
| Step 2 — the `hash8` recipe and discard rules are verbatim in `discovery.md` §0 and §5 | 36 | 26 | −10 |
| Decision Gates rows 1–3 collapsed into one (step 3 already delegates to `discovery.md`) | 38 | 17 | −21 |
| Gates: `Shared/common dir changed` | 13 | 9 | −4 |
| Gates: `Port needed outside the range` | 13 | 10 | −3 |
| Gates: `Changed paths map to nothing` | 15 | 13 | −2 |
| Hard Rule 5 (`/health`) — verbatim in `traps.md:13` | 14 | 12 | −2 |
| Hard Rule 6 (manifest is a cache) | 18 | 16 | −2 |
| Hard Rule 7 (quoting) | 10 | 9 | −1 |
| Step 4 (diff) | 14 | 12 | −2 |
| Step 7 (`pick-port.sh`) | 23 | 22 | −1 |
| **adds +33 · cuts −67 · net** | | | **−34** |

**Slice 1 lands at 463.** Slice 2 then adds two Decision Gate rows (11 + 10), one report Execution Step
(11) and `scripts/reap.sh` in References (1) = **+33**, landing at **496 ≤ 500**, inside its own +40
ceiling.

**The correction T4 needs.** "Slice 1 net ≤ +0" and "slice 2 ≤ +40" and "body ≤ 500" are jointly
satisfiable, but *net ≤ +0 alone is not sufficient*: a slice 1 that lands at 497 leaves slice 2 three
words against a forty-word ceiling. The binding constraint is `slice1_out + slice2_delta ≤ 500`, which
is why slice 1 is designed to −34 rather than to 0. Nothing in the proposal is unworkable here; the
target is under-specified, and this is the number that makes both stated ceilings true at once.

**Exact Hard Rule text for slice 1, 35 words** (replaces `Never kill a process you did not start.`):

> - Never stop a process without proof it is yours: a recorded `(pid, lstart)` that still matches, per
>   `references/reaping.md`. No record, no match, no action; a port, the manifest and the user are not
>   proof.

**DS31 — Sealing: the wording contract, and a grep that can fail.**

Same three properties DS2 fixed for the shared-state rule, restated for this one:

| Property | Requirement | Violated by |
|---|---|---|
| P1 Precondition, not procedure | The rule may state *that* a matching recorded identity is required and *where* the procedure lives. It MUST NOT state any condition under which stopping is permitted. | Any body text naming a permitting outcome. |
| P2 Absence is a refusing value | "no record" is written as a refusing state, beside "no match". | Wording like "verify ownership before stopping" with no stated default. |
| P3 Non-delegable source | A port, the manifest, and the user are each excluded as proof. | "unless you are sure", "unless the manifest says". |

The reap verdicts are named **`REAP`** and **`REPORT`** in `references/reaping.md`, which gives the body
a greppable seal: `verify.sh`'s existing case-sensitive loop over `REUSE`/`ISOLATE` gains `REAP`. The
body never uses that spelling, so an agent holding only the body can reach refusal and nothing else.

**DS32 — `compatibility` has 6 bytes of headroom, so the `lstart` note must be paid for.**

`verify.sh` measures `awk -F'"' '/^compatibility:/{print length($2)}'` against a cap of `< 500`. POSIX
`awk` counts **bytes** in the C locale, and the string's one em-dash is three of them: 492 characters
measure **494**. The note the proposal owes — roughly *"Host-overlay ownership needs `ps` with `lstart`;
busybox and MSYS have none, so those overlays are report-only."* — is about 97 bytes.

Named donor, −124 bytes, in the same sentence: the minimal-image enumeration
(*"Stock macOS, mainstream Linux and Git for Windows carry both; minimal images do not — alpine,
debian-slim and distroless ship no git, distroless no shell. Install git where a package manager exists
(apk add git)."*) compacts to *"Minimal images often lack both — install git where a package manager
exists (apk add git)."* Result ≈ 467 bytes. The byte-vs-character distinction is stated here because it
means the shipped check is already two bytes stricter than it reads.

## Data Flow

```
launch ──► overlayCommand ──anchor insert (DS24)──► docker run --label stackgraft.* ──► container
   │                       no anchor ──► REFUSE
   └── host kind ──► ps -o lstart= -p <pid> (DS23) ──┐
                                                     ▼
                        payload ──► with-lock.sh <dest> <payload> <expected>  (DS21)
                                        │   mkdir lock ─► owner ─► cp ─► mv
                                        └── exit 5 ─► re-read, re-merge, retry ≤3

every invocation (DS28):
   git worktree list ──┐
   docker ps --filter label=stackgraft.repo=<hash8> ──┤
   docker ps (legacy, report-only) ───────────────────┼──► reconcile (DS26, runtime wins)
   ps -o pid=,lstart= -p <pids> ──────────────────────┤        │
   sidecar (no lock) ─────────────────────────────────┘        ├──► report + held ports ─► pick-port excludes
                                                               └──► orphans ──flag──► reap.sh stop|remove
                                                                        (re-proved inside the actuator)
```

## File Changes

| File | Action | Slice | Description |
|---|---|---|---|
| `skills/stackgraft/SKILL.md` | Modify | 1 | Hard Rule 3 swap; step 8 pointer; step 9 `with-lock.sh`; References; the DS30 compactions; `compatibility` per DS32 |
| `skills/stackgraft/SKILL.md` | Modify | 2 | Two Decision Gate rows; the report Execution Step; `scripts/reap.sh` in References |
| `skills/stackgraft/references/reaping.md` | Create | 1 | Label contract and the `stackgraft.labels=1` constant; anchor table; sidecar shape; `(pid, lstart)` capture and probe; the lock discipline |
| `skills/stackgraft/references/reaping.md` | Modify | 2 | Liveness procedure; reconciliation table; `REAP`/`REPORT` verdicts; refusal cases; legacy reporting |
| `skills/stackgraft/references/discovery.md` | Modify | 1 | §6 gains the label-insertion step beside the existing `isolation.env` and `overlayIdentity` launch obligations |
| `skills/stackgraft/references/traps.md` | Modify | 1 | Pid reuse; the cwd proof has no referent once the worktree is gone; last-writer-wins on a concurrently rewritten manifest; **the path-spelling trap of DS27** |
| `skills/stackgraft/references/traps.md` | Modify | 2 | The unlabelled-legacy blind spot |
| `skills/stackgraft/scripts/with-lock.sh` | Create | 1 | DS21 + DS22 |
| `skills/stackgraft/scripts/reap.sh` | Create | 2 | DS29 |
| `skills/stackgraft/assets/manifest.schema.json` | Modify | 1 | `overlayCommand` description only (DS24). No field, no `schemaVersion` bump |
| `.github/scripts/verify.sh` | Modify | 1,2 | The new checks below |
| `README.md` | Modify | 1,2 | Status |

**Slicing correction.** D7's table places `references/reaping.md` in slice 2, but slice 1's Hard Rule
names it and `verify.sh` resolves every backticked `references/…` link — slice 1 would fail its own CI
on a dangling link, and slice 1's label contract would have no home. The file is therefore **created in
slice 1 with its instrumentation half and extended in slice 2**, which matches the proposal's own
content list for it ("label contract, sidecar shape, liveness procedure, reconciliation, refusal
cases") better than deferring the whole file does. `references/discovery.md` is added to slice 1 for the
same reason: §6 already owns launch-time obligations, and the label insertion is one.

## Verification Plan

`openspec/config.yaml` records no test runner. These extend `.github/scripts/verify.sh`, which already
pairs every assertion with a negative; every row below keeps that discipline.

| # | Positive assertion | Paired negative |
|---|---|---|
| 1 | `with-lock.sh`, `reap.sh` pass `dash -n` and carry a shebang | existing loop fails on a syntax error |
| 2 | The DS23 probe block is byte-identical in both scripts | a copy with one byte changed must fail the check |
| 3 | Serialised writers: A reads, B reads, A commits, B commits with the stale `<expected>` ⇒ exit 5, A's entry intact | B commits with a re-read `<expected>` ⇒ exit 0 and the destination *is* replaced — proving 5 is a refusal, not an inability to write |
| 4 | Abandoned lock whose `owner` names a dead pid ⇒ reclaimed, exit 0, within the bound | `owner` naming a **live** pid with its true `lstart` ⇒ exit 3, destination byte-identical |
| 5 | Lock with no `owner` file ⇒ reclaimed by the time bound | a lock created *during* the wait ⇒ not stolen, exit 3 |
| 6 | `TERM` to a holder ⇒ the lock directory is gone | `KILL` to a holder ⇒ the lock **remains**, and the next writer reclaims it by staleness |
| 7 | The report pass completes, exit 0, while a writer holds the lock | the report leaves no `.lock` directory behind — it must never create one |
| 8 | ubuntu/macOS: the `lstart` probe reports supported | alpine and Git Bash: the probe reports unsupported, the sidecar records `lstart: null`, and a mutation on that record is refused |
| 9 | A stub `ps` on `PATH` that honours `-p` ⇒ probe supported | a stub that ignores `-p` and prints two lines ⇒ probe **unsupported** |
| 10 | `reap.sh stop` with a live pid and its true `lstart` acts (on a disposable process) | the same pid with a wrong `lstart` ⇒ exit 3, process alive, message names the identity mismatch |
| 11 | `docker compose run --help` advertises `--label` | `docker compose up --help` does **not** — grounding the anchor table's `up` refusal |
| 12 | Each legal fixture template yields a command equal to the original plus the label elements at the anchor | an `up`-shaped template and a launcher-less container template are both refused, and the message names the anchor |
| 13 | A launched overlay carries all five labels (`docker inspect --format '{{index .Config.Labels "stackgraft.repo"}}'`, ×5) | a container launched without insertion carries none and is reported as `legacy`, never as an overlay |
| 14 | Two sibling repos: the `hash8`-filtered query returns only its own | the unfiltered query returns both — proving the filter is what scopes it |
| 15 | `reap.sh stop <hash8> c:<labelled orphan>` acts | the same call for an unlabelled base-stack-shaped container, and for a labelled container whose worktree is live, both refuse |
| 16 | Sidecar with `"overlays": []` ⇒ the report says zero | sidecar absent ⇒ the report says `unknown`, and the zero wording must **not** appear |
| 17 | Under `stop`, an exited container is reported and skipped | under `remove`, the same container is a target |
| 18 | Body ≤ 500 words; slice 1 recorded at 463, slice 2 at 496 | existing check fails over 500 |
| 19 | Body contains no `REAP` (loop extended) | the loop detects `REAP` in a fixture line — proving it can fail |
| 20 | `compatibility` < 500 bytes with the `lstart` note | existing check fails when over |
| 21 | `references/reaping.md`, `scripts/with-lock.sh`, `scripts/reap.sh` resolve | existing link loop fails on a dangling path |
| 22 | `check_schema.py`'s cross-check still passes with `reaping.md` added | its existing self-test proves the cross-check can fail |
| 23 | alpine (no docker): report exits 0 and emits `degraded<TAB>docker-unavailable` | ubuntu (docker present): that line must **not** appear |
| 24 | Portability grep stays clean | the new files must not name `jq`, `python3`, or `sha256sum` — **including in the negative**, since the grep is case-insensitive and does not read intent |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | **Applicable** — `overlayCommand` is repository data that this change now *modifies* before execution | DS24: closed anchor table, structural post-insertion check (label elements added, nothing else changed), label values as one argv element or one single-quoted word per `discovery.md` §6, refusal where no anchor exists | Fixture table of templates, one refusal per rule (rows 11–13) |
| Git repository selection | **Applicable** — `git worktree list --porcelain` decides liveness, and a path-spelling difference decides *kill or not* | DS27: both sides normalised with `CDPATH= cd -- … && pwd -P`; `core.quotePath=false`; an unnormalisable path is unproven, never orphaned; `-C <repoRoot>` mirrors `fingerprint.sh` | Run from a linked worktree, a subdirectory, and a symlinked spelling; the symlinked case must **not** read as orphaned |
| Process and container termination *(row added — this is the change's actual new hazard)* | **Applicable** — `docker stop`, `docker rm -f`, `kill` | DS29: proof re-verified inside the actuator; `c:` targets re-verified through the label filter; `p:` targets re-verified by `(pid, lstart)`; a live worktree disqualifies any target; unrecognised `stackgraft.labels` reports only | Rows 10, 15, 17 |
| Commit state | **N/A** — the reaper reads no index, no diff, and no commit | — | — |
| Push state | **N/A** — the skill never pushes | — | — |
| PR commands | **N/A** — no VCS/PR automation | — | — |

## Migration / Rollout

No manifest migration: `schemaVersion` stays 2 and only one `description` string changes, so no cache is
invalidated. Slice 1 ships inert-looking — it instruments and never reports — which is intended (D7).
Slice 2's report is empty on first run for every overlay launched before slice 1, and must say so
rather than print an empty list. Rollback is reverting the merge: labels on running containers become
inert metadata, the sidecar is orphaned and ignored by a reader that does not know it, and the manifest
write reverts to its unserialised form.

## Open Questions

- [ ] **Blocking if false** — does `docker compose run` accept `-l`/`--label`? The v2 documentation says
      yes and this design rests on it, but it is unverified here. One command settles it
      (`docker compose run --help`), and it is verification row 11. If it does not, D2's only anchor for
      compose-derived templates is gone, plain `docker run` becomes the sole labelled form, and D2 must
      be reopened rather than worked around.
- [ ] Non-blocking: `docker ps --format` field availability (`.State`, `.Label "key"`) across the
      Docker versions users actually run. Fail-safe either way — a missing field degrades a report line,
      never a mutation decision.
- [ ] Non-blocking: `podman` and `nerdctl` are recognised on CLI compatibility alone, unverified. A
      wrong guess produces a refused launch, not an unlabelled one.
- [ ] Non-blocking: `find -newer` mtime granularity under MSYS. Only the fallback branch of DS22 depends
      on it, and only where `lstart` is already unavailable — which on Git Bash it is.
- [ ] Non-blocking, carried from the proposal's Q2 residual: whether the editor's cleanup sweep deletes
      the directory or only suggests it. It constrains what the report may claim about *why* a worktree
      vanished, not whether it vanished.
