# Proposal: parallel-feature-isolation

Phase: `sdd-propose` · Input: first execution against a real repository (no `sdd-explore` artifact) · Next: `sdd-spec` + `sdd-design`
Targets `2.0.0`. `1.1.0` stays published; this is a **breaking** redesign of the isolation half.
Depends on: `portable-multi-stack` and `overlay-reaping` merged — `hash8`, the label contract, the lock discipline and the reap pass are reused unchanged.

## Scope, stated

**Local development. Several features in parallel against one running stack, without overlapping.** One host, N worktrees of one repository, one base stack the developer already has up.

The original design never said this. `portable-multi-stack/exploration.md:95` records the premise it worked from instead:

> **Share compute. Isolate state.** … Cheapest correct default: reuse the base stack's **stateless services**, and isolate state **inside the already-running datastore instance** (new database / vhost / prefix) so no second container is needed at all.

The first sentence is right and is kept. The rest — *inside the already-running instance, no second container* — is the root cause of every defect below, and it was adopted as a universal truth precisely because no scope bounded it. Isolating in place obliges the skill to know how each substrate creates a namespace, so a finite prose table became the gate for an unbounded set of stores; and a namespace created in place is **empty**, which is not what a developer testing a feature has.

Stating the scope is not only a limit. It is a **grant**: on one laptop, against volumes measured in gigabytes, the skill may copy state instead of naming a corner of it, and may refuse everything remote without apology.

## Intent

The skill was run against a real repository for the first time: 43 services, four compose files. Discovery resolved the whole topology in under a second and caught what a naive pass misses. Then **116 of 156 (service, store) pairs refused**, and the overlay never launched.

Five findings from that run carry this change:

| # | Finding | Consequence |
|---|---|---|
| F1 | `{{isolationName}}` generates `sg_<slug>_<hash8>`; the underscore separators are mandatory | S3 and MinIO bucket names forbid `_`. **Every** bucket the skill can name is rejected by `make_bucket` |
| F2 | Redis isolation is `SELECT n`, an integer 0–15 | The generator emits one 40-character snake_case shape. Nothing in the contract produces an index and nothing allocates one |
| F3 | `verifyRequest`'s closed placeholder set is `{{port}}` alone | Every route on that stack is behind a Bearer token, which has no defined source. No unit recorded a verification |
| F4 | `writes` is one array, and an absent one means nobody looked — for every store at once | Partial knowledge is inexpressible: determined for Postgres and undetermined for Redis can only be written as undetermined for both. At least 6 over-refusals came from this alone |
| F5 | Nearly every service runs `create_all` at startup | `migrates: true` is read as W=yes against **every** entry in `backingStores`, whatever the change touched |

Success: on that repository, a change that touches no store launches with no isolation and no refusal; a change that writes gets its own seeded copy of exactly the stores it reaches; and a pair that is genuinely unsafe still refuses, by name.

## Contract surfaces touched

`SKILL.md` (Activation Contract, Hard Rules, Decision Gates, Execution Steps, `description`, `version`), `references/` (3 modified, 2 new), `assets/` (**`schemaVersion` 2 → 3, breaking**), `scripts/` (1 new), plus the four version numbers `.github/scripts/verify.sh` reconciles.

## Decisions

### D1 — Scope is a contract term, written where a reader meets it

The `description`, the Activation Contract and `README.md` all state it: one host, one running base stack, N worktrees, local development. CI, shared or remote hosts, and multi-developer stacks become declared non-goals rather than untested territory.

**Accepted cost:** the skill stops implying it is universally applicable, and a class of users is turned away in the first sentence they read. Taken deliberately — 116 refusals is what the unstated universal ambition bought.

### D2 — Classify the change, not the service

Step 5 already diffs the worktree against its base branch to select which units to overlay. That same diff now selects the **gate's subject**. A pair enters the gate only where the change can reach the store; a unit that reaches no store contributes no pairs at all.

The narrowing is one-directional and evidence-bound: it may only remove a pair whose store the unit is *recorded* as not reaching, on a record that expires like every other (D3). The escalation triggers stay, and become the named re-widening — they read the launched process's behaviour, not the diff.

