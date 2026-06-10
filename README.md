# Your Mac's terminal — and Claude Code — in your phone's browser, over Tailscale

A tiny, free setup that gives you a **real terminal on your Mac** (the same `tmux`
session, with `claude` / vim / a dev server still running in it) inside **any browser
on your phone**, reachable over **Tailscale**, with an **on-screen key bar** for the
keys phone keyboards don't have (arrows, Enter, Esc, Tab, Ctrl, Ctrl-C, page-up, even a
zoom-out). It survives disconnects and reboots. Takes about ten minutes.

Why not just remote-desktop in? Because you're streaming *text*, not pixels — it's
instant even on cell data. Why not the Claude app? Because the web terminal is
literally Claude Code running on your Mac, so it has full context of whatever you're
building there.

> Platform note: written for **macOS** (Apple Silicon, Homebrew at `/opt/homebrew`)
> and **iOS** Safari for the home-screen bits. Adapt paths for Intel Macs
> (`/usr/local`) and Android (it still works in Chrome; the iOS status-bar tweaks
> just don't apply).

---

## 0. Prerequisites

- [Tailscale](https://tailscale.com) installed and logged in **on the Mac and on the
  phone** (free Personal plan is plenty). Both on the same tailnet.
- [Homebrew](https://brew.sh).
- Optional: Claude Code (`claude`) if that's your reason for doing this.

Install the two tools:

```bash
brew install ttyd tmux
```

Find your Mac's Tailscale hostname — you'll use it from the phone:

```bash
tailscale status            # first column = short name, e.g. "my-mac"
# full name is  <short>.<your-tailnet>.ts.net  (visible in the Tailscale admin console)
```

Throughout this guide, substitute that for `YOUR-MAC.YOUR-TAILNET.ts.net`.

---

## 1. A persistent `tmux` session you share across devices

The trick to "pick up where I left off" is that **everything runs inside one long-lived
`tmux` session** on the Mac. The phone browser attaches to it; you attach to the same one
locally. Close the tab, lock the phone, reboot the *phone* — the session and everything
in it keep running on the Mac.

Create `~/.tmux.conf` (tuned for a touch screen — mouse on so you can tap "tabs", login
shells so your dotfiles load, status bar on top because the web key bar takes the bottom):

```bash
cat > ~/.tmux.conf <<'EOF'
# ~/.tmux.conf — tuned for the ttyd web terminal (phone-friendly) + local use.
# The "main" session is shared: attach to it locally with `t` (alias in .zshrc)
# and via the browser.

# Run an interactive *login* shell in every pane so ~/.zshenv + ~/.zshrc
# (oh-my-zsh, theme, aliases, PATH) are always loaded — even when tmux is
# started from a LaunchAgent's bare environment.
set -g default-command "${SHELL} -l"

# Mouse: tap a window in the status bar to switch, tap a pane to focus,
# drag borders to resize, scroll wheel = scrollback. This is what makes
# "tabs" usable by touch in the browser terminal.
set -g mouse on

# Terminal / colors
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc,*256col*:Tc"

# Big scrollback
set -g history-limit 50000

# Windows ("tabs") start at 1, renumber when one closes, keep manual names
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
setw -g allow-rename off
set -g automatic-rename off

# Snappier keys
set -sg escape-time 10
set -g focus-events on

# ---------------------------------------------------------------- status bar
set -g status on
set -g status-interval 5
set -g status-position top   ;# bottom is taken by the web terminal's key bar
set -g status-style "bg=#16161e,fg=#a9b1d6"
set -g status-left "#[bg=#7aa2f7,fg=#16161e,bold] #S #[bg=#16161e,fg=#7aa2f7]"
set -g status-left-length 24
set -g status-right "#[fg=#565f89]#{?client_prefix,#[fg=#e0af68]^B ,}%a %d %b #[fg=#7aa2f7]%H:%M "
setw -g window-status-separator ""
setw -g window-status-format "#[fg=#565f89] #I:#W "
setw -g window-status-current-format "#[bg=#7aa2f7,fg=#16161e,bold] #I:#W #[default]"
set -g pane-border-style "fg=#3b4261"
set -g pane-active-border-style "fg=#7aa2f7"

# ------------------------------------------------------------------- keybinds
# prefix is the default Ctrl-b  (needs a physical/Bluetooth keyboard on phone,
#  or use the on-screen key bar's "^B" button)
bind r source-file ~/.tmux.conf \; display "tmux.conf reloaded"
bind c new-window -c "#{pane_current_path}"
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind -n M-1 select-window -t 1
bind -n M-2 select-window -t 2
bind -n M-3 select-window -t 3
bind -n M-4 select-window -t 4
bind -n M-5 select-window -t 5
bind -n M-6 select-window -t 6
EOF
```

Add a one-letter alias so you attach to that same session from any local shell.
For zsh, in `~/.zshrc`:

```bash
cat >> ~/.zshrc <<'EOF'

# Shared "main" tmux session — same one the phone web terminal attaches to.
# Run `t` to pick up exactly where you left off on the phone, and vice versa.
# Won't nest if you're already inside tmux.
alias t='[[ -z "$TMUX" ]] && exec tmux new -A -s main || tmux new -A -s main'
EOF
```

(`tmux new -A -s main` = "attach to `main`, or create it if it doesn't exist".)

---

## 2. The mobile-friendly web client (with the key bar)

`ttyd` ships a perfectly good xterm.js web client, but on a phone you can't reach Enter,
Esc, Tab, Ctrl, the arrow keys, or page-up — and arrow keys + Enter are the *entire*
interface for TUI agents like Claude Code. We fix that by feeding `ttyd` a **custom
`index.html`**: it's ttyd's stock client (the whole bundle is inlined in that one file)
plus a small key bar pinned to the bottom that injects synthetic keystrokes into xterm's
hidden textarea — the same technique every "virtual keyboard for xterm.js" uses. A few
touches that matter on a phone:

- the on-screen keyboard **stays down by default** (the bar covers what you need, so you
  get more rows of text); tap inside the terminal — or arm `Ctrl` — when you actually
  want to type prose;
- when the keyboard *is* up, the terminal is sized to the area **above** it, so no rows
  hide behind it;
- `🔍−` / `🔍+` buttons zoom the terminal text out/in (more or fewer rows on a small
  screen), persisted in `localStorage`.

We keep the customization in three small source files plus a build script that splices
them into a fresh copy of ttyd's `index.html` (so it's easy to refresh after
`brew upgrade ttyd`).

```bash
mkdir -p ~/.local/share/ttyd-web
```

**`~/.local/share/ttyd-web/keybar.head.html`** — `<head>` additions: a proper mobile
viewport, dark theme color, the iOS standalone-app metadata so the status-bar strip
around the notch / Dynamic Island is dark instead of white, and a home-screen icon.
ttyd serves exactly one file, so the `apple-touch-icon` is embedded as a base64 data
URI instead of a separate PNG (generate yours with
`base64 -i your-icon-180.png | tr -d '\n'` — a 180×180 flat PNG stays ~2 KB):

```bash
cat > ~/.local/share/ttyd-web/keybar.head.html <<'EOF'
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#16161e">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Terminal">
<meta name="mobile-web-app-capable" content="yes">
<link rel="apple-touch-icon" href="data:image/png;base64,YOUR-BASE64-PNG">
EOF
```

**`~/.local/share/ttyd-web/keybar.snippet.html`** — the key bar itself (CSS + the bar +
the JS for keyboard-on-demand, zoom, and sizing the terminal to the visible area):

```bash
cat > ~/.local/share/ttyd-web/keybar.snippet.html <<'EOF'
<style>
  html, body {
    height: 100%; margin: 0; overflow: hidden;
    background: #16161e;            /* shows around the Dynamic Island / notch */
    overscroll-behavior: none;
  }
  /* Terminal area: pinned below the island, above the key bar (+ keyboard).
     --kb-gap (px) is set by JS = key bar height + on-screen-keyboard height.
     --z is the zoom factor (🔍 buttons): the box is laid out 1/z times the
     visible size, then `transform: scale(z)` (top-left origin) shrinks it to fit,
     so xterm's FitAddon — which reads the untransformed box — lays out more,
     smaller rows/cols. At --z:1 everything reduces to a no-op. */
  #terminal-container {
    position: fixed !important;
    top: env(safe-area-inset-top) !important;
    left: 0 !important; right: auto !important; bottom: auto !important;
    width: calc(100% / var(--z, 1)) !important;
    height: calc((100% - var(--kb-gap, 52px) - env(safe-area-inset-top)) / var(--z, 1)) !important;
    transform-origin: top left;
    transform: scale(var(--z, 1));
    padding: 4px 6px 0 !important;
    box-sizing: border-box !important;
  }
  #kb {
    position: fixed; left: 0; right: 0;
    bottom: var(--kbd, 0px);        /* JS lifts it above the soft keyboard */
    display: flex; gap: 6px; align-items: stretch;
    padding: 6px 8px calc(6px + env(safe-area-inset-bottom));
    box-sizing: border-box;
    background: #16161e; border-top: 1px solid #2a2e3f;
    font: 700 16px/1 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    overflow-x: auto; -webkit-overflow-scrolling: touch; white-space: nowrap;
    z-index: 2147483647; user-select: none; -webkit-user-select: none;
  }
  #kb button {
    flex: 0 0 auto; min-width: 46px; min-height: 40px; padding: 0 13px;
    color: #c0caf5; background: #232634; border: 1px solid #2f3447;
    border-radius: 9px; font: inherit; line-height: 1; cursor: pointer;
    -webkit-tap-highlight-color: transparent; touch-action: manipulation;
  }
  #kb button:active { background: #3b4261; }
  #kb button.arr { background: #1f2335; border-color: #3d59a1; color: #7aa2f7; font-size: 21px; min-width: 50px; }
  #kb button.kbd { background: #1f2335; border-color: #3d59a1; color: #7aa2f7; font-size: 18px; }
  #kb button.on  { background: #7aa2f7; color: #16161e; border-color: #7aa2f7; }
  #kb .sp { flex: 0 0 8px; }
</style>
<div id="kb"></div>
<script>
(function () {
  var TOUCH = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
  var root = document.documentElement;
  function ta() { return document.querySelector('.xterm-helper-textarea'); }

  // --- send synthetic keystrokes into xterm.js's hidden textarea -------------
  // dispatchEvent fires xterm's keydown listener even when the textarea isn't
  // focused, so the bar works without summoning the on-screen keyboard.
  function fire(init) {
    var t = ta(); if (!t) return;
    t.dispatchEvent(new KeyboardEvent('keydown', Object.assign({ bubbles: true, cancelable: true }, init)));
  }
  var ctrlOn = false, ctrlBtn = null;
  function setCtrl(v) { ctrlOn = v; if (ctrlBtn) ctrlBtn.classList.toggle('on', v); }
  function key(k, code, keyCode) {
    fire({ key: k, code: code, keyCode: keyCode, which: keyCode, ctrlKey: ctrlOn });
    if (ctrlOn) setCtrl(false);
  }
  function ctrlKey(ch, code, keyCode) { fire({ key: ch, code: code, keyCode: keyCode, which: keyCode, ctrlKey: true }); }
  function prefixThen(k, code, keyCode) {            // tmux: Ctrl-b then <key>
    ctrlKey('b', 'KeyB', 66);
    setTimeout(function () { fire({ key: k, code: code, keyCode: keyCode, which: keyCode }); }, 25);
  }
  function burst(n, fn, gap) { for (var i = 0; i < n; i++) setTimeout(fn, i * (gap || 14)); }

  // --- build the bar ---------------------------------------------------------
  var KB = document.getElementById('kb');
  function btn(label, cls, fn) {
    var b = document.createElement('button');
    b.textContent = label; if (cls) b.className = cls;
    b.addEventListener('mousedown', function (e) { e.preventDefault(); });  // don't steal focus
    b.addEventListener('click', function (e) { e.preventDefault(); fn(b); });
    KB.appendChild(b); return b;
  }
  function sp() { var s = document.createElement('span'); s.className = 'sp'; KB.appendChild(s); }

  btn('←', 'arr', function () { key('ArrowLeft',  'ArrowLeft',  37); });
  btn('↓', 'arr', function () { key('ArrowDown',  'ArrowDown',  40); });
  btn('↑', 'arr', function () { key('ArrowUp',    'ArrowUp',    38); });
  btn('→', 'arr', function () { key('ArrowRight', 'ArrowRight', 39); });
  btn('⏎', 'arr', function () { key('Enter', 'Enter', 13); });            // right by the arrows: select / confirm
  sp();
  btn('Scrl', '', function () {                                            // enter tmux copy mode + page up
    prefixThen('PageUp', 'PageUp', 33);
    setTimeout(function () { key('PageUp', 'PageUp', 33); }, 70);
  });
  btn('⇞', '', function () { burst(2, function () { key('PageUp',   'PageUp',   33); }); });   // page up
  btn('⇟', '', function () { burst(2, function () { key('PageDown', 'PageDown', 34); }); });   // page down
  btn('⤓', '', function () { key('Escape', 'Escape', 27); });             // exit copy mode → jump to live bottom
  sp();
  btn('🔍−', 'kbd', function () { setZoom(zoom - 0.1); });                 // smaller text, more rows
  btn('🔍+', 'kbd', function () { setZoom(zoom + 0.1); });                 // bigger text
  sp();
  btn('Esc', '', function () { key('Escape', 'Escape', 27); });
  btn('Tab', '', function () { key('Tab', 'Tab', 9); });
  sp();
  ctrlBtn = btn('Ctrl', '', function () { setCtrl(!ctrlOn); var t = ta(); if (t) t.focus(); });  // arming Ctrl ⇒ about to type ⇒ show keyboard
  btn('^C', '', function () { ctrlKey('c', 'KeyC', 67); });
  btn('^X', '', function () { ctrlKey('x', 'KeyX', 88); });
  btn('^V', '', function () { ctrlKey('v', 'KeyV', 86); });
  sp();
  btn('^B', '', function () { ctrlKey('b', 'KeyB', 66); });               // tmux prefix

  // ttyd focuses the terminal on connect, which pops the on-screen keyboard.
  // On touch devices, undo that so the keyboard only appears when asked for
  // (tap inside the terminal, or arm Ctrl).
  if (TOUCH) {
    var unfocus = function () { var t = ta(); if (t && document.activeElement === t) t.blur(); };
    setTimeout(unfocus, 150); setTimeout(unfocus, 700);
  }

  // --- zoom (🔍− / 🔍+) ------------------------------------------------------
  var zoom = parseFloat((function () { try { return localStorage.getItem('kbZoom'); } catch (e) { return null; } })() || '1') || 1;
  function setZoom(z) {
    zoom = Math.round(Math.max(0.5, Math.min(1.4, z)) * 10) / 10;
    root.style.setProperty('--z', zoom);
    try { localStorage.setItem('kbZoom', zoom); } catch (e) {}
    layout();
  }

  // --- keep the terminal sized to the *visible* area (above the keyboard) -----
  var inLayout = false;
  function layout() {
    if (inLayout) return;            // ignore the resize event we dispatch below
    inLayout = true;
    try {
      var vv = window.visualViewport;
      var kbd = vv ? Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop)) : 0;
      root.style.setProperty('--kbd', kbd + 'px');
      var barH = KB.offsetHeight || 52;
      root.style.setProperty('--kb-gap', (kbd + barH) + 'px');
      window.dispatchEvent(new Event('resize'));   // nudge xterm's FitAddon
    } finally { setTimeout(function () { inLayout = false; }, 0); }
  }
  root.style.setProperty('--z', zoom);
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', layout);
    window.visualViewport.addEventListener('scroll', layout);
  }
  window.addEventListener('resize', layout);
  setTimeout(layout, 200);
  setTimeout(layout, 800);
  setTimeout(layout, 1600);
})();
</script>
EOF
```

**`~/.local/share/ttyd-web/build.sh`** — regenerates `index.html` by grabbing ttyd's
current client and splicing in the two snippets:

```bash
cat > ~/.local/share/ttyd-web/build.sh <<'EOF'
#!/bin/zsh
# Rebuild ~/.local/share/ttyd-web/index.html = ttyd's stock client + the key bar.
# Run this after `brew upgrade ttyd` so the embedded client JS stays current.
set -e
DIR="$HOME/.local/share/ttyd-web"
TTYD="$(command -v ttyd)"
PORT=7699

# Spin up a throwaway ttyd just to grab its current index.html
"$TTYD" -i 127.0.0.1 -p "$PORT" cat >/dev/null 2>&1 &
TPID=$!
sleep 0.7
curl -fsS "http://127.0.0.1:$PORT/" > "$DIR/base.html"
kill "$TPID" 2>/dev/null || true

python3 - "$DIR" <<'PY'
import sys
d = sys.argv[1]
base = open(f"{d}/base.html").read()
head = open(f"{d}/keybar.head.html").read()
body = open(f"{d}/keybar.snippet.html").read()
assert "</head>" in base and "</body>" in base, "ttyd index.html shape changed — check it"
base = base.replace("</head>", head + "</head>", 1)
base = base.replace("</body>", body + "</body>", 1)
open(f"{d}/index.html", "w").write(base)
PY

echo "rebuilt $DIR/index.html ($(wc -c < "$DIR/index.html") bytes)"
EOF
chmod +x ~/.local/share/ttyd-web/build.sh
~/.local/share/ttyd-web/build.sh
```

If that printed `rebuilt …/index.html (≈740000 bytes)`, you're good.

---

## 3. Serve it: the launcher + a LaunchAgent so it survives reboots

**`~/.local/bin/ttyd-main`** — the command that runs `ttyd`, pointed at our custom client,
wrapping the shared `main` tmux session:

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/ttyd-main <<'EOF'
#!/bin/zsh
# Serve a persistent tmux session ("main") as a web terminal via ttyd.
# Binds 0.0.0.0; remote access is gated by your tailnet (WireGuard-encrypted,
# NOT exposed to the public internet — that would be `tailscale funnel`, which
# we are deliberately not using). See the HTTPS note at the bottom.

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

exec ttyd \
  --writable \
  --port 7681 \
  --index "$HOME/.local/share/ttyd-web/index.html" \
  --client-option fontSize=16 \
  --client-option 'theme={"background":"#1a1b26"}' \
  tmux new -A -s main -c "$HOME"

# Rebuild the custom client after upgrading ttyd:
#   ~/.local/share/ttyd-web/build.sh
# Edit the key bar in ~/.local/share/ttyd-web/keybar.snippet.html, then rebuild.
EOF
chmod +x ~/.local/bin/ttyd-main
```

> Tweak to taste: `-c "$HOME"` → whatever directory you want new shells to start in;
> `fontSize=16` → base size (the `🔍−` button zooms smaller per-device too);
> add `--credential you:somepassword` if you want a login prompt on top of the tailnet
> boundary.

**LaunchAgent** so it starts on login and restarts if it dies:

```bash
cat > "$HOME/Library/LaunchAgents/com.$USER.ttyd.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.$USER.ttyd</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.local/bin/ttyd-main</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/ttyd-main.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/ttyd-main.log</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.$USER.ttyd.plist"
```

Check it's up:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7681/      # -> 200
tail -f ~/Library/Logs/ttyd-main.log                                  # Ctrl-C to quit
```

(To stop/remove it later: `launchctl bootout gui/$(id -u)/com.$USER.ttyd`.)

---

## 4. Use it from the phone

1. Make sure Tailscale is connected on the phone.
2. Open a browser → **`http://YOUR-MAC.YOUR-TAILNET.ts.net:7681`**
3. You're dropped into the `main` tmux session. Run `claude` (or `claude --continue`),
   start a dev server, whatever — it stays alive on the Mac when you leave.
4. **iOS, for the app-like experience:** Share → **Add to Home Screen**. Important: iOS
   bakes the dark status-bar style and title into the icon *at that moment* — if you ever
   change `keybar.head.html`, delete the icon and re-add it.

**The key bar** (bottom of the screen, scrolls horizontally):

`← ↓ ↑ → ⏎` · `Scrl ⇞ ⇟ ⤓` · `🔍− 🔍+` · `Esc Tab` · `Ctrl ^C ^X ^V` · `^B`

- **`← ↓ ↑ → ⏎`** — arrows and Enter sit together; that's the whole loop for picking
  options in a TUI agent.
- **`Scrl`** scrolls back through output (enters tmux copy-mode, pages up a couple of
  screens). Then `⇞ ⇟` move through the buffer — handy for long Claude transcripts — and
  **`⤓`** (or `Esc`) jumps back down to the live prompt.
- **`🔍− / 🔍+`** zoom the terminal text out / in (more or fewer rows per screen). Sticks
  per device.
- **`Ctrl`** is **sticky** — tap it (turns blue, summons the keyboard), then tap any
  normal key to send Ctrl+that. Tap again to disarm.
- **`^B`** sends the tmux prefix in one tap; then tap the next key normally.
- **The keyboard stays down by default** (so the bar's keys give you more rows of text).
  Tap inside the terminal — or arm `Ctrl` — to bring it up.
- Real work from the phone is much nicer with a Bluetooth keyboard; then `Ctrl-b` and the
  rest are just there. Without one, set up your windows/panes at the Mac, and from the
  phone **tap a tab name in the status bar** (mouse mode) to switch windows.

**Locally on the Mac:** instead of opening a bare terminal, run **`t`** — same `main`
session. Phone ↔ Mac, always the same place.

---

## 5. Optional: a clean HTTPS URL with no port (Tailscale Serve)

Plain HTTP over the tailnet is already WireGuard-encrypted, but if you want
`https://YOUR-MAC.YOUR-TAILNET.ts.net/` instead of `:7681`:

1. Enable Serve + HTTPS certs on your tailnet (one-time, in the
   [admin console](https://login.tailscale.com/admin) → DNS / Settings).
2. In `~/.local/bin/ttyd-main`, change `--port 7681` to `--interface 127.0.0.1 --port 7681`
   (so ttyd is localhost-only and Tailscale fronts it), then
   `launchctl kickstart -k gui/$(id -u)/com.$USER.ttyd`.
3. Run: `tailscale serve --bg --https=443 localhost:7681`

That config persists across reboots. (Don't use `tailscale funnel` unless you actually
want this on the public internet.)

---

## 6. Day-to-day

| Task | Command |
|---|---|
| Attach to the session locally | `t` |
| Open it on the phone | `http://YOUR-MAC.YOUR-TAILNET.ts.net:7681` |
| New tab / rename / close | `Ctrl-b c` / `Ctrl-b ,` / `exit` (or the `^B` button then `c` / `,`) |
| Scroll back through output | `Scrl` button, then `⇞ ⇟`; `⤓` (or `Esc`) back to live |
| Smaller / bigger text | `🔍−` / `🔍+` buttons (per device) |
| After `brew upgrade ttyd` | `~/.local/share/ttyd-web/build.sh && launchctl kickstart -k gui/$(id -u)/com.$USER.ttyd` |
| Edit the key bar | edit `~/.local/share/ttyd-web/keybar.snippet.html`, then run `build.sh` + `kickstart` |
| Logs | `~/Library/Logs/ttyd-main.log` |
| Restart the server | `launchctl kickstart -k gui/$(id -u)/com.$USER.ttyd` |
| Uninstall | `launchctl bootout gui/$(id -u)/com.$USER.ttyd; rm ~/Library/LaunchAgents/com.$USER.ttyd.plist ~/.local/bin/ttyd-main; rm -rf ~/.local/share/ttyd-web` (and remove the `t` alias / `~/.tmux.conf` edits if you want) |

Restarting `ttyd` does **not** kill the `tmux` server — `claude` and anything else in
`main` keep running; you just reconnect.

### Troubleshooting

- **Page won't load on the phone** → Tailscale connected on both ends? `tailscale status`
  shows the Mac? `curl localhost:7681` on the Mac returns `200`? Check
  `~/Library/Logs/ttyd-main.log`.
- **Key bar buttons do nothing / new buttons missing** → reload the page (an old cached
  client). On iOS, if a tap doesn't register during the keyboard open/close animation,
  wait a beat and retry.
- **Keyboard won't come up** → tap inside the terminal area, or arm `Ctrl`. It's kept
  down by default on purpose.
- **`claude` not found inside tmux** → the `default-command "${SHELL} -l"` line in
  `~/.tmux.conf` makes panes login shells so your `PATH` loads; open a fresh window after
  adding it.
- **Status bar still white on the home-screen icon** → delete the icon and Add to Home
  Screen again (iOS only reads that metadata at install time).

---

## How it fits together

```
phone browser ──HTTP over Tailscale──▶  ttyd  ──serves──▶  custom index.html
  (xterm.js + key bar)                    │                 (ttyd's client + keybar)
                                          ▼
                                tmux session "main"  ◀── `t` from a local shell
                                          │
                                   your shell / claude / vim / dev server …
```

- **Tailscale** = the network + the only access boundary (private to your devices).
- **ttyd** = HTTP ⇄ PTY bridge, ~1 MB single binary.
- **tmux** = the persistence layer (session outlives every client).
- **custom `index.html`** = ttyd's stock web client + the touch key bar, regenerated by
  `build.sh`.
- **LaunchAgent** = keeps `ttyd` running across reboots.

Total cost: $0. Works on cell data. The whole "client" customization is ~150 lines.

---

*Do whatever you want with this — public domain / CC0. No warranty; you're running a
writable terminal on your machine, so keep it on your tailnet (or add `--credential`) and
don't `funnel` it.*
