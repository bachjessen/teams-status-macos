# MSTeamsStatusSender

Native macOS 13 menu-bar app for publishing Microsoft Teams call state to local and external Home Assistant destinations.

## Configuration

Create `~/Library/Application Support/MSTeamsStatusSender/.env`:

```text
token="HOME_ASSISTANT_LONG_LIVED_TOKEN"
local_url="http://homeassistant.local:8123/"
webhook_url="https://example.invalid/webhook"
```

Quoted and unquoted values are supported. Malformed HTTP or HTTPS URLs are reported in the menu. Secrets are not persisted to `state.json`, and logs redact complete HTTP/HTTPS URLs.

## Runtime behavior

- First automatic check sends to both configured destinations.
- Later local sends occur only on state changes.
- Later external sends occur on state changes or 300 seconds after the last external attempt.
- Failed external attempts are throttled using the attempt time, while state changes and **Check Now** remain immediate.
- Destination health is independent. Notifications are emitted only when a destination changes from working to failing or failing to working.
- HTTP requests use short timeouts and accept only 2xx responses.
- Non-secret state is saved to `~/Library/Application Support/MSTeamsStatusSender/state.json`.
- Logs are written to `~/Library/Logs/MSTeamsStatusSender/app.log` and rotate near 1 MB.

The menu shows Teams state, destination status, check and success times, missing configuration, **Check Now**, **Open Logs**, **Open Configuration Folder**, and **Quit**.

## Development and tests

```bash
scripts/run-development.sh
swift test
```

## Build

```bash
scripts/build-app.sh
```

The build script creates `dist/MSTeamsStatusSender.app`, validates its generated `Info.plist`, and ad-hoc signs it when `codesign` is available. It never writes to the preserved legacy `app/` directory and does not install or launch the app.
