# Nudge

Nudge is a macOS-first conversation assistant prototype. This repository currently contains the native SwiftPM vertical slice: a menu bar app, onboarding/settings, local SQLite persistence, Apple Messages read-only import, bundled sample conversation import, permission health, optional Gemini structured suggestion generation, and local suggestion lifecycle actions.

## Current Build Slice

- `Nudge`: macOS menu bar executable.
- `MinderCore`: models, SQLite store, Messages/sample importers, permission/profile state, Gemini client, fallback suggestion generator, and suggestion lifecycle.
- `MinderCoreTests`: import, persistence, state transition, permission/profile, source connector, and Gemini structured-output parser tests.
- `docs/`: product and technical planning documents.

## Prerequisite

Swift/Xcode commands on this machine currently require accepting the Xcode license:

```sh
sudo xcodebuild -license
```

After accepting the license, run:

```sh
swift test
swift run Nudge
```

For realistic macOS permission prompts, build and launch the development app bundle:

```sh
scripts/build-dev-app.sh
```

The script creates `.build/NudgeDev/Nudge.app`, includes the SwiftPM resources and usage-description metadata, ad-hoc signs when possible, and launches it with `open`. Use this app bundle when granting Full Disk Access or testing Notifications, Calendar, and Reminders prompts.

## Gemini Configuration

Gemini is optional for the first slice. If `GEMINI_API_KEY` is missing, Nudge uses local heuristic suggestions. If credentials are present, cloud suggestions still remain off until the user enables Cloud AI in onboarding.

```sh
export GEMINI_API_KEY="..."
export GEMINI_MODEL="gemini-2.5-flash" # optional; defaults to gemini-2.5-flash
swift run Nudge
```

For local development, the app also reads `GEMINI_API_KEY` and `GEMINI_MODEL` from a repo-local `.env` file or `~/.nudge.env`. `.env` files are ignored by git. Existing `~/.loop.env` and `~/.minder.env` files are still read as legacy fallbacks.

## Alpha Packaging

The trusted-alpha channel uses a separate bundle ID and local data path:

```sh
NUDGE_DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NUDGE_NOTARYTOOL_PROFILE="nudge-notary" \
scripts/build-alpha-dmg.sh
```

Without signing/notary environment variables, the script still builds `.build/NudgeAlpha/Nudge.app` and packages `.build/NudgeAlpha/Nudge-alpha.dmg` with ad-hoc signing for local verification. Alpha data is stored under `~/Library/Application Support/NudgeAlpha/`.

## Onboarding and Permissions

First launch opens a setup window for the user profile and core permission health. The current SwiftPM build performs best-effort checks for:

- Full Disk Access / Apple Messages: validated by attempting to read `~/Library/Messages/chat.db`; import is read-only, keeps 30 days for context, and focuses active alerts on the last 7 days.
- Contacts: optional local-only name matching so Messages can show names instead of phone numbers or email handles.
- Notifications: shown as unsupported under `swift run` because UserNotifications requires a packaged `.app` bundle.
- Calendar: status is checked through EventKit; in-app prompts are disabled under `swift run` and should be requested from a packaged app.
- Reminders: status is checked through EventKit; in-app prompts are disabled under `swift run` and should be requested from a packaged app.

`swift run Nudge` remains useful for quick development, but macOS APIs that require a real bundle either report unsupported or behave as best-effort checks. Use `scripts/build-dev-app.sh` for realistic prompts and Full Disk Access assignment to `Nudge.app`.

## Dev Data

The app stores local development data at:

```text
~/Library/Application Support/NudgeDev/nudge.sqlite
```

On first launch after the rename, Nudge copies existing development data from `~/Library/Application Support/LoopDev/loop.sqlite`, then falls back to `~/Library/Application Support/MinderDev/minder.sqlite`, if the new database does not exist yet.

The alpha app uses:

```text
~/Library/Application Support/NudgeAlpha/nudge.sqlite
```
