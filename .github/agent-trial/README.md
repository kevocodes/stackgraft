# The agent trial

A repeatable way to hand this skill to an agent that has never seen it.

```sh
sh .github/scripts/agent-trial.sh setup      # build the subject, print the prompt
# hand .github/agent-trial/prompt.md to an agent, with the two paths filled in
sh .github/scripts/agent-trial.sh check      # measure what the run left
sh .github/scripts/agent-trial.sh teardown   # remove all of it
```

## Why it is not a CI job

It needs a model in the loop. It is not deterministic, its cost is real, and its
verdict is a report rather than an exit code.

That is also why it is worth keeping. Every floor in this repository drives the
mechanism with a script that already knows what to pass it — which is exactly
why none of them found the seeded copy published on every interface, or a
subject derived from a diff that is empty on the ordinary run, or a sentence
telling agents to write a field the schema forbids. **What an agent supplies is
the absence of that knowledge**, and nothing else here supplies it.

## What the harness does and does not do

It builds an isolated subject — the fixture as a real repository, a worktree
with an **uncommitted** change, four stores up — and refuses to run if anything
from this repository's own verification leaked into it, because a trial that can
read the floors is measuring the floors.

It captures what every store held before, and after the run it diffs. The
postgres check reads the **column list**, not a table or row count: an
`ALTER TABLE` moves neither, and that is exactly the shape of a worktree's
migration.

It does not judge the report. `prompt.md` ends with what five trials showed is
worth looking for, and `check` prints it.

## Do not help the agent

Supplying the port range, the number of stores, or the expected verdict is what
early trials did, and each of those hid a defect the next trial found without
it. The prompt is the whole of what the agent gets.
