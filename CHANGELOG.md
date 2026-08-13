# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.5] — 2026-08-13

**An overlay left objects behind that no query in this skill could find.** Found while tearing down the ninth agent trial: the harness reported itself clean and had left two volumes, a network and nine images on the machine.

### Fixed

- **An overlay launched under its own compose project materialises that project's named volumes, and they carry none of this skill's labels.** `--no-deps` skips *starting* a dependency, never *declaring* it — measured: one `--no-deps` run of a unit naming a store in `depends_on` created `<project>_<volume>`, empty, carrying `com.docker.compose.project` and `com.docker.compose.volume` and nothing else. Every ownership query in `references/reaping.md` is scoped to a label this skill writes, so `report` cannot count it and a developer accumulates one per overlay project with nothing able to enumerate them. The file now states the case beside the anonymous-volume rule it already carried: these are found by **the project prefix, which is the only name they have**, the run names them in its teardown because it chose that prefix, and a run that cannot state its own prefix reports them as unremovable rather than sweeping by pattern — acting on an unlabelled object nobody recorded a project for is the same violation as stopping a process without proof.

- **A floor called an instance unreadable that had only restarted.** A store initialising from nothing brings up a temporary server and then restarts it — `mysql` does exactly that — so a read succeeded, the read taken immediately after it did not, and the run reported an issue that produced no value. *Readable* now means answered twice a second apart, which is what it had to mean for a store that is still settling. `2.2.4` gave this floor the honest message; this gives it the honest wait.

### Added

- **Four rows that drive it rather than assert it**: that a `--no-deps` overlay run really does materialise a store's volume without starting the store, that the volume carries compose's labels and none of ours, that the actuator honestly does not report it — the fail-closed direction, and the reason the obligation sits on the run — and that removing by the project prefix reaches it.

## [2.2.4] — 2026-08-13

**An overlay was published on every interface while the service it shadows binds loopback.** The ninth agent trial drove the whole road for the first time — the generated family written after a go/no-go, all three members observed, the record raised from `inferred` to `declared` on evidence, the namespace created and dropped inside one run — and found nine things on the way. This is the one that matters most, and it is the same shape as the seeded copy published on `0.0.0.0` in `2.1.3`, one object over.

### Fixed

- **Nothing told an overlay where to publish.** `127.0.0.1` appears in the launch derivation only as `bindsTo`, which describes how an overlay *reaches* the base stack, and the loopback-publishing rule existed only for seeded copies in another file. So an overlay of a loopback-bound service came up on every interface — a developer's branch on their network while the thing it stands in for is not. **An overlay is never more exposed than the service it stands in for**, and where `bindsTo` is undetermined it publishes on loopback.
- **`2.2.3`'s own tag rule was unexpressible in the field that has to carry it.** That release required a unit baking its source to be rebuilt under a tag the base project does not own; `overlayCommand`'s placeholder set was closed to two host paths and a port, none of which is a name a tag may carry. An agent following the rule wrote a per-**repository** literal — safe against the base stack, and a collision between two worktrees overlaying the same unit. `{{isolationLabel}}` joins the set: it is already derived per branch, already has the grammar, and is the same value rather than a second spelling of it.
- **`declared` could be read as certifying the query, and it does not.** The schema raises a generated family on three exit statuses and says nothing about the read discriminating — correctly, since a family whose pairs never reach the copy road should spend no empty instance on an answer nothing consumes. But the strong rule (*a generated `SELECT 1` fails the discriminator and must*) lived in one file and the structural one in the schema, so only the weak one was enforced. Both now say outright that these are separate claims with separate expiries, and that such a family earns `declared` and still refuses at verification.
- **The approval fingerprint had no stated composition.** *"Hashed all three together"* — but `fingerprint.sh` emits one line per path and combines nothing, and concatenating digests, hashing bodies end to end, or piping its output onward are all defensible and yield different values. An unstated composition is an approval two correct runs disagree about, and a human who approved once being asked again. The recipe is now stated.
- **An observation of the read could record that it ran, never what it answered.** A read's answer is a count and its exit status records only that a count was produced. `observed` takes an `output` now; an agent that observed a read answering `4` had been writing the `4` into notes, which nothing expires.
- **A competing pair with no knob had no honest record.** A scheduler whose cadence lives in table rows has no `group.id` to substitute and none may be invented, so the only expressible `competesOn` was empty — which read as *checked and none*. The gate flagged the opposite mismatch and was silent here. An empty `competesOn` beside `competes: true` now reads as what it is: competes, and no identity exists to substitute.
- **Three smaller ones**: whether a create observed in *this* run may release the teardown (it may, and the stricter reading made `declared` unreachable forever); which checkout holds the generated family when the main one's script directory is empty and therefore absent from every worktree; and that accepting the family offer can move a pair from *refused for want of a query* to *refused for want of an env route*, which a human deciding whether to accept it is owed in advance.

### Added

- **One floor was making the conflation this skill forbids.** It compared a base store against an empty instance that had not finished starting and reported *the candidate discriminates nothing* — a verdict about the candidate where the truth was a verdict about the instance. It has three outcomes now rather than two, and a wait budget an empty `mysql` building its data directory on a loaded host can actually meet. `2.2.2` wrote that rule for the documents; the suite was still breaking it.
- **A detector for the class three of the last twelve defects came from**: a document and the schema describing one field differently. It extracts the closed placeholder set from each and compares them as sets, and fails when either side moves alone.
- Rows pinning the loopback rule, the `declared`/`discriminates` separation, and the read observation's `output`.

## [2.2.3] — 2026-08-13

**The overlay could serve the base stack's code and answer `200`.** An agent that had never seen this skill drove it end to end against a repository built for the purpose, and this is what it found first. Eight more findings came with it. `references/traps.md` already carried the sentence *"you will test the old code and believe it passed"* — for a different cause.

### Fixed

