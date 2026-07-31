# topology-discovery

Modified capability. Extends the requirements introduced by `portable-multi-stack` (`../../../portable-multi-stack/specs/topology-discovery/spec.md`); nothing already stated there is replaced. Appendability decision (D2) and its accepted cost: `../../proposal.md`.

## ADDED Requirements

### Requirement: A container-kind `overlayCommand` MUST tolerate appended arguments

The label set is appended by the skill at launch and is never stored in a discovered command, so every container-kind `overlayCommand` MUST be a form to which arguments can be appended. `assets/manifest.schema.json` MUST state this constraint in the `overlayCommand` description; it MUST NOT be expressed as a new field, MUST NOT add a placeholder to the closed set, and MUST NOT change `schemaVersion`. Discovery-generated commands MUST comply, which the preferred `docker compose config`-derived form already does, so the exposure is confined to hand-written entries. An entry whose command cannot take appended arguments — one that pipes, wraps, redirects, or otherwise terminates the argument list — MUST fail loudly at launch, naming the service and the entry. The overlay MUST NOT be launched unlabeled instead: an unlabeled container is unreapable and invisible to every later run, which is the exact failure this change exists to close. Host-kind entries are unaffected — they carry no labels and register in the sidecar instead.
(Verify: schema review of the `overlayCommand` description; file review of the launch step; a hand-written wrapped command exercised at launch; `schemaVersion` compared before and after.)

#### Scenario: Discovery-generated command

- GIVEN an `overlayCommand` derived from `docker compose config --no-interpolate`
- WHEN the overlay launches
- THEN the label arguments are appended and the container starts carrying all five labels

#### Scenario: Hand-written command that cannot take appended arguments

- GIVEN an `overlayCommand` that pipes its output or wraps the launcher so appended arguments would not reach it
- WHEN the overlay is launched
- THEN the launch fails, names the service and the offending entry, and no container is left running unlabeled

#### Scenario: Constraint is discoverable where the command is written

- GIVEN a user writing an `overlayCommand` by hand
- WHEN the schema's description for that field is read
- THEN the appendability constraint is stated there
- AND no new property was added and `schemaVersion` is still `2`

#### Scenario: Host-kind entry

- GIVEN a `kind` whose overlay runs directly on the host
- WHEN it is launched
- THEN no appendability constraint applies to its command, and ownership is recorded in the sidecar instead of in labels