**Accepted cost:** the diff becomes safety-load-bearing, and a diff under-reports by construction — a store reached only at runtime, a connection string read from the environment, an entrypoint that migrates. Two limits follow and must be stated rather than smoothed over. Absence of a record is undetermined, which refuses. And **a change confined to a unit's frontend does not make that unit stateless**: overlaying a service that runs `create_all` at startup still executes that write whatever the diff touched, so D2 relieves the *pairs it cannot reach*, never the writes its own launch performs.

### D3 — Determinacy is recorded per store

Replace the single `writes` array, and the manifest-wide reading of its absence, with one record per `(unit, store)` carrying W, X and the evidence for each, expiring on its own `serviceFingerprint`. Partial knowledge becomes expressible. An absent record is still undetermined, so the fail-closed direction is unchanged.

`migrates` is scoped in the same move: W=yes for the stores the entrypoint is **pointed at**, which the per-store record now names, instead of every key in the map. F5's amplification stops without weakening F5's reason — a service that migrates on startup still writes, and where the pointing is unknown the store is undetermined, which refuses.

**Accepted cost:** `schemaVersion` 2 → 3 with no migration path — by design, everything is re-derivable — so every cached manifest is discarded once and rediscovered. Record count grows from one per service to one per pair, paid by the discovery pass on drift.

### D4 — Two hazards, two mechanisms

The gate already separates W from X. Isolation was designed as one thing.

- **Data hazard (W)** — the overlay writes where others read → **give it its own copy of the state.**
- **Coordination hazard (X)** — the overlay attaches to a coordination primitive and steals work → **give it a distinct identity.** Cloning a Kafka broker to avoid a consumer-group collision is absurd; the answer is a different `group.id`, which is a *name*, not a copy.

This shrinks the per-substrate table from *"how do you create a namespace here"* — the open-ended question that broke — to *"what is this substrate's identity knob"*: `group.id`, a durable name, a queue name, an advisory-lock key, a replication-slot name. Small, stable, and already half-present as `competesOn[].overlayIdentity`.

**Accepted cost:** substrates with no identity knob still have no answer — a second consumer on one RabbitMQ queue round-robins, a leader election admits one holder however it is spelled. Those keep refusing, and `references/shared-state.md`'s six cases with no safe answer survive intact.

### D5 — The copy varies by runtime, not by substrate

Cloning state is the same operation for Postgres, Redis, Mongo or MinIO; it differs between Docker, Kubernetes, a host process and a managed provider. The current four-rung ladder varies by **substrate**, which is why a finite prose table gates an unbounded set and a store released tomorrow cannot work. For the data hazard, replace it with a small provider contract:

| Operation | Answers |
|---|---|
| `provision` | copy this store's state and start an instance on it |
| `address` | how the overlay reaches it — host, port, env |
| `destroy` | remove the instance and the copy |

One provider ships: **Docker**, which is where a local base stack already runs. It copies the volume and starts a second container from the same image.

**Accepted cost:** a new contract surface with its own conformance obligations, and exactly one implementation of it. Kubernetes, host-native and managed providers are declared, not built.

### D6 — Isolation means a seeded copy, not an empty namespace

An empty database cannot test a feature that depends on loaded data, which is the actual daily need. The current rungs create empty namespaces and delegate seeding to a repository target almost no repository defines.

Measured against the real repository's live volumes, nothing disturbed:

| store | size | full clone |
|---|---|---|
| postgres | 647 MB | **9 s** |
| timescaledb | 10.0 GB | **42 s** |
| redis | 8 KB | ~0 s |
| minio | 8.7 MB | ~0 s |
| **all four** | **10.7 GB** | **~51 s** |

149 GB free on the host. **51 seconds is the worst case, and only when a change touches all four stores** — under D2 a frontend change clones nothing. Rates track file profile, not size: Timescale copies at 244 MB/s (few large files), Postgres at 72 MB/s (many small ones), so extrapolating one from the other is wrong and the skill must never predict a duration from a byte count. This measurement is the evidence the approach is viable, not a footnote.

**Accepted cost:** disk, N worktrees deep, holding a copy of production-shaped data. That is a security surface and a reaping obligation — see T2 and T3.

### D7 — Managed and remote stores are refused, by name

RDS, ElastiCache, Atlas: there is no local volume to copy, and isolating inside the remote instance needs credentials and substrate knowledge the skill has neither. The honest outcome is the one the skill already practises — **refuse, and say why.** Host-native stores (a brew-installed Postgres: copy the data directory, start a second instance on another port) are possible, messier, and a separate provider.

