# Codex Quota Ring

Codex Quota Ring is a Codex plugin with a native macOS menu-bar companion. It displays the remaining Codex allowance as a live circular indicator in the top system status bar.

## What it shows

- The circle contains the lowest remaining percentage across the active Codex rate-limit windows.
- Green means above 50%, orange means 21–50%, and red means 20% or less.
- Click the circle for every available window, its remaining percentage, reset time, and last refresh time.
- Data refreshes every 10 seconds and also reacts to Codex rate-limit updates.

The data is read locally from Codex's app-server protocol (`account/rateLimits/read`). No authentication token is copied, logged, or sent to another service.

## Build and run

Requirements: macOS 13+, Swift 5.9+, Codex CLI installed and signed in.

```bash
swift build
swift run CodexQuotaRing
```

The installer automatically selects the compatible macOS 15.4 SDK when the current Command Line Tools installation exposes a newer SDK that does not match its Swift compiler.

## Install at login

```bash
chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

This installs `~/Applications/Codex Quota Ring.app` and a user LaunchAgent. To remove it, run `./scripts/uninstall.sh`.

## Build a clickable installer

```bash
chmod +x scripts/build-pkg.sh scripts/package-postinstall
./scripts/build-pkg.sh
```

The resulting `dist/Codex-Quota-Ring-0.1.0.pkg` installs the app in `/Applications`, configures a system LaunchAgent for login startup, and starts it for the current desktop user. The package is locally ad-hoc signed, not Developer ID signed or notarized.

## Plugin layout

The Codex plugin lives in `plugins/codex-quota-ring`. The repo-local marketplace manifest is in `.agents/plugins/marketplace.json`.

Codex plugins currently do not expose a native extension point for injecting a widget into the Codex desktop window's own title bar. The menu-bar companion is therefore the reliable native implementation of the requested always-visible top status indicator.
