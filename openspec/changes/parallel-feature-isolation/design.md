# Design: parallel-feature-isolation

Phase: `sdd-design` · Input: `proposal.md` (locked, D1–D10, all seven questions answered) · Next: `sdd-tasks`

> Size note: the sdd-design 800-word guidance is deliberately exceeded, on the precedent
> `portable-multi-stack/design.md` and `overlay-reaping/design.md` set. This change replaces the isolation
> half of a shipped safety gate: a provider contract with a runtime implementation, a verification
> procedure that must not know any engine, a name family, a narrowing rule that must not read as a repeal,
> and a body budget that does not currently close. Each needs its contract stated in full or the
> implementation re-decides it. Density is held by tables. **Numbering continues from DS32.**

## Technical Approach

Five properties carry the change, and each is built out of something already shipped.

1. **The gate keeps its shape; only its subject and its mechanisms change.** Pairs are still derived
   independently of any declaration, still refuse on absence, and still expire on `serviceFingerprint`.
   D2 subtracts from that set on a record; it never adds confidence, and the escalation triggers
   re-insert *after* it.
2. **Two hazards, two mechanisms, two homes, and no crossing.** W buys a copy from a provider; X buys a
   name. Neither is recorded as satisfying the other, so a pair with one applied is still undetermined.
3. **The skill learns runtimes, never engines.** `provision`/`address`/`destroy` take a source volume and
   an image reference — runtime facts discovery already records. Every engine-shaped question
   (what is a namespace here, what query reads state here, what name does this grammar accept) is
   answered by *discovered repository data* recorded per store, which drifts and expires, or it is
   undetermined and refuses.
4. **Nothing certifies itself.** The provider does not decide that its copy is good (DS34 does, from
   outside it). The generated lifecycle target is not `declared` because the skill wrote it (DS37: an
   observed run makes it so). The free-space check does not claim a guarantee it cannot hold (DS36).
5. **Sealed in the refusal direction, unchanged.** The body still states only that a verdict is required
   and where the procedure lives. Everything this change adds — the narrowing, the two mechanisms, the
   provider, the name family — stays out of the body, which is also how the budget closes (DS33).

## Architecture Decisions

### The body budget (T4)

**DS33 — The unit is words, the ceiling is 500, the shipped body is 498, and T4's named donor is not in the body.**

Three shipped files state this budget and they do not agree on the unit:

| Source | Says | Executes? |
|---|---|---|
| `.github/scripts/verify.sh:594-607` — `body_words()` + `[ "$_w" -le 500 ]` | **500 words** | **yes, every push and PR** |
| `CONTRIBUTING.md:21-25` | 500 words, same `awk` one-liner | no — prose |
| `openspec/config.yaml` `rules.apply.guidelines` | 180–450 **tokens**, max 700, hard max 1000 | no |
| `openspec/specs/portable-runtime/spec.md` — *Skill body stays within the style-guide budget* | at most **700 tokens**, "token count per slice" | no |
| `archive/2026-08-01-overlay-reaping/design.md` DS30 | 497 **words**, slice 1 → 463, slice 2 → 496 | no — forecast |

| | |
|---|---|
| **Choice** | **Words, ceiling 500, at most.** The spec requirement and `config.yaml` are corrected to that unit; the `180–450 tokens` recommendation is struck rather than carried. |
| **Alternative** | Keep tokens and add a tokenizer. **Alternative**: state both and check one. **Alternative**: raise the ceiling to fit the change. |
| **Rationale** | A token count is **unmeasurable by anything this repository is allowed to ship or run**: `python3` is a stub on stock macOS and `node` and `jq` are absent from minimal images, so no tokenizer exists on the supported floor, and `$PORTABILITY` would reject a shipped file that named one. A ceiling nothing can measure is the `compatibility` defect DS32 repaired, restated for the body. The two numbers are also near-equivalent — 500 English words is roughly 650–700 tokens — so choosing words tightens nothing and relaxes nothing; it makes the number checkable. `180–450 tokens` is already violated by the shipped body and must not survive as a rule nobody meets. |

**The measured number is 498, not 497 and not 496.** Counted by applying `body_words()`'s rule token by
token over everything after the second `---`; `verify.sh` prints the same figure as
`body is <N> words (ceiling 500)` on every run, and implementation must re-read it there rather than
trust this table:

| Section | Words | Section | Words |
|---|---:|---|---:|
| Activation Contract | 27 | Execution Steps | 150 |
| Hard Rules | 163 | Output Contract | 51 |
| Decision Gates | 88 | References | 19 |
| | | **Total** | **498** |

**Two corrections fall out of that number.**

*First, DS30's arithmetic drifted by two words at implementation and nobody noticed.* Steps 1 and 2 shipped
at 21 and 27 words against a forecast of 20 and 26. So the body is 498, not the 496 the record claims, and
the headroom is **2 words**.

*Second, `verify.sh`'s own negative fixtures were calibrated against a body that no longer exists.*
`body_fixture "$bf/over.md" 38` appends 38 filler words, which is exactly `501 - 463` — one word over
slice 1's forecast — and `adds-first.md 67` is exactly `530 - 463`, the number its comment states. Against
the real 498-word body they now produce 536 and 565. Both still fail, so CI is green and the drift is
invisible, but **the "merely over" fixture has stopped being a boundary test**: it clears the ceiling by
36 words, so a counter miscounting by up to 35 would still be reported as working. The fixtures must be
derived from the measured body (`n = 501 - $(body_words "$SKILL/SKILL.md")`) rather than hard-coded.

**T4's named donor does not exist.** T4 promises the replacement is net-negative in the body because
"the substrate table leaves it entirely and the provider contract never enters it". The provider contract
indeed never enters it — but **the per-substrate table has never been in the body**; it is in
`references/shared-state.md:109-127`. The body's entire isolation content is one Output Contract bullet
("any isolated namespace left behind", 15 words) and the sealed Hard Rule 8, which is not a donor. So T4's
mechanism is unavailable and the net-negative obligation has to be paid out of unrelated compaction. It
still closes, out of different money:

