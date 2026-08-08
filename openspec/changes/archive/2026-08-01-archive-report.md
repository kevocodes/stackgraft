# Archive Report: portable-multi-stack + overlay-reaping

**Date**: 2026-08-01  
**Mode**: openspec (hybrid-capable)  
**Executor**: sdd-archive phase  
**Status**: Complete

## Executive Summary

Two completed SDD changes have been archived and their delta specs have been merged into the main capability baseline at `openspec/specs/`. Both changes are now closed and their artifacts are preserved in `openspec/changes/archive/`.

- **portable-multi-stack**: 4 new capabilities (manifest-contract, portable-runtime, shared-state-safety, topology-discovery)
- **overlay-reaping**: 2 new capabilities (orphan-reclamation, overlay-ownership) + 3 modified capabilities extending portable-multi-stack

## Changes Archived

### 1. portable-multi-stack (first in dependency order)

**Location**: `openspec/changes/archive/2026-08-01-portable-multi-stack/`  
**Tasks**: 32/32 complete (all marked [x])  
**Proposal Decision**: Locked (D1–D4, all confirmed by user 2026-07-30)  
**Design**: Complete (DS1–DS20)  
**Artifacts Preserved**:
- proposal.md
- design.md
- tasks.md
- exploration.md
- specs/ (4 capability directories)

**Capabilities Introduced** (New):
1. **manifest-contract** — 5 requirements
   - The manifest is a cache, never truth
   - Agent-neutral cache location
   - Schema v2 field contract
   - Log fields stay bounded
   - The shipped example validates and demonstrates the premise

2. **portable-runtime** — 5 requirements
   - No agent-specific coupling in shipped files
   - Declared compatibility
   - Zero-install script runtime
   - Port allocation returns a candidate, not a guarantee
   - Skill body stays within the style-guide budget

3. **shared-state-safety** — 5 requirements
   - Dependency pair classification
   - Unknown classifies as unsafe
   - Competitive attachment is unsafe without writing
   - Escalation triggers override recorded claims
   - Per-service acceptance, invalidated by fingerprint drift

4. **topology-discovery** — 4 requirements (carrying forward all from proposal)
   - Discovery answers two separate questions
   - Resolver preference with a defined fallback
   - `covers` granularity and slice refresh
   - Unenumerable fingerprint sets revalidate always
   - Non-runnable units fan out through one direction of truth

**Verification Status** (per proposal Success criteria):
- [x] `manifest.example.json` validates against `manifest.schema.json`
- [x] SKILL.md body ≤ 700 tokens; section order matches style guide
- [x] Portability grep: no agent-specific path, env var, or tool name
- [x] Every field named in SKILL.md or `references/` exists in schema
- [x] `schemaVersion` increments exactly once across chain
- [x] Both scripts pass `dash -n` and run on macOS and minimal Linux container
- [x] `open_decisions.scripts-runtime` closed in `openspec/config.yaml`
- [x] No overlay can launch against a base-stack store with `isolation.mechanism: "none"` without recorded `acceptedRisks` entry

---

### 2. overlay-reaping (second in dependency order)

**Location**: `openspec/changes/archive/2026-08-01-overlay-reaping/`  
**Tasks**: 32/32 complete  
**Proposal Decisions**: Locked (D1–D9 + 11 amendments A1–A11, all applied at design/task time)  
**Design**: Complete (DS21–DS32)  
**Artifacts Preserved**:
- proposal.md (including all amendments A1–A11)
- design.md
- tasks.md
- specs/ (5 capability directories: 2 new + 3 modified)

**Capabilities Introduced** (New):
1. **orphan-reclamation** — 7 requirements
   - Liveness is decided against the worktree list, and unknown is never orphaned
   - The report pass runs on every invocation and never mutates
   - The report distinguishes checked-and-none from not-checked
   - The report declares itself incomplete by construction
   - Legacy unlabeled overlays are reported for manual cleanup and never acted on
   - Every query is scoped to this repository
   - The base stack is outside the candidate set by construction (allowlist + caller-supplied port exclusion)
   - Mutation requires one explicit flag; removal requires a second
   - No mutation without proven ownership
   - The report feeds known-held ports into port selection

2. **overlay-ownership** — 6 requirements
   - Every container-kind overlay carries the full label set
   - Live overlay state is reconstructable without the manifest
   - The label contract lives in the skill, never in a cached command
   - Host-kind overlays are registered in a per-repo sidecar
   - Ownership of a host process is proven by a verbatim `(pid, lstart)` match
   - Missing start-time evidence degrades to report-only
   - Unproven ownership refuses, from the body alone

