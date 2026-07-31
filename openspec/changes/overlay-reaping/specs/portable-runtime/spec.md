# portable-runtime

Modified capability. The requirements below replace the same-named requirements introduced by `portable-multi-stack` (`../../../portable-multi-stack/specs/portable-runtime/spec.md`); each is restated in full, carrying its still-valid clauses forward. New scripts (D7), `lstart` declaration (D3), port-knowledge feed (T3), body budget (T4): `../../proposal.md`.

## MODIFIED Requirements

### Requirement: Zero-install script runtime

Every file under `scripts/` MUST run on a stock macOS and a minimal Linux image with no install step, `scripts/reap.sh` and `scripts/with-lock.sh` included. Scripts MUST be POSIX `sh`, MUST use only POSIX `awk` where awk is used, and MUST NOT depend on bash-4 constructs, GNU-only flags, `jq`, `node`, `python3`, a standalone hashing binary, `flock`, `timeout`, `lsof`, or `ss` — each is absent from at least one supported platform, and macOS ships bash 3.2. Scripts MUST NOT parse or emit JSON. `scripts/with-lock.sh` is the single exception to the no-file-writing rule, and its carve-out names exactly three writes: it MAY create and remove its lock directory; it MAY create and remove one staleness-reference file adjacent to the destination, the reference its wait bound is measured against, which MUST be empty by construction and MUST NOT be placed inside the lock directory, because that directory belongs to whoever holds it; and it MAY rename a file its caller already composed into place. It MUST NOT compose, parse, or edit content. Every other script, `reap.sh` included, MUST NOT write or edit files — the agent owns the manifest and the sidecar. Fingerprints MUST be produced by git with content filters disabled, and the producing tool MUST be recorded in `fingerprintTool`.
(Verify: file review plus POSIX syntax check under `dash -n` for all four scripts; portability grep for disallowed binaries; both new scripts executed on macOS and on a minimal Linux image; every path `with-lock.sh` creates compared against the three the carve-out names.)

#### Scenario: Syntax and dependency check

- GIVEN all four shipped scripts
- WHEN each is checked under a POSIX shell parser and its invoked commands are listed
- THEN parsing succeeds and every invoked command is present on a stock macOS and a minimal Linux image
- AND no invocation of `flock`, `timeout`, `lsof`, or `ss` appears

#### Scenario: Reaper writes no file

- GIVEN `scripts/reap.sh` is run on the report path and on the mutation path
- WHEN the filesystem is compared before and after
- THEN the script has created, edited, and deleted no file

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

### Requirement: Declared compatibility

Frontmatter MUST carry a `compatibility` value of at most 500 characters on one physical line, naming POSIX systems, the unconditional dependencies, and the conditional ones. It MUST additionally declare that proving ownership of a host-run overlay needs `ps -o lstart=`, and that where that field is absent host-run overlays are report-only. The field already sits within a few characters of the ceiling, so room for that declaration MUST be made by cutting existing text — never by exceeding 500 characters and never by wrapping onto a second line. Windows-native support is out of scope and MUST NOT be implied anywhere in the shipped files.
(Verify: file review of frontmatter; character count of the value after the change; portability grep for Windows-only constructs.)

#### Scenario: Frontmatter read

- GIVEN SKILL.md frontmatter
- WHEN `compatibility` is read
- THEN it declares POSIX-only support and names git and a POSIX shell as required, with container tooling required only for container-based repositories

#### Scenario: Start-time dependency declared

- GIVEN SKILL.md frontmatter after this change
- WHEN `compatibility` is read
- THEN it names `ps -o lstart=` as what host-overlay ownership proof needs, and states that host overlays are report-only where it is unavailable

#### Scenario: Ceiling respected

- GIVEN the `compatibility` value after the declaration is added
- WHEN its length is measured
- THEN it is one physical line of at most 500 characters

### Requirement: Port allocation returns a candidate, not a guarantee

