# Discovery and slice refresh

Discovery is expensive; run it once per repo and refresh only what drifted.

## Discovery answers two questions, not one

- **(a) path → unit** — which changed files belong to which runnable unit.
- **(b) unit → launch, port, peers** — how to start it, where it binds, how it reaches dependencies.

Many ecosystem files answer only (a). A build-graph file describes what compiles, never what listens. Treating one as a topology source produces a manifest that is confident and wrong.

## 1. Prefer the ecosystem's resolver over hand-parsing

Compose alone has `-f` chains, `COMPOSE_FILE`, `compose.override.yaml` auto-merge, `extends`, recursive `include`, profiles, and `!reset`/`!override` directives. Hand-parsing that is a losing game.

```sh
docker compose config --no-interpolate --format json
```

merges every file and expands short notation into canonical form. `--no-interpolate` leaves variables unexpanded, so include, extends, override, and profiles all resolve **without printing a single secret**.

**Rule:** use a resolver when it is read-only, fast, and non-interpolating. Otherwise parse statically. Otherwise ask the user once and cache the answer.

| Stack | Resolver | Read-only |
|-------|----------|-----------|
| Compose | `docker compose config --no-interpolate --format json` | yes |
| Cargo | `cargo metadata --format-version 1 --no-deps` | yes |
| Go | `go list -m -json all` | yes |
| Nx | `nx show projects --json` | yes |
| Kustomize | `kubectl kustomize <dir>` | yes |
| Gradle | `./gradlew -q projects` | **no — runs a build** |
| Bazel | `bazel query` | **no — starts a server** |
| Tilt | `tilt dump api` | **no — executes Starlark** |
| .NET Aspire | `dotnet run --publisher manifest` | **no — builds and runs the AppHost** |

**When a resolver is unavailable** — Docker not running, toolchain absent — do not fail the run. Fall back to static parse, mark those entries `confidence: "inferred"`, and say so. An inferred entry still maps paths to units; it just may not be trusted for anything that gates safety.

Record *why* it degraded in `sources[].resolverStatus`: `docker daemon not running`, `gradle absent`, `resolver refused: not read-only`. Without it the next run cannot tell a genuine absence from a tool that happened to be down, and re-decides blind. With it, a `resolverStatus` that no longer applies — Docker is up again — is the signal to re-run the resolver and lift `confidence` off `inferred`, which is the only way a degraded entry ever becomes trustworthy for the shared-state gate.

## 2. Tier the sources

Record as `sources[]` every file that defines topology, with the manifest keys it `covers`.

**`sources` may never be empty, including when the user supplied the topology.** An empty array makes the reuse gate vacuously true forever, and the manifest stops being a cache. A user-answered topology has no file of its own, so record it as one entry anyway, `confidence: "user"`, with `resolverStatus` saying why nothing resolved it:

- If the answer is *about* a real file — an unparseable Tiltfile, a compose file whose resolver refused — point `path` at that file and fingerprint it. Editing the file then re-asks the question, which is the behaviour you want.
- If there is genuinely no file behind it, the entry has nothing that drifts, so it MUST carry `revalidate: "always"`. It is then re-derived — re-confirmed with the user — every run, which is the only honest reading of an answer no fingerprint can defend. Never record a user answer as `revalidate: "fingerprint"` against a path that does not exist: `scripts/fingerprint.sh` returns `-` for it, and `-` compared to a stored `-` reads as unchanged.

**Tier 1 — statically resolvable, answers both (a) and (b). Use these first.**

| Source | Gives |
|--------|-------|
| Compose family via `config --no-interpolate` | services, published ports, `depends_on`, env, build context |
| `package.json` scripts + workspace globs | dev servers and their `--port` flags |
| `Procfile`, `Procfile.dev` | process list and launch commands |
| `.env.example`, `.env.sample` | peer URLs and constraints |
| `devcontainer.json` | `forwardPorts`, `appPort`, `dockerComposeFile`, `service`, `runServices` |
| `launchSettings.json` (.NET) | `applicationUrl` per profile |
| `Makefile`, `Taskfile.yml`, `justfile` | launch commands only — never ports |

**Tier 2 — k8s-indirect. A local port exists only through a forward.**

- `skaffold.yaml` → `portForward[].localPort`. Not authoritative: auto-forward silently picks a random open port when the requested one is taken.
- kustomize and plain `Service` manifests → container ports only.
- `Tiltfile` → `k8s_resource(port_forwards=...)`. This is Starlark *code*; static extraction is a heuristic, so mark it `confidence: "inferred"`.

**Tier 3 — build graph only. Use for path → unit. Never infer a port from these.**