| Slice | Edit | From | To | Δ |
|---|---|---:|---:|---:|
| 1a | Activation Contract gains the scope-and-non-goals sentence (D1) | 27 | 48 | **+21** |
| 1a | Step 1 drops "never this checkout" — verbatim in `discovery.md` §0 | 21 | 17 | −4 |
| 1a | Step 2 recast; the fingerprint recipe is verbatim in `discovery.md` §5 step 1 | 27 | 20 | −7 |
| 1a | Step 3 — "overlays of this repository" → "this repository's overlays" | 11 | 10 | −1 |
| 1a | Step 4 drops the duplicate pointer (gate row 1 carries it) | 8 | 7 | −1 |
| 1a | Step 8 drops the exclusion enumeration (step 3 and `portable-runtime` own it) | 22 | 18 | −4 |
| 1a | Step 9 drops "rewiring unchanged dependencies…" — duplicates Hard Rule 1 | 14 | 7 | −7 |
| 1a | Hard Rule 6 drops "refresh drifted entries" — duplicates gate row 1 | 16 | 13 | −3 |
| 1a | Output bullet 1 — "name refreshed entries" → "naming which" | 11 | 10 | −1 |
| 1a | Decision Gates: the reaping row and the stopping row merge | 21 | 14 | −7 |
| | **slice 1a: adds +21 · cuts −34 · net** | | | **−13** |
| 4b | Output bullet 5 names the copy and its age (DS38) | 15 | 18 | **+3** |

**Slice 1a lands at 485. Slice 4b lands at 488. Net −10 against 498, with 12 words of ceiling headroom**,
and every intermediate slice is 485. Exact replacement text, so implementation does not re-decide it:

> Activation Contract, new middle line (21 words):
> `Local development only: one host, one running base stack, N worktrees. CI, shared or remote hosts and multi-developer stacks are non-goals.`
>
> Decision Gates, merged row (14 words), the two cells being *Overlay outlived its worktree* and
> *Report it — `references/reaping.md`; stop nothing unproven*.

**The adds and the cuts are one commit, not two.** `verify.sh`'s `adds-first.md` fixture exists because
applying this shape of change in the wrong order is red at that commit: 498 + 21 = 519. Same discipline
DS32 applied to `compatibility`.

**Three things deliberately do not enter the body**, and each saves words as a side effect rather than as
a reason:

| Not in the body | Why not |
|---|---|
| `references/isolation-providers.md` and `references/coordination-identity.md` in References | Naming both files *is* the hazard-to-mechanism mapping the gate spec forbids the body to carry — a reader learns there are two mechanisms and which hazard each answers from the filenames alone. They are reached through `references/shared-state.md`, which is the only verdict procedure. Cost: one more hop for an agent that loads the body only, which is an agent that must refuse anyway. |
| The narrowing rule (D2) | A body sentence saying the diff selects which pairs are gated is a permitting condition in disguise, and T1 says in as many words that a reader who takes D2 as the repeal will delete the gate. It lives whole in `references/shared-state.md` with its evidence obligation inline, or not at all. |
| The provider script in Execution Steps | It is invoked from the isolation procedure, not from the body's sequence, exactly as the isolation command is today. |

**Hard Rule 8 is not a donor.** It compacts to 48 words while keeping P1/P2/P3, for a saving of three, and
touching a sealed rule for three words is a trade this project has already priced.

**Frontmatter, which the counter does not see.** `description` gains the scope (spec: all three places) and
must stay ≤ 250 characters — measured at ≈155 today, ≈212 after ` Local development: one host, one base
stack, N worktrees.`. `compatibility` must declare the provider's runtime beside the existing conditional
one; measured at ≈477 bytes against the 500-byte cap, so `…only for container repos.` →
`…only for container repos and store copies.` (+17) lands at ≈494. If the measured value leaves less than
17 bytes, the named donor is `all CI-tested. ` (−14) in the first sentence. Both figures are hand-counted;
`compat_measure()` prints the exact one and **`description` has no check at all** — see verification row 2.

### The verification query (Q1, IP-2)

**DS34 — A verification query is a discovered command proven to discriminate a seeded instance from an empty one, run inside the copy's own container. No engine is named, and nothing is stored.**

IP-2 requires "a real query … one that reads state the copy is supposed to carry" and makes a
non-derivable query a refusal. The credential problem dissolves as Q7's correction says — the engine's own
client, run inside the instance the provider just built from the same image with the same environment,
needs nothing the skill holds. What remains is deriving the *query*, and a health probe is explicitly not
one: `pg_isready`, `PING`, and `SELECT 1` all answer identically on an empty instance, which is exactly the
thing D6 exists to distinguish a copy from.

| Rung | Source | Confidence | Note |
|---|---|---|---|
| 1 | The store service's **exec-form** `healthcheck.test` from the resolver output `discovery.md` §1 already produces | `declared` | Repository-authored, runs inside the container, usually already a real query |
| 2 | A **read** command from the repository's own lifecycle target family for that store (rung 1 of the isolation ladder, or DS37's generated pair) | `declared` | Same contract, same discovery pass |
| 3 | nothing | — | **Destroy the copy, refuse the pair, name the store and say no query could be derived** |

| | |
|---|---|
| **Choice** | The candidate command is run **against the base store and against the copy**, and its outputs must match byte for byte. The command qualifies as a *query* only once a **discriminator probe** has shown its output differs against an empty instance of the same image — recorded per store, expiring on that store's fingerprint, paid once. |
| **Alternative** | A per-engine query table in the skill. **Alternative**: accept any `healthcheck` as the query. **Alternative**: give `verifyRequest` a credential channel (D9). |
| **Rationale** | A per-engine table is the finite prose table D5 removes, re-entered through the verification door — and it drags a per-engine client, a per-engine schema assumption and the credential story back in with it. Accepting a `healthcheck` unfiltered is the false green with extra steps: it is the one shape IP-2 names as not standing in for the query. D9 is out of 2.0 per Q7 and, per Q7's correction, is about a *service* behind a Bearer token, not a *store* copy. **The match-plus-discriminator shape is the only one that proves what IP-2 asks and knows no engine**: matching proves the copy carries the base's state; discrimination proves the command could have said otherwise. A check that cannot report a failure measures nothing, applied to the copy instead of to CI. |

Three details the implementation must not re-decide.

- **A `CMD-SHELL` healthcheck is not a derivable query.** The template contract's argv rule and its
  "that program may not re-parse" row apply here unchanged — `references/shared-state.md` already says
  every rule there governs *every* command this skill discovers and runs against a store. An exec-form
  `test: ["CMD", …]` is already an argument vector; a shell-form one is shell source again. It falls
  through to rung 2, and then to refusal.
- **The discriminator probe is one empty instance of the same image, no volume, started and destroyed.**
  It is permitted by the provider carve-out (it creates a labelled runtime object and removes it) and it
  costs seconds, because an empty store image is not a 10 GB volume. It is recorded once per
  `(store, command)` and re-run only when the store's fingerprint drifts.
