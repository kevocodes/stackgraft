# Archive Report: parallel-feature-isolation

**Date**: 2026-08-08  
**Mode**: openspec (hybrid-capable)  
**Executor**: sdd-archive phase  
**Status**: Complete

## Executive Summary

The completed SDD change `parallel-feature-isolation` has been archived and its delta specs have been merged into the main capability baseline at `openspec/specs/`. Two new capabilities have been added, and five existing capabilities have been extended with new requirements. The baseline has grown from 6 to 8 capabilities.

**Capabilities Introduced** (2 new):
- isolation-providers — seeded-copy provisioning, verification, and lifetime management
- coordination-identity — distinct-identity resolution for coordination hazards

**Capabilities Modified** (5 extended):
- manifest-contract: per-store determinacy records, provider references, name family
- orphan-reclamation: copy reclamation candidates with liveness verification
- portable-runtime: scope declaration, provider carve-out, corrected budget measurement
- shared-state-safety: change-scoped pair selection, two-mechanism separation, generated lifecycle targets
- topology-discovery: per-store classification, pair-set reproducibility, provider eligibility, identity-knob discovery

## Changes Archived

### parallel-feature-isolation

**Location**: `openspec/changes/archive/2026-08-08-parallel-feature-isolation/`  
**Tasks**: 32/32 complete (all marked [x])  
**Artifacts Preserved**:
- proposal.md
- design.md
- tasks.md
- specs/ (7 delta capability directories)

**Artifacts Merged into Baseline**:
- 2 new capability specs created in `openspec/specs/`
- 5 existing capability specs extended with new requirements

## Merged Specifications

All delta specs have been synced to `openspec/specs/` following the merge rules in SKILL.md:

### Capability Count and Structure

**Total capabilities in archive baseline**: 8 (up from 6)

| Capability | Source | Status | Added | Modified |
|---|---|---|---|---|
| coordination-identity | PFI | new | 5 reqs | — |
| isolation-providers | PFI | new | 10 reqs | — |
| manifest-contract | PM + OR + PFI | baseline | 3 new | 1 renamed |
| orphan-reclamation | OR + PFI | baseline | 1 new | — |
| overlay-ownership | OR | baseline | — | — |
| portable-runtime | PM + OR + PFI | baseline | 1 new | 2 modified |
| shared-state-safety | PM + PFI | baseline | 3 new | 5 modified |
| topology-discovery | PM + PFI | baseline | 4 new | — |

Legend: PFI = parallel-feature-isolation | PM = portable-multi-stack | OR = overlay-reaping

### Merge Notes

#### New Capabilities

**coordination-identity** (5 requirements):
1. A coordination hazard resolves by a distinct identity, never by a copy
2. The substrate table answers one question — what is this substrate's identity knob
3. An identity counts only when it is distinct, delivered, and substrate-confirmed
4. Namespace names are derived, never allocated
5. The name family derives every form from one branch hash

**isolation-providers** (10 requirements):
1. The provider contract is three operations and names no substrate
2. A copy is not isolated until it has started and answered a real query
3. Copies are taken live, and the residual is stated rather than covered
4. A copy's lifetime is the worktree, and its age is reported every run
5. Managed, remote and host-native stores refuse by name
6. Free space is measured on the filesystem the copy will occupy, and reported as a candidate
7. The run reports what it copied and predicts nothing
8. Every copy is owned, labelled, named in the output, and removable
9. The provider's runtime scope and requirements
10. Provisioning and verification lifecycle

#### Modified Capabilities

**manifest-contract**:
- ADDED: "Determinacy is recorded per `(unit, store)`" — granular per-pair records replace the all-or-nothing `writes` array
- ADDED: "`migrates` names the stores the entrypoint is pointed at" — scoped to per-store records
- ADDED: "`isolation` carries a provider reference, and the placeholder set carries the name family" — provider references and SQL/DNS name variants
- RENAMED: "Schema v2 field contract" → "Schema v3 field contract" — version bump reflects per-store determinacy, provider references, and name family

**orphan-reclamation**:
- ADDED: "A store copy this skill created is a reclamation candidate; nothing else is" — reopens the volume non-goal for labelled copies only, with the same liveness and flag discipline as overlays

**portable-runtime**:
- ADDED: "The operating scope is declared where a reader meets it" — local development, one host, one base stack, N worktrees; CI/shared/remote declared non-goals
- MODIFIED: "Zero-install script runtime" — expands list to five scripts, adds provider carve-out (bounded to runtime, not filesystem), specifies no JSON parsing
- MODIFIED: "Skill body stays within the style-guide budget" — corrects the budget measurement mechanism (points to `openspec/config.yaml` counter), records the net-negative obligation, documents T4 correction

