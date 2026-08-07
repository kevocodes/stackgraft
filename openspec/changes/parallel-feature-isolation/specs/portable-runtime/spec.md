# portable-runtime

Modified capability. The requirements under `## MODIFIED Requirements` replace the same-named requirements introduced by `portable-multi-stack` (`../../../archive/2026-08-01-portable-multi-stack/specs/portable-runtime/spec.md`) and amended by `overlay-reaping` (`../../../archive/2026-08-01-overlay-reaping/specs/portable-runtime/spec.md`); each is restated in full, carrying its still-valid clauses forward. Scope as a contract term (D1), the shipped provider script (D5), the body budget on a baseline that does not close (T4): `../../proposal.md`.

`No agent-specific coupling in shipped files`, `Declared compatibility` and `Port allocation returns a candidate, not a guarantee` are unchanged by this delta and are deliberately not restated.

## ADDED Requirements

### Requirement: The operating scope is declared where a reader meets it

The shipped files MUST state the operating scope in all three places a reader meets the skill: the `description`, the Activation Contract, and `README.md`. The scope is **local development — one host, one already-running base stack, and N worktrees of one repository in parallel**.

CI, shared hosts, remote hosts, and multi-developer stacks MUST be stated as **declared non-goals**, not left as untested territory: silence about scope is what let an in-place isolation premise be adopted as a universal truth, and every defect this change repairs descends from that silence. Stating the scope is also a grant — against one laptop and gigabyte-scale volumes the skill may copy state and may refuse everything remote without apology — so the statement MUST NOT be softened into a preference. No shipped file MAY imply universal applicability, and a later change MUST NOT widen the scope without restating it in all three places, so that widening it is a visible edit rather than a quiet reading.

