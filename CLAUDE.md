# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A tiny setup that serves a persistent `tmux` session as a web terminal (via `ttyd`)
reachable over Tailscale, with a custom phone-friendly key bar. It has two faces:

1. **A publishable writeup** — `README.md` is the canonical tutorial. It embeds the
   contents of every source file inline as `cat <<'EOF'` heredocs.
2. **The live source for what runs on this Mac** — `src/` holds the actual files
   that get deployed to paths outside the repo.

There is no package manager, no test suite, no lint config, and no CI. Editing means
editing a few small files and restarting one LaunchAgent.

## The mirror invariants (read before editing)

Three copies of each file must stay in sync. If you change one, update the others.

| File in `src/` | Embedded in `README.md` as | Deployed path |
|---|---|---|
| `src/keybar.snippet.html` | heredoc in §2 | `~/.local/share/ttyd-web/keybar.snippet.html` |
| `src/keybar.head.html` | heredoc in §2 | `~/.local/share/ttyd-web/keybar.head.html` |
| `src/build.sh` | heredoc in §2 | `~/.local/share/ttyd-web/build.sh` |
| `src/ttyd-main` | heredoc in §3 | `~/.local/bin/ttyd-main` |
| `src/tmux.conf` | heredoc in §1 | `~/.tmux.conf` |
| `src/com.YOURUSER.ttyd.plist` | heredoc in §3 (uses `$USER` substitution) | `~/Library/LaunchAgents/com.caguabot.ttyd.plist` |

- The plist in `src/` is a **template** with `YOURUSER` placeholders — never copy it
  verbatim. The README's version substitutes `$USER` at install time. The deployed
  file has `caguabot` baked in.
- `src/ttyd-main` and `src/tmux.conf` reference the real Tailscale hostname
  (`js-mac-mini.triceratops-adelie.ts.net`) in comments; the README versions use the
  generic `YOUR-MAC.YOUR-TAILNET.ts.net` placeholder. Don't replace one with the
  other when syncing — comments differ on purpose.
- `src/` and deployed files are independent copies (not symlinks/hardlinks).
  After editing `src/`, copy to the deployed path manually, then rebuild and
  restart (see workflow below).

## Edit → deploy → see-it-on-the-phone workflow

When changing the key bar (the most common edit):

```bash
# 1. Edit src/keybar.snippet.html (or keybar.head.html)
# 2. Copy to deployed location
cp src/keybar.snippet.html ~/.local/share/ttyd-web/keybar.snippet.html
# 3. Rebuild the spliced index.html (ttyd's stock client + the keybar)
~/.local/share/ttyd-web/build.sh
# 4. Kick the LaunchAgent so ttyd picks up the new index.html
launchctl kickstart -k gui/$(id -u)/com.caguabot.ttyd
# 5. Hard-reload the phone browser tab
# 6. Update the corresponding heredoc inside README.md
```

When changing `ttyd-main` (server flags, tmux invocation):

```bash
cp src/ttyd-main ~/.local/bin/ttyd-main
launchctl kickstart -k gui/$(id -u)/com.caguabot.ttyd
# Update README.md §3 heredoc
```

Restarting `ttyd` never kills the `tmux` server — `claude` and anything else
running in the `main` session stay alive; clients just reconnect.

## How the custom client is built

`build.sh` is the only "build" step in the repo:

1. Spawns a throwaway `ttyd` on `127.0.0.1:7699` just to `curl` its current
   stock `index.html` to `base.html`.
2. Python splices `keybar.head.html` before `</head>` and `keybar.snippet.html`
   before `</body>`.
3. Writes the result to `index.html` (~740 KB).

Run `build.sh` after `brew upgrade ttyd` to refresh the embedded client JS.
The `assert "</head>" in base and "</body>" in base` check in the splice will
trip loudly if upstream `ttyd`'s HTML shape changes.

## Architecture in one diagram

```
phone browser ──HTTP over Tailscale──▶ ttyd (LaunchAgent, :7681) ──serves──▶ index.html
   (xterm.js + keybar.snippet.html)                  │                       (built by build.sh)
                                                     ▼
                                        tmux session "main"  ◀── `t` alias from local shell
                                                     │
                                            shell / claude / vim …
```

- **Tailscale** = the only access boundary (private to the tailnet, WireGuard).
  The repo deliberately does *not* use `tailscale funnel` (which would expose to
  the public internet).
- **ttyd** = HTTP↔PTY bridge. Runs `tmux new -A -s main` so every connection
  attaches to the same long-lived session.
- **`rendererType=dom`** in `ttyd-main` is load-bearing on iOS — the WebGL renderer
  paints on a canvas, which iOS Safari's long-press "select" gesture can't grab.
- **The keybar** dispatches synthetic `KeyboardEvent`s into xterm.js's hidden
  `.xterm-helper-textarea`. This is why the on-screen keyboard doesn't need to
  be up for keys to work, and why the `Ctrl` button can be "armed" (sticky).

## Logs and diagnostics

| Thing | Where |
|---|---|
| Server logs (stdout+stderr) | `~/Library/Logs/ttyd-main.log` |
| Is it up? | `curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7681/` → `200` |
| Restart | `launchctl kickstart -k gui/$(id -u)/com.caguabot.ttyd` |
| Stop/unload | `launchctl bootout gui/$(id -u)/com.caguabot.ttyd` |
| Reachable URL | `http://js-mac-mini.triceratops-adelie.ts.net:7681` |

## When changing the keybar JS specifically

`src/keybar.snippet.html` is one self-executing `<script>` IIFE. Important
constraints baked into the existing code that are easy to break:

- `fire()` uses `dispatchEvent` (not `.focus()` + key entry) precisely so the
  iOS keyboard stays down. Don't "fix" that by focusing the textarea.
- Layout uses CSS `--z` (zoom) and `--kb-gap` (keybar + soft-keyboard height)
  custom properties, updated from `visualViewport` events. xterm.js's FitAddon
  reads the *untransformed* container size, which is why the zoom is implemented
  as `width: 100%/var(--z)` + `transform: scale(var(--z))` instead of a font
  size change.
- Two-finger / three-finger touch scroll is wired directly to
  `.xterm-viewport.scrollTop` to stay responsive over flaky cell links (no
  WebSocket round-trip).
- Clipboard `Paste` requires a secure context — it will silently no-op over
  the plain-HTTP Tailscale URL. To make it work, front ttyd with
  `tailscale serve --bg --https=443 localhost:7681` (see comment block at
  the bottom of `src/ttyd-main`).

## Parent-repo context

This project lives under the caguabot one-man-company tree at
`~/Desktop/1/tools/phone-terminal/`. The parent `~/Desktop/1/CLAUDE.md` lists
this project in its index and the daily-session-notes dogma applies. The
LaunchAgent runs `tmux new -A -s main -c "$HOME/Desktop/1"` so the shared
`main` session opens at the caguabot root, ready for `claude --continue` in
any of the sibling projects.

## Command Center

project_id: 27
tasks: GET http://caguaserver.triceratops-adelie.ts.net:8787/api/tasks?project_id=27
