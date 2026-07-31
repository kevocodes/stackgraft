# topology-discovery

Modified capability. Extends the requirements introduced by `portable-multi-stack` (`../../../portable-multi-stack/specs/topology-discovery/spec.md`); nothing already stated there is replaced. Anchor-insertion decision (D2, as amended by A2 and A5) and its accepted cost: `../../proposal.md`.

## ADDED Requirements

### Requirement: A container-kind `overlayCommand` MUST expose a label anchor

The label set is inserted by the skill at launch, at an anchor inside the discovered command, and is never stored in a discovered command, so every container-kind `overlayCommand` MUST expose that anchor: a `run` or `create` token following a recognised launcher token, ahead of the service operand. Insertion MUST add the label elements at the anchor and change nothing else. Anchor matching MUST NOT match a token inside a quoted string — otherwise `echo "docker run x" | sh` would be "labelled" inside a string literal and the container would still launch bare. `assets/manifest.schema.json` MUST state this constraint in the `overlayCommand` description; it MUST NOT be expressed as a new field, MUST NOT add a placeholder to the closed set, and MUST NOT change `schemaVersion`. Discovery-generated commands MUST comply, which the preferred `docker compose config`-derived form already does, so the exposure is confined to hand-written entries. An entry carrying a recognised launcher with no anchor token after it, and an `up`-shaped template — `up` takes no label flag, so it exposes no anchor — MUST fail loudly at launch, naming the service and the entry. A pipe, wrapper, or redirect *after* the anchor is NOT grounds for refusal: insertion lands ahead of it and the labels reach the launcher. Templates that hand the command to an interpreter stay refused by the deny-list in `references/shared-state.md`, where that rule already lives, and are not restated here. The overlay MUST NOT be launched unlabeled instead: an unlabeled container is unreapable and invisible to every later run, which is the exact failure this change exists to close. Host-kind entries are unaffected — they carry no labels and register in the sidecar instead.
(Verify: schema review of the `overlayCommand` description; file review of the launch step; an anchorless hand-written command, an `up`-shaped template, and a quoted-launcher template each exercised at launch; a piped template with an intact anchor exercised at launch and its container inspected for labels; `schemaVersion` compared before and after.)

#### Scenario: Discovery-generated command

- GIVEN an `overlayCommand` derived from `docker compose config --no-interpolate`
- WHEN the overlay launches
- THEN the label arguments are inserted at the anchor and the container starts carrying all five labels

#### Scenario: Hand-written command with no anchor

- GIVEN a container-kind `overlayCommand` whose recognised launcher token is followed by no `run` or `create` token
- WHEN the overlay is launched
- THEN the launch fails, names the service and the offending entry, and no container is left running unlabeled
- AND a whole-stack `up` form is refused the same way, because `up` takes no label flag

#### Scenario: Piped template whose anchor is intact

- GIVEN an `overlayCommand` that pipes or wraps the launcher — `cd X && docker compose run … | tee log` — with its `run` token still following a recognised launcher
- WHEN the overlay launches
- THEN the labels are inserted at that anchor, ahead of the pipe, and the container starts carrying all five labels
- AND the launch is not refused for piping

#### Scenario: Launcher text inside a quoted string

- GIVEN an `overlayCommand` whose only `docker run` text sits inside a quoted string, as in `echo "docker run x" | sh`
- WHEN an anchor is sought
- THEN no anchor is found, nothing is inserted into the string literal, and the launch is refused rather than run bare

#### Scenario: Constraint is discoverable where the command is written

- GIVEN a user writing an `overlayCommand` by hand
- WHEN the schema's description for that field is read
- THEN the anchor constraint is stated there
- AND no new property was added and `schemaVersion` is still `2`

#### Scenario: Host-kind entry

- GIVEN a `kind` whose overlay runs directly on the host
- WHEN it is launched
- THEN no anchor constraint applies to its command, and ownership is recorded in the sidecar instead of in labels
