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
# Config (env vars):
#   GATEWAY_LOG  where the relaunched gateway logs  (default: ~/.openclaw/gateway.log)
#
set -euo pipefail

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
fi

# ---- always: restart so edits load ----------------------------------------
restart_gateway