**Accepted cost:** a developer whose stack points at a shared cloud database gets a refusal with no remedy inside this tool. That is a true statement about their situation, not a gap in the design.

### D8 — `{{isolationName}}` becomes a name family, per substrate grammar

F1 and F2 are one defect twice: a single generated shape cannot name every substrate's namespace. The family derives from the same branch hash — an SQL identifier (`sg_<slug>_<hash8>`, unchanged), a DNS/S3-safe label (`sg-<slug>-<hash8>`, no underscore, ≤63 characters), and an allocated small integer for index-addressed stores. Each consumer asks for the form its substrate accepts; the shared hash keeps them one logical namespace.

**Accepted cost:** the integer form is an *allocation*, not a derivation — bounded, exhaustible, and requiring release, which is state the other forms do not need. Where allocation fails the store is undetermined, which refuses. See Q4: this member may not survive design.

### D9 — Verification gets a credential channel, or reports that it did not verify

F3. A Bearer token has no defined source in a closed set of `{{port}}`, and a literal token in a cache file is a secret written to disk, which `references/discovery.md` already forbids. Give `verifyRequest` a credential channel carrying a **reference** — the name of an environment variable, never its value — resolved at run time. A run that cannot resolve it records no `verifiedOverlays` entry and states the overlay is unverified.

**Accepted cost:** this is the one correction not about isolation and it is separable — see Q7. It is here because a stack where nothing can be verified produces overlays whose only evidence they work is that they started, which is the false green the skill exists to prevent.

### D10 — Slicing: five PRs, evidence before narrowing, cheap mechanism before expensive

| # | Slice | Content | Forecast |
|---|-------|---------|----------|
| 1 | Scope and per-store determinacy | D1, D3. Scope in `description`, Activation Contract, README; `schemaVersion` 3; `writes` → per-pair records; `migrates` scoped; discovery writes them | ~400 |
| 2 | Change-scoped gating | D2. The diff narrows the pair set, on slice-1 records and only on them | ~300 |
| 3 | Coordination identity | D4 (X half), D8. Identity-knob table, name family, `coordination-identity` split out of `shared-state.md` | ~400 |
| 4 | Providers and seeded copies | D4 (W half), D5, D6, D7. `references/isolation-providers.md`, the Docker provider script, copy lifecycle, reap integration, remote refusals | ~400 |
| 5 | Verification credential channel | D9. Optional; droppable from 2.0 without touching the other four | ~200 |

Ordering is not stylistic. Slice 1 precedes slice 2 because narrowing without per-store evidence is exactly the failure `references/shared-state.md` was written to stop — *a set the manifest narrows is a set the manifest can empty*. Slice 3 precedes slice 4 because an identity that ends the competition removes a pair that would otherwise demand a copy: build the free mechanism before the gigabyte one.

**No slice publishes.** `2.0.0` releases once, after slice 4. Slice 1 alone is a schema bump with half a gate behind it.

## Scope

### In scope

- The scope statement itself, in the skill body and README.
- Per-store W/X determinacy records, replacing `writes` and the manifest-wide reading of its absence.
- `migrates` scoped to the stores the entrypoint is pointed at.
- The worktree diff as the gate's subject selector, one-directional and evidence-bound.
- The identity mechanism for the coordination hazard: knob per substrate, allocation, delivery channel, distinctness proof.
- The name family replacing the single `{{isolationName}}` shape.
- A provider contract for the data hazard — `provision` / `address` / `destroy` — and one Docker implementation that clones the volume and starts a second container.
- Seeded copies as the meaning of ISOLATE, and their lifecycle: ownership labelling, output naming, reaping.
- Named refusals for managed, remote and host-native stores.
- A credential reference for `verifyRequest` (slice 5, optional).

### Out of scope (explicit non-goals)

- **CI, shared hosts, and multi-developer stacks.** D1 makes this a declared boundary, not silence.
- **Cloning a managed or remote store.** D7. Refused with a reason, never approximated.
- **A host-native provider.** Possible, messier, and a separate change.
- **A Kubernetes provider.** The contract must not preclude one; this change does not build one.
- **Seeding by repository target.** The copy carries the data; a `db:seed` hunt is what D6 replaces.
- **Changing the parts that worked on first contact.** Discovery and its resolver preference, running only what changed and wiring the rest to the base stack, the fail-closed posture, ownership labelling, the report pass, reaping, the lock discipline. This change replaces the isolation half, not the skill.
- **Backporting to 1.1.0.** It stays published as-is.
- **Windows-native.** POSIX shells only, unchanged.

