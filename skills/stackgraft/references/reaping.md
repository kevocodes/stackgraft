# Overlay ownership

An overlay outlives the worktree that created it. Deleting a worktree is one click in the editors this skill exists for, and none of them offer a destroy hook, so the survivor keeps listening on a port that is already in an allowlist, serving a branch that no longer exists. The next run either collides — loud, tolerable — or lands a request on the squatter and reads it as a pass.

This file is the launch-time half of the answer: what an overlay records about itself, where that record lives, and how a later run **proves** a container or process is this repository's before anything at all is decided about it. It stops nothing and removes nothing. Ownership is recorded on objects that outlive the manifest, because the manifest is a cache and a cleaner may wipe it — an overlay whose record was wiped is invisible, not absent.

## 1. The label contract

Every container started as an overlay carries all five labels, and they are supplied **at creation**. A container therefore either exists carrying all five or does not exist; there is no post-hoc labelling step, and nothing is ever labelled after the fact to make it eligible.

| Label | Value |
|---|---|
| `stackgraft.labels` | `1` — the version of this contract |
| `stackgraft.repo` | this repository's `hash8`, derived exactly as the manifest filename derives it |
| `stackgraft.worktree` | the overlay worktree's absolute physical path, normalised per §5 |
| `stackgraft.service` | the manifest service key |
| `stackgraft.port` | the published host port |

**Fewer than five is not ownership.** A container carrying `stackgraft.repo` but missing `stackgraft.worktree` is not owned by any run: it is excluded from every candidate set and reported as unowned. Partial labelling is the shape of a launch that went wrong, and reading it as ownership is how a run acts on something it never started.

**Every value is passed as one shell word.** A worktree path holds whitespace routinely, so a raw substitution splits `stackgraft.worktree` into a label and a stray operand. Same discipline as `references/discovery.md` §6: one argv element, or one single-quoted word.

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
| no recognised launcher token | none — this is a host kind | no labels; register in the sidecar (§4) |

Recognised launcher tokens are `docker`, and by CLI compatibility `podman` and `nerdctl`.

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
| `docker compose --project-directory {{worktree}} up catalog-api` | `up` is whole-stack and takes no label flag, so there is no anchor. `references/discovery.md` §3 already forbids `up` here; the remedy is the single-unit run form it would have produced anyway |
| `cd {{worktree}}/apps/storefront && npm run dev -- --port {{port}}` | no recognised launcher token, so no container to label — this is a host kind and belongs in §4, not in this table |
| `docker --context remote catalog-api` | a recognised launcher with no `run` or `create` token after it: nothing to insert against |
| `echo "docker run x" \| sh` | the only launcher text sits inside a quoted string. No anchor is found, nothing is written into the string literal, and the launch is refused rather than run bare |

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

The script writes exactly three things: its lock directory, one empty staleness reference beside the destination, and the rename of the payload into place. It composes no content and parses no JSON — the agent owns the bytes, and the script owns only the moment they land.
