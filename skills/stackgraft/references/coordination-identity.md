# Coordination identity: the name that ends the competition

The coordination hazard — **X** in the verdict procedure — is the overlay attaching to a coordination primitive and taking work away from the base stack: a consumer group, a queue subscriber, an advisory or leader lock, a replication slot, a scheduler singleton. Its damage lands on the base stack's **behaviour**, inside a service nobody modified. `references/shared-state.md` decides whether a pair carries X; this file is the only source of what answers one, and recording something here answers nothing on its own — a pair is re-classified only by the proof below.

**X is answered by a distinct identity — a name — and never by a copy of the store.** Cloning a broker to avoid a consumer-group collision spends gigabytes and minutes on a hazard one string ends, and an overlay attached to its own copy is not exercising the coordination the base stack runs. Nothing here offers a copy as a remedy for X, because a mechanism that is permitted is a mechanism that will be reached for.

- **A pair carrying X and not W leaves the container runtime's volume and instance inventory unchanged.** Answering it creates no runtime object at all: the whole mechanism is a value and the channel that carries it.
- **A pair carrying X and W takes both mechanisms, recorded separately.** A private copy of a broker's storage does not stop the overlay joining the base stack's group on the base stack's broker, so the copy alone leaves X undetermined, which refuses, and no copy is ever recorded as having answered X.

## What is this substrate's identity knob

This table answers one question and only that one: **what is this substrate's identity knob.** It does not answer *how do you create a namespace inside this substrate* — that open-ended question is what turned a finite prose table into the gate for an unbounded set of stores, and it belongs to the data hazard, which answers it once per runtime rather than once per engine.

| Coordination primitive | Identity knob | Does a distinct value end the competition? |
|------------------------|---------------|--------------------------------------------|
| Kafka consumer group | `group.id` | **Yes** — a distinct group takes no partition from the base group |
| NATS or JetStream durable consumer | `durable` — the durable name | **Yes** — a distinct durable carries its own cursor |
| NATS subject space | `subject-prefix` | **Yes** — a distinct prefix is a different subject |
| RabbitMQ queue | `queue` — the queue name | **No** for a queue the base stack already consumes: a second consumer round-robins with it, and no spelling of the name changes that |
| Advisory or leader lock | `advisory-lock` — the lock key | **No** — the primitive exists so that exactly one holder wins, and a second holder under another key is two leaders rather than one |
| Logical replication slot | `replication-slot` — the slot name | **No** — a second slot is a second retainer on the base primary and a second reader of one stream |

**A substrate absent from this table is undetermined, which refuses.** Adding a row is a judgement about a coordination primitive rather than a lookup, so an unlisted one is not handed the nearest answer. **A substrate whose competition no name ends refuses too, and is not given a name anyway** — those pairs are among the cases with no safe answer in `references/shared-state.md`, and none of them may be reclassified as solvable by an identity.

## An identity counts only when it is distinct, delivered, and substrate-confirmed

**Recording an identity does not re-classify a pair.** X is no only when three things are proven, and **any one unproven leaves X undetermined**, which refuses — so the loop terminates on evidence rather than on repetition.

**(a) Distinct.** The recorded value must differ from the value the base stack attaches under, read from the base stack's own configuration rather than assumed, and recorded beside it as `baseIdentity` on the pair's `competesOn` entry. A value that cannot be compared, because the base stack's own value could not be read, is not distinct — unreadable is not different.

**(b) Delivered.** The value must reach the launched process. The variable that carries it is the service's **own** variable for that identity key, discovered from the service's configuration and never invented, defaulted from a sibling, or guessed from a convention, and it is recorded as `overlayIdentityEnv`. The launch sets it in the overlay's environment, which for a container-run overlay is not the launching shell's, and it crosses only by a route the launch already has — recorded as `deliveryRoute` and enumerated in `references/discovery.md` section 6. Where no available route carries it the pair refuses **before** anything launches rather than after, and a value recorded but never applied leaves X undetermined exactly as an unrecorded one does.

**A store-level environment map is not that channel.** The store's own `isolation.env` belongs to the store and is shared by every service paired with it, so one overlay's identity would be handed to every one of them.

**(c) Substrate-confirmed.** The table above must confirm that a distinct value ends the competition on that substrate. Where it does not, no name helps and none is applied.

