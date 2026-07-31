# Shared state: the verdict procedure

This file is the **only** source of a shared-state verdict. The skill body states that a verdict is required and refuses without one; it deliberately contains no fragment of the rule below, so an agent that never opens this file can only refuse.

Produce exactly one verdict per `(service, store)` pair before any overlay launches.

**The pair set is not read off `dependsOn`.** For every runnable service being overlaid, pair it with *every* entry in `backingStores`, plus any name in that service's own `dependsOn` that resolves to a store. `dependsOn` may only **add** pairs, never remove one: a store a service forgot to declare is exactly the store the gate exists to catch, and a set the manifest narrows is a set the manifest can empty.

**An empty `backingStores` is a claim, and an unevidenced claim refuses.** Everything this file enforces — the `confidence` rule, the `serviceFingerprint` rule, `mechanism` needing a way to apply it — lives inside the per-pair loop, so a pair set of zero skips all of it at once. Emptiness therefore has to be evidenced at the level it occurs, exactly as `writes: []` is: an absent map and a map one discovery pass never populated are indistinguishable, and `references/discovery.md` section 1 documents the reachable path that produces precisely that — resolver unavailable, static parse standing in for it.

So `backingStores` is **required** at the root, and when it has no members the manifest MUST carry a root `stateReview` (`{at, method}`, the same `method` enum the service-level record uses) saying that discovery looked for stateful dependencies and found none. **That record is where a genuinely storeless repository's verdict is written** — one verdict for the manifest instead of one per pair — and recording it is what satisfies the skill body's rule that nothing launches until a verdict exists. Without it the emptiness is an omission: the pair set cannot be enumerated, W, X and N are undetermined for a set nobody can name, and step 1 below refuses the overlay.

## Two hazards, not one

- **Contamination** — the overlay *writes* state the base stack reads. Migrations, inserts, deletes, cache writes. Damage lands on the base stack's **data**.
- **Theft** — the overlay *attaches* to a coordination primitive and takes work away from the base stack: consumer groups, queue subscribers, advisory or leader locks, replication slots, scheduler singletons. Damage lands on the base stack's **behavior**, inside a service nobody modified.

Theft is the nastier one, because the symptom surfaces where you are not looking.

## The verdict

For each pair, evaluate three booleans against the manifest:

- **W** — does the service mutate the store? (`writes` names it, **or** the service carries `migrates: true`)
- **X** — is attaching competitive or exclusive? (`competesOn` names it)
- **N** — does isolation exist inside the running instance? (`backingStores[store].isolation.mechanism` is not `none`, **and** the record carries a `command` that creates the namespace or an `env` that points the overlay at one). A mechanism with no way to apply it *is* `none`: `{"mechanism": "database"}` on its own names a capability and supplies nothing that could exercise it, so reading it as N=yes reaches ISOLATE with nothing to isolate with.

**`migrates: true` makes W yes for every pair of that service**, whatever `writes` lists. A migration is a write to whichever store the process is pointed at, and nothing in the manifest can say which one an entrypoint will reach, so the claim is read against all of them. The service therefore cannot arrive at step 3: it lands on step 4 or step 5, which is exactly the isolate-or-refuse the field promises. Read it before `writes`, and never let a checked-and-empty `writes` cancel it — `writes: []` with `migrates: true` is a service that was correctly found to insert nothing and still rewrites the schema under every other consumer.

Take the steps in order and stop at the first one that matches. **X is evaluated before W and independently of it**: writing is not the only way to break the base stack, so a decided W must never absorb the X question. A Kafka store with `mechanism: "topic-prefix"` satisfies N while `group.id` stays shared — isolate the topics and the overlay still steals partitions from a service nobody modified.

