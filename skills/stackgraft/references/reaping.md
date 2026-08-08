# Overlay ownership

An overlay outlives the worktree that created it. Deleting a worktree is one click in the editors this skill exists for, and none of them offer a destroy hook, so the survivor keeps listening on a port that is already in an allowlist, serving a branch that no longer exists. The next run either collides — loud, tolerable — or lands a request on the squatter and reads it as a pass.

This file is the launch-time half of the answer: what an overlay records about itself, where that record lives, and how a later run **proves** a container or process is this repository's before anything at all is decided about it. It stops nothing and removes nothing. Ownership is recorded on objects that outlive the manifest, because the manifest is a cache and a cleaner may wipe it — an overlay whose record was wiped is invisible, not absent.

## 1. The label contract

Every container started as an overlay carries all five labels, and they are supplied **at creation**. A container therefore either exists carrying all five or does not exist; there is no post-hoc labelling step, and nothing is ever labelled after the fact to make it eligible.

| Label | Value |
|---|---|
| `stackgraft.labels` | `1` — the version of this contract |
| `stackgraft.repo` | this repository's `hash8`, derived exactly as the manifest filename derives it |
| `stackgraft.worktree` | the overlay worktree's absolute physical path, normalised per *Path normalisation* (section 6) |
| `stackgraft.service` | the manifest service key |
| `stackgraft.port` | the published host port |

**Fewer than five is not ownership.** A container carrying `stackgraft.repo` but missing `stackgraft.worktree` is not owned by any run: it is excluded from every candidate set and reported as unowned. Partial labelling is the shape of a launch that went wrong, and reading it as ownership is how a run acts on something it never started.

**Every value is passed as one shell word.** A worktree path holds whitespace routinely, so a raw substitution splits `stackgraft.worktree` into a label and a stray operand. Same discipline as `references/discovery.md` section 6: one argv element, or one single-quoted word.

**`stackgraft.labels` is versioned independently of `schemaVersion`.** Raising it takes effect on the next launch and invalidates no cache, because the label text is never written into a manifest. A live container whose `stackgraft.labels` value this run does not recognise is unproven: reported, never acted on — the same fail-safe direction an unrecognised `schemaVersion` takes.

**No `overlayCommand` value ever contains a `stackgraft.` label.** `overlayCommand` is discovered from the repository and cached; synthesising the labels into it would put this contract in every user's cache, where it drifts the moment the contract changes. The labels are applied by the skill at launch, next to the version constant, which is here.

## 2. Where the labels go: the anchor

Labels are **inserted at an anchor inside the command**, never appended to it. The shipped example proves why: its `overlayCommand` ends at the service operand, so a `--label` appended after `catalog-api` becomes the container's COMMAND rather than an option. Options precede the operand.

| Template shape | Anchor | Result |
|---|---|---|
| `… docker [compose] … run …` | immediately after the first `run` token following a recognised launcher token | insert one `--label k=v` element per label |
| `… docker … create …` | after `create` | insert |
| `… docker compose … up …` | none — `up` takes no label flag | **refuse the launch** |
| recognised launcher, no anchor token after it | none | **refuse the launch** |
| container kind naming no recognised launcher at all, quoted launcher text included | none | **refuse the launch** |
| host kind | — | outside this table: no labels; register in the sidecar (section 4) |

Recognised launcher tokens are `docker`, and by CLI compatibility `podman` and `nerdctl`.

**The entry's `kind` selects the rows, not whether a launcher token happens to appear.** A container kind with no anchor is refused however the anchor went missing; a host kind is outside this table altogether and is never refused by it.

Three rules the insertion may not bend:

- **The post-condition is structural.** The resulting token sequence equals the original with **only** the label elements added at the anchor. Program, operand order, and every other element are unchanged. Read the composed line back before running it and check exactly that.
- **An anchor is never matched inside a quoted string.** `echo "docker run x" | sh` contains the text but exposes no anchor: inserting there would edit a string literal and the container would still launch bare. No anchor found means refuse, not insert-anyway.
- **A pipe, wrapper, or redirect after the anchor is not grounds for refusal.** Insertion lands immediately after the `run` token, ahead of the pipe, so the labels reach the launcher and the container starts correctly labelled.

