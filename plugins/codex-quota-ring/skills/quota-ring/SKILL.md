---
name: quota-ring
description: Install, launch, troubleshoot, or report the status of the Codex Quota Ring macOS menu-bar quota monitor in this repository.
---

# Codex Quota Ring

Use this skill when the user asks to install, start, stop, inspect, or troubleshoot the quota ring.

## Install

From the repository root, run:

```bash
chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

The installer builds the native Swift executable, creates `~/Applications/Codex Quota Ring.app`, and registers a per-user LaunchAgent. Because it writes outside the repository and launches a GUI app, request approval before running it.

## Verify

Check the LaunchAgent with:

```bash
launchctl print "gui/$UID/dev.quota-ring.codex"
```

The menu-bar circle shows the lowest remaining percentage among the Codex rate-limit windows. Click it to see each window and its reset time. Data comes from the local Codex app-server method `account/rateLimits/read` and refreshes every 60 seconds.

## Troubleshooting

- If the ring shows `!`, confirm `codex --version` works in a login shell and the user is signed in.
- Run `codex login status` to inspect authentication.
- Run the built executable from Terminal to inspect startup failures: `.build/release/CodexQuotaRing`.
- Do not request, print, or store the user's Codex authentication token.

## Uninstall

Run `./scripts/uninstall.sh` with approval. It removes the LaunchAgent and app bundle, but keeps this source repository and plugin.