- **The query is issued by the agent, not by the provider.** `address` returns the instance handle; the
  agent execs the command through the same route `applyVia: compose-exec` already documents. Adding a
  fourth provider operation to run it would let the provider certify its own output, which is the property
  DS29 spent a whole rationale removing from `reap.sh`.

### The provider contract (D5, D7)

**DS35 — Three operations, plain-string output, identity re-verified inside `destroy`, and no engine anywhere in the signature.**

```
usage:  sh scripts/provider-docker.sh provision <hash8> <worktree> <store> <source-volume> <image> <label>...
        sh scripts/provider-docker.sh address   <hash8> <worktree> <store>
        sh scripts/provider-docker.sh destroy   <hash8> <worktree> <store>
stdout: tab-separated records only — volume / instance / bytes / seconds / host / port / env / refused
exit:   0 ok · 2 usage · 3 refused, nothing created or removed · 4 environment failure
```

| Operation | Takes | Returns | Post-condition |
|---|---|---|---|
| `provision` | the source volume name and the image reference — both runtime facts `discovery.md` §1 already resolved — plus the label set | `volume<TAB>…`, `instance<TAB>…`, `bytes<TAB>n`, `seconds<TAB>n` | the copy volume exists, carries **this repository's complete label set**, and its measured byte count is non-zero. That is a structural post-condition, **not** proof of isolation — DS34 is |
| `address` | the same triple | `host`, `port`, `instance`, and zero or more `env<TAB>KEY<TAB>VALUE` | a value, never a delivery: the launch's existing channel carries it, and where no route does the pair refuses **before** launching, the same rule `isolation.env` already lives under (`discovery.md` §6) |
| `destroy` | the same triple | nothing on stdout | the instance and the copy are gone, or the run **fails loudly naming what it left** |

| | |
|---|---|
| **Choice** | The copy is taken by a second container mounting the source volume `:ro` and the destination `rw`, from the store's own image, so the base engine is never signalled, stopped, or reconfigured (Q2). `address` attaches the copy to the base stack's network, so a container-run overlay reaches it by DNS name and a host-run overlay by a published port; both are returned. |
| **Alternative** | `docker cp` through the host filesystem. **Alternative**: a fourth `verify` operation. **Alternative**: a `snapshot`/`restore` pair. **Alternative**: pass the engine name so the provider can pick a copy strategy. |
| **Rationale** | Copying through the host would put 10 GB on the host filesystem and violate the provider carve-out, which is bounded to *runtime objects*, not to files. A fourth operation lets the provider certify itself. `snapshot`/`restore` is Kubernetes's spelling of `provision` and does not generalise downward. And an engine parameter is the whole premise failing: **`provision` cannot name PostgreSQL and still be the operation this design claims it is.** |

**Why `destroy` is safe, given this project's history.** The rule is `reap.sh`'s, adapted rather than
re-invented: **the actuator re-verifies, the caller only names.**

| Guard | Detail |
|---|---|
| Scoped query only | The target is re-found with `--filter label=stackgraft.repo=<hash8>` plus the complete label set. An unfiltered listing never reaches the mutation path, exactly as DS29's query 3 never does |
| Worktree equality, not liveness | `destroy` removes only objects whose `stackgraft.worktree` label **equals the worktree argument**, normalised on both sides per DS27. Reaping supplies the orphan's recorded path; a teardown supplies its own. "Destroy another worktree's copy" is unreachable without the caller naming that worktree |
| No label set, or an unrecognised `stackgraft.labels` | Reported, never removed — the same fail-safe direction as an unrecognised `schemaVersion` |
| Flags | A copy **this run provisioned** is destroyed flaglessly (Q1 requires it on a failed verification). A copy from an earlier run is reaping and takes the mutation flag **and** the removal flag, per `orphan-reclamation` |
| Order and failure | Instance first, volume second; a volume that will not remove is an exit 4 that names it, the `with-lock.sh` unremovable-aside precedent |
| Never | `docker volume prune`, `docker system prune`, `compose down --volumes`, or any unfiltered removal — the destructive-verb class judged by effect, applied to the skill's own script |

**The second runtime, on paper**, which IP-1 requires before the shipped one is implemented:

| Operation | Docker (shipped) | Kubernetes (declared, unbuilt) | Host-native (declared, unbuilt) |
|---|---|---|---|
| `provision` | `volume create` + a copy container mounting source `:ro`, then run the same image on it | `VolumeSnapshot` → `PersistentVolumeClaim` from it → a pod of the same image bound to it | copy the data directory, start a second engine process on another port |
| `address` | container name on the base network, published host port, env pairs | `Service` DNS name and port, or a port-forward for a host-run overlay | `127.0.0.1:<second port>` |
| `destroy` | `rm -f` the instance, `volume rm` the copy, both label-scoped | delete the pod and the PVC, both label-scoped | signal by recorded `(pid, lstart)`, remove the data directory |

Managed and remote stores reach none of this: discovery records eligibility (`topology-discovery`), an
undeterminable locality is **remote**, and remote refuses by name with the recorded reason carried into the
message. Host-native refuses as *unbuilt*, not as impossible.

### Free space (Q6, IP-5)

**DS36 — There is no global budget. The check is a candidate, not a guarantee, and the run says which filesystem it measured, what this repository already holds there, and what it cannot see.**

Fifteen worktrees can each pass their own check and still fill the disk, because no worktree knows
another's copies before they exist. The reap pass sees them, but it is report-only and takes no lock.

| | |
|---|---|
| **Choice** | **No reservation ledger.** The per-copy check stays and is made against **two** filesystems — the runtime's data root, measured by one `df -P /` inside a throwaway container, and the host filesystem holding the cache directory — because the runtime's data disk is a sparse image that grows into the host, so the host figure is the binding one (Q6). Either unmeasurable ⇒ refuse. The projected size is the source volume's **measured** size, never an estimate; unmeasurable ⇒ refuse. Beside it the run reports the count and total bytes of **this repository's** copies already on that filesystem, derived from the scoped label query the report pass already makes every invocation. |
| **Alternative** | A host-global byte ledger in the cache directory, written under `with-lock.sh`, reserving before a copy and releasing after a destroy. |
| **Rationale** | The ledger is bounded, host-global, owned by nothing, and requires release — **the exact object Q4 deleted the integer allocator for**, in a different unit. A crashed run leaks a reservation permanently, and a lock on the read path contradicts D9 obligation 3. It would also still not be a budget: the disk is shared with image pulls, build caches, and every other tool on the machine, so a reservation that binds none of them is a number that looks authoritative and is not. The honest formulation is this repository's own, already earned by `pick-port.sh`: **the check narrows the unknowable set without closing it.** |