**Refusal is the only alternative to labelling.** An unlabelled container cannot be reclaimed and is invisible to every later run, so a container-kind entry with no anchor fails loudly at launch, naming the service and the offending entry. It is never launched unlabelled instead, and it never silently falls back to sidecar registration: the pid of a `docker compose run` client is not the container, so a container recorded by pid is a false ownership record — killing that pid kills the client while the container keeps the port.

Templates that hand the whole command to an interpreter stay refused by the deny-list in `references/shared-state.md`, which is where that rule already lives.

## 3. `overlayCommand` fixtures

One row per rule above. A template that is not in the accepted shapes is refused, and the refusal names the anchor.

**Accepted — the labels reach the launcher:**

| Template | Anchor | Composed |
|---|---|---|
| `docker run --rm --publish {{port}}:8080 catalog-api` | after `run` | `docker run --label stackgraft.repo=<hash8> … --rm --publish …:8080 catalog-api` |
| `docker compose run --rm --no-deps --publish {{port}}:8080 catalog-api` | after `run` | label elements between `run` and `--rm` |
| `docker create --publish {{port}}:8080 catalog-api` | after `create` | label elements between `create` and `--publish` |
| `docker compose --project-directory {{worktree}} run --rm --no-deps --publish {{port}}:8080 catalog-api` | after `run`, not after `catalog-api` | this is the shipped example, and it is the one that proves suffix-append wrong |
| `cd X && docker compose run --rm catalog-api \| tee log` | after `run`, ahead of the pipe | accepted: piping is not the test, the anchor is |

**Refused — the launch does not happen:**

| Template | Why |
|---|---|
| `docker compose --project-directory {{worktree}} up catalog-api` | `up` is whole-stack and takes no label flag, so there is no anchor. `references/discovery.md` section 3 already forbids `up` here; the remedy is the single-unit run form it would have produced anyway |
| `docker --context remote catalog-api` | a recognised launcher with no `run` or `create` token after it: nothing to insert against |
| `cd {{worktree}} && ./serve-catalog --port {{port}}` on a **container** kind | no recognised launcher token at all, so no anchor. A container this skill cannot label is one it can never reclaim, so it is refused rather than launched bare |
| `echo "docker run x" \| sh` | the only launcher text sits inside a quoted string. No anchor is found, nothing is written into the string literal, and the launch is refused rather than run bare |

A host kind is in neither table. `cd {{worktree}}/apps/storefront && npm run dev -- --port {{port}}` names no launcher because there is no container to name one for: it launches, carries no labels, and is recorded in the sidecar (section 4). Refusing it would refuse the ordinary case. The `./serve-catalog` row above is the same launcher-less shape on a **container** kind, and that one is refused — which is why the entry's `kind` decides and the launcher token does not.

## 4. Host kinds: the sidecar

A host-run overlay has nowhere to hang a label, so it is registered in one file per repository:

`${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/<repo-basename>-<hash8>.processes.json`

Same `hash8` derivation as the manifest, so every worktree of one repository resolves to the same sidecar and two repositories sharing a basename resolve to different files.

```json
{
  "version": 1,
  "repo": "<hash8>",
  "at": "2026-07-31T12:00:00Z",
  "overlays": [
    {
      "service": "storefront",
      "worktree": "/abs/physical/path",
      "port": 5174,
      "pid": 41234,
      "lstart": "Wed Jul 30 12:00:00 2026"
    }
  ]
}
```

| Rule | Detail |
|---|---|
| Keys are all lowercase | Load-bearing, not cosmetic. CI collects every backticked camelCase token in the shipped documents and requires it to be a field of `assets/manifest.schema.json`; a record key spelled in camelCase would either fail that check or force it to be widened, and widening it is how a check stops being able to fail. Lowercase keys make the constraint structural. |
| An array, not a keyed map | The natural key is `(worktree, service)` and both halves are unconstrained strings, so a composite key would be a parsing hazard on exactly the build-tool unit names this schema already had to accommodate. Uniqueness is an invariant instead: **at most one record per `(worktree, service)`**, enforced by the rewrite. |
| Growth is bounded | Every write emits only the records the run still holds true, so the file is bounded by live overlays and never by history. |
| `"overlays": []` is not an absent file | `[]` is *checked, and none*. An absent or unreadable file is *unknown*: name the file and say unknown. Never print a zero for it — the two are different claims, and reporting the second as the first tells the user the port map is complete when nobody looked. |

The sidecar is a second ownership store, and two stores can disagree. The direction is fixed and not negotiable per case: **the runtime wins.** A record is only ever an input to a proof, never the proof itself.

