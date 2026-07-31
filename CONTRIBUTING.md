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

**The body has a hard budget.** 500 words, because under progressive disclosure it is the only file loaded whole. Adding to it means cutting from it first:

```sh
awk 'f{n+=NF} /^---$/{c++; if(c==2) f=1} END{print n}' skills/stackgraft/SKILL.md
```

## Verifying a change

CI runs these on every push and pull request, and you can run them locally:

```sh
.github/scripts/verify.sh
```

It checks the schema is valid, the example validates against it, every negative fixture is rejected, both scripts pass `dash -n` and actually run, the body is within budget and contains no permitting term, every manifest field named in a document exists in the schema, and no agent-specific coupling crept in.

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

The plugin version lives in `.claude-plugin/plugin.json`. Users receive an update only when it changes, so bump it on release and add a `CHANGELOG.md` entry. The skill's own `metadata.version` in `SKILL.md` tracks the same number.