Three consequences stated rather than smoothed over.

- **IP-5's "refused *before* it starts rather than failed during it" is not achievable across concurrent
  worktrees**, and the spec sentence overstates what any check can do here. It holds for everything the run
  can see; two runs that pass simultaneously can still collide. See *Locked decisions this design cannot
  deliver as written*.
- **A copy that runs out of space mid-write is the provider's own cleanup obligation**: remove the partial
  volume, exit 3, refuse the pair. The partial must not survive a failed provision any more than it
  survives a refusal.
- **The declared blind spot**, printed with the numbers: another worktree's copy that does not exist yet,
  another repository's copies, and anything else competing for the disk are not counted and cannot be.
  The stated limitation is that the cache directory's filesystem is assumed to be the one backing the
  runtime's disk image — usually true on a single-user laptop, and a stated assumption rather than a check.

### The generated lifecycle target (Q5)

**DS37 — The skill writes its own new files and never edits one it did not author; a generated target is `inferred` until a run has observed its create and its drop succeed.**

When the skill writes a repository's `db-create`, that file becomes discoverable at rung 1 —
`declared`, the highest confidence — and its fingerprint is the fingerprint of a file the skill itself
authored. Every other `declared` record has something independent whose drift re-derives it.

| | |
|---|---|
| **Choice (falsifier)** | A generated target is recorded **`inferred`** until a run has observed *both* halves succeed against the discovered store, recorded as an event with its timestamp and exit status. Only that observation raises it to `declared`. Consent is the second, independent falsifier: `isolation.approval.sourceFingerprint` is taken over the file **as the human approved it**, so any later edit — the skill's own included — drops the approval and re-shows the template. |
| **Alternative** | Treat a generated target as `declared` on write, since a human approved it. **Alternative**: mark it permanently `inferred`. |
| **Rationale** | `declared`-on-write makes the claim and its evidence the same author, which is the shape "a gate on an optional field is no gate" describes. Permanently `inferred` means the optimisation can never be taken, so Q5's whole point — closing the wall that made the cheap path unreachable — is lost. **The observation is the only fact the skill cannot write on its own behalf**, and it is already half-required: the teardown is inert until a create has been seen to succeed, so the event is being recorded anyway; this makes it load-bearing instead of incidental. Until then the default seeded copy resolves the pair, so nothing refuses for want of a target. |

| | |
|---|---|
| **Choice (where)** | **Two new executable files under the repository's existing script directory** (`bin/`, `scripts/` — whichever discovery found, never a new convention), one create and one drop per store, named from the discovered `backingStores` key. **The skill never appends to `Makefile`, `Taskfile.yml`, `justfile`, or `package.json`.** |
| **Alternative** | Append a `db-create-<store>` target to the repository's `Makefile`. |
| **Rationale** | Appending edits repository source the skill did not write, in a file whose grammar is whitespace-significant — a recipe line indented with spaces is a silent break — and whose `.PHONY`, variable and include context the skill cannot fully model. It also entangles the diff with the developer's own work and makes rollback text surgery rather than a file deletion. A new file is discoverable by rung 1's `bin/*` arm with no edit to anything a human owns, and **the shipped template contract already names this as the intended shape**: "a repo that genuinely needs a shell puts the line in its own task target, which is rung 1". The recorded command then invokes one program with arguments and satisfies the argv, deny-list, and no-re-parse rules with no exemption. |

**The generator's output is checked by the same contract as repository input, with no exemption for being
the skill's own.** The destructive-verb class, judged by effect, is applied to the generated drop before
it is shown; the store name comes from the discovered key and is never invented; the content is shown in
full before writing; nothing is staged, committed, or pushed by the skill.

### Copy age (Q3, IP-4)

**DS38 — The copy's age is reported, because it is the only one the run can measure; the data's age is stated as unmeasured rather than implied.**

The two clocks diverge the moment the base store is restored, reseeded, or migrated.

| | |
|---|---|
| **Choice** | The output states three things and no fourth: the **absolute timestamp** the copy was taken, the **elapsed time** since it, and the standing sentence that this is the age of the **copy** and that the state it holds is the base store's **as of that timestamp** — which says nothing about how far the base store has moved since, because the run does not compare and does not know. One cheap fact is added because it is observable rather than inferred: where the base store's **runtime instance identity has changed** since the copy — the container was recreated, which is what a restore or a reseed usually does — the run says so; where that identity cannot be read, it says the comparison was not made. |
| **Alternative** | Report a data age by querying both stores for a maximum timestamp. **Alternative**: report only an interval. **Alternative**: refuse or auto-refresh on age. |
| **Rationale** | A max-timestamp query is engine-specific *and* schema-specific — the per-substrate knowledge D5 removes, in its most fragile form. An interval alone is worse than a timestamp because it invites the reader to compute the data's age from it. Refusing on age is forbidden by IP-4 in as many words, and auto-refresh would silently pay the measured cost on a run the developer did not ask it of. **The wording is a requirement, not a style note**: "data is N old", "up to date as of", "stale" and "fresh" are all comparisons the run did not perform, and none may appear. |

### The name family (D8 as amended by Q4)

**DS39 — One hash, one separator-free slug, two projections, and a per-store declaration of which projection the substrate accepts.**

F1 and F2 are one defect twice: a single generated shape cannot name every substrate's namespace. The fix
is a derivation, not a table of exceptions.

| Stage | Rule |
|---|---|
| `hash8` | first 8 characters of `printf '%s' "<full branch name>" \| git hash-object --stdin`, over the **untruncated** branch name — unchanged |
| `slug` | lowercase the branch; split on every run of characters outside `[a-z0-9]`; drop empty segments; **the slug is a list of alphanumeric segments and carries no separator of its own**; truncate the joined length to 28; if nothing survives, `x` |
| projection | each consumer joins the same segments with **its own** separator and prefix |