## 5. Proving a host process is yours

A pid alone proves nothing, because pids are reused: a pid recorded an hour ago may be the user's editor now. The proof is composite.

**At registration**, record `ps -o lstart= -p <pid>` exactly as emitted. **Before any action on that pid**, read it again and compare as an exact string.

The comparison never parses, normalises, reformats, tolerates whitespace, or matches partially. BSD and procps `ps` disagree on the format and it does not matter: the same binary on the same host produced both strings, so equality is the only operation the proof needs. Any inequality refuses, and the refusal names the pid and the mismatch.

This replaces the working-directory check for the orphan case, where the deleted worktree leaves that check with no referent, and supplements it everywhere else.

**The capability probe.** Two conditions, and the second is what makes the first a check:

1. `ps -o lstart= -p $$` exits 0 and emits exactly one non-blank line.
2. `ps -o lstart= -p 1` also emits exactly one line.

A `ps` that ignores `-p` — busybox does — answers the first plausibly and the second with the whole table. Without the second condition the probe passes on a host that cannot do the thing at all. The batched form for several pids is one process: `ps -o pid=,lstart= -p <comma-separated list>`. The shipped copy of this probe lives in `scripts/with-lock.sh`, between its `BEGIN lstart probe` and `END lstart probe` sentinels.

**Three states, not two:**

| Recorded `lstart` | Meaning | Consequence |
|---|---|---|
| a string | captured and comparable | the identity proof is available once it re-matches |
| `null` | this host's `ps` cannot supply it | permanently unproven — report only, under every flag |
| key absent | never captured: an older or truncated record | unproven **and** the sidecar is reported damaged |

`null` and absent are separated for the same reason `[]` and a missing file are: *checked, and this host cannot* must not read as *nobody looked*. An empty string is never recorded, because two absences would compare equal to each other and manufacture a proof out of nothing. Nor is the absence worked around with another signal — process name, command line, port, or an approximate start time each admit exactly the mistaken-identity kill the composite proof exists to prevent.

**Note the resolution, and what it costs.** `lstart` has one-second granularity, so two processes started inside the same second carry a byte-identical string — verified, not inferred: two `sleep`s launched back to back both report `Fri Jul 31 16:52:08 2026`. The composite therefore proves something narrower than *the pid was not recycled since capture*. What it actually proves is that **the pid is not now held by a process that started in a different second from the one recorded** — which refuses every recycle except one.

The residual window is the same-second recycle: the recorded process exits, the pid is reissued, and the new process starts inside the same one-second tick. That case compares equal and is acted on. It is named here rather than papered over, because nothing available closes it. Verbatim equality is what the proof mandates precisely because both strings come from one `ps` on one host, where the format is whatever that `ps` prints; a finer clock would have to be parsed out of it, and parsing is the thing this comparison refuses to do. The window is narrow — a pid must be reissued within the same second on a host whose pid space is large — and every alternative signal considered above is wider by orders of magnitude, which is the argument for this pair rather than a claim that it is exact.

## 6. Path normalisation

The worktree path is what connects a record to a live checkout, and a difference of spelling reads as *the worktree is gone*. On macOS a worktree under `/tmp` stores as `/private/tmp/…` after `pwd -P` but can be reported the other way.

So, on **both** sides: `CDPATH= cd -- <path> && pwd -P`. The label value and the sidecar `worktree` are written that way at launch; anything they are later compared against is normalised the same way before comparing. Compare the whole recorded value, never a word-split of it — paths contain spaces.

**A path that cannot be normalised is unproven, never treated as gone.** Same fail-safe direction `scripts/fingerprint.sh` takes with `-`.

## 7. Writing either cache file

The manifest and the sidecar are written under one discipline, through one script: `sh scripts/with-lock.sh <destination> <payload> <expected>`. Read paths take no lock and are never blockable by a writer.

**The lock is necessary and not sufficient.** Serialising the write does not fix last-writer-wins: two runs each read the file, each merge their own entry, and each write under a perfect lock — the loser's entry is still gone. The loss is in the read-modify-write window, not in the write. So `<expected>` is mandatory: it is `git hash-object --stdin < <destination>` as the caller read it, or `-` when the caller found no file there, and a destination that has changed since is refused.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | committed | nothing |
| 2 | usage error | fix the call |
| 3 | lock not acquired, destination untouched | report the write as **failed**, naming the file. Never report the record as stored, and never fall back to an unlocked write |
| 4 | environment failure — cache directory, copy, or rename | run manifest-less and say so |
| 5 | destination changed since `<expected>` | re-read the destination, re-merge this run's entry into what is now there, recompute `<expected>`, and retry — **at most 3 attempts**, then stop and ask |

