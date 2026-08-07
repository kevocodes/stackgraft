# Isolation providers: copying a store's state

A writing pair needs its own state. Where the store offers a namespace inside the running instance, `references/shared-state.md` takes that road and nothing here is needed. Where it does not — and that is the common case, not the exception — the answer is a **seeded copy**: a second instance of the same image, started on a copy of the base stack's data.

This file is the whole of how that copy is made. `references/shared-state.md` decides *whether* a pair needs one; `references/coordination-identity.md` answers the other hazard and never this one; `references/reaping.md` reclaims a copy that outlived its worktree.

## The contract

Three operations. Not two, and **not four**.

| Operation | Takes | Answers |
|---|---|---|
| `provision` | the repository hash, the worktree, the store key, the runtime object holding its state, the image running it, and the ownership labels | a copy exists, an instance runs on it, and both are named — with the bytes and the seconds this run measured |
| `address` | the same first three | how the overlay reaches that instance: a name its runtime resolves, a published port, and any value the caller could not derive from those two |
| `destroy` | the same first three | the instance and the copy are gone, or the run fails loudly naming what it left |

**The contract varies by runtime and never by substrate.** Cloning state is the same operation whatever wrote the bytes, and it differs between a container runtime, a cluster, and a process on the host. So no operation, parameter, return value, or obligation above names an engine, and none may be added that does. A store engine released after this version is provisionable with no edit here and no edit to the shipped provider's interface — a contract that enumerated engines would be the finite table this skill deleted, walked back in through another door.

**There is no `verify` operation, and its absence is the design.** A fourth one would let the provider certify its own output — the property that had to be removed from `reap.sh` and is not being re-introduced here. Verification is issued by the agent, through the same channel `applyVia` already documents, against the address the third operation returned.

Three exit meanings, and they are the same three every script here uses: refused is `3`, a usage error is `2`, and an environment failure is `4`. **A refusal creates nothing and removes nothing** — or, where it is discovered part-way, removes what it made before reporting.

## The Docker provider

One provider ships: `scripts/provider-docker.sh`, because a local base stack already runs there.

- **The copy is taken by a second container**, mounting the source read-only and the destination writable, started from the store's own image. The base engine is never signalled, stopped, paused or reconfigured.
- **Everything engine-specific is read back from the runtime**, never guessed and never defaulted: which object holds the state, which image runs it, where that image mounts it, what environment and command the base container runs under, and which network it sits on. A fact that cannot be read is a refusal. This is what keeps the provider engine-blind — it never has to know what the bytes mean, only what wrote them.
- **The copy's size is counted in bytes inside a container**, with the volume mounted read-only, and the runtime's own report is not read. Measured on server 29.5.3 and again on 24.0.9: the runtime's disk-usage report answers `"7.34MB"`, a human string with a unit that it does not promise to keep stable, and its volume-inspection usage field answers `null` on both. Counting inside a container answers `7344130` on both, and an integer needs no parsing at all. A size that cannot be counted is a refusal, not an estimate.
- **The two numbers measure different things.** Counting inside the volume reports what it *contains*; the runtime reports what it *occupies*. They are not interchangeable, and the free-space arithmetic below uses one measure on both sides.

`address` returns the instance's name — which is what the runtime's DNS resolves for a container-run overlay — together with any port the runtime published for a host-run one. **It is a value, never a delivery**: the launch's existing channel carries it, and where no route sets it in the overlay's environment the pair refuses before launching, which is the rule `references/discovery.md` already holds every recorded identity to.

`destroy` re-finds its target rather than trusting the caller's. **The actuator re-verifies, the caller only names.**

| Guard | Detail |
|---|---|
| Scoped query only | The target is found with a label filter carrying this repository's hash and this store's key. No unfiltered listing exists in the script, so one can never reach a removal |
| Worktree equality | An object is removed only where its recorded worktree label **equals the worktree argument**, both sides normalised to an absolute physical path first. Not a prefix, not a substring, not liveness. "Destroy another worktree's copy" is unreachable without the caller naming that worktree, and a path that will not normalise matches nothing |
| No labels, or a set version this run does not recognise | Reported and left alone — the same fail-safe direction an unrecognised `schemaVersion` takes |
| Order | Instance first, copy second. A copy still attached to a running instance is one the runtime refuses to remove, and reporting that as success is the half of the leak that matters |
| Never | No prune of any kind, no bringing the base stack down with its volumes, and no removal that did not come out of a scoped query |

