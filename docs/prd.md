# Product Requirements Document

## Overview

Nudge is a macOS menu bar assistant that monitors user-authorized Apple Messages locally and creates actionable suggestions from them. The first version supports Apple Messages through local, read-only ingestion.

The app should reduce the user's ongoing manual effort after a deliberate setup process.

## Goals

- Detect conversational obligations without requiring users to manually copy every message.
- Surface a compact list of actionable suggestions.
- Require confirmation before creating calendar/reminder items or initiating replies.
- Keep raw conversation data local by default.
- Make permission and connector health transparent.
- Work gracefully when permissions are missing, revoked, or unsupported.

## Personas

### Busy Personal User

Receives commitments through friends, family, email, and small work conversations. Wants help remembering replies and deadlines without changing communication behavior.

### Power User

Is comfortable granting permissions and using a direct-distribution Mac utility. Values automation and local data control more than frictionless onboarding.

### Privacy-Sensitive User

Wants assistance but needs clear data boundaries, deletion controls, and confidence that raw messages are not sent to cloud services by default.

## User Stories

- As a user, I want Nudge to notice when someone mentions a deadline so I can add it to my calendar.
- As a user, I want Nudge to remind me when I have not replied to an important message.
- As a user, I want to see the message evidence behind every suggestion.
- As a user, I want to approve actions before Nudge writes to Calendar or Reminders.
- As a user, I want to know exactly which permissions and sources are active.
- As a user, I want to delete all local conversation data and derived AI artifacts.
- As a user, I want Nudge to keep working locally when cloud AI is disabled.

## Onboarding Requirements

The onboarding flow must be a checklist with clear permission states. It should not hide the friction.

Required for core v1:

- Full Disk Access: enables local Apple Messages ingestion where available.
- Notifications: enables nudge delivery.
- Calendar access: enables calendar event creation after confirmation.
- Reminders access: enables reminder creation after confirmation.
- Login Item or LaunchAgent approval: enables background monitoring.

Recommended or optional:

- Contacts access: improves sender naming and identity matching.
- Automation / Apple Events: enables app-to-app actions where supported.
- Accessibility: enables optional deep-link or UI automation experiments.

Each permission or source must show one of these health states:

- Available: permission granted and feature working.
- Missing: permission not granted or not connected.
- Degraded: permission granted but source is unavailable or partially readable.
- Revoked: previously granted permission is no longer available.
- Unsupported: feature is not available on the current macOS version or source state.

## Source Requirements

### Apple Messages Local Connector

- Must be read-only.
- Must require explicit user setup and Full Disk Access.
- Must treat local Messages storage as schema-sensitive.
- Must never modify Messages data.
- Must import recent 30-day messages for context while active alerts focus on the last 7 days.
- Should use local Contacts permission, when granted, to show names instead of phone numbers or email handles.
- Must fail closed when access is denied or schema parsing fails.
- Must record connector health and last successful sync time.

## Suggestion Requirements

Nudge must create suggestions for:

- Stale reply.
- Unanswered question.
- Deadline.
- Calendar event.
- Reminder.
- Promised task.
- Important context.
- Follow-up nudge.

Each suggestion must include:

- Type.
- Title.
- Suggested action.
- Source app.
- Thread identifier.
- Sender or participant label where available.
- Source timestamp.
- Evidence snippet or local summary.
- Confidence level.
- Current state.
- Created time.
- Last updated time.

Suggestion states:

- New.
- Viewed.
- Confirmed.
- Dismissed.
- Snoozed.
- Completed.
- Failed.
- Needs permission.

## Action Requirements

Nudge may draft actions automatically, but must require confirmation before external writes.

Supported v1 action targets:

- Apple Calendar event.
- Apple Reminder.
- macOS notification.
- Open source app or thread where feasible.
- Copy suggested reply or task text.

Before confirmation, the user must be able to review:

- Suggested title.
- Date/time or due date.
- Notes/body.
- Source evidence.
- Target app.
- Any missing permission.

Nudge must prevent duplicate calendar/reminder creation by storing an action fingerprint for confirmed suggestions.

## Menu Bar Inbox Requirements

The menu bar inbox must:

- Show count of new/high-priority suggestions.
- Group suggestions by urgency and source.
- Support confirm, snooze, dismiss, and open detail.
- Make permission problems visible without overwhelming the main list.
- Allow quick access to settings and onboarding repair.
- Offer source import actions for Apple Messages.

## Settings Requirements

Settings must include:

- Connector health.
- Permission health.
- AI processing mode.
- Cloud AI consent controls.
- Data retention controls.
- Delete all local data.
- Export local data.
- Notification preferences.
- Login Item/background agent status.

## Privacy Requirements

- Raw conversation data must stay local by default.
- Cloud AI must be opt-in and explain exactly what data may be sent.
- The app must support deletion of raw messages, summaries, embeddings, suggestions, and audit events.
- The app must not use conversation data for advertising.
- The app must not sell or share conversation data.
- Logs must avoid raw message text unless explicitly enabled for diagnostics.

## Non-Functional Requirements

Reliability:

- The app must tolerate missing permissions and connector failures.
- Background monitoring must resume after restart if enabled.
- Connector failures must not corrupt local data.

Performance:

- The app should not noticeably slow down Messages, Calendar, Reminders, or the Mac.
- Initial ingestion should be resumable.
- Background scanning should be incremental after initial sync.

Security:

- The app must use Hardened Runtime.
- The app must be signed and notarized for distribution.
- Sensitive local data must be encrypted or protected using platform-appropriate controls.
- Secrets and future OAuth tokens must be stored outside SQLite.

Usability:

- Onboarding must explain why each permission is requested.
- The menu bar UI must remain compact.
- Suggestions must be dismissible and reversible when possible.

## Acceptance Scenarios

- Fresh install walks the user through setup and clearly shows which automations are active.
- Full Disk Access is missing or revoked, and the app degrades without crashing or pretending monitoring is active.
- A new Apple Messages deadline produces a calendar suggestion with source evidence.
- A stale Apple Messages thread produces a reply nudge without sending anything automatically.
- User confirms a calendar/reminder suggestion and the item is created once.
- User dismisses a poor suggestion and similar future suggestions are suppressed or lowered in priority.
- Cloud AI is disabled and the app still produces basic local suggestions.
- User deletes local data and raw messages, summaries, suggestions, and embeddings are removed.