**Both bounds, as values.** Acquisition retries `mkdir` **10 times, 1 second apart**, so the wait bound is **10 seconds**; the same 10 seconds is the staleness bound, a lock already present when the wait began and unchanged when it ended. The whole acquisition spends at most two of those bounds — **20 seconds** worst case, never an unbounded wait.

Staleness is decided by liveness first and by the clock only where liveness cannot answer. A holder whose pid is gone, or whose recorded start time no longer matches, is provably dead and its lock is reclaimed at once and the reclamation reported. A holder that is provably alive is never stolen from. Only an unprovable holder reaches the time bound, and that asymmetry is the argument: reclaiming from a live holder degrades to last-writer-wins, which the compare-and-swap guard still refuses, while never reclaiming turns one crash into a permanent outage. `SIGKILL` cannot be trapped, which is why a staleness policy is mandatory rather than a refinement.

The script writes exactly four things: its lock directory, the transient name that directory is renamed to while it is being reclaimed — the rename is what elects one waiter out of many, so the name lives for the length of one reclaim and goes with it — one empty staleness reference beside the destination, and the rename of the payload into place. It composes no content and parses no JSON — the agent owns the bytes, and the script owns only the moment they land.

## 8. The two verdicts

Every overlay this run can see resolves to exactly one of two words.

| Verdict | Meaning |
|---|---|
| **`REPORT`** | Say what is there and change nothing. The default, and the only verdict any run reaches without an explicit flag from the user. |
| **`REAP`** | Act on it — stop, or stop and remove. Reachable only for a candidate that cleared candidacy, liveness and reconciliation — sections 9, 10 and 11 — and only under the flags in section 12. |

There is no third verdict and no "probably". Everything a run cannot prove is `REPORT`, which is why an unreadable store, an absent start time, a prunable worktree and an unrecognised label version all land in the same place: they are different reasons for the same answer.

## 9. Candidacy is a closed allowlist

A container is a **candidate** only if it carries the full five-label set of the label contract in section 1 with `stackgraft.repo` equal to this repository's `hash8`. That is a positive test, and it is what puts every base-stack container outside the candidate set **by construction** rather than by exclusion: only an overlay launch ever writes `stackgraft.repo`, so a base-stack container was never in the set to be removed from it.

The difference matters because a deny-list has to be complete to be safe and an allowlist does not. A base-stack service this skill has never heard of is outside the set for free.

A second, independent condition covers the repository that writes the label itself — a compose file that hard-codes `stackgraft.repo`, or a hand-labelled container:

- A candidate publishing a port **the run passed** as a `basePort` is never a target, and the anomaly is reported. The script parses no JSON, so those ports are read out of the manifest by the run and passed as `-b <port>`, once per port; the decision they drive lives in the actuator, which sees the values and never the manifest.
- A candidate whose `stackgraft.worktree` is **present** in the worktree list is live, and live is never a target — section 10.

Each `-b` value is validated as a decimal port in 1–65535 with leading zeros stripped, the same rule `scripts/pick-port.sh` applies to its own port arguments. That is worth having on its own terms: `-b 0` and `-b 99999999` are not ports at all, and `018103` — a manifest value typed with a leading zero — would otherwise be kept as a string that matches no published port, so the container it was meant to protect would be reaped while the run looked correct. It removes typos. **It closes nothing else, and nothing below is any narrower because of it**: `1` is a valid port, so no range test can tell a wrong port from a right one.

**Those ports are evidence, and not having them is *unknown* rather than *none*.** A mutation run that passed no `-b` at all has told the actuator nothing about the base stack, and a port set nobody supplied answers *no base port matches* for every container on the host. That is a gate keyed on an optional input, which is no gate: omit the flag and the condition above silently stops applying. So a `c:` target under `stop` or `remove` is **refused outright until the run supplies at least one `-b <port>`**, and that refusal has **no override**. Its message names what is missing and nothing else, because a refusal that advertises its own bypass is not a refusal. The report path decides nothing and needs no `-b`, which keeps the benefit every invocation gets free of the requirement only a mutation carries.

