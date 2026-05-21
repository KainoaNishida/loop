# UX Spec

## UX Intent

Loop should feel like a quiet Mac utility: present when needed, small when not. The main surface is a menu bar inbox. Larger windows are used only for onboarding, settings, thread review, and action confirmation.

The UI should emphasize triage, evidence, and confident action.

## Information Architecture

- Menu bar inbox.
- Suggestion detail window.
- Action confirmation sheet.
- Onboarding checklist window.
- Permission repair screen.
- Settings window.
- Source import controls for Apple Messages.
- Local data management screen.

## Menu Bar Item

The menu bar item shows:

- Loop icon.
- Optional badge count for new high-priority suggestions.
- Warning indicator when a core permission is missing or revoked.

Clicking the menu bar item opens the suggestion inbox popover.

## Suggestion Inbox

The inbox is a compact popover with these sections:

- Needs attention: high-confidence deadlines, unanswered questions, stale replies, and failed actions.
- Upcoming: calendar/reminder drafts and snoozed suggestions due soon.
- Recent: lower-priority suggestions from recent conversations.
- Permission issues: collapsed by default unless a core capability is broken.

Each suggestion row includes:

- Type icon.
- Short title.
- Source app label.
- Thread or participant label.
- Relative time.
- Confidence indicator.
- Primary action button.
- More menu for snooze, dismiss, open detail, and mark complete.

Rows should be scan-friendly and avoid long message bodies. Evidence belongs in detail view.

## Suggestion Detail

The detail view opens as a lightweight window or popover expansion.

It includes:

- Suggestion title.
- Suggested action.
- Source app.
- Thread participants.
- Source timestamp.
- Evidence snippet or summary.
- Confidence explanation.
- Editable action fields where relevant.
- Confirm, snooze, dismiss, and complete controls.

The evidence area must make it obvious that Loop is interpreting a specific conversation, not inventing work.

## Action Confirmation

Calendar and reminder actions use a confirmation sheet before writing externally.

Calendar confirmation fields:

- Event title.
- Date.
- Start time.
- End time or duration.
- Calendar destination.
- Location if detected.
- Notes.
- Source evidence.

Reminder confirmation fields:

- Reminder title.
- Due date/time.
- List destination.
- Notes.
- Source evidence.

The primary button uses direct action language:

- Add Event.
- Add Reminder.
- Snooze.
- Dismiss.

If permission is missing, the primary action becomes a repair action such as Open Calendar Permission Settings.

## Onboarding

Onboarding is a full window with a checklist. It should be direct about the tradeoff: setup is tedious because the app is trying to automate sensitive personal workflows locally.

Recommended steps:

1. Welcome and privacy promise.
2. Profile defaults.
3. Validate Full Disk Access and import recent Apple Messages.
4. Optional: configure cloud AI.
5. Review privacy, diagnostics, and About.
6. Finish with permission and source health summary.

Each step includes:

- Why this permission or source is needed.
- What Loop can do with it.
- What Loop will not do with it.
- Current status.
- Open System Settings button where applicable.
- Retry/check button.

## Permission Repair

Permission repair appears when a capability changes state after onboarding.

Repair screens must:

- Name the broken capability.
- Explain the user-visible impact.
- Offer an action to open the relevant system settings page where possible.
- Offer a continue-degraded option.
- Avoid implying that data is being monitored when it is not.

Example degraded state:

"Apple Messages import is paused because Full Disk Access is not available. Loop can still show existing suggestions and manual notes."

## Settings

Settings sections:

- General: launch at login, menu bar behavior, notifications.
- Messages: Full Disk Access, Contacts, import status, and source health.
- Permissions: health table and repair actions.
- AI: local mode, cloud AI opt-in, model/provider configuration if applicable.
- Privacy: retention, delete data, export data, diagnostics.
- About: version, update channel, notarization/distribution notes, legal links.

## Notifications

Notifications are used sparingly.

Notification types:

- High-confidence deadline detected.
- Stale reply nudge.
- Permission revoked.
- Background agent stopped.
- Confirmed action succeeded or failed.

Notifications should open the relevant suggestion or repair screen.

## Empty States

No suggestions:

"Nothing needs attention right now."

Connector inactive:

"Apple Messages import is not active."

Cloud AI disabled:

"Local suggestions are active. Cloud AI is off."

## Accessibility

- All controls must be keyboard reachable.
- Suggestion rows must expose clear labels to VoiceOver.
- Confidence and health states must not rely on color alone.
- Menu bar interactions must have equivalent window-based controls.
- Onboarding instructions must be concise enough to be followed while switching into System Settings or the browser.
