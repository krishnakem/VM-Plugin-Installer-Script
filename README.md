# VM Plugin Installer Scripts

**The "git push → live on the VM in one command" loop for OpenClaw plugins.** Two small shell scripts that keep GitHub-hosted plugins installed and up to date on a remote agent box, so iterating on a plugin doesn't mean re-doing install plumbing every time.

```bash
./getplugin.sh owner/repo      # first install, or update + reinstall
./reinstall.sh repo-name       # fast: pull latest + npm install while iterating
```

---

## Why this exists

I develop OpenClaw plugins locally and run them on a GCP VM (provisioned by [OpenClaw-VM-Script](https://github.com/krishnakem/OpenClaw-VM-Script)). The inner loop — push a change, get it onto the box, reinstall into OpenClaw, restart the gateway — is exactly the kind of friction that quietly kills iteration speed. These two scripts collapse it to one command each.

## `getplugin.sh` — install or update a plugin from GitHub

```bash
./getplugin.sh owner/repo
```

- Clones `https://github.com/owner/repo.git` if it isn't on the VM yet; otherwise `git pull --ff-only`
- Uses the **repo name as the local directory name** (custom targets are rejected on purpose, so the plugin dir always matches the repo)
- Runs `npm install` when `package.json` exists
- Installs Playwright Chromium automatically when Playwright is detected
- Installs the plugin into OpenClaw with a live link
- Adds the plugin id from `openclaw.plugin.json` to `plugins.allow` **without** clobbering existing trusted ids

Flags:

| Flag | Effect |
| --- | --- |
| `-r` | Restart the OpenClaw gateway after installing |
| `-n` | Clone/update + dependency setup only; skip the OpenClaw install step |
| `-nr` | Combine the above |

## `reinstall.sh` — the fast iteration path

```bash
./reinstall.sh repo-name
```

For when you're rapidly iterating and just need the box to catch up to GitHub: enters the local plugin dir, `git pull --ff-only`, and `npm install` if there's a `package.json`. No re-clone, no OpenClaw round-trip.

## Where these live

These scripts are staged onto the VM automatically by the [OpenClaw VM provisioner](https://github.com/krishnakem/OpenClaw-VM-Script), so a freshly provisioned box already has them in the home folder — ready to pull in whichever agent you want to test.

## License

See repository.