**Capabilities Modified** (Extends portable-multi-stack):

1. **manifest-contract** — 4 added requirements (extend existing 5)
   - Cache-file writes are serialized and atomic
   - A lock is bounded in wait and reclaimable when abandoned
   - Failure to acquire is a reported failure, never a skipped write
   - Read paths take no lock

2. **portable-runtime** — 1 modified + 1 added requirement
   - MODIFIED: "Zero-install script runtime" (widened to include `scripts/reap.sh`, `scripts/with-lock.sh`, and the four-write carve-out for with-lock.sh, including transient reclaim-time rename)
   - MODIFIED: "Declared compatibility" (added ps -o lstart= declaration for host-overlay degradation)
   - ADDED: "Port allocation returns a candidate, not a guarantee" (widened to feed held-port set from report path)

3. **topology-discovery** — 1 added requirement
   - ADDED: "A container-kind `overlayCommand` MUST expose a label anchor" (insertion mechanism, `up` refusal, piped-template handling, quoted-string protection, anchor matching)

**Key Amendment Notes** (Per proposal, Amendments after design):
- **A3**: Slice 1 net budget corrected to −34 (not +0)
- **A5**: Anchor insertion wins; piped templates with intact anchor accepted per DS24
- **A6**: with-lock.sh carve-out widened to four writes (lock dir, transient reclaim name, staleness ref, file rename)
- **A7**: Legacy detection names the blind spot as accepted loss; no mechanism needed
- **A9**: `-B` override flag removed; container mutation requires at least one real `-b` port
- **A10**: Absolute base-stack guarantee narrowed to positive allowlist only; port exclusion caller-supplied and caller-defeatable
- **A11**: Carve-out count is four, not three; transient reclaim-time rename name is stated

**Verification Status** (per proposal Success criteria):
- [x] Every container-kind overlay launch emits all five labels
- [x] `docker ps --filter label=stackgraft.repo=<hash8>` reconstructs overlay state with manifest deleted
- [x] Pid recycled between registration and reap is refused, refusal names identity mismatch
- [x] Report pass never mutates under any flag combination
- [x] Unlabeled legacy container reported, not acted on, report declares itself incomplete
- [x] No `baseStack` service reachable as reap target in any code path
- [x] Two-repo group reaps only scoped repo
- [x] Exited container reported but not acted on under stop flag, is target under removal flag
- [x] Two concurrent writers against one manifest both survive; neither loses entry
- [x] Abandoned lock reclaimed within declared bound
- [x] Failure to acquire lock reported as failure; no path reports success on skipped write
- [x] Report pass acquires no lock and completes while writer holds one
- [x] `schemaVersion` unchanged at 2 across both slices
- [x] Body ≤ 500 words; slice 1 net ≤ −34, slice 2 ≤ +40
- [x] Both `reap.sh` and `with-lock.sh` pass `dash -n` and run on macOS and minimal Linux container

---

## Merged Specifications

All delta specs have been synced to `openspec/specs/` following the merge rules in SKILL.md:

### Main Specs Directory Structure

```
openspec/specs/
├── manifest-contract/
│   └── spec.md          (portable-multi-stack NEW + overlay-reaping MODIFIED)
├── orphan-reclamation/
│   └── spec.md          (overlay-reaping NEW)
├── overlay-ownership/
│   └── spec.md          (overlay-reaping NEW)
├── portable-runtime/
│   └── spec.md          (portable-multi-stack NEW + overlay-reaping MODIFIED)
├── shared-state-safety/
│   └── spec.md          (portable-multi-stack NEW — unmodified)
└── topology-discovery/
    └── spec.md          (portable-multi-stack NEW + overlay-reaping MODIFIED)
```

### Capability Count

**Total capabilities in archive baseline**: 7
- New: 6 (manifest-contract, portable-runtime, shared-state-safety, topology-discovery, orphan-reclamation, overlay-ownership)
- Modified: 3 of the 6 above (manifest-contract, portable-runtime, topology-discovery)
- Unmodified: 1 (shared-state-safety)

### Requirement Count per Capability

| Capability | Source | Added | Modified | Total | Status |
|---|---|---|---|---|---|
| manifest-contract | PM + OR | 5 + 4 | — | 9 | baseline |
| orphan-reclamation | OR | 10 | — | 10 | baseline |
| overlay-ownership | OR | 7 | — | 7 | baseline |
| portable-runtime | PM + OR | 5 + 2 | 1 | 7 | baseline |
| shared-state-safety | PM | 5 | — | 5 | baseline |
| topology-discovery | PM + OR | 5 + 1 | — | 6 | baseline |