**shared-state-safety**:
- ADDED: "Change-scoped pair selection is one-directional and evidence-bound" — narrowing is removal-only, relief expires on source drift, `dependsOn` still cannot narrow
- ADDED: "The two hazards resolve by two mechanisms, and neither substitutes for the other" — W→copy, X→identity, separation is enforced
- ADDED: "A missing lifecycle target is offered, never invented, and its teardown is inert until its create has succeeded" — generation rules, approval flow, inert teardown until proven create
- MODIFIED: "Dependency pair classification" — updated to include change-scoped subjects, per-store determinacy, scope bounds (managed/remote/host-native refuse by name)
- MODIFIED: "Unknown classifies as unsafe" — per-store granularity rule, body self-sufficiency required, no permitting conditions in the body
- MODIFIED: "Competitive attachment is unsafe without writing" — X independent of W, identity-based resolution, no copy for X-only pairs
- MODIFIED: "Escalation triggers override recorded claims" — adds unit-migration-on-startup trigger, documents narrowing limit, re-widening visible in output
- RENAMED: "Isolation reuses the server, never the namespace" → "ISOLATE means a seeded copy, and in-instance isolation is the optimisation" — default is copy, in-instance is optimization, corrects table-deletion confusion

**topology-discovery**:
- ADDED: "Discovery writes one determinacy record per `(unit, store)`" — per-pair records, omit rather than guess, degraded confidence tracking
- ADDED: "The pair set's derivation is recorded and reproducible" — count reporting for regression baseline, narrowed-vs-derived distinction
- ADDED: "Discovery records each store's provider eligibility" — local vs managed/remote/host-native determination, reason preservation in refusal
- ADDED: "Discovery records the identity knob and the route that delivers it" — three-part identity discovery, undetermined X handling

## Verification Notes

### Copy Reclamation Implementation

Copy reclamation was specified in this change and shipped unimplemented initially: `reap.sh` had no volume target configuration while five files in `orphan-reclamation` described the copy-reclamation mechanism as working. The mechanism was implemented in a later commit in response to verify-phase review. The current archive includes the implemented version; the unimplemented intermediate state is part of the development history.

Fixtures now cover:
- Copy of a deleted worktree classification and removal
- Copy of a live worktree survival
- Removal flag requirement
- Unlabelled volume preservation
- Unrecognised label-contract-version handling
- Container runtime unavailability handling

### Worktree-List-Unreachable Branch

The `worktree-list-unavailable` branch mentioned in `orphan-reclamation` scenarios (liveness undetermined when `git worktree list --porcelain` fails) is unreachable for a `v:` target (the report-via-volume path) by construction. The repository-identity gate is tested first, and both gates require the same git call to answer. The branch remains reachable via the report-file path and is tested there.

## Merged Specifications Location

All merged specifications are now at `openspec/specs/`:

```
openspec/specs/
├── coordination-identity/spec.md       (NEW)
├── isolation-providers/spec.md         (NEW)
├── manifest-contract/spec.md           (EXTENDED)
├── orphan-reclamation/spec.md          (EXTENDED)
├── overlay-ownership/spec.md           (unchanged)
├── portable-runtime/spec.md            (EXTENDED)
├── shared-state-safety/spec.md         (EXTENDED)
└── topology-discovery/spec.md          (EXTENDED)
```

## Archive Integrity Checklist

- [x] All parallel-feature-isolation delta specs merged to baseline
- [x] 2 new capabilities added (coordination-identity, isolation-providers)
- [x] 5 existing capabilities extended with new/modified requirements
- [x] All per-store determinacy, provider references, and name family fields in place
- [x] Copy reclamation mechanism (initially unimplemented) now implemented and tested
- [x] Capability count: 8 (6 baseline + 2 new)
- [x] No stale unchecked implementation tasks remain
- [x] Dependency order: capabilities consumed (shared-state-safety, isolation-providers, coordination-identity) before consumers (orphan-reclamation, portable-runtime, topology-discovery)
- [x] Archive folder moved to `openspec/changes/archive/2026-08-08-parallel-feature-isolation/`
- [x] Source folder no longer exists in `openspec/changes/`
- [x] All artifacts (proposal, design, tasks, specs) preserved in archive

## Final Note

This archive report marks the closure of the `parallel-feature-isolation` SDD cycle. The merged baseline at `openspec/specs/` now incorporates all eight capabilities with their complete requirement sets as of 2026-08-08. The two new capabilities establish the isolation and coordination hazard mechanisms. The five modified capabilities integrate these mechanisms into the existing decision gates and discovery workflows.

The change introduced a net increase of 20 requirements across the system: 5 for coordination-identity, 10 for isolation-providers, and 5 net additions to existing capabilities (after accounting for renamed requirements). The capability baseline is now positioned to implement per-store determinacy gates, seeded-copy provisioning, and coordination-identity verification in the runtime.