## Tensions the locked decisions create

**T1 — D2 narrows a set the shipped gate forbids narrowing, and the spec must say so in those words.** `references/shared-state.md` refuses to let `dependsOn` remove a pair, for a reason that still holds: saying *less* would gate *less*, and the laziest manifest would be the least refused. D2 does not repeal that rule; it moves the evidence requirement down one level, so every *absence* is claimed at the granularity it occurs and expires on the same fingerprint as everything else. The surviving principle is this repository's own — emptiness is a claim. What changes is only where the claim is written. A reader who takes D2 as the repeal will delete the gate.

**T2 — The copy is a data copy, and the base stack's data is whatever the developer has.** D6 duplicates a live volume onto the same disk under a stackgraft-owned name. `SECURITY.md` describes no such surface today. The answer is not encryption; it is ownership, labelling, a named lifetime, and an output contract that says the copy exists and how to remove it — the same posture the skill already takes toward a namespace it leaves behind.

**T3 — D6 reopens a locked non-goal.** `overlay-reaping` excluded volume GC because *"volumes may hold data the user wants"*. That is correct for volumes stackgraft did not create and wrong for volumes it did, and the label contract is what tells them apart. Reopened deliberately, for the labelled subset only, and for no volume the skill did not write.

**T4 — Body budget, on a baseline that does not currently close.** The archived `overlay-reaping` recorded the body at 497 of 500 words and set slice targets whose arithmetic does not hold (463 + 40 = 503). This change adds a scope statement and replaces the isolation half. The counter named in `openspec/config.yaml` MUST be run before slice 1 is planned, and the replacement must be net-negative in the body: the substrate table leaves it entirely and the provider contract never enters it.

**T5 — 51 seconds is one sample.** One host, one SSD, one file profile per store. The 244 MB/s versus 72 MB/s spread already proves the figure does not transfer by size. So the skill *reports* what it copied and how long it took and never *predicts* a duration — and the proposal cites the measurement as evidence of feasibility, not as a guarantee of cost.

## Capabilities

### New

- `isolation-providers`: the `provision` / `address` / `destroy` contract, the Docker implementation, copy ownership and lifetime, and the refusal contract for managed and remote stores.
- `coordination-identity`: the identity knob per substrate, its allocation, the channel that delivers it to the process, and what makes it verifiably distinct. Split out of `shared-state-safety` so the two hazards have two homes.

### Modified

- `shared-state-safety`: **the heaviest delta.** The gate's subject becomes the change's reachable pairs (D2); determinacy is per store (D3); ISOLATE means a seeded copy from a provider rather than a namespace inside the running instance (D5, D6); the step-2 identity procedure moves out to `coordination-identity`.
- `manifest-contract`: `schemaVersion` 2 → 3, breaking. `writes` → per-pair records; `isolation` → a provider reference; `{{isolationName}}` → the name family.
- `topology-discovery`: discovers per-store reachability and classification, the identity knob and its env channel, and (slice 5) the credential reference.
- `portable-runtime`: one new script, the Docker provider, under the existing POSIX-sh, no-install, parses-no-JSON constraints.
- `orphan-reclamation`: reaps stackgraft-created store copies. Narrowly reopens the volume-GC non-goal, per T3.

## Affected areas

