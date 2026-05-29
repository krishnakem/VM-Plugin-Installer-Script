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
#
set -euo pipefail

restart_gateway() {
  echo "==> restarting OpenClaw gateway"
  if pkill -f "dist/index.js gateway" 2>/dev/null; then
    echo "    stopped gateway; waiting for supervisor to respawn it"
  else
    echo "    no running gateway matched dist/index.js gateway"
  fi
  sleep 2

  local gateway_line pid
  for _ in {1..10}; do
    gateway_line="$(pgrep -af "dist/index.js gateway" | head -n 1 || true)"
    if [[ -n "$gateway_line" ]]; then
      pid="${gateway_line%% *}"
      echo "    gateway is running (pid $pid)"
      return 0
    fi
    sleep 1
  done

  echo "    warning: gateway did not respawn; check that the OpenClaw TUI/supervisor is running" >&2
  echo "    manual fallback: openclaw gateway run" >&2
  return 1
}

read_plugin_id() {
  local manifest="$1/openclaw.plugin.json"
  if [[ ! -f "$manifest" ]]; then
    echo ""
    return 0
  fi
  node -e '
    const fs = require("fs");
    const manifest = process.argv[1];
    const id = JSON.parse(fs.readFileSync(manifest, "utf8")).id;
    if (typeof id === "string" && id.length) process.stdout.write(id);
  ' "$manifest"
}

allow_plugin() {
  local dir="$1"
  local id current merged

  if ! command -v node >/dev/null 2>&1; then
    echo "==> node not found on PATH; cannot update plugins.allow safely" >&2
    return 1
  fi

  id="$(read_plugin_id "$dir")"
  if [[ -z "$id" ]]; then
    echo "==> no openclaw.plugin.json id found; skipping plugins.allow update"
    return 0
  fi

  echo "==> trusting plugin id in OpenClaw: $id"
  current="$(openclaw config get plugins.allow 2>/dev/null || true)"
  if ! merged="$(
    PLUGINS_ALLOW="$current" PLUGIN_ID="$id" node -e '
      const current = (process.env.PLUGINS_ALLOW || "").trim();
      const id = process.env.PLUGIN_ID;
      let allow = [];
      if (current && current !== "null") {
        allow = JSON.parse(current);
        if (!Array.isArray(allow)) {
          throw new Error("plugins.allow is not a JSON array");
        }
      }
      if (!allow.includes(id)) allow.push(id);
      process.stdout.write(JSON.stringify(allow));
    '
  )"; then
    echo "    could not parse existing plugins.allow; leaving it unchanged" >&2
    return 1
  fi

  openclaw config set plugins.allow "$merged"
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
  allow_plugin "$DEST"
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
