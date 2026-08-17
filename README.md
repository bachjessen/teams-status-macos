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

## Install

Download the DMG from the latest GitHub Release, open it, and drag **Teams Meeting Status for Home Assistant** to **Applications**.

Current GitHub builds are ad-hoc signed and are intended for testing. A future production release should use Developer ID signing and Apple notarization to provide the standard Gatekeeper experience.

## Configuration

Open **Settings…** from the menu-bar app. Configuration is stored locally at:

`~/Library/Application Support/TeamsMeetingStatus/.env`

The settings window provides:

- Local Home Assistant URL
- Long-lived access token
- Optional external webhook delivery
- Delivery failure and recovery notifications
- Launch at login through macOS Login Items

Earlier development builds used different runtime paths. There is no automatic migration because no public release has used those paths. Testers upgrading from an earlier development build should re-enter settings.

## Home Assistant

### Direct local delivery

Direct delivery updates:

`input_text.teams_meeting_status`

The Home Assistant base URL must be reachable from the Mac. New Home Assistant OS installations created with Home Assistant 2026.8 or later use port 80 by default and normally do not need an explicit port. Existing installations and Home Assistant Container commonly continue using port 8123. Use the server port shown under **Settings → System → Network**.

### Home Assistant Cloud webhook

External delivery is useful when a corporate VPN prevents access to the local Home Assistant URL. A Home Assistant Cloud subscription is required for a Nabu Casa cloud webhook.

1. In Home Assistant, go to **Settings → Automations & scenes**.
2. Create an automation with a **Webhook** trigger.
3. Open the webhook trigger settings and clear **Only accessible from the local network**.
4. Add an action that writes `trigger.json.state` to `input_text.teams_meeting_status`.
5. Save the automation.
6. Go to **Settings → Cloud → Webhooks**, manage the new webhook, and copy its unique URL.
7. In the macOS app, enable **Send through external webhook**, paste the URL, and save.

Treat the webhook URL as a secret. Anyone with the URL can trigger the automation.

## Notifications

When **Show delivery notifications** is enabled, the app requests macOS notification permission and displays a notification only when Home Assistant delivery begins failing or recovers. Meeting start and end events do not create notifications.

## Launch at login

Enable **Launch at login** in Settings to register the installed app through the native macOS Login Items service. The setting is also visible under **System Settings → General → Login Items**. No scripts or manually installed LaunchAgent files are required.

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
- Non-secret runtime state is stored in `~/Library/Application Support/TeamsMeetingStatus/state.json`.
- App logs are stored in `~/Library/Logs/TeamsMeetingStatus/app.log` and rotate near 1 MB.
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

## Releases

Push a semantic version tag such as `v1.0.0` to run the release workflow. The workflow runs tests, builds the app, creates a DMG with an Applications shortcut, verifies the app signature and DMG, and publishes the DMG in a GitHub Release with generated release notes.

The release workflow does not yet perform Developer ID signing or Apple notarization.

## Attribution

This project is a Swift reimplementation and macOS packaging based on Robert Drinovac's MIT-licensed [TeamsStatusMacOS](https://github.com/RobertD502/TeamsStatusMacOS) project.

The original shell scripts and meeting-detection approach are attributed to Robert Drinovac. The native Swift application, reliability improvements, interface, tests, packaging, and subsequent maintenance are by Simon Bach Jessen.

See [NOTICE.md](NOTICE.md) for details.

## Licence

Licensed under the MIT License. See [LICENSE](LICENSE).
