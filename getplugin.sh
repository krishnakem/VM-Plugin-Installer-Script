#!/usr/bin/env bash
#
# getplugin — clone an OpenClaw plugin repo by name, install its deps,
# and live-link it into OpenClaw so it loads on the next gateway boot.
#
# Usage:
#   ./getplugin.sh owner/repo            # clone + setup + install into openclaw
#   ./getplugin.sh -r owner/repo         # ...and restart the gateway afterward
#   ./getplugin.sh -n owner/repo         # clone + npm install only, skip openclaw
#
# Flags (combinable, e.g. -nr):
#   -n   skip the OpenClaw install step
#   -r   restart the OpenClaw gateway after a successful install
#
# Config (env vars, all optional):
#   PLUGIN_DIR   base directory to clone into        (default: current dir)
#   GIT_HOST     git host                            (default: github.com)
#   NO_OPENCLAW  set to 1 to skip the openclaw step  (same as -n)
#   GATEWAY_LOG  where the relaunched gateway logs    (default: ~/.openclaw/gateway.log)
#
set -euo pipefail

# ---- shared: restart the (foreground) gateway as a detached process -------
restart_gateway() {
  echo "==> restarting OpenClaw gateway"
  if pkill -f "openclaw gateway run" 2>/dev/null; then
    echo "    stopped running gateway; waiting for it to release"
    sleep 2
  fi
  local log="${GATEWAY_LOG:-$HOME/.openclaw/gateway.log}"
  mkdir -p "$(dirname "$log")"
  nohup openclaw gateway run >"$log" 2>&1 &
  disown 2>/dev/null || true
  echo "    gateway relaunched (pid $!), logging to $log"
  echo "    follow it with:  tail -f $log"
}

# ---- args -----------------------------------------------------------------
SKIP_OPENCLAW="${NO_OPENCLAW:-0}"
RESTART=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -n) SKIP_OPENCLAW=1 ;;
    -r) RESTART=1 ;;
    -nr|-rn) SKIP_OPENCLAW=1; RESTART=1 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "usage: $0 [-n] [-r] owner/repo" >&2
  exit 1
fi
if [[ -n "${2:-}" ]]; then
  echo "error: target directory is not supported; plugin directory must match repo name" >&2
  exit 1
fi
if [[ "$REPO" != */* ]]; then
  echo "error: expected 'owner/repo' format, got '$REPO'" >&2
  exit 1
fi

GIT_HOST="${GIT_HOST:-github.com}"
BASE="${PLUGIN_DIR:-$(pwd)}"
NAME="${REPO##*/}"                       # repo part after the slash
DEST="$BASE/$NAME"
URL="https://${GIT_HOST}/${REPO}.git"

# ---- clone (or update if it already exists) -------------------------------
if [[ -d "$DEST/.git" ]]; then
  echo "==> $DEST already exists — pulling latest"
  git -C "$DEST" pull --ff-only
else
  echo "==> cloning $URL -> $DEST"
  git clone "$URL" "$DEST"
fi
cd "$DEST"

# ---- npm install ----------------------------------------------------------
if [[ -f package.json ]]; then
  echo "==> installing npm dependencies"
  npm install

  # Playwright-based plugins need the browser binary + system libs.
  if grep -q '"playwright' package.json; then
    echo "==> playwright detected — installing chromium"
    npx playwright install chromium || true
    # system libs need root; best-effort so a non-sudo box still proceeds
    if command -v sudo >/dev/null 2>&1; then
      sudo npx playwright install-deps chromium || \
        echo "    (could not install system deps — run 'sudo npx playwright install-deps chromium' manually if Chromium fails to launch)"
    fi
  fi
else
  echo "==> no package.json, skipping npm install"
fi

# ---- install into OpenClaw ------------------------------------------------
if [[ "$SKIP_OPENCLAW" == "1" ]]; then
  echo "==> skipping OpenClaw install (-n). Plugin is ready at: $DEST"
  [[ "$RESTART" == "1" ]] && restart_gateway
  exit 0
fi
if ! command -v openclaw >/dev/null 2>&1; then
  echo "==> openclaw CLI not found on PATH — skipping install step."
  echo "    Plugin is cloned and built at: $DEST"
  exit 0
fi

echo "==> installing into OpenClaw (live-linked)"
if openclaw plugins install "$DEST" --link --dangerously-force-unsafe-install; then
  echo ""
  echo "✅ Installed."
  if [[ "$RESTART" == "1" ]]; then
    restart_gateway
  else
    echo "   Restart the gateway to load it:  openclaw gateway run   (or re-run with -r)"
  fi
else
  echo ""
  echo "⚠️  openclaw install failed. The most common cause is a plugin whose"
  echo "    configSchema requires values that aren't set yet (OpenClaw validates"
  echo "    config at install time). Set them, then re-run this script, e.g.:"
  echo "      openclaw config set plugins.entries.<plugin-id>.config.<key> \"<value>\""
  echo "    The repo itself is fine at: $DEST"
  exit 1
fi