- **A unit that bakes its source into an image was launched from the image already there.** The `overlayCommand` derived from the orchestrator's own single-unit run form reuses the existing tag, and that tag was built from the **main checkout** — so on any repository with a `build:` stanza and no source mount, which is most of them, the overlay ran the code without the change and verified successfully. `discovery.md` now asks which shape the unit is: a mounted tree needs the mount pointed at the worktree, a baked tree needs the image rebuilt from it.
- **And rebuilding it under the base project's own selector retagged the base stack's image.** The running containers keep theirs, so nothing looks wrong until the developer's next whole-stack `up` comes up on the worktree's build — the overlay writing an artefact the base stack reads, in a dimension the shared-state gate does not cover because that gate is about stores. It collides specifically with the network route this file *prefers*, which runs under the base project. **Build under a tag the base project does not own**, and the two stop colliding.
- **A unit's fingerprint could not see the shared file its build copies in.** `serviceFingerprint` is computed over the unit's `paths`, and a shared build context may not be any unit's `paths` — correctly, since recording it there maps every change under it to every unit. But a unit whose Dockerfile copies a file out of that tree runs that file. Measured: five units shared one `serve.sh`, and an edit to it would have left every one of their determinacy records reading as valid over code that had changed. The recipe now covers the `paths` of every non-runnable entry whose `consumers` name the unit — the same relation, read from the other end.
- **The scheduler escalation had no scope while the migrations trigger beside it insisted on one.** Unscoped, a `while true` reading one table returns a unit's cache, its object store and its backup volume to the subject for a competition none of them can host. It is scoped now, and where the loop is established and its target is not, that is `unknown` and every store of the unit refuses — exactly as an unscoped `migrates` does.
- **`portGroup`'s grouping rule was true of a build context.** *"A directory that holds some of the units and not others"* describes `backend/` exactly, and a shared context is chosen so units can share a base image, which says nothing about who shares a port budget. Both readings were defensible and they differ by one stop-and-ask question against six. A build context is now named as not a grouping.
- **`nameForm` read as demanding a write to the base store.** Learning what a server *rejects* means attempting to create a namespace in it, and the only instance available at discovery is the developer's own. The documented grammar is the ordinary source — the shipped example already used it — and a rejection is only evidence when provoked against an instance the run owns. An agent unwilling to write had omitted the field on every store and closed the generated-family road for the whole repository.
- **Three documents rendered as something other than what they said.** A paragraph in `reaping.md` jammed five rules into one line, repeated a sentence verbatim and left bold unclosed; a second paragraph there closed emphasis nothing opened; `discovery.md`'s section 5 numbered two consecutive steps `4`, which a renderer rewrites — under two cross-references that cite it *by step number*.
- **`substrate` had no spelling for an engine that could not be established.** The prose says the honest value is `none`; the schema's examples never listed it, so the literal was inferred.

### Added

- **A floor for the first two, driven rather than asserted.** It builds a base image from a main checkout, changes a baked file in a worktree, and shows the documented run form serving the **main** checkout's code from a worktree launch. Then it shows the rule that replaced it serving the worktree's, leaving the base project's image untouched — and, as the negative control, that a rebuild under the base project's own selector really does move it while the running container quietly keeps the old one.
- **Two general detectors for how the documents render**, not pins: every paragraph in every shipped document closes the bold it opens (inline code stripped first, since a `paths` glob is two asterisks that are not emphasis), and every ordered list carries the numbers a renderer would give it, with each `section 5 step N` citation resolved against a step that exists. The bold detector found a third damaged paragraph nobody had reported.

## [2.2.2] — 2026-08-13

**Two fields the documents told an agent to record, that the schema rejected.** Both were found by driving the skill end to end against a 45-service repository and writing the manifest the run's own evidence supported: the field existed, one level away from where the sentence put it, and a manifest the schema rejects is a cache discarded and a full rediscovery bought — for recording exactly what the gate asks for.

### Fixed

- **A service entry had nowhere to record its `confidence`.** `references/shared-state.md` describes the service-level `stateReview` and the root one as one scale of `method` and `confidence`, and names an *inferred service entry* as evidence that does not count. The root record requires the field; the service-level record was closed to it. It is now accepted there — optional rather than required, so nothing that was valid becomes invalid, absence stays governed by that file's existing rule that an absent `confidence` is not `declared`, and the degraded signal stays required per pair on the determinacy record, which is the granularity the gate actually reads. The shipped example now carries it on every service, so the example is what proves the field is writable.
- **`notes` was described inside `isolation`, where the schema is closed to it.** The sentence sits in the `isolation` bullet and says to record *why a mechanism is `none`* — and `mechanism` is one of `isolation`'s own fields, so the note reads as belonging where the mechanism does. It belongs on the store entry, beside `isolation`, and `discovery.md` now says so and names the cost, exactly as the `baseStack` paragraph below it already did. Measured on a real run: an agent recording why four stores had no mechanism put all four inside the closed node and lost the whole pass.

### Added

- **The suite can now run on a machine that is using the skill.** One section's inventory guard named every object any stackgraft run on the host had ever made, rather than its own, so a contributor with a live overlay could not run the suite at all — measured: a real overlay and its store copy failed the row while the section had leaked nothing. A foreign object appears in both snapshots and cancels out of the comparison, so scoping the guard to the section's own hash loses no coverage; planting an object in that namespace still fails it.
- **Four checks for the dimension both defects passed through.** The suite already held every manifest field a document names to existing in the schema; both of these existed, at another path. The new rows check the **path**: that the service-level and root `stateReview` really do accept the same `method` and `confidence` enums that `shared-state.md` claims of them, that the sentence making that claim is still there to be held to, that `notes` is on the store entry and `isolation` is closed to it, and that `discovery.md` says which of the two. Each was run against its own defect restored and fails there.

## [2.2.1] — 2026-08-12

**A store whose image wraps its own start-up could not be copied.** `--entrypoint` takes one string, an image that boots through an init declares several — `["tini", "--", "/docker-entrypoint.sh"]` is three — and the provider refused that shape rather than reproducing it. The refusal was honest about why, and it was a property of the runtime's CLI rather than of the store, so it excluded a large share of published store images from the copy road for no reason that had anything to do with isolation.

### Fixed