The same discipline runs the other way at `provision`: the label set the caller supplies is **re-verified against the arguments** before a byte is written, so a caller that names one worktree and labels another creates nothing rather than creating a copy nothing can later find.

## The second runtime, on paper

A contract that cannot describe a second runtime has failed the premise it exists for. Both below are **declared and unbuilt** — stated as a runtime nothing implements yet, never as an impossibility.

| Operation | Docker (shipped) | Kubernetes (declared, unbuilt) | Host-native (declared, unbuilt) |
|---|---|---|---|
| `provision` | create a volume, copy into it from a second container mounting the source read-only, then run the same image on it | snapshot the claim, create a new claim from the snapshot, bind a pod of the same image to it | copy the data directory, start a second engine process on another port |
| `address` | the instance name on the base network, plus whatever port the runtime published | the service's DNS name and port, or a forwarded port for a host-run overlay | the loopback address and the second port |
| `destroy` | remove the instance, then the copy, both label-scoped | delete the pod and the claim, both label-scoped | signal the recorded process identity, then remove the data directory |

## Free space

Two filesystems are measured, and **both in the same unit**, because they are not the same claim.

1. **The runtime's data root**, measured inside a throwaway container.
2. **The host filesystem holding the cache directory**, measured on the host.

The second is usually the binding one: the runtime's data disk is a sparse image that grows into the host, so a comfortable figure inside the runtime can sit on top of a host that has far less. The run names which of the two **bound** the decision.

**The unit is not optional and is not assumed.** POSIX `df -P` reports 512-byte blocks and the same flag inside a minimal image reports 1024-byte ones; measured on one host, the bare flag reported `330306512` for the same filesystem the kilobyte flag reported `165152016` for. Reading each side in its own unit reports the host as twice as free as it is, which is the permissive direction. Both sides are measured in kilobytes.

**Either one unmeasurable is a refusal.** An unknown is not a permission. The projected size is the source's *measured* size and never an estimate, and a size that cannot be measured refuses too.

**What this produces is a candidate, not a guarantee**, and the run says so in those words. No worktree can see a copy another worktree has not yet made, so two runs that each pass their own check can still collide, and nothing here holds a reservation — a host-global ledger would be bounded, owned by nothing, and would leak permanently on a crashed run, which is the object this design deleted elsewhere for the same reasons. Beside the numbers the run therefore prints its blind spot, in one sentence: **another worktree's copy that does not exist yet, another repository's copies, and every other consumer of this disk are not counted and cannot be.** Silence about that reads as completeness.

It also reports how many copies of **this repository** already sit on the measured filesystem, from the scoped label query it makes anyway. Where the runtime will not answer, that count is reported as **unknown, never zero**: zero is a claim, and an unanswered query is not one.

A copy the arithmetic refuses is refused before any bytes are written. A copy that runs out of room while writing **removes its own partial**, refuses the pair, and leaves the runtime's object inventory exactly as it found it — a partial must not survive a failed provision any more than it survives a refusal.

One stated assumption rather than a check: the cache directory's filesystem is taken to be the one backing the runtime's disk image. That is usually true on a single-user machine and is stated rather than proven.

## The copy is taken live, and what that costs

Provisioning does not stop, pause, quiesce or freeze the base stack's store. **Not disturbing the base stack is the property this whole tool exists for**, and trading it for a cleaner copy trades the premise for the detail.

So the copy is **crash-consistent**: a file-level copy of a running engine is what a power cut looks like, and engines are built to recover from that. **An engine with an fsync-ordering dependency may not recover from it.** That is the residual, and it is stated here rather than described as small: no shipped file claims a live copy is sound for every engine.

**Verification is what catches the cases where crash consistency was not enough**, which is why it is mandatory rather than advisory, and why a copy that started is not yet isolation.

## Verifying the copy

**A start is not proof.** A process that is running, a connection the port accepted, a health endpoint answering 200, a zero exit status and a log line announcing readiness are none of them evidence that the copy carries the base stack's state — not one of them, and not all five together. Until the copy has answered a real query it is not isolated.

**Where the query fails, cannot be issued, or cannot be derived at all, the copy is destroyed and the pair refuses.** The overlay is not launched against an unverified copy and it is **never wired to the base store instead**: a silent fall back is the contamination the whole gate exists to prevent, and an unverified copy the overlay then writes into is a false green with the loss already committed. The absence of a derivable query is a refusal, not a waiver.

### Where the candidate comes from

