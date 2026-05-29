# VM Plugin Installer Scripts

Small helper scripts for managing OpenClaw plugins on a GCP VM.

These scripts are meant for plugins that live in GitHub repos and are loaded
into OpenClaw through the `openclaw` CLI.

## Scripts

### `getplugin.sh`

Use this for the first install of a plugin repo, or to update and reinstall a
plugin that already exists locally.

```bash
./getplugin.sh owner/repo
```

What it does:

- Clones `https://github.com/owner/repo.git` if the plugin is not already on the VM.
- If the plugin already exists, runs `git pull --ff-only`.
- Uses the repo name as the local plugin directory name.
- Runs `npm install` when `package.json` exists.
- Installs Playwright Chromium when Playwright is detected in `package.json`.
- Installs the plugin into OpenClaw using a live link.

The local directory always matches the repo name. For example:

```bash
./getplugin.sh my-org/calendar-agent
```

creates or updates:

```bash
./calendar-agent
```

Custom target directories are intentionally rejected so the plugin name stays
aligned with the repo name.

Useful flags:

```bash
./getplugin.sh -r owner/repo
```

Install the plugin and restart the OpenClaw gateway afterward.

```bash
./getplugin.sh -n owner/repo
```

Clone/update the repo and run dependency setup, but skip the OpenClaw install
step.

Flags can be combined:

```bash
./getplugin.sh -nr owner/repo
```

### `reinstall.sh`

Use this while rapidly iterating on a plugin.

After pushing changes to GitHub, run this on the VM:

```bash
./reinstall.sh repo-name
```

What it does:

- Enters the local plugin directory.
- Runs `git pull --ff-only` if the directory is a git repo.
- Runs `npm install` when `package.json` exists.
- Restarts the OpenClaw gateway so it loads the latest code.

If the plugin id, manifest, or install metadata changed, use `-d`:

```bash
./reinstall.sh -d repo-name
```

That also re-runs:

```bash
openclaw plugins install "$(pwd)" --link --dangerously-force-unsafe-install
```

before restarting the gateway.

With no directory, `reinstall.sh` only restarts the gateway:

```bash
./reinstall.sh
```

## Typical VM Workflow

First install:

```bash
./getplugin.sh -r owner/my-plugin
```

Later, after pushing new plugin changes to GitHub:

```bash
./reinstall.sh my-plugin
```

If the plugin manifest or id changed:

```bash
./reinstall.sh -d my-plugin
```

## Configuration

Environment variables:

| Variable | Used by | Default | Purpose |
| --- | --- | --- | --- |
| `PLUGIN_DIR` | `getplugin.sh` | current directory | Base directory where plugin repos are cloned |
| `GIT_HOST` | `getplugin.sh` | `github.com` | Git host used to build clone URLs |
| `NO_OPENCLAW` | `getplugin.sh` | unset | Set to `1` to skip OpenClaw install, same as `-n` |
| `GATEWAY_LOG` | both | `~/.openclaw/gateway.log` | Log file for restarted gateway process |

Example:

```bash
PLUGIN_DIR=~/plugins ./getplugin.sh -r owner/my-plugin
```

This clones or updates the plugin at:

```bash
~/plugins/my-plugin
```

## Requirements

The VM should have:

- `bash`
- `git`
- `npm`
- `openclaw`
- `npx`, if using Playwright-based plugins
- `sudo`, optional, for Playwright system dependency installation

## Notes

Both scripts use `git pull --ff-only`. If the VM has local commits or divergent
changes, the pull will fail instead of overwriting work.

The gateway restart logic stops any process matching:

```bash
openclaw gateway run
```

and relaunches it in the background with logs written to `GATEWAY_LOG`.

Follow gateway logs with:

```bash
tail -f ~/.openclaw/gateway.log
```