- **A read whose failure is invisible could get a command recorded as a query that discriminates nothing.** The three issues of the verification read — the base store, an empty instance, the copy — are compared against each other, and `0` is a real count, so a read that exits zero when it could not reach the store at all makes *"has not finished starting"* and *"holding nothing"* the same value. Where the failing issue is the empty instance, the difference against the base is one nothing produced, and a copy that lost its state answers what the base answers and is certified. Both documents now say it: the read must exit non-zero when it cannot reach the instance, three issues are comparable only where all three answered, and any that did not answer makes the candidate **undetermined rather than discriminating** — retried, and refused for want of a query where it still does not answer. The ordinary way to write a count is a client piped into something that counts, and the shell keeps only the counter's status, which is how the failure disappears; run the client first and count once there is an answer. A floor drives both halves against a store that is running and not serving, with the forbidden shape beside it answering `0` for that same instance.
- **The seeded copy now reproduces a multi-element entrypoint instead of refusing it.** The first element is what `--entrypoint` takes; the rest go at the front of the command, which is where the runtime would have put them. The container runs the same argv the base container runs, element for element. Nothing else about the copy changed — same image, same environment, same loopback-only publication, same verification before it is used.

### Added

- **A floor that drives an engine no document in the skill names.** The four engines the other floors boot are four engines someone chose, and a procedure tuned to them passes every one of those jobs. This one checks first that no reference, asset or script contains the engine's name, aborts if any of them has learned it, and then drives the whole copy road: bytes copied, the repository's own read discriminating a base holding data from an empty instance, the copy answering what the base answers, the copy destroyed. The entrypoint defect above is what it found on its first run, and the read-failure hole is what writing its read command turned up — the shape is what anyone reaches for.
- **A macOS job.** `/bin/sh` on macOS is bash 3.2, whose parser cannot read a `case` pattern inside `$( )` — it counts the pattern's own `)` as the substitution's close. `dash` and bash 5 accept that shape, so fifteen green jobs could sit on top of a script no macOS user can run. The job is the shell itself rather than a lint for the shapes we happen to know about. The shipped scripts were already clean; a check that drives them was not.

## [2.2.0] — 2026-08-10

The release this project became adoptable at, and the number moves for one reason: the first run now **says what it will cost you before you install**, which is a thing the skill tells a reader rather than a thing it does differently.

Nothing about a verdict changed. No schema moved. No signature changed.

### Added

- **`README.md` states what a first run costs.** One port range, once per repository, because nothing in your repository says which host ports an overlay may take and this skill will not guess one. Plus, per writing store you actually overlay, a read command it offers to write as three files you approve. Until now that was discoverable only by reading two reference files, which is not where somebody decides whether to install something.

### Fixed

- **The actuator had never been driven, and it is the only code here that stops and removes objects on your machine.** Every other verification reads, copies or launches — a mistake there is a wrong answer, and a mistake here is something gone. One hard rule in the body hangs entirely off it: *never stop a process without proof it is yours*. What existed was the report and one row asserting a portless mutation refuses; the refusal path, never the removal path. It is driven now, negatives first, because on this path a false pass is a container that survived: `stop` and `remove` both refuse while a worktree is still listed, a portless mutation refuses, a copy under `stop` is refused by name, and a container carrying none of these labels is refused and survives. Only then is a worktree deleted, its overlay classified an orphan, stopped, and removed — with the other worktree's overlay still running beside it at every step.
- **What a first run gets on a repository with no read command had never been driven.** Every copy-road check is handed one because the test fixture ships it; a real repository ships none. So the outcome most repositories meet — the bytes copied, no query derivable for them, the copy destroyed, the pair refused, and the offer made — was documented and unexecuted. It runs now, including the two things that make the refusal safe rather than merely correct: the base store is never wired to instead, and the three names the offer needs are free, which is the way out.
- **The agent trial was easier than life.** Its subject shipped the read commands, so seven trials had the copy's query pre-answered and never met the offer a real repository reaches on its first run. The subject ships none now.

## [2.1.10] — 2026-08-10

The seventh trial found the most load-bearing gap of the series, and it was in the body — the one file every run reads first.

### Fixed

- **The stop every first run hits was missing from `SKILL.md`.** Its gate table read *Port outside the range → stop and ask*, which presumes a range **exists**, and step 8 reads `<lo> <hi>` as always available. The missing-range stop was stated only in `references/discovery.md`, under a `portGroup` bullet. An agent executing the body's steps reached step 8 with no instruction to stop, and the two failure modes it would fall into are the two that section names by name: guess a range, or fall back to any free port. Two words in the gate table close it.
- **The reaper refused its own empty-instance probe.** Same class as the copy-instance line `2.1.4` fixed, and not covered by it: the probe carries this repository's hash so a run that died still leaves something findable, and deliberately carries no complete label set — so the container pass read an absent labels version as an unrecognised one and reported this skill's own probe as an ownership anomaly.
- **The shipped example's `overlayCommand` used a form `2.1.5` documented as unlaunchable.** `run --rm` holds the terminal, and step 10 then has to make a request against something the run is still blocking on. Three files carried that line and only the rule was reconciled; both example commands are detached now.
- **The measured four-store table read as a finding about whichever repository you are in.** Four stores, one called `postgres`, no rung-1 candidate for the store that matters — common enough to be mistaken for local, and read that way it says to refuse a pair that a repository shipping its own read has already answered. It says which repository it measured, and to re-derive against yours.
- **`baseStack` could not be both the repository's own entry point and carry a selector that entry point does not state.** Where a wrapper script relies on the compose file's `name:`, the selector wins and the command is derived, with the script named in `notes`.
- **`fingerprintTool` had no canonical literal.** The schema offers one as an example; a different spelling of the same tool marks **every** source drifted and buys a full rediscovery with no warning that a spelling is what it paid for. The value is stated.
- **No step owned provisioning the seeded copy**, so a run stopping between the verdict and the launch could leave gigabytes of the developer's data behind for a launch that never happened. It belongs to the launch.
- **The guidance on a bind-mounted tree now prefers the narrow glob and names what it excludes.** A mount of a whole directory is not evidence that a unit owns all of it: a `./db` mounted for one service's migrations also holds three stores' initdb seeds, and the wide glob puts them inside that service's `paths` — so editing another store's seed drifts its `serviceFingerprint` and selects it for overlay.