| Area | Impact | Change |
|---|---|---|
| `skills/stackgraft/SKILL.md` | Modified | Scope in `description` and Activation Contract; Hard Rule and Decision Gate rows for the two mechanisms; `version` → 2.0.0; body budget per T4 |
| `skills/stackgraft/references/shared-state.md` | Modified | The verdict keeps its home; per-store determinacy; ISOLATE redefined; the four rungs, the per-substrate namespace column and the template contract leave |
| `skills/stackgraft/references/isolation-providers.md` | New | Provider contract, Docker implementation, copy lifetime, refusal cases |
| `skills/stackgraft/references/coordination-identity.md` | New | Identity knob per substrate, allocation, delivery channel, distinctness proof |
| `skills/stackgraft/references/discovery.md` | Modified | Per-store classification records, reachability, identity-knob discovery, credential reference |
| `skills/stackgraft/references/reaping.md` | Modified | Store copies as reap targets, labelled and scoped |
| `skills/stackgraft/references/traps.md` | Modified | A copy that started but was never verified; a diff that under-reports a store; an allocation that silently wrapped |
| `skills/stackgraft/scripts/` | New | The Docker provider script |
| `skills/stackgraft/assets/manifest.schema.json` | Modified | `schemaVersion` 3; per-pair records; provider reference; name family |
| `skills/stackgraft/assets/manifest.example.json` | Modified | Rewritten against schema 3 |
| `README.md`, `docs/SHARED-STATE.md`, `docs/HOW-IT-WORKS.md` | Modified | Scope; isolation now means a copy |
| `CHANGELOG.md`, `.claude-plugin/plugin.json` | Modified | 2.0.0, breaking, with the four numbers `verify.sh` reconciles |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A crash-consistent volume copy starts but is subtly wrong, and the overlay tests against corruption | Med | The copy is not isolated until it starts and answers a real query; unverified copies are destroyed and the pair refuses — see Q1 |
| Copying a live volume races the running server's writes | Med | Q2 must resolve copy-live versus quiesce before slice 4; the measurement claims "nothing disturbed", which the spec has to make true rather than assume |
| Disk exhaustion: N worktrees × 10 GB | Med | Free-space check against the filesystem the daemon actually uses (Q6), refusal before the copy rather than a failure during it, and reaping per T3 |
| D2 is read as permission to trust `dependsOn` again | **High** | T1 is a spec requirement, not commentary; the narrowing rule is written with its evidence obligation inline |
| The schema bump strands users mid-migration | Low | No slice publishes; unrecognised `schemaVersion` already discards and rediscovers, which is the whole migration |
| The provider contract fits Docker and nothing else | Med | Its three operations are named against Kubernetes and host-native before slice 4 lands, on paper; a contract that cannot describe a second runtime is D5 failing at its own premise |
| 2.0 deletes safety machinery that earned the skill's reputation | Med | Q5 is answered by the owner, not by design; the six cases with no safe answer are preserved either way |
| The five slices drift apart and 2.0 ships internally inconsistent | Med | Slices stack onto one feature branch and release once; each slice's spec delta lands with it |

## Rollback

Adoption is copy-a-folder, so rollback is reverting the folder to `1.1.0`. Two things do not revert themselves and must be stated in the release notes: a manifest written at `schemaVersion` 3 is unrecognised by 1.1.0, which **discards and rediscovers** — the intended fail-safe, and the reason no migration path exists; and any store copy created while 2.0 was live remains on disk, labelled, removable with the documented command. No data of the user's is moved or deleted by the rollback itself.

## Dependencies

- `portable-multi-stack` and `overlay-reaping` merged — `hash8`, the label contract, `scripts/with-lock.sh` and the reap pass are load-bearing.
- `git` 2.5+, POSIX `sh` + `awk` (already required, unchanged).
- `docker` for the only shipped provider — a conditional dependency, consistent with today's container-kind conditionality, and the reason D7's refusal exists.
- No new package, build step, or runtime.

## Success criteria

- [ ] On the 43-service repository, a change touching only frontend paths launches with zero store pairs gated and zero copies made.
- [ ] A change writing to one store gets a copy of that store only; the other three are untouched and unread.
- [ ] Each of F1–F5 has a named regression case that fails against 1.1.0 and passes at 2.0.
- [ ] A MinIO bucket is created under a name the substrate accepts.
- [ ] A pair with a coordination hazard and no data hazard resolves by identity, never by copy.
- [ ] A pair with a data hazard resolves by copy, and the copy is verified by a real query before the pair counts as isolated.
- [ ] A managed or remote store refuses with the reason named and no partial isolation attempted.
- [ ] A store with no per-store record is undetermined and refuses, in every mode including manifest-less.
- [ ] `dependsOn` still cannot narrow a pair set; only an expiring per-store record can.
- [ ] Every copy carries the ownership labels and is reaped by the existing pass; no unlabelled volume is ever a target.
- [ ] The run reports each copy, its size and its elapsed time, and predicts none.
- [ ] The six cases with no safe answer still refuse, unchanged.
- [ ] `schemaVersion` is 3 and an unrecognised version still discards and rediscovers.
- [ ] Body within the measured ceiling, counted by the command in `openspec/config.yaml`, never by eye.
- [ ] The provider script passes `dash -n` and runs on macOS and a minimal Linux image.
- [ ] The four version numbers agree at 2.0.0 and `CHANGELOG.md` carries a breaking-change entry.

