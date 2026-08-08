# Shared state

The feature that makes stackgraft safe rather than merely convenient — and the one worth understanding before you trust it.

> This page explains the reasoning. The **normative** procedure the agent follows is [`skills/stackgraft/references/shared-state.md`](../skills/stackgraft/references/shared-state.md), and that file is the only source of a verdict.

## Two hazards, not one

**Contamination** — your overlay *writes* state the base stack reads. Migrations, inserts, deletes, cache writes. The damage lands on everyone's **data**.

**Theft** — your overlay *attaches* to a coordination primitive and takes work away from the base stack: a consumer group, a queue subscriber, an advisory lock, a replication slot, a scheduler singleton. The damage lands on the base stack's **behavior**.

Theft is the nastier one. A service that only reads can cause it, and the symptom surfaces inside a service nobody modified — so you debug the wrong thing.

## The verdict

For every `(service, store)` pair, three questions:

- **W** — does the service *mutate* the store?
- **X** — is attaching *competitive or exclusive*?
- **N** — does isolation exist *inside the instance already running*?

Evaluated in order, stopping at the first match:

| Step | Condition | Verdict |
|:--:|---|---|
| 1 | **Any** of W, X, N undetermined | **Refuse** |
| 2 | X — attaching competes | **Refuse** a plain attach; a distinct consumer identity re-opens the question |
| 3 | No write, no competition | **Reuse** the base store |
| 4 | Writes, and in-instance isolation exists | **Isolate in place** — a namespace inside the running instance |
| 5 | Writes, no in-instance isolation | **Isolate onto a seeded copy** where the store records a provider; **refuse** where it does not |

**Step 1 is the load-bearing one, and it is an *any*, not an *all*.** One undetermined value refuses the pair; the other two being known changes nothing.

X is evaluated **before** W and independently of it. Writing is not the only way to break the base stack, so a decided W must never absorb the X question — a Kafka store isolated by topic prefix satisfies N while `group.id` stays shared, and the overlay still steals partitions.

## Empty is a claim, not an omission

A recorded `mutates: false` means *checked, and none, for that one store*. A **missing** record for a pair means nobody looked at that pair. Those are different, and conflating them is how a gate quietly dies. The service-level `writes` array this replaced could not tell them apart across stores: it was a positive claim that asserted checked-and-none for every other store at the same time, so a partially-informed pass had to omit it and lose all of them.

Because an empty list is unfalsifiable on its own — a lazy pass could emit it everywhere and permanently disarm the gate — any classification must carry a `stateReview` recording **how** it was reached and a fingerprint of the source it describes. When that fingerprint stops matching, the classification is stale, and stale is undetermined.

The same rule applies one level up: a repository claiming to have **no** stateful dependencies at all must evidence that claim, and that evidence expires like any other.

> This principle took five attempts to get right. The gate's trigger kept resting on data that could be absent — an optional map, then an optional list, then an empty list, then a second optional map. Each fix was correct for the case in front of it and blind to the one a level up. What finally closed it was not another trigger: it was making emptiness cost something at **every** level.

## Isolating onto a copy

**A copy counts as isolation only once it has been verified, and a copy that merely started has not been.** One command is issued against your base store, against the copy, and against an empty instance of the same image, and the copy counts only where its answer matches the base store's byte for byte *and* the empty instance answers something else. Where that query fails or cannot be derived, the copy is destroyed and the pair refuses — it is never wired to the base store instead.

An isolate verdict at step 5 means a **seeded copy**: a second instance of the same image, started on a copy of the state your base stack holds. **Making it asks your repository for nothing** — no task target, no discovered command, no approval. **Verifying it does ask**: the query above is your store's own exec-form healthcheck, or a read command living in your repository, and where nothing defines one the run offers to write it. Against a repository that supplies neither, this version provisions a copy and then refuses every writing pair. **An empty namespace is a different thing from a copy**, and the difference is what your feature is tested against.

Three things about it, stated rather than implied:

- **It is taken live, so it is crash-consistent.** Your base stack is never stopped, paused or reconfigured — that is the property the whole tool exists for. A file-level copy of a running engine is what a power cut looks like, and an engine with an fsync-ordering dependency may not recover from one.
- **It costs disk, and the check before it is a candidate rather than a guarantee.** Two filesystems are measured — the runtime's data root and the host behind it — and the run says which one bound the decision and what it cannot see.
- **It is yours to remove, and you will be told how.** Every run names the copy and the exact command that removes it, including a run that removed nothing.

`references/isolation-providers.md` is the whole of it; `SECURITY.md` states what having a duplicate of your data on your disk means.

## Isolating in place

Where the store offers a namespace inside the instance already running, that road is taken first, because it copies nothing. On such a verdict stackgraft reuses the **server process** and never the **namespace** — a new database, schema, vhost, or prefix inside the container that is already up.

The command that creates it is **discovered from your repository**, never embedded here, on a four-rung ladder:

| Rung | Source | Confidence |
|:--:|---|---|
| 1 | A task target your repo already defines — a `Makefile`, `Taskfile.yml`, `justfile`, npm script | `declared` |
| 2 | The client *inside the running store container*, borrowed from the image so none is needed on your host | `inferred` |
| 3 | No command needed — isolation is an env or URI change | `declared` or `inferred` |
| 4 | Nothing discoverable | `none` → step 5, which is the copy |

Only `declared` evidence satisfies the gate. A degraded discovery path cannot launder a guess into a safety verdict.

Because a discovered template is repository data that gets executed, it is treated as untrusted input: a closed placeholder set, a character deny-list on the template's own grammar, argv execution with no shell fallback, and a rejection of any program that would **re-parse an argument as code** — `sh -c '…'` puts a substituted path back into shell grammar, which argv had just neutralised.

## Cases with no safe answer

Stated plainly, because pretending otherwise is worse than refusing:

1. **A migration against a shared database too large to clone.** Pay for a dedicated instance, or refuse. There is no middle option.
2. **Redis pub/sub.** Logical database selection does not isolate channels — publishing on database 10 reaches a subscriber on database 1. Prefixing channels is an application change, not an overlay knob.
3. **Externally visible side effects.** No infrastructure trick un-sends an email or un-charges a card.
4. **Host singletons.** A fixed socket path, lockfile, bind-mount or hardcoded port. Two instances collide by construction.
5. **When the shared state *is* what is under test.** It cannot be verified in an isolated copy, nor safely in the shared one.

## The escape hatch

One explicit acceptance per `(service, store)`, recording the reason, who accepted it, and the service's fingerprint at that moment. It is treated as **absent** once that fingerprint drifts — the acceptance was granted for code that no longer exists.

There is no global bypass, and an acceptance naming neither a reason nor a person is indistinguishable from one the agent granted itself.