**Both the proven value and its channel are recorded**, or the re-classification does not persist and the pair is back at REFUSE on the next run — `overlayIdentity` holds what the overlay attaches under, and the `identity` beside it holds the knob's name, never its value.

**Say what a distinct identity changes.** An overlay with its own consumer group receives every message the base stack receives, so any externally visible side effect it then performs is now duplicated — mail, notifications, webhooks, charges — which the escalations in `references/shared-state.md` refuse on their own terms.

## The name family: one hash, one slug, two projections

`{{isolationName}}` was one generated shape, and one shape cannot name every substrate's namespace: the SQL identifier's underscores are forbidden in DNS labels and object-store bucket names, so every bucket this skill could name was rejected by the substrate itself. It is replaced by a family whose members all derive from one branch hash, which is what keeps them one logical namespace.

| Stage | Rule |
|-------|------|
| `hash8` | the **first 8 characters** of `printf '%s' "<full branch name>" \| git hash-object --stdin`, taken over the **untruncated** branch name, which is what keeps two branches sharing a truncated slug out of one namespace. The piping form is part of the rule: `echo` appends a newline and digests to something else |
| slug | lowercase the branch name, split it on every run of characters outside `[a-z0-9]`, and drop the empty segments. **The slug is a list of alphanumeric segments and carries no separator of its own.** Truncate the joined length to **28** characters, dropping a separator the cut left trailing; where nothing survives, use `x` |
| projection | each consumer joins **the same segments** with its own prefix and separator |

| Form | Placeholder | Prefix | Join | Grammar |
|------|-------------|--------|------|---------|
| SQL identifier | `{{isolationIdent}}` | `sg_` | `_` | `^[a-z][a-z0-9_]{0,39}$`, at most 40 characters |
| DNS and object-store label | `{{isolationLabel}}` | `sg-` | `-` | `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, at most 63 characters |

**The separator belongs to the projection and never to the slug, and no form is produced from another by substitution**: turning `_` into `-` afterwards is exactly where the rejected-bucket defect came from — one canonical shape and a rule somebody has to remember to apply. Joining the same segments with the consumer's own separator makes *no underscore in a label* true by construction rather than by review.

Edge cases close by construction rather than by rule: the `sg_` and `sg-` prefixes fix a slug starting with a digit; a label can neither begin nor end in a hyphen, because it ends in hexadecimal `hash8`; uppercase cannot occur; an empty slug becomes `x`. Both forms are at most 40 characters at a 28-character slug, so the label's 63 is the grammar's ceiling and not the generator's. **The SQL form is byte-identical to what `1.1.0` generated for the same branch**, because joining the same segments with `_` under `sg_` *is* the old transform.

**Each consumer asks for the form its substrate accepts, and one form is never substituted for another.** Which form a store accepts is recorded per store as `nameForm` on its `backingStores` entry, discovered from the substrate's own rejection surface rather than looked up in a table here, so it grows without an edit to this file and expires with the map it sits in. **A store recording neither form is undetermined, which refuses — where a generated name would be given to it.** The refusal is about handing a store a name from this family, so it reaches the roads that do: an in-instance namespace created per branch, and a coordination identity substituted into a client's own configuration. **It does not reach the seeded copy**, which is named from the repository's hash, the worktree's, and the store's key by the provider itself and never from this family — nothing asks that store to accept a name, so nothing about the grammar it accepts is undetermined. Read unscoped, this sentence refuses every store in a repository whose namespace grammars nobody recorded, including every one the copy road answers without ever naming — the nearest fitting name is never offered to a substrate that has not accepted it. A third form is added only when a substrate rejects both and that rejection is recorded, never in advance.

## Every name is derived, and none is drawn from a pool

**A name this skill uses is derived and never allocated.** An allocation is state a derivation never needs: it can run out, it has to be handed back, and a pool nothing owns is a pool two worktrees draw the same value from and never detect.

**Sixteen host-global logical-database indexes shared by every repository on the machine are exactly that shape, so this family has never had an integer member and this skill picks no index**: a store whose only in-instance isolation would be a numeric position records `mechanism: "none"` and is answered by whatever answers every other writing pair, never by a position inside the running instance that nothing owns.

**No name has a pool, a bounded range, an exhaustion case or a release obligation, and no placeholder yields an allocated value** — a placeholder is never a draw from anything.

Two worktrees of one repository therefore never have to agree about anything: their branch names differ, so `hash8` differs, so every member of both families differs, and neither run reads or writes any shared state to find that out.