**A flag asserting that the manifest records none was tried here, and removed.** Nothing in the actuator can check such a claim, so it was an unverifiable assertion that switched the whole exclusion off — the same gate-keyed-on-an-optional-input shape wearing a different name, and executed it stopped a hand-labelled base-stack container. It is not the *checked-and-none* of section 14 either: those zeros are claims about the very store the report speaks of, while that flag was checked-and-none about the **manifest** when the decision is about the base stack's **real ports** — and those two diverge in the manifest-less mode `SKILL.md` supports, where a truthful assertion would still have reaped a base-stack container.

The cost of having no override is real, accepted, and stated: a repository whose manifest records no `basePort` cannot mutate a container target until one is supplied. It is a small cost. This skill exists to overlay onto a running base stack whose ports the overlay must avoid, and `scripts/pick-port.sh` already needs those same ports, so a repository with none of them is degenerate here.

Both conditions are re-tested inside `scripts/reap.sh` immediately before it acts, not once at classification time. A run that never opened this file therefore cannot reach a hand-labelled base-stack container by leaving the flag off: with no `-b` at all every container mutation refuses, and no flag stands in for one. **That is the whole of what the port half guarantees.** Past it the exclusion is exactly as good as the values passed — and that is not a residue at the edge of the test, it *is* the test. A caller that passes a wrong port defeats it completely, whether by typo, by a stale manifest, or on purpose, and nothing here can tell a wrong port from a right one: the actuator parses no JSON, so it never sees the manifest the value was supposed to come from. **The port exclusion is caller-supplied and caller-defeatable.** Three rounds of fixes went looking for a mechanism that would close it; there is none to find under the zero-JSON constraint, and the fourth round wrote the limit down instead.

**Declared limit: past the ports it was handed, a base-stack service is not identifiable from here.** The requirement this section implements is written to that limit rather than past it. Nothing on a running container separates a base-stack one from an overlay except the port: `stackgraft.service` holds a manifest service key and the base stack runs those same services, so refusing on the name would refuse every overlay this file exists to reclaim. A compose project name would need the base project's, which lives in the manifest this script does not parse and over which the caller has no more authority than the ports it already passes.

So exactly one shape falls outside the exclusion: a container hand-labelled with this repository's complete label set, whose `stackgraft.worktree` is absent from the worktree list, and whose published port is not among the ones the run passed. **One thing keeps that shape rare, and it is not the port test.** It is the positive allowlist at the top of this section: only an overlay launch writes `stackgraft.repo`, so everything this skill never started is outside the candidate set for free, under every flag, whatever ports are passed. That half is structural. The port half is a caller's assertion the runtime cannot check, so it is stated as an accepted coverage loss — here, in `README.md`, and in the requirement itself — rather than described as closed. It is not a gap awaiting a mechanism.

## 9a. Store copies are reap targets, and the more expensive kind

A seeded copy — `references/isolation-providers.md` — is a runtime object this skill created, so it outlives its worktree exactly the way an overlay does, and it costs disk while it does. It is reclaimed here under the same rules, with **one deliberate difference**.

The target is `v:<volume-name>`, one argument, and it is reported on every invocation exactly as a container is.

**Candidacy is the same positive closed allowlist.** A copy is a candidate only if it carries the complete label set for a copy with `stackgraft.repo` equal to this repository's `hash8`: `stackgraft.labels`, `stackgraft.repo`, `stackgraft.worktree`, `stackgraft.store`. Four rather than the overlay's five — `stackgraft.service` holds a manifest service key, and a copy belongs to a store rather than to a service. An object carrying three of the four is reachable by no query this skill makes, which is the point: the set is complete or the object is not ours.

**Liveness is decided the same way**, against the worktree list of section 10: a copy whose recorded worktree is still listed belongs to work in progress and is never a target, whatever its age.

**Removal takes the removal verb *in addition to* the mutation flag, and `stop` is not available at all.** A `v:` target under `stop` is refused by name rather than downgraded, and `remove` already refuses without `-m` before any target is read. That is the real asymmetry, and it runs the opposite way to intuition: a copy is the more expensive thing to have destroyed by accident, not the less. An overlay container that should not have been stopped is restarted from its image in seconds; a copy that should not have been removed is a state nothing on this host can reproduce — the base stack has moved on since it was taken. So the cheap verb does not exist for it: the only verb a copy has is the expensive one.