## Proposal question round

Seven questions the proposal could not resolve from the evidence. Four block design; three are corrections to the brief this proposal was written from, recorded here rather than absorbed silently.

**All seven are now answered.** The questions are kept below with their original reasoning, because the reasoning is what makes the answers checkable.

### Answers

**Q1 — yes, blocking.** A copy is not isolated until it has started and answered a real query; failing that it is destroyed and the pair refuses. The proposal's pending assumption is confirmed rather than overridden: this project's posture is that a start is not proof, and an unverified copy the overlay then writes into is a false green with the loss already committed.

**Q2 — copy live, accept crash-consistent.** Not disturbing the base stack is the property the whole tool exists for, and surrendering it to gain a cleaner copy trades the premise for the detail. A file-level copy of a live engine is what a power cut looks like, and engines are built to recover from that. The residual is stated rather than covered: a store with an fsync-ordering dependency may not survive it, and the run must verify (Q1) rather than assume.

**Q3 — per worktree, with an explicit refresh.** The copy is made once when the worktree is created and reused on every launch, so the first start pays the measured cost and the rest are free. Data ages, which is the accepted cost — the report must say how old the copy is, every run, so ageing is visible rather than discovered.

**Q4 — clone Redis, delete the integer allocator.** 8 KB copies in effectively zero time. `SELECT n` offers sixteen host-global slots that nothing owns, so two worktrees can pick the same index and collide silently — building and maintaining an allocator with machine-global state to save eight kilobytes is a footgun bought at a cost. This removes D8's only stateful member.

**Q5 — keep both, and close the wall that made the cheap path unreachable.** The copy is the default and asks the repository for nothing. In-instance isolation stays as the optimisation for anyone who wants zero disk — but today it demands a lifecycle target almost no repository has, which is why it is a wall rather than an option.

**So the skill offers to write it.** Where the cheap path is unavailable for want of a target, the run says what is missing, generates it from the store it discovered, shows it before writing, and with approval leaves it **committed in the repository**. From then on it is the repository's own — versioned, reviewable in a pull request, and a legitimate `declared` rather than something synthesised at run time.

Three constraints on that generation, because a `db-create` is harmless and a `db-drop` aimed at the wrong database is not: the store name comes from discovery and is never invented; the content is shown before it is written; and the teardown half is generated but not executed until at least one run has seen the create succeed.

This is also the one thing an agent skill can do that a script cannot. Refusing over a file the agent could have written is wasting the medium.

**Q6 — answered by measurement, and the brief's figure was the wrong disk.** Volumes land in the Docker VM's data disk, which reports 362 GB free of 452 GB. But that image is sparse and grows into the host, which has ~160 GB free — so **the binding constraint is host free space**, roughly fifteen full clones at 10.7 GB each. Comfortable, and not the number the proposal was written with.

**Q7 — `verifyRequest` credentials are their own change.** Out of 2.0. The gap is real but separable, and 2.0 is already five slices.

**Correction, recorded because the spec pass reached the opposite conclusion.** The spec reported that IP-2's verification makes the deferred D9 load-bearing for 2.0 — that on a token-gated stack no verification query is derivable, so every writing pair refuses. **That conflates two different subjects.** `verifyRequest` issues an HTTP request to a *service* behind a Bearer token; IP-2 issues a query against the *store copy*. A query against a copied Postgres needs the database credential, not the application's JWT — and that credential already lives inside the copy's own container, which the provider built from the same image with the same environment. The engine's own client, run inside the instance the provider just created, needs nothing the skill has to store.

So D9 stays out of 2.0. What remains true, and belongs to design rather than to this deferral, is that *deriving* the query per store is a real obligation: a compose `healthcheck`, where the repository declares one, is both discoverable and usually already a real query rather than a liveness ping.

### Q1 — Does a copy count as isolated before it has answered a query? (blocking)

