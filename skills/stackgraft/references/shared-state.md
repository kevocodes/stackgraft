# Shared state: the verdict procedure

This file is the **only** source of a shared-state verdict. The skill body states that a verdict is required and refuses without one; it deliberately contains no fragment of the rule below, so an agent that never opens this file can only refuse.

Produce exactly one verdict per `(service, store)` pair before any overlay launches.

## Two hazards, not one

- **Contamination** — the overlay *writes* state the base stack reads. Migrations, inserts, deletes, cache writes. Damage lands on the base stack's **data**.
- **Theft** — the overlay *attaches* to a coordination primitive and takes work away from the base stack: consumer groups, queue subscribers, advisory or leader locks, replication slots, scheduler singletons. Damage lands on the base stack's **behavior**, inside a service nobody modified.

Theft is the nastier one, because the symptom surfaces where you are not looking.

## The verdict

For each pair, evaluate three booleans against the manifest:

- **W** — does the service mutate the store? (`writes` names it)
- **X** — is attaching competitive or exclusive? (`competesOn` names it)
- **N** — does isolation exist inside the running instance? (`backingStores[store].isolation.mechanism` is not `none`)

Take the steps in order and stop at the first one that matches. **X is evaluated before W and independently of it**: writing is not the only way to break the base stack, so a decided W must never absorb the X question. A Kafka store with `mechanism: "topic-prefix"` satisfies N while `group.id` stays shared — isolate the topics and the overlay still steals partitions from a service nobody modified.

| Step | Condition | Verdict |
|:----:|-----------|---------|
| 1 | **Any** of W, X, N undetermined | Treat that pair as `W=yes, X=yes, N=no` → **REFUSE**. |
| 2 | **X = yes**, whatever W and N say | **REFUSE** a plain attach. Read-only is not enough when the read protocol competes: a consumer joining the base `group.id` takes partitions even if it only logs. Supply a distinct consumer identity, then re-enter at step 1 with X evaluated again — the substitution alone never approves. |
| 3 | X = no, W = no | **REUSE** the base store. The only unconditionally safe case. |
| 4 | X = no, **W = yes**, N = yes | **ISOLATE** inside the running instance. Reuse the server process, never the namespace. |
| 5 | X = no, **W = yes**, N = no | **REFUSE**, or run a dedicated store. Never reuse. |

**Step 1 is load-bearing, and it is an `any`, not an `all`.** One undetermined boolean refuses the pair; the other two being known changes nothing. `writes: []` means checked-and-none; an *absent* `writes` means nobody looked. Silence must resolve to unsafe or the gate is decoration. A pair with no verdict is not a pair that passed.

### Evidence that does not count

- `confidence` other than `declared` on `isolation`, or classification without `stateReview`. A degraded discovery path must not launder a guess into a safety verdict.
- A dependency name found in neither `services` nor `backingStores`. Unknown fails closed.
- The user's assertion, the manifest's claim, or your own inference *in place of* this procedure. They are inputs to W, X, and N — never a substitute for the verdict.

### Escalations that override any recorded claim

Force ISOLATE-or-REFUSE regardless of what the manifest says, because these are visible in the diff:

- The worktree diff touches a migrations directory, or a launch/prepare command runs a migration step (`db:migrate`, `alembic`, `rake db:`, `prisma migrate`).
- The service's entrypoint is a scheduler, cron, beat, or worker singleton. Double-firing means duplicate emails and duplicate charges.
- The service sends externally visible side effects: email, SMS, webhooks, payments.

## Isolating in place

**Share compute, isolate state.** Application services are expensive to start and safe to share; stores are cheap to start and dangerous to share. Isolate *inside* the instance already running — a new database, vhost, or prefix — and no second container is needed at all.

The isolation command is **discovered from the repository**, never embedded here. Four rungs:

| Rung | Source | Confidence |
|------|--------|------------|
| 1 | A task target the repo already defines — `Makefile`, `Taskfile.yml`, `justfile`, `package.json` script, `bin/*` — whose name matches the intent (`db:create`, `createdb`, `vhost`, `topic`) | `declared` |
| 2 | The client **inside the running store container**, e.g. `docker compose exec -T postgres createdb …`. Borrowing it from the image is why no client has to exist on the host | `inferred` |
| 3 | No command needed: isolation is an env or URI change — Mongo database name, Redis `SELECT n`, S3 key prefix, Kafka `group.id`, index prefix | `declared` or `inferred` |
| 4 | Nothing discoverable → `mechanism: "none"` | — |

Rung 2 is recorded `inferred`, so on the interlock above it does not satisfy the gate on its own; a first-use failure downgrades the store to `none`, which refuses. That is the safe direction.

### Template contract

A discovered template is repository data, so it is treated as untrusted input.