**Where a copy is proven harder than a container, and where it is proven less.** Stating both, because an adversarial review found this paragraph claiming a protection that ran the other way:

- **Harder:** `hash8` is re-derived from `-C` and compared before anything irreversible runs. The argument as the caller spelled it is not evidence — a run given one repository's root and another's hash would return the second repository's copies, find its worktrees absent from the first's list, and read every one of them as an orphan. A container target is not proven this way; a copy is, because a container comes back from its image and a copy comes back from nothing.
- **Less:** there is no `-b` for a copy, and there is no port analogue to supply. A volume publishes nothing, so the base-stack exclusion here is **structural only**: only a provision writes the four labels. The shape that remains is the one section 9 already declares for containers, minus the port test — a volume hand-labelled with this repository's complete copy label set, whose recorded worktree is unlisted, **is reaped**. That is stated rather than covered, exactly as the port limit is.

**A listing row that does not carry its four fields is unknown, and unknown is never orphaned.** A label value may contain a newline, and the runtime then emits one logical row as two physical lines — the first carrying three fields, which would otherwise give the worktree and the store the *same* value, pass the completeness test, and reach an orphan verdict on a path that is really the store's. Measured on Docker 29.5.3. A row that is not exactly four fields is refused by name instead.

**The cost of that, stated rather than covered:** a copy whose recorded worktree path contains a tab or a newline is refused **for good** by this script — its row can never read as four clean fields, so there is no invocation that reclaims it. `provider-docker.sh destroy` remains the only route, and it needs a worktree you can still name. The direction is the safe one, and the residual is real.

**An object whose `stackgraft.labels` value this run does not recognise is reported and never acted on** — the same fail-safe direction section 14 takes for everything else it cannot read. A future label-set version means this run does not know what those labels mean, and acting on an object you cannot read is the failure this whole file is written against.

**An object carrying no ownership label at all is not reported, because no query reaches it.** That is the candidacy allowlist working, not a gap: the copy listing is filtered on `stackgraft.repo`, so an unlabelled volume is never returned, never classified and never removed. It is also therefore never *named* — the same structural blind spot section 13 declares for pre-label containers, and for the same reason. A report that tried to name it would have to list every volume on the host, which reaches a neighbouring repository's objects and is not ours to enumerate.

**A runtime that cannot be queried reports *unknown*, never zero copies.** This is section 14's distinction with the highest cost attached: a report that says *no copies* over a daemon that never answered tells a developer their disk is clear when it may hold gigabytes, and they will believe it because it is a number.

## 10. Liveness, decided against the worktree list

The recorded worktree path is compared against `git -c core.quotePath=false worktree list --porcelain`, parsed as `awk '/^worktree /{print substr($0, 10)}'`. `-z` is not used: it postdates the declared git 2.5+ floor.

| Recorded path | Verdict |
|---|---|
| listed, and the entry is ordinary | **live** — `REPORT`, and never a target under any flag |
| absent from the list | **orphan candidate** — the only state the flags in section 12 can escalate |
| listed, and the entry is marked prunable | **unknown** — proof of neither liveness nor absence |
| the list could not be read at all | **unknown**, for every overlay at once |
| some entry in the list will not resolve | **unknown** — a path nobody can spell might be the one being looked for |

Normalisation is the rule in section 6, and it applies to the **porcelain side**. The recorded value was already written physically at launch, so it is compared whole and never re-resolved — an orphan's directory is gone by definition, and re-resolving it would turn the single case this exists for into "unproven". A path git still C-quotes is unresolvable, which makes every `absent` answer in that run unknown instead.

Neither archiving nor sleeping a workspace removes its directory, so both leave the worktree listed and both read as live. Deleting one removes it, and that is the case this file exists for.

## 11. Reconciliation: the runtime wins, and the report writes nothing

| Stored record | Runtime evidence | Verdict |
|---|---|---|
| `(pid, lstart)` re-matches | worktree listed | live — keep |
| `(pid, lstart)` re-matches | worktree absent | **orphan** — the only host-kind target |
| pid absent from `ps` | — | dead; dropped at the next write |
| pid live, `lstart` differs | — | **recycled pid** — drop, never act, and say why |
| `lstart` is `null` | any | unproven; `REPORT`, permanently |
| no record, container labelled | — | container kind; the label *is* the record |
| store absent or unparseable | — | `unknown`, plus a damaged-registry line |