| Rung | Source | What it yields |
|------|--------|----------------|
| 1 | the store service's **exec-form** `healthcheck.test`, as the resolver already reported it | an argument vector, already in the shape this skill runs |
| 2 | a **read** command from the repository's own lifecycle target family for that store, including one the run offered to write per `references/shared-state.md` | the same, out of a file the repository owns |
| 3 | nothing | destroy the copy, refuse the pair, name the store, and say that **no query could be derived** |

A `CMD-SHELL` healthcheck is not a candidate: it is shell source again rather than an argument vector, and it falls through to rung 2 and then to rung 3. The template contract in `references/shared-state.md` governs the harvested vector unchanged — every rule there applies to every command this skill discovers and runs against a store — so a vector whose program re-parses its argument is rejected here for the reason it is rejected there.

**Measured on the repository this change was written for: zero of its four stores supply a rung-1 candidate.**

| store | exec form? | why it yields no query |
|-------|-----------|------------------------|
| postgres | no | `CMD-SHELL`, so the argv rule excludes it before anything else is asked |
| timescaledb | no | `CMD-SHELL`, the same |
| redis | yes | `redis-cli ping` answers `PONG` on an instance holding nothing, so it discriminates nothing |
| minio | yes | a health endpoint, which is the one shape named above as never standing in for the query |

So against a repository like that one, **this version provisions a copy and then refuses every writing pair** until rung 2 has a source. That source is a read command living in the repository, and where nothing defines one the run **offers to write it** — `references/shared-state.md` holds the offer, its three constraints, and the two falsifiers that stop a file this skill wrote from vouching for itself. Until such a target is approved and a run has observed it work, the refusal above is what that repository gets, stated here rather than met as a bug.

### The three outputs

The candidate is issued three times, **through one route**, and two comparisons decide the pair.

| Where the candidate runs | What starts it | How the candidate is issued |
|--------------------------|----------------|-----------------------------|
| the base store | nothing — it is the instance discovery recorded as `baseInstance` | `docker exec "$instance" "$@"` |
| an empty instance of the same image | `docker run -d --rm --label "stackgraft.repo=$hash8" --label "stackgraft.worktree=$worktree" --label "stackgraft.probe=$store" "$image"` | `docker exec "$instance" "$@"` |
| the copy | nothing — it is the instance `address` returned | `docker exec "$instance" "$@"` |

**One route, and that is an assertion rather than a convenience.** A candidate issued one way against the empty instance and another way against the base store can differ for a reason that has nothing to do with the data — and a difference is exactly the signal being read, so a second route would manufacture the discrimination and admit a liveness ping as a query.

- **The candidate is a query only once its output on the base store differs from its output on the empty instance.** A command that answers the same on an instance holding nothing cannot tell a copy from an empty namespace, which is the one distinction this whole road exists to make. Recorded once per store and command as `verification`, and re-run only once that record's `sourceFingerprint` stops matching.
- **The copy is verified only once its output matches the base store's, byte for byte.** That is what proves the copy carries the base's state, and it knows no engine: nothing here has to understand what the bytes mean, only that two instances said the same thing and an empty one did not.

**The empty instance carries no state and is removed by the runtime rather than by a query.** It mounts nothing, so it can hold nothing; it is started with `--rm`, so the runtime takes it and its anonymous volumes away when it stops and **no command here ever names an object to remove**. It carries this repository's hash and the worktree so that a run which died still leaves something a person can find, and it deliberately carries no `stackgraft.store`: the complete four-label set is what a copy *is*, and a probe that answered the copy's own query would be a copy nothing ever seeded.

### The match is a property of the moment the copy was made

The byte-for-byte comparison runs when the copy is **taken**, and again on every explicit refresh, because that is the only moment the copy and the base store are meant to hold the same state. It is not re-run later. From the first launch onwards **the overlay has been writing into the copy** — that is what the copy is for — and the base stack has moved on independently, so a comparison then would report the overlay's own work as a corrupt copy and destroy the thing reuse exists to keep.

**What every later launch does still issue is the query, against the copy and against an empty instance.** The copy must **still answer differently from an instance holding nothing**. That costs one empty instance, runs on every launch, and is what stops a copy nobody verified — one left behind by a run that died between provisioning and reading back — from being put into service on the strength of existing. It proves the copy still carries state; it does not, and cannot, prove the copy still matches a base store that has moved.

## The copy's lifetime, and its age

**A copy is made once per `(worktree, store)`** and reused on every later launch from that worktree, so the first start pays the cost that run measured and every later one pays none.