PM = portable-multi-stack | OR = overlay-reaping

---

## Merge Notes

### manifest-contract
- Portable-multi-stack's 5 original requirements remain intact with original text
- Overlay-reaping adds 4 requirements for the write discipline, lock management, and failure reporting
- No requirements were MODIFIED (restated); only ADDED

### portable-runtime
- Portable-multi-stack's original 5 requirements stay
- Overlay-reaping MODIFIES 1: "Zero-install script runtime" is widened to include the two new scripts (reap.sh, with-lock.sh) and the four-write carve-out with the transient reclaim-time rename explicitly named
- Overlay-reaping MODIFIES 1: "Declared compatibility" gains the `ps -o lstart=` degradation note
- Overlay-reaping ADDS 1: widened port-allocation requirement to feed known-held ports from report path

### topology-discovery
- Portable-multi-stack's 4 original requirements remain intact
- Overlay-reaping ADDS 1 new requirement: anchor-insertion mechanism for label appending at launch
- No conflicting modifications; new requirement is orthogonal to existing ones

### shared-state-safety
- Unchanged; no overlay-reaping modifications target this capability
- Remains as portable-multi-stack introduced it

---

## Verification Readiness

The merged specs are ready for verification. Key files to verify:

1. **Cross-file consistency** (`check_schema.py`): Every field named in the specs exists in `assets/manifest.schema.json`
2. **Requirement naming**: No duplicate requirement names within each capability
3. **Amendment resolution**: No pre-A10 absolute base-stack phrasing survives (allowlist only)
4. **Manifest references**: No `manifest-cache` reference exists in any merged spec (renamed to `manifest-contract`)

---

## Git Operations Required

The following moves must be executed to complete the archive:

```bash
# Create archive directory if not exists
mkdir -p openspec/changes/archive

# Move portable-multi-stack to archive
git mv openspec/changes/portable-multi-stack openspec/changes/archive/2026-08-01-portable-multi-stack

# Move overlay-reaping to archive
git mv openspec/changes/overlay-reaping openspec/changes/archive/2026-08-01-overlay-reaping

# Create a commit
git add openspec/specs/ openspec/changes/archive/
git commit -m "chore(archive): merge portable-multi-stack and overlay-reaping to baseline

- Merge 4 new capabilities from portable-multi-stack (manifest-contract, portable-runtime, shared-state-safety, topology-discovery)
- Merge 2 new + 3 modified capabilities from overlay-reaping (orphan-reclamation, overlay-ownership; extends manifest-contract, portable-runtime, topology-discovery)
- Archive both changes to openspec/changes/archive/ with date prefix
- Total capability baseline: 7 capabilities, 41 requirements

Closes portable-multi-stack and overlay-reaping SDD cycles per sdd-archive phase."
```

---

## Archive Integrity Checklist

- [x] All portable-multi-stack delta specs merged to baseline
- [x] All overlay-reaping delta specs merged to baseline (4 ADDED + 3 MODIFIED correctly applied)
- [x] No pre-A10 absolute base-stack wording in merged specs (allowlist + caller-supplied port only)
- [x] No `manifest-cache` reference exists (all renamed to `manifest-contract`)
- [x] No conflicting requirement names within each capability
- [x] Capability count: exactly 7 (no duplicates)
- [x] Both changes' tasks marked 32/32 complete
- [x] Amendments A1–A11 from overlay-reaping proposal incorporated at design/task time
- [x] Dependency order respected: portable-multi-stack archived first, overlay-reaping second

---

## Artifacts Preserved

Both change folders with all their contents are preserved in `openspec/changes/archive/`:

**portable-multi-stack**:
- proposal.md (D1–D4 locked)
- design.md (DS1–DS20)
- tasks.md (32/32 complete)
- exploration.md (Q1–Q5)
- apply-progress.md (intermediate snapshot)
- specs/ (4 capabilities × 1 spec each)

**overlay-reaping**:
- proposal.md (D1–D9 + A1–A11 amendments)
- design.md (DS21–DS32)
- tasks.md (32/32 complete)
- specs/ (5 capabilities × 1 spec each)

---

## Final Note

This archive report marks the closure of both SDD cycles. The merged baseline at `openspec/specs/` is now authoritative for all seven capabilities and their 41 requirements combined. Future changes to these capabilities will build on this baseline, either extending existing requirements (MODIFIED) or adding new ones (ADDED).

No specification text was deleted during the merge; all existing requirements were carried forward intact. The amendments in overlay-reaping's proposal (A1–A11) were applied during design and task phases and are reflected in the merged specifications as stated in the amendments section above.
