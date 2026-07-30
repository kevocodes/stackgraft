# Overlay traps

Each of these has been hit for real. Check them every run — they fail silently or report a false green.

## Ports

- **A port free in `lsof` is not a port available.** The user's own dev servers are not always running when you look. Treat `portPolicy.reserved` as absolute and ask before binding anything outside the allowed range.
- **Never kill a process without proving it is yours.** `lsof -a -p <pid> -d cwd -Fn` prints its working directory — that is what distinguishes your overlay from the user's work. Assuming a background server died and relaunching leaves squatters holding ports.
- **Use `--strictPort` (or the equivalent) on dev servers.** Silent fallback to the next port makes the manifest lie and the user's browser hit the wrong build.

## False greens

- **`/health` returning 200 proves nothing about the overlay.** Header gating, CORS, auth, and tenant checks all sit above the health route. Verify a real endpoint with the real headers and read the response headers back.
- **A blocked cross-origin request still answers 200 on the server.** The browser reports only "Failed to fetch". Always inspect for the echoed allow-origin header, not just the status.
- **Widened is not opened.** After adding an origin or host to an allowlist, confirm an *unlisted* value is still rejected. Otherwise you cannot tell a widened allowlist from a disabled one.

## Wiring

- **Orchestrator DNS names do not resolve from the host.** `http://search-indexer:8090` works inside a compose network; a host-run overlay must use `localhost:<published port>`. Rewrite every peer URL.
- **A shared/common edit does not reach every service.** Only those whose build context includes that tree. Read the Dockerfile per service; `sharedDirsIncluded` exists because this is not uniform.
- **Co-overlaid peers must point at each other**, not at the base stack. Rewrite those URLs to the overlay ports, or you will test the old code and believe it passed.

## Environment

- **Never place a worktree in `/tmp` or `/var/tmp`.** Both trees are reaped on a schedule no run controls, so a worktree can vanish mid-session and take uncommitted work with it. Use `<repo-parent>/<repo-name>-worktrees/<name>` or a path inside the repo's ignored area.
- **Clone dependency trees instead of reinstalling.** On APFS, `cp -Rc <base>/node_modules <worktree>/node_modules` is a clonefile: near-instant, near-zero real disk, and each server keeps its own pre-bundle cache. Symlinking breaks that cache; reinstalling wastes minutes.
- **zsh does not word-split unquoted variables.** `for s in "auth 8080"; do set -- $s` leaves `$2` empty and produces a URL like `localhost:/health`, which reads as a service failure. Use arrays or literals.
- **`assets/manifest.example.json` is illustrative, not factual.** It shows three services of a large compose backend plus a non-dockerized dev server; a real manifest lists every runnable unit. Its ports, paths, and commands are examples — discover them against the real files instead of copying them, or the manifest lies from the first run.
- **Commands that dump merged config or `.env` are correctly permission-blocked** — they would print every secret. Ask the user to edit the file and verify by observable effect instead.