| Step | Condition | Verdict |
|:----:|-----------|---------|
| 1 | **Any** of W, X, N undetermined | Treat that pair as `W=yes, X=yes, N=no` → **REFUSE**. |
| 2 | **X = yes**, whatever W and N say | **REFUSE** a plain attach. Read-only is not enough when the read protocol competes: a consumer joining the base `group.id` takes partitions even if it only logs. Supply a distinct consumer identity, **record the value as `competesOn[].overlayIdentity`**, then re-enter at step 1 with X evaluated again — the substitution alone never approves. `identity` holds the key's name (`group.id`); `overlayIdentity` holds what the overlay actually attaches under, and without it recorded the re-classification does not persist and the pair is back at REFUSE on the next run. |
| 3 | X = no, W = no | **REUSE** the base store. The only unconditionally safe case. |
| 4 | X = no, **W = yes**, N = yes | **ISOLATE** inside the running instance. Reuse the server process, never the namespace. |
| 5 | X = no, **W = yes**, N = no | **REFUSE**, or run a dedicated store. Never reuse. |

**Step 1 is load-bearing, and it is an `any`, not an `all`.** One undetermined boolean refuses the pair; the other two being known changes nothing. `writes: []` means checked-and-none; an *absent* `writes` means nobody looked. Silence must resolve to unsafe or the gate is decoration. A pair with no verdict is not a pair that passed.

### Evidence that does not count

- `confidence` other than `declared` — on the store's `isolation` **and** on the service entry itself — or classification without `stateReview`. Both readings count: an `inferred` service entry is a static parse standing in for an unavailable resolver, and a classification read off a fallback parse is exactly the guess this rule exists to stop, however `declared` the store's isolation is. **An absent `confidence` is not `declared` either.** A rule about degraded evidence that any omission walks around gates nothing, and the degraded path is the one least likely to write the field. A degraded discovery path must not launder a guess into a safety verdict.
- **A classification whose `stateReview.serviceFingerprint` no longer matches the service's source.** Recompute it with the recipe at the end of this file and compare. A drifted value makes W, X and N **undetermined** — not still valid, and not merely stale — so the pair refuses at step 1 until the classification is re-derived. `sources[]` fingerprints do not cover this: they track topology files, and a service's own tree is not a topology source, so on the case this skill exists for — a worktree whose service code changed — nothing else would notice. A service discovered read-only and since given an INSERT still reads `writes: []`.
- A dependency name found in neither `services` nor `backingStores`. Unknown fails closed.
- **A pair set narrowed by the service's own declaration.** `dependsOn: []` is the reachable case, and the schema blesses it as checked-and-none — so it must remove nothing. Every entry in `backingStores` still yields a pair, and each of those pairs is undetermined until W, X and N are answered for it, which refuses at step 1. Without this, saying *less* would gate *less* than saying something, and the laziest manifest would be the least refused. A procedure that runs per pair does nothing when there are no pairs, which is why the one pair set allowed to be empty — the one an empty `backingStores` produces — is allowed only while the root `stateReview` evidences it. Unevidenced, that emptiness is undetermined like any other, and an absent `backingStores` is not emptiness at all: the schema requires the key, so its absence invalidates the manifest, which discards the cache rather than launching past a gate that never ran.
- The user's assertion, the manifest's claim, or your own inference *in place of* this procedure. They are inputs to W, X, and N — never a substitute for the verdict.

### Escalations that override any recorded claim

Force ISOLATE-or-REFUSE regardless of what the rest of the classification claims. The first is read out of the manifest; the others are read out of the diff and the commands, so they override a manifest that stays silent about them:

- **`migrates: true` on the service**, which is W = yes for every one of its pairs as above. This is the entry the diff cannot supply: a service that migrates from its own entrypoint, with a diff touching no migrations directory and a launch command naming no migrate step, evaluates to W = no on `writes` alone and would otherwise reach reuse while migrating the base store.
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

**Every rule below applies to every command this skill discovers and runs against a store, not to `isolation.command` alone.** `isolation.teardownCommand` comes from the same repository, carries the same placeholders and executes against the same running instance — and it is the one more likely to be destructive, so exempting it would exempt the dangerous half. Read each row as "the template", meaning whichever of the two is about to run.