## [2.1.9] — 2026-08-10

The last three an agent trial left open. None blocking, and all three the same class: a document or an actuator saying something that cannot be true of the shape in front of it.

### Fixed

- **An absent host registry was reported as a store that could not be read.** One flag carried both, so a first run of a container-only repository — where the sidecar has never existed and never will, because nothing registers a host launch — printed *"an ownership store could not be read, so the held-port set is short of what is really held"*. A read failure **is** short of what is really held, and a later pick can be handed a port something already holds; an absence is short of nothing. They say different things now. The verification row covering this had made the same mistake — its fixture's registry is absent and its label said unreadable — and both halves are pinned now, in both directions.
- **`verifyRequest` had nowhere to put the host it must aim at, and should not have one.** Its closed set is `{{port}}` alone, which is correct rather than a gap: the interface an overlay answers on is the one **this run bound it to** a moment earlier, a fact of the run and never of the cache, so a stored line carrying a literal host is stale the first time a run binds elsewhere. Record the path, the method and the headers; the run supplies where to send them. `baseStack.bindsTo` is about reaching the base stack and decides nothing here.
- **`buildContext` was written as though every unit has one.** A unit running a prebuilt image with bind mounts has no build stanza at all, which is ordinary rather than exceptional, and *recorded verbatim, it is not decoration* reads as an instruction to produce something. *Verbatim* governs a context that exists and never the absence of one; what identifies such a unit's code is `paths`, which the mounts already give.

## [2.1.8] — 2026-08-10

The first trial run through the harness rather than a subject built by hand — and the harness measured what five earlier trials had measured by hand: every store unchanged, nothing left running, a manifest written. Its report and the measurement agreed line for line.

### Fixed

- **A stopping run had no step that writes the manifest, and was required to have written one.** Step 10 was the only writing step in the body, and a stop at the port question never reaches it — while `references/discovery.md` says a manifest carrying the whole discovery and no `ranges` is exactly what a stopping run leaves behind, and that stopping without writing discards a resolver pass, every fingerprint and every classification. The two halves of that contradiction were added in different releases and neither noticed the other. Step 10 says it now, at one word less than it cost before.
- **The generated-family offer was scoped to a rung no containerised store reaches.** Rung 2 is a client borrowed from inside the store's own container, so a compose stack whose image ships its own client always has it — and a rung it reaches is a rung it does not descend past. Read as *reaches rung 4*, the offer was unreachable for exactly the repositories it was written for. It is scoped by the outcome instead: a pair ending at `mechanism: "none"` because no target the repository owns exists to create a namespace with.
- **The `portGroup` key rule decided nothing for a single-unit repository.** A grouping is one the repository chose *in order to group* — a profile, a workspace member list, a directory holding some of the units and not others. A directory every unit sits under is not one: with a single runnable unit `services/` satisfies it trivially and so does the repository root, so both branches were true at once.
- **The root `stateReview` read as unconditional and then conditional in consecutive sentences.** *Either way* means `declared` or `inferred`, never empty map or populated one.

## [2.1.7] — 2026-08-09

The last two an agent run left open. Neither blocking, and both the same shape: an object a run creates and then cannot point at.

### Fixed

- **A published copy holds a host port and nothing recorded it.** The runtime picks it at provision time, so it belongs in no manifest — per-worktree and per-provision, exactly like the instance name, and `portPolicy` holds the base stack's ports rather than this run's. But it is a real allocation, and `scripts/pick-port.sh` excludes what it is given and nothing else, so a later run could be handed the copy's own port as a candidate. A run now reports the ports its own copies publish and passes them as exclusions, recovering each from the `port` record `address` already returned. Not tracked in the cache, because a value the runtime chooses is not a fact about the repository — recovered from the runtime, which is where every other engine-specific fact here comes from.
- **An overlay running a store's image inherits an anonymous volume nobody can find.** A unit that runs `postgres` for `psql` alone still gets that image's declared volume, created by the launch and carrying none of this skill's labels — so no scoped query returns it, and an unscoped listing on a working machine returns thousands. `2.1.6` made the teardown carry `-v`, which takes it; the run names it as well, which is what lets a developer who already removed the container without the flag find the object afterwards.

## [2.1.6] — 2026-08-09

A fifth agent ran with **no port range supplied**, so the stop this skill is built around was exercised for the first time rather than skipped. It stopped at step 8 with the whole discovery already written down — a schema-valid manifest carrying `reserved` and no `ranges` — asked one question, wrote only that key on the answer, and completed: an overlay on a picked port, pointed at a verified copy, with the base store untouched at column level.

The stop, the write-before-asking, the resume and the completion are one loop, and this is the release where all four of them ran.

### Fixed

- **`baseStack` has no `notes`, and the schema forbids one.** `2.1.2` said to record a published-spec disagreement there; following that sentence emits a manifest the schema **rejects**, which discards the cache and buys a full rediscovery for a note. It belongs on the unit whose spec differs, in that unit's own `notes`.
- **The `--rm` fixtures in `references/reaping.md` read as launch forms.** That table demonstrates where ownership labels are appended and holds whatever the rest of the line is — read as forms to copy, it lands a reader on one that deadlocks at the verification step `2.1.5` had just warned about from the other side.
- **Where the discriminator probe runs was unstated**, and the schema settles it: `discriminates` is required inside `verification`, so the record cannot be written without having issued the candidate. It runs at discovery — and **not for every store in the map**: an empty instance per store, to establish a discriminator for a pair pass 3 removed and nothing will read, spends a container on an answer nobody consumes.
- **No field held how an isolated store's address reaches the overlay.** A seeded copy's instance name does not exist until it is provisioned and differs per worktree, so it is a value of the run and never of the cache — while `isolation.env` belongs to the in-instance road and is shared by every service paired with that store. The manifest records **which variable carries it**, on the unit that reads it; the run supplies what the provider returned.
- **The Output Contract owed a teardown the reaper deliberately will not give.** A live overlay is never a target while its worktree is listed, so the command is the runtime's own — naming the container the run recorded and carrying `-v`, because a unit running a store's image inherits that image's declared volume as an anonymous one that no scoped query can find after the fact.

