#!/bin/zsh
# Rebuild ~/.local/share/ttyd-web/index.html = ttyd's stock client + the key bar.
# Run this after `brew upgrade ttyd` so the embedded client JS stays current.
set -e
DIR="$HOME/.local/share/ttyd-web"
TTYD=/opt/homebrew/bin/ttyd
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
