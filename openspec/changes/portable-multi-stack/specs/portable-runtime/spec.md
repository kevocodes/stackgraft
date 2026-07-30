# portable-runtime

New capability. Runtime and portability decisions: `../../proposal.md` (Contract surfaces, T1, T3). Platform evidence: `../../exploration.md` Q3, Q5.

## ADDED Requirements

### Requirement: No agent-specific coupling in shipped files

No file under `skills/stackgraft/` MAY name a filesystem path, environment variable, or tool that only one agent provides. Every `assets/` and `references/` link in SKILL.md MUST resolve relative to the skill directory, and no external URL MAY serve as a primary reference.
(Verify: portability grep across shipped files; file review that each link resolves.)

#### Scenario: Portability grep

- GIVEN the shipped skill folder
- WHEN it is searched for single-agent paths, environment variables, and vendor tool names
- THEN there are no matches, including the previous home-directory manifest path and the vendor code-index rule

#### Scenario: Tool-neutral hazard retained

- GIVEN the worktree-placement hazard
- WHEN the Hard Rules are read
- THEN the prohibition on `/tmp` and `/var/tmp` stands on its own bullet, justified without naming any vendor tool

### Requirement: Declared compatibility

Frontmatter MUST carry a `compatibility` value of at most 500 characters on one line, naming POSIX systems, the unconditional dependencies, and the conditional ones. Windows-native support is out of scope and MUST NOT be implied anywhere in the shipped files.
(Verify: file review of frontmatter; portability grep for Windows-only constructs.)

#### Scenario: Frontmatter read

- GIVEN SKILL.md frontmatter
- WHEN `compatibility` is read
- THEN it declares POSIX-only support and names git and a POSIX shell as required, with container tooling required only for container-based repositories

### Requirement: Zero-install script runtime

Every file under `scripts/` MUST run on a stock macOS and a minimal Linux image with no install step. Scripts MUST be POSIX `sh`, MUST use only POSIX `awk` where awk is used, and MUST NOT depend on bash-4 constructs, GNU-only flags, `jq`, `node`, `python3`, or a standalone hashing binary. Scripts MUST NOT parse or emit JSON, MUST NOT write or edit files in place — the agent owns the manifest file. Fingerprints MUST be produced by git with content filters disabled, and the producing tool MUST be recorded in `fingerprintTool`.
(Verify: file review plus POSIX syntax check under `dash -n`; portability grep for disallowed binaries.)

#### Scenario: Syntax and dependency check

- GIVEN both shipped scripts
- WHEN each is checked under a POSIX shell parser and its invoked commands are listed
- THEN parsing succeeds and every invoked command is present on a stock macOS and a minimal Linux image

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

### Requirement: Port allocation returns a candidate, not a guarantee

The port selection contract MUST be stated as a *candidate* port. It MUST exclude `portPolicy.reserved`, every known `basePort`, and every port already allocated in the current run, and it MUST NOT assert that the port is free. The authoritative check is the launcher's strict-port failure, so every overlay launch MUST use the launcher's strict-port option and MUST NOT permit silent fallback to another port. A strict-port failure MUST cause a new candidate to be requested, and the failed port MUST NOT be recorded in the manifest.
(Verify: file review of the script's documented output contract, SKILL.md Hard Rules, and the example's launch commands.)

#### Scenario: Candidate accepted

- GIVEN a candidate port inside the allowed range for the service's `portGroup`
- WHEN the launcher binds it with strict-port enabled
- THEN the overlay runs on that port and the port is recorded

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

#### Scenario: Range exhausted or exceeded

- GIVEN no candidate remains inside the allowed range
- WHEN a port is requested
- THEN the run stops and asks the user before binding anything outside the range

### Requirement: Skill body stays within the style-guide budget

The SKILL.md body MUST remain at most 700 tokens and MUST follow the style-guide section order: frontmatter, Activation Contract, Hard Rules, Decision Gates, Execution Steps, Output Contract, References. `description` MUST be one physical quoted line of at most 250 characters with trigger words first. Detail that does not fit MUST move to `references/` or `assets/`, except the refusal direction of the shared-state gate, which MUST stay in the body.
(Verify: file review against the LLM-first skill style guide; token count per slice.)

#### Scenario: Body reviewed after every slice

- GIVEN the skill body after any slice of this change
- WHEN it is counted and its sections are listed
- THEN the count is at most 700 tokens and the section order matches the style guide

#### Scenario: Gate detail relocated

- GIVEN the full classification procedure
- WHEN the body is read
- THEN the procedure lives in `references/shared-state.md` and the body carries only the gate row, the link, and the refuse-on-unclassified rule