`go.work`, Cargo workspace `members`, `settings.gradle(.kts)`, Maven `<modules>`, Bazel, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`, `lerna.json`. One useful hint: a `turbo.json` task marked `persistent: true` is a dev server — that tells you a unit is runnable, not which port it takes.

Never hash a gitignored `.env`. Read the constraint it implies and record the constraint, never the secret.

## 3. Extract per unit

Resolve from the source files, never from assumption:

- **`paths`** — the globs whose change means this unit changed. Start from `build.context` for compose services, from the package directory for workspace members.
- **`buildContext`** — that build context recorded verbatim. It is not decoration: it is what decides which shared trees actually reach this unit, so a non-runnable entry's `consumers` list is derived from it rather than guessed.
- **`runnable`** — `false` for a tree that is never launched and never takes a port (shared code, generated assets). Such an entry exists only to fan a change out to its `consumers`.
- **`consumers`** — on a non-runnable entry, every unit whose build context includes that tree. This is the single direction of truth for shared-code fan-out; do not restate it as a per-service flag that can drift out of sync.
- **`portGroup`** — which range in `portPolicy.ranges` this unit draws from. Keep it independent of `kind`, which is descriptive only. **A `portGroup` with no matching key in `portPolicy.ranges` means stop and ask.** Never guess a range, never widen another group's range to cover it, and never fall back to "any free port": the user owns this machine's ports, and a range nobody sized for this unit is how an overlay lands on one of theirs. `ranges` is optional, so the minimal manifest reaches this case on its very first overlay — it is the normal path, not an error path.
- **`basePort`** — the port published on the host, not the container port.
- **`peerEnv`** — the env vars holding peer URLs. See §4; the right value depends on where the overlay runs.
- **`verifyRequest`** — a real endpoint with real headers. If any gating exists (CORS, tenant, auth), it belongs in this command.
- **`overlayCommand`** — the line that launches this one unit, templated with `{{port}}`, `{{worktree}}` and `{{repoRoot}}`. Derive it from the orchestrator's own single-unit run form (`docker compose run --rm --no-deps --publish {{port}}:<container port>`) or from the package script the repo already defines; never invent one, and never use the whole-stack `up`. A dev server's strict-port flag belongs here, since silent port fallback is what makes the manifest lie.
- **`prepareCommand`** — one-time setup the worktree needs before its first launch, e.g. cloning `node_modules` instead of reinstalling. Omit it when the unit needs none; it is not a second launch hook.
- **`dependsOn`** — every dependency the unit reaches. Each name must resolve to a `services` or a `backingStores` entry; a name in neither is unknown and fails closed. **Required on every runnable unit**, because it is what drives the redirect of unchanged peers to the base stack, so an incomplete list is a peer the overlay never rewires. It only *adds* to the shared-state gate's pair set and cannot narrow it — per `references/shared-state.md` every runnable service is paired with every `backingStores` entry regardless — so omitting a store here does not un-gate it. An empty array means checked-and-none and must carry `stateReview` like any other classification claim. Collect it from every source, not just the orchestrator's own `depends_on`: a peer named only in `peerEnv`, a connection string in `.env.example`, or a client the code constructs is a dependency too. When you cannot prove the list is complete, say so — an unproven list is not a verified-empty one.
- **`backingStores`** — one entry per stateful dependency the base stack runs (database, broker, cache, object store, scheduler), keyed by the exact name `dependsOn` uses. Record `substrate` and `isolation` for each, with `mechanism: "none"` when nothing is discoverable. Inside `isolation`, `applyVia` says how the command reaches the store: `compose-exec` borrows the client from inside the running container, which is why none has to exist on the host; `host-client` needs one that does; `manual` means a human runs it. Put anything a later run would otherwise rediscover into `notes` — above all *why* a mechanism is `none`, since that is the record that stops the next pass from re-deriving a mechanism that does not work. **Never leave a stateful dependency out of this map.** The shared-state gate fires on the dependency, so an unmapped store is a dependency the gate must refuse rather than one it can classify. **Always emit the key, even as `{}`.** An absent map is not "no stores": it is the shape a pass that never looked leaves behind, and the gate pairs every service against this map, so an empty one runs the gate zero times — see the root `stateReview` below.
- **`writes`, `competesOn`, `migrates`, `stateReview`** — classify each unit against every store in `backingStores`, not merely the ones it declares, in the same pass. Emit `[]` only for a list you actually checked; leave the field absent when nobody looked, and record how you looked in `stateReview.method`. Record `stateReview.serviceFingerprint` too, computed over that unit's own `paths` with the recipe at the end of `references/shared-state.md`: it is the only baseline that expires the classification when the service's code changes, and without it the gate reads a verdict derived from code that is gone. The verdict procedure is `references/shared-state.md`; discovery only supplies its inputs.

Three entries are repo-wide rather than per unit, and are extracted in the same pass:

- **`stateReview` at the root** — one record for the whole manifest, `{at, method}`, written whenever this pass leaves `backingStores` empty. It states that discovery *looked* for stateful dependencies and found none, which is what turns an empty map from an omission into a falsifiable claim; `references/shared-state.md` writes the storeless repository's single verdict against it, and refuses everything without it. Only a pass that actually looked may write it: if this run fell back to the degraded path in section 1 — resolver unavailable, static parse standing in for it — then it did not establish absence, so leave the record off and let the gate refuse instead of certifying that no store exists because nothing was able to look. `method` uses the same scale as the per-service record, and `user-asserted` is the weakest of all here: a human saying the repo has no database disarms the gate for every service at once, so check it against the orchestrator's own file before writing it down.
- **`baseStack`** — `startCommand`, `statusCommand` and `teardownCommand` from the orchestrator's own entry points, plus **`bindsTo`**: the interface the base stack publishes on, read from the published-port spec. `127.0.0.1:8080:8080` binds loopback only; `8080:8080` binds every interface. It decides what host an overlay uses to reach a base service (§4) and whether a probe on `localhost` says anything at all, so a wrong value produces connection-refused errors that look like a dead dependency.
- **`constraints`** — repo-wide rules that break an overlay silently rather than loudly: a CORS or host allowlist, a bound interface, a port hardcoded in source, a required header, a fixed socket path. Record `kind`, `where`, `effect` and a `remedy` for each. Read them from `.env.example`, compose env blocks, and gateway or proxy config — never hash a gitignored `.env`; record the constraint it implies instead of the secret.

## 4. Reaching the base stack from an overlay

This is where overlays fail silently, and the correct answer depends on where the overlay runs.

- **Host-run overlay** (a dev server started directly) → `localhost:<basePort>`. The base stack publishes to the host, so this works.
- **Container-run overlay** → **`localhost` is the container, not the host.** A peer URL of `localhost:<basePort>` resolves to the overlay itself and fails with connection refused. Two ways out, in order of preference:
  1. **Attach the overlay to the base stack's network and keep its DNS names.** Declare that network `external: true` in the worktree's compose file, then `http://search-indexer:8090` resolves exactly as it does for the base stack. Nothing about the URL changes.
  2. **Route to the host gateway.** `host.docker.internal` on Docker Desktop; on Linux add `--add-host=host.docker.internal:host-gateway`. Then peers become `http://host.docker.internal:<basePort>`.