| Rule | Detail |
|------|--------|
| Placeholders | Closed set of five, each with a defined source: `{{isolationName}}` (generated below, never read from the repo), `{{store}}` (the `backingStores` key), `{{worktree}}` (the overlay's checkout), `{{repoRoot}}` (the manifest's `repoRoot`), `{{port}}` (the port picked this run). `assets/manifest.schema.json` states the same five. Any other `{{…}}` invalidates the template → `mechanism: "none"`. `{{templateName}}` is deliberately **not** a member: nothing defines where its value would come from, and a discovered template already names its source namespace literally — `createdb -T bookshop {{isolationName}}` in the shipped example is exactly that. |
| Deny-list | `` ` `` `$` `;` `&` `|` `>` `<` and newline are forbidden anywhere in the raw template. |
| Re-validate after substitution | Every placeholder value is repository data too — `{{store}}` is a `backingStores` key, `{{repoRoot}}` and `{{worktree}}` are paths — so the **substituted** command is checked against the same deny-list again, immediately before execution. Checking only the raw template leaves substitution as the way in: a store key holding `;` or `|` never appears in the template and lands in the executed command. A failed re-check invalidates the template → `mechanism: "none"`. |
| Execute as argv | Build the argument vector first, substituting each placeholder into its own element, then execute that vector directly. **This is mandatory, not preferred, and there is no shell fallback.** The deny-list does not cover whitespace, and `{{worktree}}` and `{{repoRoot}}` are host paths that routinely contain it: under any shell, `/Users/dev/my repo` becomes two arguments and the command runs against a path that does not exist. The deny-list and the store-name pattern stop metacharacters; only argv stops re-splitting. If the only available tool runs a shell string, the template is not executable here — record `mechanism: "none"` and refuse rather than quoting your way around it. The commands this skill substitutes into but does not run against a store — `overlayCommand`, `prepareCommand`, `verifyRequest`, the `baseStack` commands — cannot take this rule, since a repository writes them as shell lines; they are covered by the equivalent quoting rule in `references/discovery.md` section 6, and neither rule excuses the other. |
| One program | The template invokes one program with arguments. No pipelines, chains, or redirection — a repo needing them wraps them in its own task target, which is rung 1. |
| Name generation | `{{isolationName}}` is generated here, never read from the repo: `sg_<branch-slug>_<hash8>`, matching `^[a-z][a-z0-9_]{0,39}$` — 40 characters total, of which `sg_`, the separator and `hash8` take 12, leaving the slug **28**. **Transform:** lowercase the branch name; replace every run of characters outside `[a-z0-9]` with a single `_`; strip leading and trailing `_`. **Truncate the slug to 28 characters**, then strip a `_` the cut left trailing; if nothing survives, use `x`. Ordinary branch names exceed 28 routinely — `feature/checkout-rewrite-phase-two` slugs to 34 — so without a stated truncation the rule is unsatisfiable rather than strict. `hash8` is the first 8 characters of `git hash-object --stdin` over the **full**, untruncated branch name, which is what keeps two branches sharing a truncated slug from sharing a namespace. |
| Destructive verbs | **Reject any template that destroys or empties a namespace, volume, or instance not derived from `{{isolationName}}`.** This is a class, not a list: decide on what the command does, because a literal list is a list of the spellings someone already thought of. `dropdb production`, `dropdb -U app app`, `DROP DATABASE app`, `DROP SCHEMA public`, `TRUNCATE`, `db:reset`, `docker volume rm` and `rm -rf` are all the same rejection, and none of them contains the string `DROP DATABASE`. Emptying a whole instance is always rejected, since no instance is derived from `{{isolationName}}`: `FLUSHALL`, `FLUSHDB`, `compose down --volumes`. Creating the isolated namespace, and dropping one whose name **is** `{{isolationName}}`, are what belong here. Judge an option by what it is an option to: `docker compose down -v` removes the base stack's volumes and is rejected, while `psql -v ON_ERROR_STOP=1` sets a client variable and is not — a bare `-v` token is not a destructive verb. |
| Approval | Show **both** substituted commands — `command` and `teardownCommand` — and their target store before the first run per repo and store. Approving a create without seeing the drop that follows it approves half the operation. Record `isolation.approval` with `at` and `sourceFingerprint`, the fingerprint of `discoveredFrom` at approval time — that stored baseline is the only thing a drift can be compared against. Compute it the way every other source fingerprint is computed, `sh scripts/fingerprint.sh -C <repoRoot> <discoveredFrom>`: that path is relative to the main worktree, and hashing the overlay's copy of it would compare two different files run to run. The approval is treated as **absent** once it stops matching, the way `acceptedRisks.serviceFingerprint` works, so a rewritten template is shown again instead of inheriting the old consent. |

Rejected examples, one per rule: `psql -c 'CREATE DATABASE {{dbName}}'` (unknown placeholder) · `createdb {{isolationName}} && echo ok` (`&`) · ``createdb `whoami` `` (backtick) · `createdb $DB` (`$`) · `createdb a; dropdb b` (`;`) · `createdb x | tee log` (`|`) · `createdb x > out` (`>`) · `pg_dump < in` (`<`) · `createdb {{repoDbName}}` (repo-supplied name) · `docker compose exec -T postgres dropdb -U app app` (destructive verb: it drops the base database, and matches no literal spelling — which is why the rule is about the effect) · `redis-cli FLUSHALL` (empties a whole instance). Accepted by contrast: `psql -v ON_ERROR_STOP=1 -c '…'` — `-v` here is a client variable, not `--volumes`.

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

The only bypass is one explicit `acceptedRisks` entry per `(service, store)`, keyed `<service>::<store>` and **read by splitting at the last `::`** — a store name can hold no colon, so that split stays unambiguous for a unit named `:core:data` or `//pkg:target`. It records the timestamp and the service's fingerprint at acceptance, plus `reason` and `acceptedBy` — an acceptance naming neither is indistinguishable from one the agent granted itself. It is treated as **absent** once that fingerprint drifts — acceptance was granted for code that no longer exists. There is no global bypass.