**A copy is re-provisioned only on an explicit refresh request.** No elapsed time, no size and no staleness heuristic refreshes one on its own, and none **refuses a launch on age** alone — an age is a number to report, never a verdict. A refresh is `destroy` followed by `provision`, spelled that way so that it stays something a person asked for, and the new copy is verified exactly as a first one is.

**Every run that uses a copy reports that copy's age**, whether or not it provisioned, refreshed or destroyed anything. Three things are stated and no fourth:

- the **absolute timestamp** the copy was taken,
- the **elapsed** time since,
- and the standing sentence that this is the age of the **copy**, and that what it holds is the base stack's state **as of that timestamp** — which says nothing whatever about how far the base store has moved since, because this run **did not compare** them and cannot.

One further fact is reported because it is observed rather than inferred: where the base store's runtime **instance identity has changed** since the copy was taken — the container was recreated, which is what a restore or a reseed usually looks like — the run says so. Where that identity cannot be read, it says the **comparison was not made** rather than reporting agreement.

**Four phrases may never appear beside a copy, and that is a requirement rather than a style note:** *up to date as of*, *stale*, *fresh*, and a data age of the form *the data is N old*. Every one of them is a comparison against the base store that no run here performed, and a developer who read one would believe a measurement nobody took.

## Refusals, by name

A store this provider cannot copy locally refuses, naming the store, the reason, and the fact that nothing was attempted. Discovery's recorded reason for the store's `locality` travels into the message, so the refusal says what was actually observed rather than restating the rule.

| Case | Why | What the run does |
|---|---|---|
| **Managed** — its lifecycle belongs to a provider this skill does not operate | There is no local state to copy, and isolating inside the remote instance needs credentials and substrate knowledge this skill has neither of | Refuses by name. **It requests no credential and attempts no in-place isolation there** |
| **Remote** — its address resolves off this host | Same: nothing local to copy | Refuses by name |
| **Host-native** — it runs directly on the host rather than in the container runtime | A provider for that runtime is **unbuilt** in this version. Messier, not impossible | Refuses by name, stating that no provider for that runtime ships yet |
| **Locality undetermined** | An **unknown is not a permission** | Treated as remote and refused |

**A refusal does not cascade.** It is one pair's outcome: the unit's other pairs are still classified on their own, and a unit paired with one refused store and one local store still gets a copy of the local one.

The provider sees the same thing from its own end. A store whose runtime object cannot be found on this host has no local state to copy, so it refuses there too — with nothing created and the sibling pair beside it unaffected.

## Ownership, lifetime and removal

A copy is a duplicate of whatever the developer's base stack holds, on the same disk, under a name this skill chose. That is a surface, and it is answered by ownership rather than by encryption.

Every copy carries the complete label set, scoped to this repository:

| Label | Value |
|---|---|
| `stackgraft.labels` | the label-set version, so a future one is recognised as unrecognised rather than misread |
| `stackgraft.repo` | this repository's hash |
| `stackgraft.worktree` | the worktree the copy belongs to, absolute and physical |
| `stackgraft.store` | the `backingStores` key |

Four, not the overlay's five: `stackgraft.service` holds a manifest service key, and a copy belongs to a store rather than to a service. Writing one there would make a volume claim to be a launched service.

**A partial set is not a copy.** The scoped query asks for all four, so an object carrying three is reachable by no flag combination this skill offers — which is the point: the set is complete or the object is not ours, and an object that is not ours is never removed.

**Every run names the copy and the exact command that removes it**, including a run that **removed nothing** because the overlay is still up or a destroy failed. That is the run that most needs to say so: the only thing that will ever remove it otherwise is a person who was told it exists.

```
docker rm -f <name> && docker volume rm <name>
```

An unlabelled object is never provisioned over, never destroyed, and never named as a copy of ours — see `references/reaping.md`, which reclaims a copy whose worktree is gone and takes the removal flag in addition to the mutation flag before it touches one.

## What the run reports

For every copy: the store, the bytes copied, and the elapsed time — **all three measured on this run**.

**Nothing is predicted.** Not from a byte count, not from another store's observed rate, not from a previous run of the same store. The measured spread is the reason: on one host, one SSD, one run, a store of few large files moved at 244 MB/s while a store of many small ones moved at 72 MB/s. Rate tracks file profile rather than size, so a figure derived from a size is derived from the wrong variable.

Measurements may be cited as evidence that the approach is viable, and they are labelled as **one sample** where they appear: on that host, four live stores totalling 10.7 GB were copied with nothing disturbed — 647 MB in 9 s, 10.0 GB in 42 s, and the two remaining stores in under a second each. That is one sample, not a rate to plan against.
