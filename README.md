# Teams Meeting Status for Home Assistant

A native macOS 13+ menu-bar app that detects Microsoft Teams meeting activity and publishes the derived state to Home Assistant.

This is an unofficial project. It is not affiliated with or endorsed by Microsoft or the Home Assistant project.

## How it works

The app runs `/usr/bin/log show` locally and inspects recent `powerd` events for Microsoft Teams call assertions. It derives one of three states:

- `In meeting`
- `Not in meeting`
- `Unknown`

Only the derived state is sent to Home Assistant. Raw macOS unified-log output is not uploaded or retained by the app.

When no recent event exists, the last known state is preserved. This prevents meetings longer than the 30-minute log window from incorrectly changing to `Unknown`.

## Configuration

Open **Settings…** from the menu-bar app, or create the compatibility configuration file manually at:

`~/Library/Application Support/MSTeamsStatusSender/.env`

```text
token="HOME_ASSISTANT_LONG_LIVED_TOKEN"
local_url="http://homeassistant.local/"
webhook_url="https://example.invalid/api/webhook/example"
```

The `webhook_url` setting is optional unless external delivery is enabled. Existing runtime locations retain the `MSTeamsStatusSender` name for compatibility.

## Home Assistant

Local delivery updates:

`input_text.microsoft_teams_status`

The Home Assistant base URL must be reachable from the Mac. New Home Assistant OS installations created with Home Assistant 2026.8 or later use port 80 by default and normally do not need an explicit port. Existing installations and Home Assistant Container commonly continue using port 8123. Use the server port shown under **Settings → System → Network**. A local URL might not be reachable while a restrictive corporate VPN is active. External webhook delivery can be used when an externally accessible Home Assistant webhook is available.

## Menu

The menu shows:

- Current meeting status
- Home Assistant delivery health
- External webhook health when enabled
- Relative time of the last successful detection check
- Configuration or detection warnings only when actionable
- **Check Now**
- **Settings…**
- **Open Logs**
- **Quit**

## Permissions and managed Macs

Some macOS configurations restrict access to the unified log. If access fails, the app:

- Preserves the last known meeting state
- Does not send an incorrect `Unknown` state
- Shows **Status unavailable: Log access denied**
- Offers **Open Privacy Settings…**

Managed Macs may prevent users from granting the required access. Do not disable System Integrity Protection, change permissions on system log directories, or add an account to the local administrator group solely for this app.

## Data and privacy

- Configuration is stored locally.
- The Home Assistant token is not written to `state.json`.
- Non-secret runtime state is stored in `~/Library/Application Support/MSTeamsStatusSender/state.json`.
- App logs are stored in `~/Library/Logs/MSTeamsStatusSender/app.log` and rotate near 1 MB.
- Complete HTTP and HTTPS URLs are redacted from app log messages.
- Raw unified-log output is processed in memory and is not transmitted or copied into the app log.

## Development

```bash
scripts/run-development.sh
swift test
```

## Build

```bash
scripts/build-app.sh
```

The build script creates and ad-hoc signs:

`dist/Teams Meeting Status for Home Assistant.app`

It validates the generated `Info.plist`. It does not install or launch the app.

## Attribution

This project is a Swift reimplementation and macOS packaging based on Robert Drinovac's MIT-licensed [TeamsStatusMacOS](https://github.com/RobertD502/TeamsStatusMacOS) project.

The original shell scripts and meeting-detection approach are attributed to Robert Drinovac. The native Swift application, reliability improvements, interface, tests, packaging, and subsequent maintenance are by Simon Bach Jessen.

See [NOTICE.md](NOTICE.md) for details.

## Licence

Licensed under the MIT License. See [LICENSE](LICENSE).