### Known

- **A reported contradiction was measured and is not one.** `--project-directory` *does* select which compose file is read when no `-f` is given: run from one directory against another, the orchestrator read the target's file and used its project name. Recorded because the report was specific and wrong, and the next reader deserves the measurement rather than the claim.

## [2.1.5] — 2026-08-09

A fourth agent completed the run on a harder subject — four stores rather than two — and the gate held: four pairs derived, three removed each on its own record, the migration escalation scoped to `postgres` alone and neither the keyspace, the second relational store nor the document store touched. That is what `2.1.2`'s scoping repair was for.

It reported seven things, and the first is the ordinary run.

### Fixed

- **The subject was derived from a diff that is empty on the run this skill exists for.** A worktree's change is usually uncommitted — a developer opens one, edits, and runs this before committing anything — so a comparison against the base branch sees none of it, selects no unit, and produces no overlay. The change set is three legs now: the committed diff, the staged and unstaged diff, and the untracked files, which are the same three the `serviceFingerprint` recipe hashes and for the same reason — **the code the overlay launches is the working tree, not the commit**. Untracked matters most and drops most easily: a new migrations directory is untracked by definition on the run that adds it, and it is the strongest escalation the gate has.
- **A refresh discarded the one answer only a human can give.** The topology source covers `portPolicy` because `reserved` is read from it, and carries `revalidate: "always"` — so `ranges`, the answer to the question this skill stops to ask, was re-derived away every run and asked again the next. That is what the stop-and-ask repair exists to prevent, arriving through the refresh door. A refresh writes what it can derive and **carries forward what nothing can**; `covers` gained `portPolicy.reserved` so a source can own the derivable half precisely.
- **The `nameForm` refusal was unscoped.** Read literally it refused every store in a repository whose namespace grammars nobody recorded — including every one the seeded copy answers *without ever naming*, since the provider names a copy from hashes and never from the name family. It is scoped to the roads that hand a store a name, and the shipped example, which asserted both halves of that contradiction in one sentence, is corrected with it.
- **A run form that attaches cannot be verified while it runs**, and `--rm` and `-d` are mutually exclusive in Compose, so the only form an orchestrator offers can be one that holds the terminal. Derive the detached form, or background the client and record the **container** — a client's pid is not the container, as `references/reaping.md` already said from the other side.
- **A rung table broken in `2.1.2`** is repaired: the rung-2 paragraph was inserted between rows 2 and 3, so it rendered as a table, a paragraph and an orphan row.

### Known

- **A container-only repository never reaches zero-checked on host overlays.** Nothing will register a host launch, so the sidecar is never written and `registry-missing` is permanent — the repository's shape rather than a fault in the run. Read it as *this repository runs nothing on the host*, and do not go looking for a file whose absence is the correct state.

## [2.1.4] — 2026-08-09

The four findings a completed agent run left behind, none of them blocking and one of them a report that refused this skill's own work to itself.

### Fixed

- **The ownership report named one object twice, once as a refusal against itself.** A copy's instance carries this repository's hash, so it reaches the container listing as well — where it has a store and neither a service nor a port, because **a copy belongs to a store rather than to a service**. That is what a copy is, not an overlay that lost two labels. The store label joins the row now and the container pass leaves that object to the pass that owns it, names it, and prints the command that removes it.
- **The generated-family offer was unreachable on the repository closest to needing it.** One that wrote `db-read-<store>` and neither lifecycle half could never be offered the two it lacks: the read sat at a family name, so the collision rule withdrew the whole offer. That rule exists because a generated name landing on somebody else's file is a conflict this skill has no standing to resolve — and that reasoning does not reach a file **doing that member's job**. Where the file at a family name is a member this rung already accepted, the offer now completes the family: the missing members are generated, the supplied one is untouched, and the approval is fingerprinted over all three, because what a human approves is the family and a value over the new files alone leaves the one they already had outside their consent. Anything else at a family name is a collision as before.
- **A third route from an overlay to the base stack's network was in use and unlisted.** Running the overlay under the base stack's own project joins that network by construction, with no edit to any file — so it is now preferred over declaring the network `external: true` in the worktree's compose file, which is an edit this skill may never make and may only name for the developer.
- **`covers` had no per-store token.** It carried `services.<name>` and no `backingStores.<name>`, so a repository whose stores are read from different files could not have a drift in one re-derive that store alone.

## [2.1.3] — 2026-08-09

A third agent completed the run this skill exists for: the changed service on its own port, against a verified copy of the base stack's data, answering a real request — with the base store measurably untouched afterwards. It also found that the copy it had just been handed was published on every interface of the machine.

### Fixed

- **The seeded copy was published on every interface, and the store it copied was not.** The provider started it with `-P`, which hands every exposed port to the runtime bound to `0.0.0.0`. Measured on the fixture: the copy landed on `0.0.0.0:55006` while the store it duplicates publishes `127.0.0.1:15432` and nothing else. A full copy of the developer's data, opened by the base store's own credentials, reachable from addresses the original deliberately refuses — and **the copy is the more sensitive of the two objects, not the less**: identical bytes, and nobody watching it. It publishes one flag per exposed port now, each bound to `127.0.0.1` with the host port left empty, so the runtime stays the only allocator, which is the property `-P` was there for and the reason this provider says it picks no port.

### Known

- **Nothing in this repository had ever run the shipped provider.** Five layers of behavioural checks build their copies by hand beside it — the same `docker run`, written in the test — so they exercised *a copy* and never *the code that makes one*, which is how `-P` survived all of them. Provision, publication and destroy now go through `scripts/provider-docker.sh`. The lesson generalises past this defect: a floor that reimplements the thing it checks proves the reimplementation.

## [2.1.2] — 2026-08-09

An agent holding nothing but this skill and a repository was run against a fixture, isolated from every test in this repository so it could not read the answers. It stopped at the port question, correctly, and its report named seven things these documents left to be guessed. This release closes them.

The instrument matters as much as the findings: five layers of behavioural checks pass on this codebase, and none of them could have found any of this. They drive the mechanism with a script that already knows what to pass it. What an agent supplies instead is the absence of that knowledge, and that turns out to be the thing worth testing.

