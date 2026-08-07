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
