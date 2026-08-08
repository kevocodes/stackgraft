# Contributing

Issues and pull requests are welcome. This project is small and has a few opinions worth knowing before you spend time on a change.

## The two things most likely to be wrong

**The topology stackgraft discovers for your repository.** It is a cache of an inference, and the inference is where the real bugs are. If the manifest it writes does not match how your stack actually runs, that is the most valuable report you can file — attach the manifest from `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/` with anything private removed.

**The shared-state judgements in `references/shared-state.md`.** The per-substrate table encodes claims about Postgres, Kafka, RabbitMQ, Redis, S3 and others. A wrong claim there makes the gate approve something dangerous *with confidence*, which is worse than having no gate. Corrections with a reference to substrate documentation are worth more than any feature.

## Ground rules

**The skill is agent-agnostic.** No path, environment variable, or tool that only one agent provides. If a change makes stackgraft work better in one agent and worse in the others, it does not go in.

**Scripts assume nothing.** POSIX `sh`, `git`, POSIX `awk`. Not `python3` (a stub on stock macOS), not `node`, `jq`, `sha256sum`, `lsof`, `ss` or `timeout` — each is missing from at least one supported platform. macOS ships bash 3.2, so no bash-4 idioms.

**The gate fails closed.** Any change that lets unknown, absent, empty or degraded data reach a permissive outcome will be rejected, however convenient. If you find such a path, that is a bug report worth opening immediately.

**The body is sealed.** `SKILL.md` may state *that* a verdict is required and *where* it comes from — never a condition under which an overlay is permitted. A summary of the rule in the body would make skipping the reference permissive, which is exactly the failure the seal prevents.

**The body has a hard budget.** At most 500 **words** — the unit the counter below measures, never tokens, because no tokenizer runs on the floor this project supports. It is a hard budget because under progressive disclosure the body is the only file loaded whole. Adding to it means cutting from it first:

```sh
awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' skills/stackgraft/SKILL.md
```

The shipped body measures **497**, so there are three words of headroom. `.github/scripts/verify.sh` asserts that measured number as a literal rather than merely asserting it is under 500, and it reads **this paragraph's own two figures** and holds them to the same measurement — which is what stops this paragraph and the check drifting apart in silence. They had drifted: this sentence said 484 for two slices after the body reached 487, and it said 487 again for the length of one commit after the Output Contract gained the fan-out line. Both times the row above caught it, which is the whole reason the figure is a literal.

## Verifying a change

CI runs these on every push and pull request, and you can run them locally:

```sh
.github/scripts/verify.sh
```

It checks the schema is valid, the example validates against it, every negative fixture is rejected, both scripts pass `dash -n` and actually run, the body is within budget and contains no permitting term, every manifest field named in a document exists in the schema, the four release version strings agree, the released version has a `CHANGELOG.md` entry that extracts to a usable release body, and no agent-specific coupling crept in.

Two things worth doing before you trust a green run:

- **Feed a check something you know is broken** and confirm it goes red. A verifier that cannot fail is not a verifier, and the failure mode is silent.
- **Build the minimal instance the schema accepts** and trace what the gate does with it. Most safety holes live in the smallest legal input, not the realistic one.

## Commits and pull requests

Conventional commits, one work unit per commit — a deliverable outcome, not a file type. Tests and docs travel with the change they describe. A pre-existing defect you fix along the way is its own commit.

```
fix(stackgraft): stop the gate being satisfiable by declaring nothing

- Require dependsOn on every runnable entry, since the gate derives its pair set from that field
- Remove the perverse incentive where omitting every classification field gated less than declaring one
```

Keep pull requests under roughly 400 changed lines. If a change is genuinely larger, say so and explain how to review it.

## Releasing

One `CHANGELOG.md` entry, one number in **four** places, one tag — in that order. Pushing the tag is what publishes: `.github/workflows/release.yml` builds the GitHub release out of the changelog section for that version.

### 1. Write the entry, with its link definition

Newest section first, definitions at the foot of the file:

````md
## [1.2.0] — 2026-09-14

What changed, in prose.

### Added

- ...

[1.2.0]: https://github.com/kevocodes/stackgraft/releases/tag/v1.2.0
````

Both halves. The heading is what the release workflow looks for; the definition is what makes `[1.2.0]` render as a link rather than as literal brackets, and a heading shipped without one is a mistake this project has already made.

Write the section as the release notes, because that is what it becomes — `.github/scripts/changelog-section.sh` prints it verbatim with the heading removed. Do not repeat the version inside the body: GitHub renders it as the release title and shows the tag beside it, so a heading there says the same thing a third time.

### 2. Bump the version in four places, in the same commit

| Where | Why it is there |
|---|---|
| `.claude-plugin/plugin.json` | the source of truth — a Claude Code user receives an update only when this changes |
| `.claude-plugin/marketplace.json` | the version the marketplace lists |
| `SKILL.md`, top-level `version` | what the skill package managers read; `paks` refuses a skill that has no top-level semver `version` |
| `SKILL.md`, `metadata.version` | the skill's own record of the same number |

**CI enforces their agreement.** The `release version` section of `.github/scripts/verify.sh` compares the other three against `plugin.json` and rejects a value that is not semver, so a partial bump is a red run rather than a drift nobody notices until an install fails. Remembering four files is exactly the ritual that already drifted once, which is why it is a check and not a paragraph.

### 3. Merge, then push the signed tag

```sh
git tag -s v1.2.0 -m 'stackgraft 1.2.0'
git push origin v1.2.0
```

### What the tag push checks, and what it cannot

The workflow refuses to publish — loudly, and before creating anything — when:

- **the tag disagrees with `.claude-plugin/plugin.json`.** Pushing `v1.2.0` while the manifest still says `1.1.0` fails the job and names both numbers.
- **`CHANGELOG.md` has no entry for that version.** The extractor exits non-zero naming the version, and a heading with an empty body under it is refused the same way rather than published as a release with no notes.

`verify.sh` covers the rest on every pull request: that the four numbers agree and are semver, that the version `plugin.json` declares has both an entry and a link definition, and that the extracted body carries neither the `## [` heading nor a link-reference line.

**What none of it can see is whether the number is the right one.** All four places agreeing on `1.0.0` is exactly what this repository looked like while `main` had gained 1456 lines of shipped skill since that entry was written — agreement, and stale. Deciding that what shipped is a patch, a minor or a major, and that the entry describes it honestly, is the human half, and it is the half that has actually gone wrong here. The release title is human too: the workflow titles the release with the tag and does not invent the phrase beside it.
