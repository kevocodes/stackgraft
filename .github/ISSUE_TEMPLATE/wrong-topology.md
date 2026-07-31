---
name: Wrong topology
about: stackgraft discovered your repository incorrectly
title: 'topology: '
labels: topology
---

The manifest is a cache of an inference, and the inference is where the real bugs are. This is the most useful report you can file.

**What your stack actually is**
Which services, which ports, how they start. A trimmed `docker-compose.yml` or the equivalent for your stack is ideal.

**What stackgraft discovered instead**
Paste the manifest from `${XDG_CACHE_HOME:-$HOME/.cache}/stackgraft/`, with anything private removed. Paths and service names are usually enough — no need for secrets, and there should be none in there.

**What went wrong as a result**
The wrong service started, a peer resolved to the wrong address, a change mapped to nothing, a port collided — whatever you actually saw.

**Your stack**
Orchestrator and version, plus anything unusual: `include:` chains, override files, a monorepo tool, a non-obvious build context.

**Platform**
macOS / Linux / WSL, and `git --version`.