A file-level copy of a live Postgres data directory is *crash-consistent*, which Postgres is built to recover from — but the measured 9 s was a volume copy, not a verified start. This project's whole posture is that a start is not proof.

**Assumption pending correction:** yes, blocking. The copy must start and answer a real query, or it is destroyed and the pair refuses. An unverified copy that the overlay then writes into is a false green with the data loss already committed.

### Q2 — Copy live, or quiesce the base store? (blocking)

The measurement claims *nothing disturbed*, which implies a live copy racing the running server's writes. Postgres survives that as a crash; Redis and MinIO probably do; a store with an fsync-ordering dependency may not. Stopping the base store for the duration is the alternative and it contradicts the property that makes the measurement attractive.

**Assumption pending correction:** copy live, accept crash consistency, and let Q1's verified start be what catches the cases where it was not enough.

### Q3 — What is a copy's lifetime: per run, per worktree, or per branch? (blocking)

Per run pays 51 s on every launch. Per worktree tests today's code against yesterday's data. Per branch is what `{{isolationName}}`'s derivation implies today. This decides whether D6's cost is paid once or every time, and it is the number a developer will actually feel.

**Assumption pending correction:** per worktree, reused until reaped, with the copy's age reported at every launch so staleness is visible rather than inferred.

### Q4 — Should Redis go to a copy and the integer allocator be deleted? (blocking)

D8's integer member is its only stateful one: 16 slots, host-global across repositories, owned by nothing. The measurement says a Redis copy costs ~0 s on 8 KB. A second Redis container may simply be the correct answer, which would delete the allocator, its exhaustion case and its release obligation together.

**Leaning, and it questions the brief:** yes — delete it. But that removes in-instance isolation as a *concept*, which is a larger move than the brief describes, and it feeds Q5 directly.

### Q5 — Does 2.0 keep in-instance isolation at all?

If D5/D6 own the data hazard and D4 owns the coordination hazard, then `isolation.mechanism`, `applyVia`, the four rungs, the template contract, the placeholder deny-list, the destructive-verb rule and the approval flow all become dead surface. Deleting them is a large simplification, and a large deletion in a skill whose safety reputation rests on that machinery. Keeping them is a second mechanism to maintain that the scope statement says is unnecessary.

Not resolvable from evidence. It is an owner's call about what 2.0 *is*, and it changes slice 4's size by more than the whole review budget.

### Q6 — Whose disk is the 149 GB?

The provider runs against the same daemon as the base stack. On Docker Desktop that daemon lives in a VM, so a 10 GB copy consumes the VM's disk, not the host's. The free-space check has to interrogate the filesystem the copy will actually land on, and the answer differs by platform.

### Q7 — Is D9 in 2.0, or its own change?

It is the only correction not about isolation, it is separable, and it is the difference between a verified overlay and one whose evidence is that it started. In as slice 5 unless the owner prefers a smaller 2.0.

### Corrections to the brief this proposal was written from

**C1 — "the closed placeholder set has no numeric member" is not quite the defect.** `{{port}}` is numeric; what no placeholder yields is a value in 0–15, and nothing allocates one. Separately, `isolation.env` is a free-form `string → string` map in the schema, so `REDIS_DB=3` is *expressible* today. What is missing is a generator and an allocator, not schema permission. F2 is stated above in those terms.

**C2 — "no unit could carry a `verifyRequest` at all" is overstated as an impossibility.** The closed set forbids a `{{token}}` placeholder, but `verifyRequest` is substituted as a shell line per `references/discovery.md` section 6, and the isolation deny-list on `` ` `` `$` `;` does **not** apply to it — so `curl -H "Authorization: Bearer $TOKEN" …` is forbidden by no shipped rule. What is genuinely absent is a *defined source* for the credential and any acquisition step, and in practice the run recorded no verification. D9 is scoped to that, not to a placeholder count.

**C3 — F4's mechanism is the inverse of the brief's wording.** `writes: ["postgres"]` is a positive claim that simultaneously asserts checked-and-none for every other store, so a partially-informed pass must omit the field entirely, which makes all four undetermined. The defect is that determinacy has no per-store granularity — not that a per-store negative cannot be written. D3 is aimed at the granularity.

**C4 — 156 pairs implies 39 runnable units, not 43.** 43 services × 4 stores is 172. The spec should pin how the pair count is derived, so the 116/156 figure stays reproducible as a regression baseline.