| Rule | Detail |
|------|--------|
| Placeholders | Closed set: `{{isolationName}}`, `{{templateName}}`, `{{store}}`, `{{worktree}}`, `{{repoRoot}}`, `{{port}}`. Any other `{{…}}` invalidates the template → `mechanism: "none"`. |
| Deny-list | `` ` `` `$` `;` `&` `|` `>` `<` and newline are forbidden anywhere in the raw template. |
| Re-validate after substitution | Every placeholder value is repository data too — `{{store}}` is a `backingStores` key, `{{repoRoot}}` and `{{worktree}}` are paths — so the **substituted** command is checked against the same deny-list again, immediately before execution. Checking only the raw template leaves substitution as the way in: a store key holding `;` or `|` never appears in the template and lands in the executed command. A failed re-check invalidates the template → `mechanism: "none"`. |
| Execute as argv | Split the substituted command into an argument vector and execute it directly; no shell. A value containing a space is one argument, never re-split — a worktree path like `/Users/dev/my repo` is a single path, not two. When only a shell is available, the deny-list plus the store-name pattern `^[a-z][a-z0-9_-]{0,39}$` in the schema are exactly what make that fallback safe: neither the template nor any substituted value can carry a metacharacter or whitespace. |
| One program | The template invokes one program with arguments. No pipelines, chains, or redirection — a repo needing them wraps them in its own task target, which is rung 1. |
| Name generation | `{{isolationName}}` is generated here, never read from the repo: `sg_<branch-slug>_<hash8>`, matching `^[a-z][a-z0-9_]{0,39}$`. |
| Destructive verbs | Reject `DROP DATABASE`/`DROP SCHEMA` of a name not derived from `{{isolationName}}`, plus `FLUSHALL`, `FLUSHDB`, `compose down`, `-v`, `--volumes`, `rm -rf`. |
| Approval | Show the substituted command and its target store before the first run per repo and store. Record `isolation.approval` with `at` and `sourceFingerprint`, the fingerprint of `discoveredFrom` at approval time — that stored baseline is the only thing a drift can be compared against. The approval is treated as **absent** once it stops matching, the way `acceptedRisks.serviceFingerprint` works, so a rewritten template is shown again instead of inheriting the old consent. |

Rejected examples, one per rule: `psql -c 'CREATE DATABASE {{dbName}}'` (unknown placeholder) · `createdb {{isolationName}} && echo ok` (`&`) · ``createdb `whoami` `` (backtick) · `createdb $DB` (`$`) · `createdb a; dropdb b` (`;`) · `createdb x | tee log` (`|`) · `createdb x > out` (`>`) · `pg_dump < in` (`<`) · `createdb {{repoDbName}}` (repo-supplied name) · `dropdb production` (destructive verb on a name not derived from `{{isolationName}}`) · `redis-cli FLUSHALL` (destructive verb).

## Per substrate

| Substrate | In-instance isolation | The catch |
|-----------|----------------------|-----------|
| PostgreSQL | New database (`TEMPLATE`) or schema + `search_path` | `TEMPLATE` needs no active connections to the source; `search_path` fails if code hardcodes the schema; roles and extensions must pre-exist |
| MySQL / MariaDB | New schema | Same class |
| SQLite | Copy the file | Trivially safe — separate file, no shared server |
| MongoDB | New database name in the URI | Trivially safe |
| Redis keyspace | `SELECT n` — 16 logical databases | Redis Cluster has none; `FLUSHALL` crosses all of them; many clients pin database 0 |
| Redis pub/sub | **None** | Channels are unrelated to the keyspace: publishing on database 10 reaches a subscriber on database 1 |
| Kafka | Distinct `group.id` + topic prefix | Same group steals partitions; a different group receives everything, so side effects duplicate. Neither is free |
| RabbitMQ | Separate vhost, or own exchange and queue names | Consuming an existing queue is round-robin theft; a vhost needs permissions |
| NATS / JetStream | Subject prefix, distinct durable name | Queue groups steal like Kafka |
| Object storage | Separate bucket or key prefix | Prefix isolation needs app support; lifecycle rules may not follow |
| Elasticsearch | Separate index or prefix behind an alias | Mapping conflicts when the alias is shared |
| CDC / logical replication | Unique slot and publication name | Duplicate slot errors, or unbounded WAL retention |
| Scheduler / leader-elected worker | **Do not run it in the overlay** | Double-firing; leader-election libraries actively fight |
| External SaaS | **None at this layer** | Needs sandbox credentials in the application |

## Cases with no safe answer

Say so plainly and refuse; do not offer a middle option.

1. A migration against a shared database too large or slow to clone. Pay for a dedicated instance, or refuse.
2. Redis pub/sub. Logical database selection does not isolate channels, and prefixing them is an application change.
3. Externally visible side effects. No infrastructure trick un-sends an email or un-charges a card.
4. Host singletons — a fixed socket path, lockfile, bind-mount, or a port hardcoded in source. Two instances collide by construction.
5. When the shared state *is* what is under test. It cannot be verified in an isolated copy, nor safely in the shared one.
6. Exactly-once consumption while the base consumer is being observed. Any distinct-group workaround changes what is being measured.

## Accepting a risk

The only bypass is one explicit `acceptedRisks` entry per `(service, store)`, recording the timestamp and the service's fingerprint at acceptance. It is treated as **absent** once that fingerprint drifts — acceptance was granted for code that no longer exists. There is no global bypass.

Compute the fingerprint by piping, in order, into `git hash-object --stdin`:

1. `git ls-files -s -- <service paths>` — index object ids,
2. `git diff --no-color --binary -- <service paths>` — unstaged delta; `--binary` matters, or a binary edit reads as "Binary files differ" and never moves the hash,
3. the untracked files from `git ls-files --others --exclude-standard -- <service paths>`, hashed with `scripts/fingerprint.sh`.

Verified: a staged-only edit, an unstaged-only edit, a new untracked file, and an unstaged binary edit each move the value, and reverting every mutation returns it to the exact base.