**The pid re-read is the run's, not the script's.** `scripts/reap.sh` cannot open the registry, so the run reads it, batches every recorded pid into the single `ps -o pid=,lstart= -p <comma-separated list>` of section 5, and hands each proven identity back as a `p:<pid> <recorded-lstart>` target — which the actuator then re-verifies for itself before it signals anything. Two reads of the same fact, and the second one is the one that is allowed to matter.

**The report computes this and persists nothing.** The next legitimate write — a launch registration, or a completed mutation — commits the reconciled set through the write discipline of section 7. A pass that rewrote a file on every invocation would need the lock on every invocation, and "the report acquires no lock" would stop being true.

That is safe because every reader re-runs the reconciliation: **a registry that is never rewritten still cannot cause a wrong action**, since a stale row is re-tested against the runtime before it means anything.

## 12. The flags

Two flags, and they are not one flag with two settings.

| Flags | Running orphan | Already-exited orphan |
|---|---|---|
| neither | `REPORT` | `REPORT` |
| mutation | `docker stop`, or `kill` for a host kind | reported and **skipped** — not counted as work done |
| mutation + removal | `docker rm -f -v` | `docker rm -f -v` |
| removal alone | nothing is mutated, and the run says the mutation flag is required | same |

Four consequences worth stating on their own:

- **Removal takes the container's anonymous volumes with it, and nothing else.** An image declaring `VOLUME` in its own Dockerfile gives every container of it an unnamed volume whether or not the launch asked for one, and a removal without `-v` leaves an object with no name, no label and no owner — the shape this file exists to reclaim, in the one form nothing could afterwards find. `-v` reaches anonymous volumes only: a named volume is never removed by it, so a base stack's data and every copy this skill provisions — always named — are out of its reach by construction rather than by care.
- **A stop leaves the logs readable.** An orphan is evidence of something that went wrong, and its logs are the only account of it. Freeing the port is the urgent part; freeing disk is not, which is the whole reason removal is a second flag.
- **An exited container is a target only under removal.** Stopping something already stopped is a no-op that would report as work done, and a run that counts no-ops as work is a run whose count means nothing.
- **Removal has no meaning for a process.** A `p:` target under the removal verb is refused by name, not silently downgraded to stopping it.

The mutation flag reaches `scripts/reap.sh` as its own token, `-m`, rather than being implied by the verb. An agent that never received the user's flag cannot produce that argument, and the editors this skill exists for pre-fill permission bypasses — so the confirmation cannot live in a prompt.

## 13. What the report cannot see, and why it says so anyway

A container launched before the `stackgraft.labels` contract existed carries no label. **Nothing distinguishes it from any other container on this host** — not its image, not its name, not its ports, none of which this skill wrote or can claim. There is therefore no query that finds legacy overlays: an unfiltered listing does not detect them, it lists everything and cannot say which is which, and widening the query buys noise rather than coverage while reaching a sibling repository's containers, which are not ours to enumerate.

So no query widens, and **the blind spot is stated instead**. Every report carries a standing `legacy` record that:

- names the category — overlays predating the label contract, and overlays whose worktree lives on another host;
- states that they are invisible **by construction**, not merely absent today;
- prints the command the user runs themselves, `docker ps --all`, so the check is available even though this run cannot make it;
- **claims no number, zero included**, because no query can produce one.

It prints whether or not anything was found, because there is nothing to find it with — and because the first run after instrumentation is exactly the run that looks broken without it. A reaper that is quietly partial is worse than one that is loudly partial. This is an accepted coverage loss, stated loudly; it is not a gap awaiting a mechanism.

## 14. Distinguishing checked-and-none from not-checked

Emptiness is a claim that needs evidence, never an omission. Four different sentences, and only two of them are zeros:

| Situation | What the report says |
|---|---|
| the runtime answered and matched nothing | container overlays: **zero, checked** |
| the runtime is absent or did not answer | container overlays: **unknown**, with the reason |
| the registry exists and its list is empty | host overlays: **zero, checked** |
| the registry is missing, unreadable, or damaged | host overlays: **unknown**, and the file is named |

**A missing registry is never rendered as zero host overlays.** They are different claims and only one of them is evidence; reporting the second as the first tells the user the port map is complete when nobody looked. The same rule, applied twice.

`scripts/reap.sh` answers whether each store could be **read**; the run answers what is in it, because the script parses no JSON. A registry the run cannot parse is `unknown` by that same rule.

