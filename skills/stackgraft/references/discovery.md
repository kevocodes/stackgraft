# Discovery and slice refresh

Discovery is expensive; run it once per repo and refresh only what drifted.

## 1. Pick the sources

Record as `sources[]` every file that defines topology, and what each one `covers`:

| File found | Covers |
|------------|--------|
| `docker-compose*.yml`, `compose*.yaml` | `services`, `baseStack`, `constraints` |
| `package.json` (dev/start scripts) | that service entry |
| `Procfile`, `Makefile`, `Taskfile.yml`, `justfile` | `baseStack`, launch commands |
| `.env.example`, `.env.sample` | `peerEnv`, `constraints` |
| `turbo.json`, `nx.json`, `pnpm-workspace.yaml` | package-to-path mapping |

Never hash a gitignored `.env` — read the constraint it implies and record the constraint instead of the secret.

## 2. Extract per service

For each runnable unit, resolve from the source files, never from assumption:

- **`paths`** — the source globs whose change means this service changed. Start from `build.context` for compose services, from the workspace package directory for JS packages.
- **`sharedDirsIncluded`** — read the Dockerfile. `COPY shared/ ./shared/` with a parent build context means shared edits reach it; `COPY . .` from its own directory means they do not. This is per service; do not generalize across the repo.
- **`basePort`** — the published host port, not the container port.
- **`dependsOn` / `peerEnv`** — the env vars holding peer URLs. Inside a compose network these are DNS names; from a host overlay they must become `localhost:<basePort>`.
- **`consumers`** — for shared/common directories only. List every service whose build context includes that tree.
- **`verifyRequest`** — a real endpoint with real headers. If any header gating exists (CORS, tenant, auth), it belongs in this command.

## 3. Detect constraints

Look for repo-wide settings that silently break an overlay: origin allowlists, host allowlists, hardcoded port lists, fixed tenant headers, `strictPort`, or a proxy that only knows base-stack ports. Record `where`, `effect`, and `remedy`. These are the entries most worth caching — they cost the most to rediscover by failure.

## 4. Refresh a drifted slice

1. Hash each `sources[].path`. Collect the drifted ones.
2. Union their `covers` values — that is the refresh set.
3. Re-derive only those keys. Leave every other entry, and `verifiedOverlays`, untouched.
4. Update the drifted hashes and `discoveredAt`.
5. If a source file disappeared, drop it and re-discover its `covers` from scratch.

Bump `schemaVersion` handling by discarding and rediscovering any manifest whose version you do not recognize.

## 5. Wire the overlay

Start the mapped services with:

- a port from `portPolicy.ranges` for its `kind`,
- every `peerEnv` entry for an **unchanged** peer rewritten to the base stack's `localhost:<basePort>`,
- every `peerEnv` entry for a **co-overlaid** peer rewritten to that overlay's port,
- the worktree as the working directory or build context.

Then run `verifyRequest` and append the result to `verifiedOverlays`.