| Form | Prefix | Join | Grammar | Generator ceiling |
|---|---|---|---|---:|
| SQL identifier | `sg_` | `_` | `^[a-z][a-z0-9_]{0,39}$` | 40 |
| DNS / object-store label | `sg-` | `-` | `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, ≤ 63 | 40 |

| | |
|---|---|
| **Choice** | The separator belongs to the **projection**, never to the slug. Which projection a consumer takes is a **per-store recorded field**, discovered from the substrate's own rejection surface, drifting and expiring like every other record; a store declaring none is undetermined and refuses. |
| **Alternative** | Post-process the SQL form into a label (`tr '_' '-'`). **Alternative**: a per-substrate table of accepted forms in the skill. **Alternative**: keep D8's integer member. |
| **Rationale** | Post-processing is where F1 came from — one canonical shape and a rule someone has to remember to apply. Making the separator the projection's makes "no underscore in a label" true **by construction**, not by review. A per-substrate table of forms is the finite prose table again, one door further along; a recorded field per store grows without an edit to the skill and expires when the store changes. The integer member is deleted per Q4: it is an *allocation* from sixteen host-global slots that nothing owns, undetectable on collision, for eight kilobytes of saving. Both forms are ≤ 40 characters at a 28-character slug, so the label's 63 is the grammar's ceiling and not the generator's — the two forms are always the same length and always distinguishable by separator alone. |

Edge cases closed by construction rather than by rule: a slug starting with a digit is fixed by the `sg_`
prefix; a label starting or ending in a hyphen is impossible because it ends in hex `hash8`; uppercase
cannot occur; an empty slug becomes `x`. The SQL form is byte-identical to `1.1.0`'s for the same branch,
because joining the same segments with `_` under `sg_` **is** the old transform. **A third form is added
only when a substrate rejects both and its rejection is recorded — never in advance.**

### Change-scoped pair selection (D2, T1)

**DS40 — The diff selects units; only a record answers stores. Derive, then remove, then re-insert, then classify — in that order.**

| Pass | Operation | May it narrow? |
|---|---|---|
| 1 | Changed paths → units through `paths`, plus `consumers` fan-out from non-runnable trees | unchanged |
| 2 | **Derive**: every selected runnable unit × every `backingStores` entry, plus `dependsOn` names resolving to stores | **no** — `dependsOn` may only add, unchanged |
| 3 | **Remove** one pair at a time, each on its own `(unit, store)` determinacy record | **only here** |
| 4 | **Re-insert** on an escalation trigger, which reads the launched process's behaviour rather than the diff | widens only |
| 5 | Classify the survivors — W, X, N, one verdict each | unchanged |

**What counts as reaching a store**: nothing in the diff, by itself, ever answers that. A pair leaves the
subject only when a record for **exactly that pair** states the changed code does not reach that store,
its `serviceFingerprint` still matches the unit's source, and its confidence is `declared`. Absent record,
drifted fingerprint, `inferred` or `user` confidence, or a record about another store — all leave the pair
in. A unit that "reaches no store" is not a special case: it is the same rule applied to every store of
that unit, each still requiring its own record.

**Why one-directional.** The two errors are asymmetric — removing a pair that should have been gated is a
silent write into shared state, keeping one that could have been relieved is a copy nobody needed. And it
is structural: a record may only subtract from a set derived independently of it, so **the laziest manifest
yields the largest subject and the most refusals**, which is the property `dependsOn`'s prohibition exists
to preserve. T1 is a spec requirement, not commentary: `references/shared-state.md` restates the
`dependsOn` prohibition **beside** the narrowing rule, in those words.

**Why it cannot relieve the writes a unit's own launch performs.** Pass 4 runs after pass 3 and outranks
it. `migrates` names the stores the entrypoint is pointed at; those pairs are re-inserted with W=yes
whatever the diff touched — the frontend-only diff against a service that creates schema at startup.
Where the pointing is unknown, **every** store of that unit is undetermined and refuses, so an unscoped
`migrates` cannot be laundered into relief by a small diff. A pair may be removed in pass 3 and returned
in pass 4 within one run, and the run names both events.

**What the run reports**, so a narrowing is visible rather than inferred: the derived count, each removed
pair with the record that removed it, each re-inserted pair with the trigger that returned it, and the
gated count — **beside** the derived one, never in place of it.

### Slicing (D10)

**DS41 — Seven slices, not five: two of D10's exceed the review budget and Q7 removed one entirely.**

| | |
|---|---|
| **Choice** | Split D10's slice 1 into 1a/1b and slice 4 into 4a/4b, drop D10's slice 5 (D9, out per Q7), and add a final slice for Q5's generated target. Release once, after the last one. |
| **Alternative** | Keep five slices and accept the size. **Alternative**: merge Q5 into slice 4. |
| **Rationale** | D10 forecast slice 1 at ~400 lines before `schemaVersion` 3 also required `assets/manifest.example.json` rewritten whole, and forecast slice 4 at ~400 before Q1's verification, Q3's lifetime, Q6's space check and T3's reap integration were all locked into it — both now land 450–650. Splitting 1a out has a second benefit the budget makes decisive: **the body's adds and cuts land in a commit with nothing else in the diff**, so the word count is reviewable in one screen instead of buried in a schema rewrite. Q5's generated target must land *after* the seeded copy exists, because its whole safety property is that a declined offer falls back to the default rather than refusing. |

| # | Slice | Content | Lines | Depends on |
|---|---|---|---:|---|
| 1a | Scope and body budget | D1, T4. `description`, `compatibility`, Activation Contract, the DS33 cuts, README, `docs/`; `verify.sh` gains a `description` measure and recalibrated body fixtures | ~140 | — |
| 1b | Per-store determinacy | D3. `schemaVersion` 3, `writes` removed, `migrates` scoped, example rewritten, discovery's classification pass, the per-store reading in `shared-state.md` | ~350 | 1a |
| 2 | Change-scoped gating | D2, T1. The narrowing rule with its evidence obligation and the `dependsOn` prohibition inline; pass order; the reported counts | ~280 | **1b** |
| 3 | Coordination identity | D4 (X), D8/Q4. `references/coordination-identity.md`, the knob rows moved out of `shared-state.md`, the name family, the allocator deleted, closed placeholder set updated | ~380 | 1b |
| 4a | Provider and copies | D5, D6, D7, Q2, Q6, T2, T3. `references/isolation-providers.md`, `scripts/provider-docker.sh`, free space, labels, reap integration, `SECURITY.md` | ~380 | **3** |
| 4b | Verification and lifetime | Q1, Q3. The readback and its discriminator, copy lifetime and age, refusals by name, Output Contract | ~300 | 4a |
| 5 | Generated lifecycle target | Q5. Offer, show, approve, write; `inferred` until observed; inert teardown; the four version numbers and `CHANGELOG.md` | ~250 | 4b |

Ordering is the proposal's, preserved: **1b before 2** (narrowing without per-store evidence is the exact
failure `shared-state.md` was written to stop) and **3 before 4a** (an identity that ends the competition
removes a pair that would otherwise demand a copy — build the free mechanism before the gigabyte one).
Stacked onto one feature branch; PR 1a targets it and each child targets its predecessor. **No slice
publishes.**

## Data Flow

```
diff ──► units (paths, consumers) ──► DERIVE pairs: units × backingStores        (DS40 pass 2)
                                          │
              determinacy records ────────┼──► REMOVE, one pair, one record       (pass 3)
              escalation triggers ────────┼──► RE-INSERT, W=yes                   (pass 4)
                                          ▼
                                     CLASSIFY  W · X · N                          (pass 5)
                                    ╱                    ╲
                             X ────╱                      ╲──── W
                    coordination-identity              isolation-providers
                    knob · base value · env             df ×2 + measured size (DS36)
                    route · distinctness                      │ short/unknown ─► REFUSE
                          │ any unproven ─► REFUSE            ▼
                          ▼                            provision  volume :ro ─► copy ─► instance
                    delivered at launch                       │  (base engine never signalled)
                    (discovery.md §6 route)                   ▼
                                                        address  host · port · instance · env
                                                              │
                                                        DS34 readback:
                                                        base ──cmd──► out ═══ copy ──cmd──► out ?
                                                              │              │
                                                       differs from an       └─ mismatch ─► destroy, REFUSE
                                                       empty instance? ──no──► not a query ─► REFUSE
                                                              │ yes
                                                              ▼
                                                        ISOLATED ─► launch, report age (DS38)
                                                              │
                                              teardown / reap ─► destroy (label + worktree equality, DS35)
