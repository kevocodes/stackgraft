---
name: Unsafe verdict
about: The shared-state gate allowed something it should have refused
title: 'gate: '
labels: safety
---

Treat this as the highest-priority category. A gate that approves something dangerous **with confidence** is worse than no gate at all.

**What was allowed**
The service, the store, and the verdict you got.

**Why it was unsafe**
What the overlay actually did to shared state — wrote rows, ran a migration, joined a consumer group, took a lock, fired a scheduled job.

**The classification it was working from**
The relevant `services[...]` and `backingStores[...]` entries from your manifest.

**Where you think the reasoning goes wrong**
If it is a substrate claim in `references/shared-state.md` — how Postgres, Kafka, RabbitMQ, Redis or S3 actually behave — a link to the substrate's own documentation is worth more than anything else you can include.

---

If instead the gate **refused something that was genuinely safe**, use this template too and say so. Over-refusal is a real cost; it is just a cheaper failure than the other direction.