### Fixed

- **A first run stopped at the port question and threw away everything it had discovered.** The rule it stopped on is right and is unchanged: never guess a range, never widen another group's, never fall back to any free port. What it cost was the defect. `portPolicy` requires only `reserved`, derived from the base stack's published ports and needing nobody's answer, and `ranges` is optional — so a manifest carrying the whole discovery and no `ranges` is valid, and is what a stopping run leaves behind. Nothing said so, so a resolver pass, every fingerprint and every classification were discarded and the next run asked the same question having redone all of it. The stop is one question; it was costing the pass, every run, forever. **The key it asks about is now derived too**: `portGroup` is the unit's own name unless the repository already groups its units, because inventing a category is inventing a range one level up and does it silently, a mis-keyed unit drawing from a range that looks answered.
- **Nothing applied a worktree's migration, and inventing a route was forbidden.** The central act of the change had no derivable road. The repair is not a new road: a unit that migrates does it from its own entrypoint, which is the shape the `migrates` escalation was always written for, so the migration reaches the copy because the overlay was launched against the copy and for no other reason.
- **The base stack was unfindable whenever its selector differs from the name its file declares** — `-p`, `COMPOSE_PROJECT_NAME`, or the directory. The three `baseStack` commands now carry the selector read back from the runtime. The dangerous half is the reading: **an empty status table is not a stopped stack**, it is a selector that asked for nothing, and step 6 starts what is missing — so a wrong selector brought up a second copy of a running stack on the ports the first one held, which is the outcome this skill exists to avoid.
- **The diff-based migration escalation had no scope**, so an `ALTER TABLE` refused a cache and a broker too: the amplification the per-pair record exists to end, returning through the escalation door. It is scoped now the way `migrates` is, and unevidenced leaves every store of that unit undetermined. It reads the diff and never a source, which is why it needs no fingerprint — a migrations directory can never be a `sources[]` entry, and nothing is lost, because the diff is recomputed every run.
- **A changed path that maps to no unit still enters the gate's diff.** The decision gate governs which units are overlaid; the escalations read the diff of the units already selected. Those never collided, and the table read as though they did.
- **`none` could be read as possibly undetermined.** A careful reader hesitated between refusing and copying on identical evidence. N is undetermined when nobody established what the store offers, and answered `no` when a pass established that it offers nothing; an `inferred` record is not a third state to weigh.
- **The rung-2 read was prescribed in a form the contract governing it rejects outright.** `2.1.1` stated that a repository's read file is issued on the host as ``sh <file> "$instance"`` — and the template contract rejects `sh` as the program by name, so the one shape this version added was refused by the rule it was subordinated to. The file is invoked directly instead, as the executable it is written to be; a read file that is not executable supplies no vector and the rung is empty. **What shape that record takes is stated too**: the path relative to `repoRoot` as a one-element vector, with the instance appended by the issuer rather than stored in it, because the instance changes three times per verification and the candidate does not.
- **`bindsTo` took the widest published form where it should take the narrowest.** One field cannot hold two bindings, and the fail-closed direction is the narrow one: loopback where the truth is wider costs a route that goes the long way round and works, while every-interface where the truth is loopback sends an overlay at an address that refuses it and reads as a store that is down.
- **The shipped example broke the quoting rule it illustrates**, carrying bare `{{worktree}}` and `{{repoRoot}}` where section 6 requires each substituted value be one single-quoted word. `references/traps.md` excuses that file's *values* as illustrative; a rule it demonstrates wrongly is a different thing, and every placeholder in it is quoted now.

### Known

- **A container-run overlay whose compose file writes its connection string as a literal has no channel to reach an isolated copy, and refuses.** That is correct — launching anyway points the overlay at the base store, which is the contamination the gate exists to stop — but the shape is ordinary rather than exotic, and a refusal that only says *no route* leaves a developer with nothing to do. It now **names the change and whose it is**: the variable in the unit's own `environment:` with no value, or written as `${…}`, either being one line in a file the developer owns, reviews and commits. The skill does not write it, stage it, or offer to. It never edits a file it did not author, and that prohibition is general rather than scoped to the section it appears in — which is now said where the question arises.

## [2.1.1] — 2026-08-09

The copy road was driven against a real store for the first time, and it did not complete. Not because the copy was wrong — the copy was byte-for-byte correct on the first attempt — but because the instance it had to be compared against never started, so nothing could certify it.

Every runtime row in this repository launches `docker run --entrypoint sh` against `alpine/git`, and overriding the entrypoint is exactly what keeps a store image's boot requirements out of view. The remaining rows ask whether a document contains a sentence and whether a record validates. Both classes are worth having and both caught something during this release. Neither can notice a recipe that does not run, because they check that the prose says what the prose says: **the broken recipe was pinned, carried a negative control, and 848 checks were defending it exactly as written.**

### Fixed

- **The empty instance was launched with no environment and never booted, so no copy could ever be certified.** `postgres` exits `1` with *"Database is uninitialized and superuser password is not specified"* before a query could be issued against it, and an instance that never booted is not an empty instance but an absent one — the discriminating comparison could not be made, and the pair refused however faithful the copy actually was. That is a different failure from the one this project documented: not *until a read command exists*, but *even with one*. The environment is now read back from the base container exactly as the image, the mount point and the command already were, which is what `references/isolation-providers.md`'s own rule required rather than an exception to it. It is passed as a file rather than expanded on a command line, because the shipped image bakes in a value holding whitespace — one argument to the runtime and several to a shell. Emptiness stays a property of what the instance is *given*: it mounts nothing, so it initialises the store's empty shape and never its contents, which is the distinction the discriminator reads.
- **The three-outputs table gave rung 1's issuing route as though it were the only one.** ``docker exec "$instance" "$@"`` reaches a vector already inside the image; a rung-2 candidate is a file in the repository, which is not in that image and never will be, so issued that way it resolves to nothing and the pair fails for a reason that has nothing to do with the data. The host route is now stated beside the table, and *one route* is scoped to the three issues of a single candidate rather than to the two rungs.

### Added

