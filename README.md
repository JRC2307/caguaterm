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
     --kb-gap (px) is set by JS = bar height + on-screen-keyboard height.
     Zoom is a real xterm fontSize change (window.term.options.fontSize), NOT a
     CSS transform — transforms desync tap coordinates from xterm's cell math.
     Horizontal env() insets keep the first column readable in landscape. */
  #terminal-container {
    position: fixed !important;
    top: env(safe-area-inset-top) !important;
    left: 0 !important; right: 0 !important; bottom: auto !important;
    width: 100% !important;
    height: calc(100% - var(--kb-gap, 64px) - env(safe-area-inset-top)) !important;
    padding: 4px calc(6px + env(safe-area-inset-right)) 0 calc(6px + env(safe-area-inset-left)) !important;
    box-sizing: border-box !important;
  }
  /* --sab is zeroed by JS while the soft keyboard is up: the bar then sits on
     the keyboard, not the home indicator, so the inset is dead space. */
  #bar {
    position: fixed; left: 0; right: 0;
    bottom: var(--kbd, 0px);        /* JS lifts it above the soft keyboard */
    background: #16161e; border-top: 1px solid #2a2e3f;
    padding-left: env(safe-area-inset-left);
    padding-right: env(safe-area-inset-right);
    padding-bottom: var(--sab, env(safe-area-inset-bottom));
    z-index: 2147483647; user-select: none; -webkit-user-select: none;
    font: 700 16px/1 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  }
  #expired {
    display: none;
    padding: 8px; text-align: center;
  }
  #expired.show { display: block; }
  #expired button {
    min-height: 44px; padding: 0 16px; width: 100%;
    background: #7aa2f7; color: #16161e; border: 0; border-radius: 9px;
    font: 700 15px/1 -apple-system, system-ui, sans-serif; cursor: pointer;
  }
  /* Single scrollable row — vertical space on the phone beats visible keys. */
  #kb {
    display: flex; gap: 6px; align-items: stretch;
    padding: 6px 8px; box-sizing: border-box;
    overflow-x: auto; -webkit-overflow-scrolling: touch; white-space: nowrap;
    scrollbar-width: none;
  }
  #kb::-webkit-scrollbar { display: none; }
  #kb button {
    flex: 0 0 auto; min-width: 46px; min-height: 44px; padding: 0 13px;
    color: #c0caf5; background: #232634; border: 1px solid #2f3447;
    border-radius: 9px; font: inherit; line-height: 1; cursor: pointer;
    -webkit-tap-highlight-color: transparent; touch-action: manipulation;
  }
  #kb button:active { background: #3b4261; }
  #kb button.arr { background: #1f2335; border-color: #3d59a1; color: #7aa2f7; font-size: 21px; min-width: 50px; }
  #kb button.on  { background: #7aa2f7; color: #16161e; border-color: #7aa2f7; }
  #kb button.tm  { background: #1f2a22; border-color: #4f8a5a; color: #9ece6a; }   /* tmux actions: ledger / agents */
  #kb button.sel-on { background: #9ece6a; color: #16161e; border-color: #9ece6a; }
  #kb .sp { flex: 0 0 6px; }
  /* Selection mode: xterm's handlers are muted (capture-phase stopPropagation
     in JS) and the DOM-renderer rows become real selectable text. */
  body.selmode .xterm-rows, body.selmode .xterm-rows * {
    user-select: text !important; -webkit-user-select: text !important;
    cursor: text;
  }
  body.selmode #terminal-container { outline: 2px solid #9ece6a; outline-offset: -2px; }
</style>
<div id="bar">
  <div id="expired"></div>
  <div id="kb"></div>