The port selection contract MUST be stated as a *candidate* port. It MUST exclude `portPolicy.reserved`, every known `basePort`, every port already allocated in the current run, and every port this repository's own live overlays are known to hold, and it MUST NOT assert that the port is free. The held-port set MUST be sourced from the report path and MUST NOT require a mutation flag. That knowledge narrows the unknowable set without closing it: ports held by anything that is not a stackgraft overlay of this repository — another repository's overlays included — remain unknown. The authoritative check is therefore still the launcher's strict-port failure, so every overlay launch MUST use the launcher's strict-port option and MUST NOT permit silent fallback to another port. A strict-port failure MUST cause a new candidate to be requested, and the failed port MUST NOT be recorded in the manifest.
(Verify: file review of the script's documented output contract, SKILL.md Hard Rules, and the example's launch commands; a held port exercised end to end.)

#### Scenario: Candidate accepted

- GIVEN a candidate port inside the allowed range for the service's `portGroup`
- WHEN the launcher binds it with strict-port enabled
- THEN the overlay runs on that port and the port is recorded

#### Scenario: Known-held port excluded

- GIVEN a live labelled overlay of this repository publishes a port inside the allowed range
- WHEN a candidate is requested with no mutation flag passed
- THEN that port is among the exclusions and is not returned

#### Scenario: Candidate already occupied

- GIVEN the candidate port is held by a process the run did not start
- WHEN the launcher fails on strict-port
- THEN a new candidate is requested and the failed port is not recorded
- AND no process is killed to free it

#### Scenario: No port-inspection tool present

- GIVEN neither common port-listing utility exists on the host
- WHEN a candidate is requested
- THEN a candidate is still returned from the allowed range minus the exclusions
- AND the run does not fail for lack of an availability check

#### Scenario: Ownership records unreadable

- GIVEN the sidecar is missing or the container runtime cannot be queried
- WHEN a candidate is requested
- THEN a candidate is still returned, the run states that the held-port set is incomplete, and no port is asserted to be free

#### Scenario: Range exhausted or exceeded

- GIVEN no candidate remains inside the allowed range
- WHEN a port is requested
- THEN the run stops and asks the user before binding anything outside the range

### Requirement: Skill body stays within the style-guide budget

The SKILL.md body MUST remain at most 700 tokens and at most 500 words by the counter published in `CONTRIBUTING.md`, and MUST follow the style-guide section order: frontmatter, Activation Contract, Hard Rules, Decision Gates, Execution Steps, Output Contract, References. `description` MUST be one physical quoted line of at most 250 characters with trigger words first. Detail that does not fit MUST move to `references/` or `assets/`, except the refusal direction of the shared-state gate and of the ownership gate, both of which MUST stay in the body. Slice 1 MUST be net at most +0 words, achieved by rewriting the working-directory Hard Rule into the composite-identity rule rather than adding a rule alongside it; slice 2 MUST add at most 40 words. The body MUST NOT state a condition under which an overlay may be stopped or removed.
(Verify: file review against the LLM-first skill style guide; word and token count per slice; body grep for permitting terms.)

#### Scenario: Body reviewed after every slice

- GIVEN the skill body after any slice of this change
- WHEN it is counted and its sections are listed
- THEN the count is at most 700 tokens and at most 500 words, and the section order matches the style guide

#### Scenario: Slice budgets measured

- GIVEN the word count before this change
- WHEN the body is counted after slice 1 and again after slice 2
- THEN slice 1 is at most the pre-change count and slice 2 is at most slice 1's count plus 40

#### Scenario: Ownership rule replaces rather than accompanies

- GIVEN the Hard Rules after slice 1
- WHEN they are read
- THEN exactly one rule states how ownership is proven, and the working-directory formulation is gone rather than sitting beside its replacement

#### Scenario: Gate detail relocated

- GIVEN the full classification procedure
- WHEN the body is read
- THEN the procedure lives in `references/shared-state.md` and the body carries only the gate row, the link, and the refuse-on-unclassified rule

#### Scenario: Reaping detail relocated

- GIVEN the full liveness, reconciliation, and refusal procedure
- WHEN the body is read
- THEN the procedure lives in `references/reaping.md` and the body carries only the gate rows, the link, and the refuse-on-unproven rule