- **A behavioural floor, which does not ship and is the reason both fixes above exist.** `.github/scripts/integration.sh` boots `postgres:16-alpine` **under its own entrypoint** and drives the three outputs end to end — read the image, mount point, state volume and environment back from the runtime, copy the volume, start the copy on it, start an empty instance, issue one read through one route against all three, assert both comparisons, and leave the volume inventory as it found it. Eleven checks, run as their own CI job against a fixture built to be the ordinary case rather than a friendly one: a `CMD-SHELL` healthcheck the argv rule excludes, no lifecycle target anywhere in the repository, and a `scripts/` directory that already exists. One of its checks proves an un-environed instance still fails, so the environment cannot be taken back out and the floor still pass.

**Scope, so this is not read as more than it is.** The floor proves the provider road against **one** real engine. The offer flow above it — showing a generated family, approval, the fingerprint over three files — has no floor of its own yet, and `README.md`'s `Honest limits` keeps its entry saying so.

## [2.1.0] — 2026-08-08

Run against a real repository for the second time, on a worktree whose diff touched a shared tree, and the answer was 25 consumers — most of the repository. That is correct and it is expensive, and nothing said so before starting.

### Added

- **The fan-out is reported before it is launched, and it gates nothing.** Two numbers, in the Output Contract so an agent holding only the body still states them: how many overlays this change needs, and how many services the base stack currently has up. The developer decides whether that trade is worth it; the run proceeds either way.
- **The denominator is the runtime's answer, never the count of units in the topology.** This is the whole of the rule. A compose file defining 45 services while 19 are up makes *26 of 45* read as a saving where *10 of 19* is the real trade against a second full stack, and the two point opposite ways. Measured on the repository this was tested against: a shared-tree change fanned out to 25 recorded consumers of which **10 were actually running**. The rule exists because that mistake was made during this release — the topology's count was taken for a fact about the moment, which is the same defect this project spends its verification budget on everywhere else.

## [2.0.0] — 2026-08-07

Run against a real repository for the first time — 43 services, four compose files — the skill resolved the whole topology in under a second and then refused 116 of 156 `(service, store)` pairs. The overlay never launched. This release replaces the isolation half of the skill with the two things that run produced: a scope, and a copy.

**Breaking.** `schemaVersion` moves from `2` to `3` and there is **no migration path**. That is the design and not an omission: every field here is re-derivable from the repository, so a manifest whose version a reader does not recognise is **discarded** whole and rediscovered, which costs one discovery pass and carries nothing forward. Carrying a field forward would be worse than dropping it — the retired service-level `writes` array was one claim about a whole unit, and re-reading it as evidence about one pair is the amplification this version exists to end.

Two things do not revert themselves, and rolling back to `1.1.0` does not undo them. A manifest written at `3` is unrecognised by `1.1.0`, which discards it — the intended fail-safe. And **any store copy or approved lifecycle target created while 2.0 was live stays where it is**: the copy is on your disk, labelled, removable with the command every run prints, and the target is in your repository, where it is now yours. No data of yours is moved or deleted by the rollback itself.

### Added

- **The scope, stated where a reader meets it.** Local development: one host, one running base stack, N worktrees. CI, shared or remote hosts and multi-developer stacks are declared non-goals rather than untested territory. It is a grant as much as a limit — on one laptop, against gigabyte volumes, the skill may copy state instead of naming a corner of it.
- **ISOLATE means a seeded copy.** A second instance of the same image, started on a copy of the state your base stack holds, so it carries the data you have; making it asks your repository for nothing, and the bullet below says what verifying it asks for. `scripts/provider-docker.sh` ships one provider — `provision`, `address`, `destroy` — and names no store engine anywhere in its signature. In-instance isolation stays as the zero-disk optimisation with every rule it ever had intact.
- **A copy is not isolated until it answers a query an empty instance answers differently.** One command, issued through one route against the base store, the copy, and an empty instance of the same image. Matching proves the copy carries the base's state; discrimination proves the command could have said otherwise. `pg_isready`, `redis-cli ping` and `SELECT 1` are all measured to fail that test and are refused as queries. A copy that fails is destroyed and the pair refuses; it is never wired to the base store instead.
- **A missing lifecycle target is offered, never invented.** Where the cheap path is unavailable only because nothing defines a target, the run generates three files per store — create, drop **and read** — shows them in full, and writes them only on explicit approval, as new executable files in your existing script directory. It never appends to `Makefile`, `Taskfile.yml`, `justfile` or `package.json`, never edits a file it did not author, and never stages, commits or pushes. What it wrote is recorded `inferred` until a run has observed all three succeed, and the approval is fingerprinted over the files as you approved them.
- **Two hazards, two mechanisms.** A data hazard buys a copy; a coordination hazard buys a distinct identity. `references/coordination-identity.md` holds the identity knob per substrate and the three-part proof a recorded value passes before the competition is over. Cloning a broker to avoid a consumer-group collision is not the answer and is no longer offered.
- **A name family instead of one shape.** One branch hash, one separator-free slug, two projections: an SQL identifier and a DNS or object-store label. The separator belongs to the projection, which makes "no underscore in a label" true by construction — every bucket `1.1.0` could name was rejected by the substrate itself.
- **Store copies are reap targets**, as `v:<volume-name>`, labelled and scoped. Candidacy is the complete four-label copy set with this repository's hash — four rather than an overlay's five, because a copy belongs to a store rather than to a service — and liveness is git's own worktree list, never a timer. Removal takes the removal verb **in addition to** the mutation flag: a `v:` target under `stop` is refused by name, because a copy removed by accident is state nothing on the host can reproduce. The repository's own `hash8` is **re-derived from `-C` and compared** before anything irreversible runs, because a caller's spelling of the label scope is not evidence that it names this repository — one root paired with another repository's hash would read that repository's live copies as orphans. An unrecognised label-set version, an object carrying three of the four labels, a listing row that did not carry its four fields, and a worktree list that cannot be read are all refused by name and never acted on, and a runtime that will not answer the copy listing reports **unknown, never zero copies** — a report saying *no copies* over an unanswered query tells a developer their disk is clear when it may hold gigabytes.

### Changed