</div>
<script>
(function () {
  var TOUCH = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
  var root = document.documentElement;
  var PORT = location.port;
  var IS_OPENCODE = PORT === '7682' || PORT === '4096';
  function ta() { return document.querySelector('.xterm-helper-textarea'); }
  function container() { return document.getElementById('terminal-container'); }
  function hasSelection() { return !!(window.getSelection && String(window.getSelection())); }

  // --- send synthetic keystrokes into xterm.js's hidden textarea -------------
  function fire(init) {
    var t = ta(); if (!t) return;
    t.dispatchEvent(new KeyboardEvent('keydown', Object.assign({ bubbles: true, cancelable: true }, init)));
    // xterm sets _keyDownSeen on keydown and only clears it on keyup; without
    // this, the flag stays true and xterm's input handler drops every composed
    // insertText (iOS QuickType / dictation / autocorrect / emoji keyboard).
    t.dispatchEvent(new KeyboardEvent('keyup', { key: 'Shift', code: 'ShiftLeft', keyCode: 16, which: 16, bubbles: true }));
  }
  var ctrlOn = false, ctrlBtn = null, ctrlTimer = null;
  function setCtrl(v) {
    ctrlOn = v;
    if (ctrlBtn) ctrlBtn.classList.toggle('on', v);
    if (ctrlTimer) { clearTimeout(ctrlTimer); ctrlTimer = null; }
    if (v) ctrlTimer = setTimeout(function () { setCtrl(false); }, 6000);
  }
  function key(k, code, keyCode) {
    fire({ key: k, code: code, keyCode: keyCode, which: keyCode, ctrlKey: ctrlOn });
    if (ctrlOn) setCtrl(false);
  }
  function ctrlKey(ch, code, keyCode) { fire({ key: ch, code: code, keyCode: keyCode, which: keyCode, ctrlKey: true }); }
  function burst(n, fn, gap) { for (var i = 0; i < n; i++) setTimeout(fn, i * (gap || 14)); }
  function prefixThen(k, code, keyCode) {            // tmux: Ctrl-b then <key>
    ctrlKey('b', 'KeyB', 66);
    setTimeout(function () { fire({ key: k, code: code, keyCode: keyCode, which: keyCode }); }, 25);
  }

  // Sticky Ctrl for the iOS soft keyboard: characters typed there arrive via
  // beforeinput/input on the helper textarea, never as keydown — so translate
  // the next typed char to its control code and feed it straight to xterm.
  function ctrlTransform(ch) {
    if (ch === ' ') return '\x00';
    if (ch === '?') return '\x7f';
    var c = ch.toUpperCase().charCodeAt(0);
    if (c >= 64 && c < 128) return String.fromCharCode(c & 31);
    return null;                     // digits/punctuation: let them through untouched
  }
  function termInput(data) {
    if (window.term && typeof window.term.input === 'function') {
      try { window.term.input(data, true); return true; } catch (e) {}
    }
    return false;
  }
  // tmux prefix (Ctrl-b) + one printable char, e.g. 'L' / 'A'. The bytes go
  // straight into xterm's input pipe as ONE write ("\x02L"): that is exact
  // (uppercase survives; a synthetic keydown's shiftKey is ignored by xterm,
  // which just uses ev.key) and has no inter-key timing for tmux to trip on.
  // Falls back to synthetic events if window.term is not exposed.
  function tmuxPrefixChar(ch) {
    setCtrl(false);
    if (termInput('\x02' + ch)) return;
    var up = ch.toUpperCase() === ch && ch.toLowerCase() !== ch;
    var kc = ch.toUpperCase().charCodeAt(0);
    ctrlKey('b', 'KeyB', 66);
    setTimeout(function () {
      fire({ key: ch, code: 'Key' + ch.toUpperCase(), keyCode: kc, which: kc, shiftKey: up });
    }, 30);
  }
  document.addEventListener('beforeinput', function (e) {
    if (!ctrlOn) return;
    var t = e.target;
    if (!t || !t.classList || !t.classList.contains('xterm-helper-textarea')) return;
    if (e.inputType !== 'insertText' || !e.data || e.data.length !== 1) return;
    var out = ctrlTransform(e.data);
    if (out === null) { setCtrl(false); return; }
    e.preventDefault(); e.stopPropagation();
    termInput(out);
    setCtrl(false);
  }, true);
  document.addEventListener('keydown', function (e) {   // hardware keyboards
    if (!ctrlOn || e.isTrusted === false) return;
    var t = e.target;
    if (!t || !t.classList || !t.classList.contains('xterm-helper-textarea')) return;
    if (e.key.length !== 1 || e.ctrlKey || e.metaKey || e.keyCode === 229) return;
    var out = ctrlTransform(e.key);
    if (out === null) { setCtrl(false); return; }
    e.preventDefault(); e.stopPropagation();
    termInput(out);
    setCtrl(false);
  }, true);

  // iOS dictation (board 1665): Safari delivers every recognition update as an
  // insertText whose data is the WHOLE phrase so far ("agrega", "agrega en", ...)
  // and xterm forwards e.data verbatim, so the terminal got the cumulative text
  // repeated. Diff each multi-char insert against the previous one: erase the
  // divergent tail with DEL and type only the new suffix. Single chars (normal
  // typing) and unrelated multi-char inserts (QuickType words) pass untouched.
  var dict = { last: '', at: 0 };
  var DICT_WINDOW_MS = 6000;
  function dictReset() { dict.last = ''; dict.at = 0; }
  function commonPrefix(a, b, fold) {
    var n = Math.min(a.length, b.length), i = 0;
    if (fold) { a = a.toLowerCase(); b = b.toLowerCase(); }
    while (i < n && a.charCodeAt(i) === b.charCodeAt(i)) i++;
    return i;
  }
  document.addEventListener('beforeinput', function (e) {
    if (ctrlOn || e.defaultPrevented) return;
    var t = e.target;
    if (!t || !t.classList || !t.classList.contains('xterm-helper-textarea')) return;
    if (e.inputType !== 'insertText' && e.inputType !== 'insertReplacementText') return;
    var data = e.data;
    if (data == null && e.dataTransfer) { try { data = e.dataTransfer.getData('text/plain'); } catch (_) { data = ''; } }
    if (!data) return;
    var now = Date.now();
    if (now - dict.at > DICT_WINDOW_MS) dictReset();
    if (data.length === 1) { dictReset(); return; }          // ordinary keystroke
    var prev = dict.last;
    var out = data;
    if (prev && commonPrefix(prev, data, true) > 0) {        // revision of the running phrase
      var p = commonPrefix(prev, data, false);
      out = new Array(prev.length - p + 1).join('\x7f') + data.slice(p);
    }
    e.preventDefault(); e.stopPropagation();
    if (out) termInput(out);
    dict.last = data; dict.at = now;
  }, true);
  document.addEventListener('keydown', function (e) { if (e.isTrusted !== false && e.keyCode !== 229) dictReset(); }, true);
  document.addEventListener('compositionend', dictReset, true);
  document.addEventListener('focusout', function (e) {
    var t = e.target; if (t && t.classList && t.classList.contains('xterm-helper-textarea')) dictReset();
  }, true);

  // Blur-then-focus in one gesture forces WebKit to re-present the keyboard
  // even when the textarea is (stale-)focused already.
  function raiseKbd() {
    var t = ta(); if (!t) return;
    t.blur(); t.focus();
  }

  // --- session-expiry watch ---------------------------------------------------
  // The auth proxy's cookie can expire/be revoked; without this the terminal
  // just goes dead with no hint. Cheap poll; 401 → show a sign-in banner.
  // (Window switching itself is done by tapping tmux's own status bar — taps
  // are cell-accurate now that zoom is a real fontSize change.)
  if (!IS_OPENCODE) {
    var EXP = document.getElementById('expired');
    var expBtn = document.createElement('button');
    expBtn.textContent = 'Session expired — tap to sign in';
    expBtn.addEventListener('click', function () { location.reload(); });
    EXP.appendChild(expBtn);
    function checkSession() {
      if (document.hidden) return;
      fetch(location.origin + '/tmux/tabs', { credentials: 'same-origin' })
        .then(function (r) {
          var show = r.status === 401;
          if (show !== EXP.classList.contains('show')) {
            EXP.classList.toggle('show', show);
            layout();
          }
        }, function () {});
    }
    setInterval(checkSession, 60000);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) checkSession();
    });
  }

  // --- build the key bar (single scrollable row) ------------------------------
  var KB = document.getElementById('kb');
  function btn(label, cls, fn) {
    var b = document.createElement('button');
    b.textContent = label; if (cls) b.className = cls;
    b.addEventListener('mousedown', function (e) { e.preventDefault(); });  // don't steal focus
    b.addEventListener('click', function (e) { e.preventDefault(); fn(b); });
    KB.appendChild(b); return b;
  }
  function sp() { var s = document.createElement('span'); s.className = 'sp'; KB.appendChild(s); }

  var kbdBtn = null, selBtn = null;

  btn('←', 'arr', function () { key('ArrowLeft',  'ArrowLeft',  37); });
  btn('↓', 'arr', function () { key('ArrowDown',  'ArrowDown',  40); });
  btn('↑', 'arr', function () { key('ArrowUp',    'ArrowUp',    38); });
  btn('→', 'arr', function () { key('ArrowRight', 'ArrowRight', 39); });
  btn('⏎', 'arr', function () { key('Enter', 'Enter', 13); });
  sp();
  btn('Esc', '', function () { key('Escape', 'Escape', 27); });
  btn('Tab', '', function () { key('Tab', 'Tab', 9); });
  ctrlBtn = btn('Ctrl', '', function () {
    setCtrl(!ctrlOn);
    if (ctrlOn) raiseKbd();          // about to type the combo → summon keyboard
  });
  btn('^C', '', function () { ctrlKey('c', 'KeyC', 67); });
  btn('^B', '', function () { ctrlKey('b', 'KeyB', 66); });               // tmux prefix
  btn('ledger', 'tm', function () { tmuxPrefixChar('L'); });              // prefix L: change-record pane/popup
  btn('agents', 'tm', function () { tmuxPrefixChar('A'); });              // prefix A: board of all Claude sessions
  sp();
  var selOn = false;
  selBtn = btn('Sel', '', function () {
    selOn = !selOn;
    setCtrl(false);
    selBtn.classList.toggle('sel-on', selOn);
    document.body.classList.toggle('selmode', selOn);
    if (!selOn && window.getSelection) window.getSelection().removeAllRanges();
  });
  var copyBtn = btn('Copy', '', function () {
    var text = window.getSelection ? String(window.getSelection()) : '';
    if (!text) return;
    function flash() {
      copyBtn.classList.add('on');
      setTimeout(function () { copyBtn.classList.remove('on'); }, 220);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(flash, function () {});
    } else {
      var tmp = document.createElement('textarea');
      tmp.value = text; document.body.appendChild(tmp);
      tmp.select();
      try { document.execCommand('copy'); flash(); } catch (e) {}
      document.body.removeChild(tmp);
    }
  });
  var pasteBtn = btn('Paste', '', function () {
    if (!navigator.clipboard || !navigator.clipboard.readText) return;
    navigator.clipboard.readText().then(function (text) {
      if (!text) return;
      var t = ta(); if (!t) return;
      var dt;
      try { dt = new DataTransfer(); dt.setData('text/plain', text); } catch (e) {}
      if (dt && typeof ClipboardEvent === 'function') {
        try {
          t.dispatchEvent(new ClipboardEvent('paste', {
            clipboardData: dt, bubbles: true, cancelable: true
          }));
        } catch (e) {}
      }
      pasteBtn.classList.add('on');
      setTimeout(function () { pasteBtn.classList.remove('on'); }, 220);
    }, function () {});
  });
  sp();
  btn('A−', '', function () { setFontSize(fontSize - 1); });
  btn('A+', '', function () { setFontSize(fontSize + 1); });
  kbdBtn = btn('⌨', '', function () {
    if (kbdOpen) { var t = ta(); if (t) t.blur(); }
    else raiseKbd();
  });
  // Extras (kept from the earlier bar; one-finger drag already scrolls, these
  // are for precise paging). Trailing so the main keys stay first in the row.
  sp();
  btn('Scrl', '', function () {                                            // enter tmux copy mode + page up
    prefixThen('PageUp', 'PageUp', 33);
    setTimeout(function () { key('PageUp', 'PageUp', 33); }, 70);
  });
  btn('⇞', '', function () { burst(2, function () { key('PageUp',   'PageUp',   33); }); });
  btn('⇟', '', function () { burst(2, function () { key('PageDown', 'PageDown', 34); }); });
  btn('⤓', '', function () { key('Escape', 'Escape', 27); });             // leave copy mode → live bottom
  btn('^X', '', function () { ctrlKey('x', 'KeyX', 88); });
  btn('^V', '', function () { ctrlKey('v', 'KeyV', 86); });
  if (IS_OPENCODE) {
    sp();
    btn('^XL', '', function () {                                           // list sessions
      ctrlKey('x', 'KeyX', 88);
      setTimeout(function () { key('l', 'KeyL', 76); }, 30);
    });
    btn('^XN', '', function () {                                           // new session
      ctrlKey('x', 'KeyX', 88);
      setTimeout(function () { key('n', 'KeyN', 78); }, 30);
    });
    btn('/Cmd', '', function () {
      fire({ key: '/', code: 'Slash', keyCode: 191, which: 191 });
    });
  }

  // Selection-mode muter: silence xterm's mouse handling so the browser's own
  // selection machinery runs. Touch/wheel events are only muted once a
  // selection EXISTS — before that, drag-to-scroll still works, so a long
  // capture can be scrolled to, long-pressed, and extended. Mouse events are
  // always muted in Sel mode (desktop drag-select).
  var MUTE_TOUCH = { touchstart: 1, touchmove: 1, touchend: 1, wheel: 1 };
  ['mousedown', 'mousemove', 'mouseup', 'touchstart', 'touchmove', 'touchend',
   'pointerdown', 'pointermove', 'pointerup', 'click', 'dblclick', 'contextmenu',
   'wheel'].forEach(function (ev) {
    document.addEventListener(ev, function (e) {
      if (!selOn) return;
      var c = container();
      if (!c || !c.contains(e.target)) return;
      if (MUTE_TOUCH[e.type] && !hasSelection()) return;
      e.stopPropagation();           // default browser behavior still runs
    }, true);
  });

  // ttyd focuses the terminal on connect, which pops the on-screen keyboard.
  // On touch devices, undo that so the keyboard only appears when asked for.
  if (TOUCH) {
    var unfocus = function () { var t = ta(); if (t && document.activeElement === t) t.blur(); };
    setTimeout(unfocus, 150); setTimeout(unfocus, 700);
  }

  // --- zoom = real xterm font size ------------------------------------------
  var fontSize = parseInt((function () { try { return localStorage.getItem('kbFontSize'); } catch (e) { return null; } })() || '16', 10) || 16;
  function applyFontSize() {
    if (window.term && window.term.options) {
      try { window.term.options.fontSize = fontSize; } catch (e) {}
      scheduleFit();
    }
  }
  function setFontSize(n) {
    fontSize = Math.max(10, Math.min(24, n));
    try { localStorage.setItem('kbFontSize', String(fontSize)); } catch (e) {}
    // Mirror into the query string: ttyd re-reads URL options on every
    // reconnect (they outrank server prefs), so reconnects keep the zoom.
    try {
      var u = new URL(location.href);
      u.searchParams.set('fontSize', String(fontSize));
      history.replaceState(null, '', u);
    } catch (e) {}
    applyFontSize();
  }
  // Reconciler instead of a one-shot: ttyd's SET_PREFERENCES lands whenever
  // the (possibly slow, cellular) WS connects and resets fontSize to the
  // server default — keep putting the user's choice back.
  var blurHooked = false;
  setInterval(function () {
    var t = window.term;
    if (t && t.options && t.options.fontSize !== fontSize) applyFontSize();
    if (!blurHooked) {
      var el = ta();
      if (el) {
        blurHooked = true;
        el.addEventListener('blur', function () { kbdOpen = false; if (kbdBtn) kbdBtn.classList.remove('on'); });
      }
    }
  }, 500);

  // --- keep the terminal sized to the *visible* area (above the keyboard) ----
  // CSS vars update synchronously so geometry tracks the keyboard animation,
  // but the expensive part (FitAddon refit → SIGWINCH → tmux redraw) is
  // coalesced: one leading rAF fit + one trailing fit after the viewport
  // settles, instead of ~60/s during the keyboard animation.
  var BAR = document.getElementById('bar');
  var kbdOpen = false;
  var lastKbd = -1, lastGap = -1, fitting = false, fitRaf = null, fitTimer = null;
  function doFit() {
    fitting = true;
    try { window.dispatchEvent(new Event('resize')); } finally { fitting = false; }
  }
  function scheduleFit() {
    if (!fitRaf) fitRaf = requestAnimationFrame(function () { fitRaf = null; doFit(); });
    if (fitTimer) clearTimeout(fitTimer);
    fitTimer = setTimeout(doFit, 300);
  }
  function layout() {
    var vv = window.visualViewport;
    var kbd = vv ? Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop)) : 0;
    if (kbd > 40) root.style.setProperty('--sab', '0px');
    else root.style.removeProperty('--sab');
    kbdOpen = kbd > 150;
    if (kbdBtn) kbdBtn.classList.toggle('on', kbdOpen);
    root.style.setProperty('--kbd', kbd + 'px');
    var barH = BAR.offsetHeight || 64;
    var gap = kbd + barH;
    root.style.setProperty('--kb-gap', gap + 'px');
    if (kbd !== lastKbd || gap !== lastGap) {
      lastKbd = kbd; lastGap = gap;
      scheduleFit();
    }
  }
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', layout);
    window.visualViewport.addEventListener('scroll', layout);
  }
  window.addEventListener('resize', function () { if (!fitting) layout(); });
  setTimeout(layout, 200);
  setTimeout(layout, 800);
  setTimeout(layout, 1600);

  // --- one-finger drag scrolling, routed INTO tmux ---------------------------
  // tmux runs on the alternate screen, so the scrollback lives in tmux, not in
  // xterm's local viewport. Synthesize wheel events on the terminal: xterm
  // forwards them to tmux as mouse-wheel input (mouse mode is on), which
  // enters copy-mode and scrolls real history.
  //   - Coordinates matter: without clientX/Y the wheel report lands at cell
  //     1,1 = tmux's status line (status-position top), where wheel bindings
  //     switch windows or do nothing. Clamp below the status row.
  //   - PX_PER_WHEEL: 0.2 ≈ 1:1 finger tracking (xterm accumulates deltaY into
  //     one wheel notch per row-height, tmux scrolls 5 lines per notch);
  //     0.4 = 2x — content moves twice as far as the finger.
  if (TOUCH) {
    var dragY = null, dragX = 0, dragMoved = false, velocity = 0, lastT = 0, momentumId = null;
    var THRESHOLD = 12;      // px before a touch counts as a drag, not a tap
    var PX_PER_WHEEL = 0.4;

    function rowH() { return Math.max(8, Math.round(fontSize * 1.2)); }
    function sendWheel(dy, x, y) {
      var el = document.querySelector('.xterm-screen') || container();
      if (!el) return;
      var r = el.getBoundingClientRect();
      var cx = Math.min(Math.max(x || 0, r.left + 2), r.right - 2);
      var cy = Math.min(Math.max(y || 0, r.top + rowH() * 1.5), r.bottom - 2);
      el.dispatchEvent(new WheelEvent('wheel', {
        deltaY: dy, deltaMode: 0, clientX: cx, clientY: cy,
        bubbles: true, cancelable: true
      }));
    }
    function stopMomentum() {
      if (momentumId) { cancelAnimationFrame(momentumId); momentumId = null; }
      velocity = 0;
    }
    var momY = 0;
    function momentum() {
      sendWheel(velocity * PX_PER_WHEEL, dragX, momY);
      velocity *= 0.94;
      if (Math.abs(velocity) < 1) { momentumId = null; velocity = 0; return; }
      momentumId = requestAnimationFrame(momentum);
    }

    var c = container();
    if (c) {
      // Fingers: 1 = normal drag, 2 = 2x faster, 3+ = 5x faster (the old
      // "multi-finger scroll", now routed through tmux like the 1-finger drag).
      function avg(touches, prop) {
        var sum = 0;
        for (var i = 0; i < touches.length; i++) sum += touches[i][prop];
        return sum / touches.length;
      }
      var fingers = 0;
      function mult() { return fingers >= 3 ? 5 : fingers === 2 ? 2 : 1; }
      c.addEventListener('touchstart', function (e) {
        stopMomentum();
        if (selOn && hasSelection()) return;
        if (e.touches.length >= 1) {
          fingers = e.touches.length;
          dragY = avg(e.touches, 'clientY'); dragX = avg(e.touches, 'clientX');
          dragMoved = false; lastT = e.timeStamp;
        } else {
          dragY = null;
        }
      }, { passive: true });
      c.addEventListener('touchmove', function (e) {
        if (dragY === null) return;
        if (selOn && hasSelection()) { dragY = null; return; }
        var y = avg(e.touches, 'clientY');
        dragX = avg(e.touches, 'clientX');
        if (e.touches.length !== fingers) {            // finger added/lifted: re-baseline, no jump
          fingers = e.touches.length; dragY = y; lastT = e.timeStamp; velocity = 0;
          return;
        }
        var dy = dragY - y;
        if (!dragMoved && Math.abs(dy) < THRESHOLD) return;
        if (!dragMoved) { dragMoved = true; dy = dy > 0 ? dy - THRESHOLD : dy + THRESHOLD; }
        dy *= mult();
        dragY = y; momY = y;
        var dt = Math.max(1, e.timeStamp - lastT);
        velocity = 0.7 * velocity + 0.3 * (dy / dt * 16);   // smoothed px/frame
        lastT = e.timeStamp;
        sendWheel(dy * PX_PER_WHEEL, dragX, y);
        e.preventDefault();
      }, { passive: false });
      c.addEventListener('touchend', function (e) {
        if (dragY !== null && dragMoved && e.touches.length === 0) {
          if (e.timeStamp - lastT > 80) velocity = 0;   // finger paused → no fling
          if (Math.abs(velocity) > 3) momentumId = requestAnimationFrame(momentum);
          else velocity = 0;
        }
        if (e.touches.length === 0) dragY = null;
        else { fingers = e.touches.length; dragY = avg(e.touches, 'clientY'); lastT = e.timeStamp; velocity = 0; }
        setTimeout(function () { dragMoved = false; }, 80);
      });
      c.addEventListener('touchcancel', function () { dragY = null; velocity = 0; dragMoved = false; fingers = 0; });
      // A drag must not fall through as a click/tap into the terminal.
      ['click', 'mousedown', 'mouseup'].forEach(function (ev) {
        c.addEventListener(ev, function (e) {
          if (dragMoved) { e.stopPropagation(); e.preventDefault(); }
        }, true);
      });
    }
  }

  // --- OSC 52: forward in-terminal copies to the BROWSER clipboard ---------
  // Inner TUIs (hermes chat, tmux copy-mode with set-clipboard on) emit
  // OSC 52 to publish a copy. Stock ttyd/xterm.js ignores it, so the text
  // only ever reached the HOST machine's clipboard via pbcopy — useless from
  // a phone/laptop viewing this page. Register a handler so the copy lands
  // in the viewing device's clipboard. Payload: "<target>;<base64 text>";
  // "?" is a clipboard READ request, which we deliberately do not serve.
  (function hookOsc52() {
    var t = window.term;
    if (!t || !t.parser || !t.parser.registerOscHandler) {
      return void setTimeout(hookOsc52, 300);
    }
    t.parser.registerOscHandler(52, function (data) {
      try {
        var semi = data.indexOf(';');
        var payload = semi >= 0 ? data.slice(semi + 1) : data;
        if (!payload || payload === '?') return true;
        var text = decodeURIComponent(escape(atob(payload)));
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).catch(function () {});
        }
      } catch (e) {}
      return true; // handled — don't let it fall through
    });
  })();
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