The conditional runtime the shipped isolation provider needs MUST be declared where the other conditional dependencies are declared, alongside the existing container-tooling condition, rather than introduced as a new unconditional requirement.
(Verify: file review of `description`, the Activation Contract and `README.md` — the scope and the non-goals appear in each; character count of `description` after the edit; portability grep for any claim of universal applicability; file review that the provider's runtime dependency is declared beside the existing conditional ones.)

#### Scenario: Description read

- GIVEN SKILL.md frontmatter after this change
- WHEN `description` is read
- THEN it states the local-development scope
- AND it remains one physical quoted line of at most 250 characters with trigger words first

#### Scenario: Activation Contract read

- GIVEN the Activation Contract
- WHEN it is read
- THEN it states the scope and names CI, shared hosts, remote hosts, and multi-developer stacks as non-goals

#### Scenario: README read

- GIVEN `README.md`
- WHEN a prospective user reads its opening
- THEN the same scope and the same non-goals are stated there

#### Scenario: A user outside the scope

- GIVEN a user whose stack runs on a shared or CI host
- WHEN they read the first statement of scope they meet
- THEN they are told the skill is not for that situation, rather than discovering it through a refusal later

#### Scenario: Provider dependency declared conditionally

- GIVEN the compatibility declaration after this change
- WHEN it is read
- THEN the runtime the shipped provider needs is named as conditional, beside the existing container-tooling condition

## MODIFIED Requirements

### Requirement: Zero-install script runtime

Every file under `scripts/` MUST run on a stock macOS and a minimal Linux image with no install step, `scripts/reap.sh`, `scripts/with-lock.sh` and the shipped isolation provider included. Scripts MUST be POSIX `sh`, MUST use only POSIX `awk` where awk is used, and MUST NOT depend on bash-4 constructs, GNU-only flags, `jq`, `node`, `python3`, a standalone hashing binary, `flock`, `timeout`, `lsof`, or `ss` — each is absent from at least one supported platform, and macOS ships bash 3.2. Scripts MUST NOT parse or emit JSON.

`scripts/with-lock.sh` is one exception to the no-file-writing rule, and its carve-out names exactly four writes: it MAY create and remove its lock directory, **and rename that directory to one transient adjacent name while removing it** — the rename is what elects a single waiter, so the transient is the same directory under another name for the length of one reclaim and MUST be removed with it, or the run MUST fail loudly naming what it left; it MAY create and remove one staleness-reference file adjacent to the destination, the reference its wait bound is measured against, which MUST be empty by construction and MUST NOT be placed inside the lock directory, because that directory belongs to whoever holds it; and it MAY rename a file its caller already composed into place. It MUST NOT compose, parse, or edit content.

**The shipped isolation provider is the second exception, and its carve-out is bounded to the runtime, not to the filesystem.** It MAY create, populate, and remove container-runtime objects — instances and their state — that it labels as this repository's on creation, because provisioning a seeded copy is exactly that act. It MUST NOT create, edit, or delete any file on the host filesystem outside those objects, MUST NOT touch the manifest or the sidecar, MUST NOT act on any runtime object that does not carry this repository's complete label set, and MUST NOT parse or emit JSON — the daemon values it needs MUST be obtained as plain strings.

Every other script, `reap.sh` included, MUST NOT write or edit files — the agent owns the manifest and the sidecar. Fingerprints MUST be produced by git with content filters disabled, and the producing tool MUST be recorded in `fingerprintTool`.
(Verify: file review plus POSIX syntax check under `dash -n` for all five scripts; portability grep for disallowed binaries; every shipped script executed on macOS and on a minimal Linux image; every path `with-lock.sh` creates compared against the four the carve-out names, the transient reclaim name included, and each confirmed gone once the run ends; the host filesystem diffed across a full provision-address-destroy cycle; the provider exercised against an unlabelled runtime object.)

#### Scenario: Syntax and dependency check

- GIVEN all five shipped scripts
- WHEN each is checked under a POSIX shell parser and its invoked commands are listed
- THEN parsing succeeds and every invoked command is present on a stock macOS and a minimal Linux image
- AND no invocation of `flock`, `timeout`, `lsof`, or `ss` appears

#### Scenario: Reaper writes no file

- GIVEN `scripts/reap.sh` is run on the report path and on the mutation path
- WHEN the filesystem is compared before and after
- THEN the script has created, edited, and deleted no file

#### Scenario: Provider writes no host file

- GIVEN the provider is run through provision, address, and destroy
- WHEN the host filesystem is compared before and after
- THEN no file was created, edited, or deleted outside the runtime objects it made

#### Scenario: Provider refuses an unlabelled object

- GIVEN a runtime object carrying no stackgraft label set
- WHEN the provider is asked to destroy it
- THEN it refuses, names the missing ownership, and the object is untouched

#### Scenario: Provider parses no JSON

- GIVEN the provider's invocations of the container runtime
- WHEN they are reviewed
- THEN each requests a plain string, and no JSON is parsed or emitted anywhere in the script

#### Scenario: Lock script handles bytes it did not author

- GIVEN a caller has composed a replacement cache file
- WHEN `scripts/with-lock.sh` puts it in place
- THEN it takes the lock, renames the prepared file into the destination, releases the lock, and at no point parses or emits JSON
- AND any staleness-reference file it created beside the destination was empty and is gone when it exits

#### Scenario: Fingerprint I/O contract

- GIVEN a list of paths on stdin, including one outside the work tree
- WHEN the fingerprint script runs
- THEN it emits one `<hash><TAB><path>` line per input path, in input order, and writes no file

#### Scenario: Content filters present

- GIVEN the repository configures a content filter for a fingerprinted path
- WHEN the fingerprint is computed
- THEN it reflects the raw file bytes, so a real content change cannot be masked

#### Scenario: Hash format changed

- GIVEN the repository's object format changed since the manifest was written
- WHEN fingerprints are compared
- THEN every comparison mismatches and full rediscovery runs, rather than a false match

### Requirement: Skill body stays within the style-guide budget

The SKILL.md body MUST remain within the declared ceiling and MUST follow the style-guide section order: frontmatter, Activation Contract, Hard Rules, Decision Gates, Execution Steps, Output Contract, References. `description` MUST be one physical quoted line of at most 250 characters with trigger words first. Detail that does not fit MUST move to `references/` or `assets/`, except the refusal direction of the shared-state gate, which MUST stay in the body.

**The count MUST be produced by the counter named in `openspec/config.yaml`, never by eye, and the ceiling MUST be expressed in the unit that counter measures**, so that the requirement and the check answer the same question — a ceiling stated in one unit and checked in another is a ceiling nobody is measuring. The counter MUST be run before each slice is planned and again after it lands, and its negative fixture MUST be exercised, because a counter that cannot report a failure measures nothing.

**This change's net effect on the body MUST be negative.** The per-substrate namespace table and the provider contract MUST both stay out of the body: a change that replaces the isolation half and adds a scope statement pays for the addition out of unrelated compaction, not out of the ceiling. The body MUST state that a verdict is required and where the procedure lives, and MUST NOT state any condition under which an overlay is permitted (`../shared-state-safety/spec.md`).

**Correction, recorded rather than applied silently (`design.md`, *Locked decisions this design cannot deliver as written*, item 1).** This clause previously read *the per-substrate namespace table MUST leave the body entirely*, which names a donor that does not exist: that table has never been in the body — it is in `references/shared-state.md` — and the body's only isolation content is one Output Contract bullet plus the sealed Hard Rule 8. A requirement that names a saving no edit can make is a requirement whose check must either measure something else or be quietly dropped, which is the shape T4 was already carrying. The obligation is unchanged and still closes: measured **498 → 487** across the chain, net −11, out of unrelated compaction (DS33's nine donor rows), with no intermediate slice above the 1a figure of 484. What is corrected is the mechanism the sentence names, not the budget it enforces.
(Verify: file review against the LLM-first skill style guide; the config-named counter run before and after each slice, with its negative fixture; the before and after counts compared for a net decrease; grep of the body for the substrate table and for the provider contract, finding neither.)

#### Scenario: Body reviewed after every slice

- GIVEN the skill body after any slice of this change
- WHEN it is counted with the command `openspec/config.yaml` names and its sections are listed
- THEN the count is within the declared ceiling and the section order matches the style guide

#### Scenario: Counter and ceiling agree

- GIVEN the ceiling this requirement declares and the counter the config names
- WHEN both are read
- THEN the ceiling is expressed in the unit the counter measures

#### Scenario: Counter can fail

- GIVEN a deliberately over-ceiling body fixture
- WHEN the counter runs
- THEN it reports the failure

#### Scenario: Net-negative replacement

- GIVEN the body before this change and after its last slice
- WHEN the two counts are compared
- THEN the later count is lower

#### Scenario: Gate detail relocated

- GIVEN the full classification procedure and the provider contract
- WHEN the body is read
- THEN both live in `references/`, and the body carries only the gate row, the link, and the refuse-on-unclassified rule