- **Co-overlaid peer** → that overlay's address, never the base stack's. Otherwise you exercise the old code and believe it passed.

## 5. Refresh a drifted slice

1. Fingerprint each `sources[].path` with `scripts/fingerprint.sh` and record the tool that produced them in `fingerprintTool`. A stored `fingerprintTool` that is not the one in use marks **every** source drifted — full rediscovery — because two tools' values are not comparable and an equality test between them is meaningless rather than reassuring. Collect the drifted ones.
2. Union the drifted entries' `covers`, then **remove any token that is a strict descendant of another token already in the set**. `covers` values are dot-delimited key paths: `services`, `services.<name>`, `backingStores`, `baseStack`, `portPolicy`, `constraints`.
3. **Coarse wins.** Refreshing `services` re-derives the whole object from every source covering any part of it, including sources that did not themselves drift — and every one of those sources is **re-fingerprinted in the same pass**. Otherwise a fine source keeps a stored fingerprint asserting ownership of a value the coarse pass just overwrote. Over-refresh is cheap; under-refresh is silent staleness.
4. **Fine stays fine.** A drift in `services.storefront` re-derives that key alone. It may create, update, or delete that one key — never another.
5. **A `revalidate: "always"` source is re-derived every run, fingerprint equality or not.** Its stored hash covers the entry file alone while its real input set is not enumerable — a compose file using `include:` or `extends:`, a Tiltfile importing arbitrary Starlark — so an unchanged hash proves nothing about what it pulled in.
6. **Refreshing `services.<name>` drops that service's `verifiedOverlays` record and invalidates its `acceptedRisks` entries.** Both were evidence about code that just changed: a verification proved the old entry worked, and an acceptance was granted for the old fingerprint. Neither is refreshable from the repository, which is why no source may `cover` them — a human or a real request is the only thing that writes them back.
7. Update the drifted fingerprints and `discoveredAt`. Leave every untouched entry alone.
8. If a source file disappeared, drop it and re-discover its `covers` from scratch.
9. Discard and fully rediscover any manifest whose `schemaVersion` you do not recognize. There is no migration path, and there does not need to be — everything here is re-derivable.

## 6. Wire and verify

**Evaluate every `constraints` entry before launching anything — every run, not only the first.** Read each `effect` and decide whether this run's ports, worktree path, or host trips it; apply the `remedy` first if it does. A constraint that bites and has no remedy is a stop-and-ask, not something to launch into and then diagnose from a false green — that is the whole reason these are recorded rather than rediscovered from a failure.

Then start each mapped unit with a candidate port from its `portGroup` range, the worktree as working directory or build context, `prepareCommand` run once if the entry has one, and every `peerEnv` entry rewritten per §4 — resolving a base-stack peer against `baseStack.bindsTo`, since a stack bound to `127.0.0.1` is reachable from the host and from nowhere else. Launch with `overlayCommand`, substituting `{{port}}`, `{{worktree}}` and `{{repoRoot}}`. Bind strictly: a candidate is not a guarantee, and a strict-port failure is the only authoritative signal that the port was taken. Then run `verifyRequest` and record the result in `verifiedOverlays`.