Compute the fingerprint by piping, in order, into `git hash-object --stdin`. `<service paths>` is that service's `paths` globs, each **quoted** and passed as a `:(glob)` pathspec — `':(glob)services/catalog/**'` — so git expands them and not the shell. An unquoted glob is expanded by the shell before git sees it, and POSIX shell globbing skips names beginning with a dot: `services/catalog/.env.example` is silently dropped from all three legs, so editing it never moves the value.

1. `git ls-files -s -- <service paths>` — index object ids,
2. `git diff --no-color --binary -- <service paths>` — unstaged delta; `--binary` matters, or a binary edit reads as "Binary files differ" and never moves the hash,
3. the untracked files from `git -c core.quotePath=false ls-files --others --exclude-standard -- <service paths>`, hashed with `scripts/fingerprint.sh` — run from the worktree top and **without** `-C`, unlike a source fingerprint: this value is about the checkout's own code, so all three legs must read the same tree the overlay will launch. `core.quotePath=false` matters as much as `--binary` does: git otherwise C-quotes any path holding a non-ASCII byte and prints `"services/catalog/caf\303\251.txt"`, which `fingerprint.sh` cannot stat — it emits the constant `-` for it, so every later edit to that file leaves the hash exactly where it was.

Verified on a scratch repository: a staged-only edit, an unstaged-only edit, a new untracked file, and an unstaged binary edit each move the value, and reverting every mutation returns it to the exact base. The boundary is deliberate and is not covered: a path `.gitignore` excludes never moves it, because `--exclude-standard` never lists it, and neither does any change outside the service's own `paths`.