- **Determinacy is recorded per `(unit, store)`.** The single `writes` array is gone: it was a positive claim that asserted checked-and-none for every other store at once, so a pass that determined one store and could not determine the next had to say nothing about any of them. `migrates` now names only the stores an entrypoint is pointed at.
- **The gate's subject is the pairs the change can reach.** The worktree diff that already selects which units to overlay now selects which pairs enter the gate — one-directional, evidence-bound, and reported with the narrowed count beside the derived one. `dependsOn` still narrows nothing.
- **Managed, remote, host-native and undeterminable-locality stores refuse by name**, with the fact discovery recorded carried into the message. A refusal does not cascade.
- **The integer allocator is deleted.** Sixteen host-global slots that nothing owns are a pool two worktrees draw the same value from and never detect. An index-addressed store gets a copy like every other store.

### Fixed

- **`{{isolationName}}` could not name an S3 or MinIO bucket at all** — its underscores are mandatory and those grammars forbid them. Measured against a real object store: every bucket `1.1.0` could name is rejected by `make_bucket`, and every one the label form names is created.
- **A startup migration made W = yes against every store in the map**, whatever the change touched. It is now scoped, and an unscoped one leaves every store of that unit undetermined rather than relieved.
- **A volume copy leaked one anonymous volume per provision.** A store image commonly declares a volume path of its own, and any such path the run does not mount over becomes an unnamed volume that no scoped query can ever find.

## [1.1.0] — 2026-08-02

An overlay used to outlive the worktree that created it, holding a port and serving a branch that no longer existed. This release makes an overlay identifiable after the fact, and reclaimable only with proof.

Backward compatible: `schemaVersion` stays at `2` and a manifest written before this release still loads and is reused, with no forced rediscovery.

### Added

- **Overlay ownership.** Every container-kind overlay now carries five labels, so `docker ps --filter label=stackgraft.repo=<hash8>` reconstructs live overlay state **with the manifest deleted**. Host-run services, which have nowhere to hang a label, register in a per-repository sidecar beside the manifest.
- **Ownership proof by `(pid, lstart)`**, compared as verbatim strings — the same `ps` on the same host produced both, so equality is the only operation needed and nothing is parsed. A pid recycled between registration and reap is refused, and the refusal names the mismatch. Where `ps` has no `lstart`, host overlays degrade to report-only rather than being silently unproven.
- **A report pass on every invocation**, which never mutates under any flag combination and completes while another run holds the lock.
- **`scripts/reap.sh`.** Reclaiming requires an explicit flag and **stops** the container; removal is a second flag, so an orphan's logs survive the reap that frees its port. A target whose ownership cannot be proven is refused by name and the proven targets beside it are still acted on.
- **`scripts/with-lock.sh`** and `references/reaping.md`.

### Fixed

- **The manifest's last-writer-wins window.** `SKILL.md` said *rewrite the manifest*, with no lock and no atomic replace, while the design already treats concurrent worktrees as the expected case — two runs would reach that step against one file and the loser's `verifiedOverlays` entry vanished with no error. Writes are now serialized **and** compare-and-swap: serializing alone does not fix it, because the loss happens in the read-modify-write window, not in the write.
- A reclaim that could not delete what it set aside used to exit `0` reporting success over the debris. It now fails loudly and names what it left.

### Changed

- **Two limits are stated rather than covered.** Overlays launched before the label contract carry no label, so nothing distinguishes them from any other container on the machine — the report names the category and declares itself incomplete instead of pretending to enumerate them. And the base-stack port exclusion is **caller-supplied and caller-defeatable**: the helpers parse no JSON, so nothing can check a passed port against the manifest it came from. What holds unconditionally is the positive allowlist.
- Installation leads with the Agent Skills package managers — `npx skills add kevocodes/stackgraft` — instead of asking the reader to know where their agent keeps skills.
- The skill frontmatter gained a top-level semver `version`, which `paks` requires. One release is now one number in four places, and CI rejects a partial bump.

## [1.0.0] — 2026-07-31

First public release.

### Added

- **The skill.** An [Agent Skills](https://agentskills.io) folder read by roughly forty agents: `SKILL.md` plus `references/`, `assets/` and `scripts/`. No per-agent adapters.
- **Selective overlay.** Starts only the services a git worktree changed, on candidate ports, wiring every unchanged dependency back to the base stack already running.
- **A cached topology manifest** under `XDG_CACHE_HOME`, keyed by the git common directory so every worktree of a repository shares one. Invalidation is per slice: a drifted source re-derives only the manifest keys it owns.
- **Discovery that prefers each ecosystem's own resolver** over hand-parsing — leading with `docker compose config --no-interpolate`, which resolves overrides, `extends` and `include` without expanding a secret — and degrades to a marked static parse rather than failing.
- **The shared-state gate.** Every `(service, store)` pair receives a verdict before anything launches: reuse, isolate inside the running instance, or refuse. Unknown resolves to refusal, and emptiness is a claim requiring evidence at every level.
- **A discovered-template contract.** Isolation commands come from the repository and are therefore untrusted: closed placeholder set, a deny-list on the template's own grammar, argv execution with no shell fallback, and rejection of any program that would re-parse an argument as code.
- **Two POSIX `sh` helpers** needing only `git` and `awk`. Neither reads stdin by default, because for a tool an agent invokes, hanging is worse than failing.
- **A Claude Code plugin** wrapping the same folder, for one-command install.
- **A verification suite** run in CI on every push, including a job that exercises the helpers on Alpine with nothing but `git`, `dash` and busybox `awk`.

[2.2.5]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.5
[2.2.4]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.4
[2.2.3]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.3
[2.2.2]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.2
[2.2.1]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.1
[2.2.0]: https://github.com/kevocodes/stackgraft/releases/tag/v2.2.0
[2.1.10]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.10
[2.1.9]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.9
[2.1.8]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.8
[2.1.7]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.7
[2.1.6]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.6
[2.1.5]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.5
[2.1.4]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.4
[2.1.3]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.3
[2.1.2]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.2
[2.1.1]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.1
[2.1.0]: https://github.com/kevocodes/stackgraft/releases/tag/v2.1.0
[2.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v2.0.0
[1.1.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.1.0
[1.0.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.0.0