## 15. Refusal cases

**A refusal refuses its own target and nothing else.** Each case below is reported with its reason, and the run carries on with the candidates that did prove out: every target is proven, every proven one is acted on, every unproven one is refused by name, and both sets are reported before the run exits non-zero to say some target was refused. There is nothing to re-invoke and nothing lost by naming an unprovable target alongside provable ones.

This used to read the other way — one refusal refused the whole invocation, on the argument that a run should never be half-applied and then stopped. That argument does not survive what is actually here: each stop is independent, no state spans two targets, and there is no transaction a partial run could violate. What it did cost was real, because one unprovable target withheld the reap from every orphan named beside it, and an unprovable target is the ordinary case rather than the exception — a live worktree, an unreadable store and a recycled pid all land there. A run that acts on nothing because one candidate could not be proven is not safer; it just does not work.

The same rule applies after the proof: a proven target the runtime will not act on is that target's failure, reported and counted, while the rest of the plan still runs and the `acted` record is still printed. A run that stops mid-loop leaves exactly the half-applied state this section once claimed to prevent, and hides it by suppressing the one record that says what happened.

And it applies **before** the proof, at the parsing layer, where the same shape survived one round longer. A target that will not parse — a `p:` with a non-decimal pid, an empty `c:` id, a shape that is neither — used to end the whole invocation at exit 2 with the proven orphans beside it left running and no `acted` record printed at all. A malformed target is one target's problem: it is refused by name like any other unprovable one, and the run carries on. Only what is not a target stays a usage error — the verb, the `hash8`, and the options, none of which belongs to one target and any of which leaves the run with no idea what it was asked to do.

| Case | Why it refuses |
|---|---|
| the target will not parse | a malformed target is one target's problem, not the invocation's |
| the worktree is still listed | the overlay is live; archiving and sleeping both leave it listed |
| the worktree list could not be read | liveness is unestablished, so nothing is an orphan |
| the recorded path will not resolve, or git C-quotes it | unproven, and unproven is never orphaned |
| a port **the run passed** as a `basePort` | excluded however the container is labelled, and the anomaly is reported. Only the values actually passed exclude anything — section 9 |
| no `-b` was given at all | absent is unknown, never none; the exclusion cannot be applied against a port set nobody supplied, and no flag stands in for one — section 9 |
| a `-b` value outside 1–65535 | not a port, so it is a usage error naming the value. This catches typos; it does not narrow the declared limit in section 9 |
| fewer than five labels | partial labelling is a launch that went wrong, not ownership |
| an unrecognised `stackgraft.labels` value | the same fail-safe direction an unrecognised `schemaVersion` takes |
| the recorded `lstart` is `null` or absent | permanently unproven on this host |
| `ps` here reports no start time at all | ownership cannot be proven, so nothing may be acted on |
| the pid's start time no longer matches | the pid was recycled; the refusal names both strings |
| the container's state field is missing | a mutation decision is never taken on a field that is not there |
| the runtime is unavailable | a target that cannot be re-verified cannot be acted on |

Ownership is never inferred from port occupancy, container name, image, compose project, or a manifest record. A process this run did not start is never signalled, and the manifest being deleted changes nothing about what is reapable — that is the point of recording ownership on the runtime object.

## 16. Held ports feed port selection, on the report path

The report's `held` records are what makes the stackgraft-held part of the range knowable without probing anything. Pass each one to `sh scripts/pick-port.sh <lo> <hi> <worktree> [excluded-port ...]` as **its own argument**, alongside the reserved and base ports already excluded there.

They are about occupancy and not about liveness, so a *running orphan* is held too: it holds its port exactly as firmly as a live overlay does, right up until something stops it, and port selection cares which ports are taken rather than which of them ought to be.

Three constraints on that:

- **It belongs to the report path, with no mutation flag.** The report is what every invocation runs, so this is the benefit that lands whether or not anybody ever reaps anything.
- **The knowledge is repository-local.** One registry per repository, and every container query scoped to one `hash8`, means a sibling repository's ports stay unknown. They are not excluded, they are not reaped to free them, and a collision on one is caught by the launcher's strict-port bind — which stays authoritative, because the output was always a candidate and still is.
- **Where a store could not be read, still return a candidate, and say the held-port set is short.** Refusing to pick a port because one store was unreadable trades a real capability for a hypothetical collision the strict bind already catches.
