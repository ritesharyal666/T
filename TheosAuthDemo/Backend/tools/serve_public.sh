#!/usr/bin/env bash
#
# serve_public.sh — run the TheosAuthDemo backend AND expose it on a public
# HTTPS URL with a Cloudflare quick tunnel (no account, no signup).
#
# Usage:   ./serve_public.sh
# Stop:    Ctrl-C  (stops both the tunnel and the server)
#
# The printed https://<random>.trycloudflare.com URL is what you put into
# kTADBaseURL in Theos/NetworkManager.m (keep the trailing slash). The URL is
# RANDOM and changes every run — for a stable URL you'd need a (free) Cloudflare
# account + a named tunnel.
#
set -euo pipefail

PORT="${PORT:-8787}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CLOUDFLARED="${CLOUDFLARED:-$HOME/.local/bin/cloudflared}"

if [ ! -x "$CLOUDFLARED" ]; then
  echo "cloudflared not found at $CLOUDFLARED"
  echo "Download it once with:"
  echo "  mkdir -p ~/.local/bin && curl -sL -o ~/.local/bin/cloudflared \\"
  echo "    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x ~/.local/bin/cloudflared"
  exit 1
fi

cleanup() { kill "${SERVER_PID:-}" "${TUNNEL_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

echo "Starting backend on 127.0.0.1:$PORT ..."
PORT="$PORT" python3 "$HERE/devserver.py" &
SERVER_PID=$!
sleep 1

echo "Opening Cloudflare quick tunnel ..."
"$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" 2>&1 | \
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *trycloudflare.com*)
        url=$(echo "$line" | grep -oE 'https://[a-z0-9.-]+trycloudflare.com' | head -1)
        if [ -n "$url" ]; then
          echo ""
          echo "============================================================"
          echo "  PUBLIC HTTPS URL:  $url"
          echo "  Put this in kTADBaseURL (with a trailing slash):"
          echo "      @\"$url/\""
          echo "============================================================"
        fi
        ;;
    esac
  done &
TUNNEL_PID=$!

wait
