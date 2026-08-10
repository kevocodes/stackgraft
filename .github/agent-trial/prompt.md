# The agent trial prompt

Hand this to an agent that has never seen this skill. Substitute nothing except
the two paths, which `agent-trial.sh setup` prints.

Do **not** add the port range, the verdict, the number of stores, or any hint
about what the skill will do. Every one of those was supplied in an early trial
and every one of them hid a defect that the next trial, without it, found.

---

You are working in a developer's project. Your working directory is the git
worktree:

    <TREE>

The developer says:

> run this worktree against the stack that's already up

A skill that covers this is installed in the repository at
`.agents/skills/stackgraft/` (relative to the main checkout at `<MAIN>`). Read
it and follow it.

Constraints for this run:

- Work only inside the trial directory. Do not read, modify, or take guidance
  from any other repository on this machine.
- Docker is available. The base stack is already running.
- **If the skill tells you to stop and ask, stop and ask.** Do not guess, and do
  not pick a value the documents forbid you to pick. State the question plainly
  and end your turn; you will be answered and can continue. A correct stop is a
  successful outcome, not a failure.
- If the skill tells you to refuse for any other reason, refuse and say so.

When you stop or finish, report:

1. Exactly where you are in the skill's own steps, and what you have written
   down — including whether a manifest exists and what it does and does not
   contain.
2. The gate's arithmetic: pairs derived, which were removed or escalated and on
   what evidence, and the verdict for each.
3. If you finished: the overlay's port, what data it was pointed at, the exact
   verification request, and the response body.
4. Whether every store's data was left untouched, and how you established that
   for each one.
5. What you left behind, and the exact command to remove each thing.
6. Anywhere the instructions were ambiguous, contradictory, incomplete, or led
   somewhere that did not work — name the file and quote the line. **Do not
   soften this.**
7. Anything you had to guess or invent because the documents did not say.

Be honest about failure. An accurate account of getting stuck is worth more
than a claim of success.

---

## Judging the report

The mechanical half — did any store move, what is still running, was a manifest
written — is what `agent-trial.sh check` measures. The rest is read by a human,
and these are the things five trials showed are worth looking for.

- **A stop is not a failure.** The skill is built to stop rather than guess a
  port range. A run that stops with the whole discovery already written down is
  the designed outcome; a run that stops having written nothing is a defect.
- **Read §6 first and §3 last.** Every expensive finding so far came from §6.
  Completion is the least informative part of the report.
- **Treat every claim as a lead, not a verdict.** Two reports have been specific
  and wrong — one about an engine's persistence, one about `--project-directory`.
  Measure before fixing; record the measurement when the claim does not survive.
- **A guess in §7 is a gap in the documents, even when the guess was right.**
  The agent had to invent something the documents should have said.
- **Ask what the agent could not have known.** It cannot see the floors, so
  anything it found is something no floor covers — that is the whole point of
  running it.