```

## File Changes

| File | Action | Slice | Description |
|---|---|---|---|
| `skills/stackgraft/SKILL.md` | Modify | 1a | `description` scope; `compatibility` provider clause; Activation Contract; the DS33 adds and cuts, one commit |
| `skills/stackgraft/SKILL.md` | Modify | 4b | Output Contract bullet 5 names the copy and its age |
| `skills/stackgraft/SKILL.md` | Modify | 5 | `version` and `metadata.version` → 2.0.0 |
| `skills/stackgraft/references/shared-state.md` | Modify | 1b | Determinacy read per store; the all-or-nothing reading named as the defect |
| `skills/stackgraft/references/shared-state.md` | Modify | 2 | The narrowing rule, its evidence obligation, the `dependsOn` prohibition restated beside it, the pass order |
| `skills/stackgraft/references/shared-state.md` | Modify | 3 | Identity procedure and the knob rows move out; the **In-instance isolation column** of the per-substrate table is deleted, the catches stay |
| `skills/stackgraft/references/shared-state.md` | Modify | 4a | ISOLATE means a seeded copy; in-instance kept as the optimisation with every rule intact |
| `skills/stackgraft/references/shared-state.md` | Modify | 5 | The generated-target offer, its three constraints, and its `inferred`-until-observed rule |
| `skills/stackgraft/references/coordination-identity.md` | Create | 3 | Knob per substrate, distinct/delivered/confirmed, the name family, no allocator |
| `skills/stackgraft/references/isolation-providers.md` | Create | 4a | The three operations, the Docker implementation, the second runtime on paper, free space, copy ownership and lifetime, refusals |
| `skills/stackgraft/references/isolation-providers.md` | Modify | 4b | The readback, the discriminator, the age wording rules |
| `skills/stackgraft/references/discovery.md` | Modify | 1b | Per-pair classification pass; `migrates` pointing; provider eligibility |
| `skills/stackgraft/references/discovery.md` | Modify | 3 | Knob, base value, variable and route recorded |
| `skills/stackgraft/references/discovery.md` | Modify | 4b | `healthcheck` harvested as a verification candidate; exec-form only |
| `skills/stackgraft/references/reaping.md` | Modify | 4a | Store copies as labelled reap targets, both flags, unknown ≠ zero |
| `skills/stackgraft/references/traps.md` | Modify | 2, 4a, 4b | A diff that under-reports a store; a copy that started but was never verified; an age read as data freshness |
| `skills/stackgraft/scripts/provider-docker.sh` | Create | 4a | DS35 |
| `skills/stackgraft/assets/manifest.schema.json` | Modify | 1b | `schemaVersion` 3; determinacy records; `writes` removed; `migrates` scoped |
| `skills/stackgraft/assets/manifest.schema.json` | Modify | 3, 4a, 4b | Name-family placeholders; provider reference; verification record |
| `skills/stackgraft/assets/manifest.example.json` | Modify | 1b, 3, 4a | Rewritten against schema 3, then extended |
| `.github/scripts/verify.sh` | Modify | all | The rows below |
| `README.md`, `docs/SHARED-STATE.md`, `docs/HOW-IT-WORKS.md` | Modify | 1a, 4a | Scope; isolation now means a copy |
| `SECURITY.md` | Modify | 4a | The copy as a data surface (T2) |
| `CONTRIBUTING.md` | Modify | 1a | The budget paragraph, corrected to the measured number |
| `CHANGELOG.md`, `.claude-plugin/{plugin,marketplace}.json` | Modify | 5 | 2.0.0, breaking |

**Slicing correction, same shape as `overlay-reaping`'s.** `references/isolation-providers.md` is created
in **4a**, not 4b, because `shared-state.md`'s slice-4a edit backlinks to it and `verify.sh`'s link loop
resolves every backticked `references/…` path — a dangling link fails slice 4a's own CI. Every backticked
camelCase token this design introduces (`determinacy`, the verification record, the provider reference)
must land in `manifest.schema.json` **in the same slice as the reference file that names it**, because
`check_schema.py` cross-checks `references/*.md` against the schema and widening its `FOREIGN` list is how
that check stops being able to fail.

## Portability and the folder contract

Per `rules.design`. `scripts/provider-docker.sh` is justified against the agentskills.io folder contract on
the same ground as `pick-port.sh`, `fingerprint.sh`, `with-lock.sh` and `reap.sh`: it is a helper the
**agent invokes**, not a library, and `scripts/` is that folder's declared purpose. The two new
`references/` files exist because progressive disclosure loads them only when the procedure reaches them —
which is also why neither is named in the body.

Runtime is unchanged and needs no install step: POSIX `sh` plus POSIX `awk`, invoked as
`sh scripts/provider-docker.sh`, so neither the executable bit nor the shebang is load-bearing (DS19).
Every daemon value the provider needs is requested as a **plain string** (`--format '{{.Name}}'`-shaped),
never JSON, so `jq` never appears — and `$PORTABILITY` is case-insensitive and intent-blind, so the word
must not appear in the new reference files' prose either. Non-Claude agents are affected in exactly one
way: the container runtime becomes a **conditional** dependency for a second reason (store copies as well
as container repos), declared in `compatibility` beside the existing condition, and a run without it
refuses by name rather than degrading.

## Verification Plan

`openspec/config.yaml` records no test runner; these extend `.github/scripts/verify.sh`, which pairs every
assertion with a negative. Twenty-two vacuous checks were found in the last audit, so every row below
states what must be **rejected**, and the negatives reuse the shipped helpers rather than second copies of
them.

| # | Positive assertion | Paired negative |
|---|---|---|
| 1 | `body_words` reports ≤ 500 and the slice's recorded figure (1a: 485; 4b: 488) | the over-ceiling fixture is **rederived** as `501 - body_words(SKILL.md)` filler words and must fail — a hard-coded 38 no longer sits one word over |
| 2 | `description` is one quoted physical line of ≤ 250 characters, measured by a `desc_measure()` modelled on `compat_measure` | four fixtures, as `compatibility` has: deleted, unquoted, embedded quote, 251 characters — **this check does not exist today and the change edits the field** |
| 3 | `compat_measure` ≤ 500 with the provider clause present | the clause kept while its donor cut is reverted must fail, the DS32 fixture shape |
| 4 | The body contains no `REUSE`, `ISOLATE`, `REAP`, and no new verdict term | the loop fires on a fixture line naming each, the new ones included |
| 5 | The body names neither `isolation-providers` nor `coordination-identity` nor any hazard-to-mechanism wording | a fixture body carrying a gate row whose action cell reads *Copy it* must be rejected by that grep |
| 6 | `provider-docker.sh` passes `dash -n`, carries a shebang, and is in the named script inventory | the inventory notices it deleted, as it already does for `reap.sh` |
| 7 | The script names no `jq`, `python3`, `sha256sum`, `flock`, `timeout`, `lsof`, `ss`, and no GNU-only construct | `$PORTABILITY` and `$GNUISM` fixtures, and the new `references/` prose is scanned too |
| 8 | `provision` → `address` → `destroy` leaves the **host filesystem** byte-identical outside the runtime objects it made | a fixture provider writing one file beside the destination is caught by `unreported_debris` |
| 9 | `destroy` removes a copy whose `stackgraft.worktree` equals the argument | the same copy with a *different* worktree argument, an unlabelled volume, and a volume with an unrecognised `stackgraft.labels` all refuse and all still exist afterwards |
| 10 | A provision that runs out of space exits 3 and leaves no partial volume | the runtime's volume list before and after must be identical — an exit code alone cannot see a surviving partial |
| 11 | The space check interrogates the runtime's data root **and** the host filesystem, and names which one bound the decision | a probe that cannot answer for either ⇒ refuse; a check reading only the working directory's filesystem must fail the row |
| 12 | An exec-form `healthcheck` is harvested as a verification candidate | a `CMD-SHELL` healthcheck must **not** be, and the refusal names the shell form |
| 13 | A candidate whose output differs against an empty instance is recorded as a query | a candidate whose output is identical on an empty instance (`PONG`, `accepting connections`) is **rejected as a query**, and the pair refuses |
| 14 | A copy seeded from a good volume matches the base's readback and counts as isolated | a copy from a deliberately truncated volume mismatches ⇒ destroyed, pair refuses, and the overlay's peer configuration is inspected to prove it was **not** wired to the base store |
| 15 | The base store's container uptime, restart count and open connections are unchanged across a copy | a fixture that stops the base store must fail this row, so it can report a disturbance |
| 16 | Two launches from one worktree reuse one instance identity and report the age | a run that provisions, refreshes and destroys nothing still prints the age line — its absence fails |
| 17 | No shipped file states an expected, typical, or worst-case duration | a fixture line "typically 51 s" is caught by that grep |
| 18 | No shipped file states a data age: no "up to date as of", "stale", "fresh" beside a copy | fixture lines for each must be caught |
| 19 | The SQL form is byte-identical to `1.1.0` for a fixed branch; the label form carries no `_`, is ≤ 63, and is alphanumeric at both ends | two branches whose slugs truncate identically must differ in **both** forms; a generator that post-processes `_`→`-` must fail the byte-identity row |
| 20 | No shipped file describes an allocation, a slot pool, an exhaustion case, or a release obligation for a name | a fixture naming "16 logical databases, allocated per worktree" is caught |
| 21 | A frontend-only diff against a multi-store repository gates zero pairs and reports each removal with its record | the same diff against a unit recorded as migrating re-inserts that pair with W=yes and names the trigger |
| 22 | A manifest with a record for one store and none for another validates and classifies each separately | a manifest carrying a service-level `writes` array is rejected by the schema |
| 23 | `references/shared-state.md` states the `dependsOn` prohibition **inside** the narrowing rule | a copy of that file with the prohibition deleted must fail the row — proving the check reads the sentence and not the file |
| 24 | Both new `references/` files resolve and pass `check_schema.py`'s cross-check | its existing `notAManifestField` self-test proves the cross-check can fail |
| 25 | The generated target is recorded `inferred` before first use and `declared` after an observed create-and-drop | a target written and never run must **not** satisfy the gate; a generated drop aimed at a name not derived from the name family is rejected by the destructive-verb rule |
| 26 | The four version numbers agree at 2.0.0 with a breaking `CHANGELOG.md` entry | the existing partial-bump fixtures |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths (repository data executed) | **Applicable** — `healthcheck.test` and lifecycle targets become commands this skill runs against a store | DS34: the shipped template contract applies unchanged; exec-form only; deny-list, argv, no-re-parse, closed placeholders | 12, 13 |
| Shell commands and subprocesses | **Applicable** — a new script, a copy container, an exec'd query | DS35: plain-string output, no JSON, no shell fallback, argv for every repository-authored element | 6, 7, 8 |
| Executable-file classification | **Applicable** — DS37 writes executable files into the user's repository | New files only, under a directory discovery already found, content shown in full, store name from the discovered key, generator output judged by the destructive-verb class | 25 |
| Container and volume destruction | **Applicable** — `destroy`, and the reopened volume non-goal | DS35: scoped query, worktree equality normalised per DS27, no label ⇒ report only, two flags on the reap path, loud failure on a surviving volume, never a `prune` | 9, 10 |
| Git repository selection | **Applicable** — `stackgraft.worktree` decides destroy-or-not | DS27 reused verbatim: both sides `CDPATH= cd -- … && pwd -P`; an unnormalisable path is unproven, never a target | 9 |
| Commit state | **Applicable** — DS37 writes into the working tree | The skill writes files and **never stages, commits, or pushes**; the human's pull request is the review | 25 |
| Push state / PR commands | **N/A** — the skill never pushes and automates no PR | — | — |
| Routing | **N/A** — no request routing is introduced | — | — |

## Migration / Rollout

`schemaVersion` 2 → 3 once, in slice 1b, with **no migration path by design**: every field is
re-derivable, so an unrecognised version discards the cache and rediscovers, which is also how a `3`
manifest survives a rollback to `1.1.0`. No slice publishes; `2.0.0` releases after slice 5. Two things do
not revert themselves and belong in the release notes: a `3` manifest is unrecognised by `1.1.0` and is
discarded, and **any store copy created while 2.0 was live stays on disk, labelled, removable with the
documented command** — and any lifecycle target the user approved stays in their repository, where it is
now theirs.

## Open Questions

- [ ] **Blocking before slice 4b** — how many of the 43-service repository's four stores declare an
      **exec-form** `healthcheck`? DS34 makes an underivable query a refusal, so if the answer is "few",
      2.0 copies gigabytes and then refuses on exactly the repository that motivated the change. One
      command settles it against the resolver output already being run. If the coverage is poor, rung 2
      has to be widened *before* slice 4b, not after.
- [ ] **Blocking before slice 4a** — does the shipped `--format` string surface a volume's byte size as a
      plain string on the Docker versions users run? DS36 refuses when the size cannot be measured, so a
      missing field turns every copy into a refusal rather than a degraded report. Fail-safe, but the
      remedy differs by answer.
- [ ] Non-blocking: whether the cache directory's filesystem is the one backing the runtime's disk image
      on every supported platform. Stated as an assumption in DS36; wrong only makes the host figure
      conservative in one direction, and the run says which filesystem it measured.
- [ ] Non-blocking: whether a store image without a shell (distroless) can host the copy container. The
      copy uses the store's own image; where it cannot run one, the provider refuses and names it.
- [ ] Non-blocking: `podman` and `nerdctl` volume-and-label parity with the Docker provider. A wrong guess
      produces a refusal, not an unlabelled copy.

## Locked decisions this design cannot deliver as written

Stated plainly rather than designed around, because the proposal was rewritten twice for exactly that.

1. **T4's donor does not exist.** "The substrate table leaves the body entirely" — the per-substrate table
   has never been in the body; it is in `references/shared-state.md`. The body's only isolation content is
   one Output Contract bullet and the sealed Hard Rule. The net-negative obligation still closes (DS33),
   but out of unrelated compaction, and T4's stated mechanism must be corrected rather than implemented.
2. **"The substrate namespace table is gone" cannot be taken literally.** `shared-state-safety`'s renamed
   requirement keeps in-instance isolation with *every* rule intact (Q5) while its Verify clause says the
   substrate table is gone. `coordination-identity` needs that table's knob rows, and four of the six cases
   with no safe answer rest on its "catch" column — Redis pub/sub, Kafka's group, RabbitMQ's round-robin,
   the leader-elected worker. **What must be deleted is the *In-instance isolation* column, not the
   table.** A reader who deletes the table deletes the evidence for the refuse-cases, which is the T1
   hazard wearing different clothes, and the spec sentence must be narrowed to the column before slice 3.
3. **IP-5's "refused *before* it starts rather than failed during it" is not achievable across concurrent
   worktrees.** No worktree can see a copy another worktree has not yet made, and the only thing that
   would close that window is the host-global reservation ledger DS36 rejects for being the allocator Q4
   deleted. The requirement holds for everything one run can see; beyond that the honest wording is this
   repository's own — **a candidate, not a guarantee** — with a mid-copy failure that cleans up its own
   partial. The spec sentence overstates what any check can do here and should be reworded.
4. **D10's five slices are seven.** Two exceed the 400-line review budget once the answered questions are
   folded in, and Q7 removed the original slice 5 from 2.0 entirely (DS41).

---

## Amendments after measurement

**DS42 — the generated target family is three files, not two. DS34 rung 2 has no source otherwise.**

DS34's rung 2 accepts "a **read** command from the repository's own lifecycle target family … or DS37's generated pair". DS37 generates a **create** and a **drop**. Neither reads, so the pair it generates cannot supply rung 2, and the chain that was supposed to close does not.

Measured against the 43-service repository that motivated this change, every rung fails:

| store | rung 1 | why |
|---|---|---|
| postgres | ✗ | `CMD-SHELL`, excluded by DS34's argv rule |
| timescaledb | ✗ | `CMD-SHELL`, same |
| redis | ✗ | exec-form, but `redis-cli ping` answers identically on an empty instance — it fails the discriminator |
| minio | ✗ | exec-form, but it is a health endpoint, the one shape IP-2 names by name |

All four fall to rung 2, which does not exist, and then to rung 3. **2.0 would copy 10.7 GB and refuse every pair for want of a verification query** — the failure DS34's own risk row anticipated, reached by a path nobody traced.

**Correction: DS37 generates three files per store — create, drop, and read.** The read is the verification probe and is held to DS34's discriminator like any other candidate: it qualifies only once its output is shown to differ against an empty instance of the same image. A generated `SELECT 1` fails that test and must, exactly as `pg_isready` does.

This does not put engine knowledge into the skill, and the distinction is the one D5 rests on. The skill carries no query table. **The agent writes an engine-appropriate probe once, at generation time, with the human approving it, and from then on the file is the repository's** — versioned, reviewable, and subject to DS37's existing falsifiers: `inferred` until a run has observed it, and the approval fingerprint dropped by any later edit.

A schema-agnostic read is what to generate, because the skill has no schema: something that counts what an instance carries rather than naming a table the repository owns. An empty instance answers zero; a seeded one does not. That is precisely the discriminator DS34 already requires, so the generated read is tested by the mechanism that was already there.

**Consequence for slicing.** The generated read belongs to slice 5 with the rest of DS37, but slice 4b's verification cannot be demonstrated end to end against a repository with no exec-form discriminating healthcheck until slice 5 lands. Either 4b's acceptance uses a fixture that has one, or the read moves forward into 4b. That is a tasks decision, and it must be made deliberately rather than discovered when 4b is verified against the repository this change exists for.
