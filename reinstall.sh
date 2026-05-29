#!/usr/bin/env bash
#
# reinstall — update and reload an OpenClaw plugin during rapid iteration.
#
# Plugins installed with `--link` (see getplugin.sh) are symlinked to their
# working tree. On the VM, this script pulls the latest repo changes, refreshes
# dependencies, and restarts the gateway so OpenClaw loads the new code.
#
#   ./reinstall.sh                 # source-only edit: just restart the gateway
#   ./reinstall.sh <dir>           # git pull + npm install in <dir>, then restart
#   ./reinstall.sh -d <dir>        # also re-run `openclaw plugins install --link`
#                                  #   (use if the plugin id / manifest changed)
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
REINSTALL=0
if [[ "${1:-}" == "-d" ]]; then REINSTALL=1; shift; fi
DIR="${1:-}"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "error: openclaw CLI not found on PATH" >&2
  exit 1
fi

# ---- dir given: pull latest / refresh deps / re-link -----------------------
if [[ -n "$DIR" ]]; then
  if [[ ! -d "$DIR" ]]; then
    echo "error: '$DIR' is not a directory" >&2
    exit 1
  fi
  cd "$DIR"
  if [[ -d .git ]]; then
    echo "==> pulling latest changes in $DIR"
    git pull --ff-only
  else
    echo "==> $DIR is not a git repo, skipping git pull"
  fi
  if [[ -f package.json ]]; then
    echo "==> npm install in $DIR"
    npm install
  fi
  if [[ "$REINSTALL" == "1" ]]; then
    echo "==> re-linking into OpenClaw"
    openclaw plugins install "$(pwd)" --link --dangerously-force-unsafe-install
  fi
  allow_plugin "$(pwd)"
fi

# ---- always: restart so edits load ----------------------------------------
restart_gateway
