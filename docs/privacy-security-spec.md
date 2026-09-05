# Privacy and Security Spec

## Privacy Position

Nudge processes highly sensitive personal conversations. The default position is local-first processing, explicit consent, data minimization, and visible control.

The app should never imply that privacy is solved merely because data is local. Local data must still be protected against accidental exposure, overbroad logging, insecure backups, and unclear deletion.

## Data Categories

Raw sensitive data:

- Message text.
- Participant names.
- Contact identifiers.
- Conversation timestamps.
- Attachment metadata if ever collected.

Derived sensitive data:

- Summaries.
- Suggestions.
- Embeddings.
- Confidence scores.
- User decisions.
- Action history.

Operational data:

- Connector health.
- Permission state.
- Last sync times.
- Error categories.
- Version/update state.

Diagnostics:

- Crash reports.
- Non-sensitive logs.
- Optional user-submitted support bundles.

## Permission Rationale

Full Disk Access:

- Used to read local Apple Messages data where available.
- Must be explained as powerful and sensitive.
- The app must continue in degraded mode if not granted.

Login Item or LaunchAgent:

- Used for background monitoring.
- Must be user-approved.
- Must be removable from settings.

Notifications:

- Used for important suggestions and permission failures.
- Must be configurable.

Calendar and Reminders:

- Used only after user confirmation to create events or reminders.
- Must not be required for viewing suggestions.

Contacts:

- Optional; improves display names and identity matching.

Automation and Accessibility:

- Optional or future-facing.
- Must not be requested until a feature needs them.

## Storage Policy

Raw messages:

- Stored locally by default only when needed for evidence, dedupe, and local search.
- Never sent to cloud AI without explicit user consent.
- Deleted when the user deletes a source, thread, or all local data.

OAuth tokens:

- Stored in Keychain.
- Never stored in SQLite.
- Removed when the user disconnects the account or deletes connector configuration.

Summaries and embeddings:

- Treated as sensitive derived data.
- Deleted alongside their source messages unless the user explicitly chooses to retain derived-only history.

Suggestions:

- Stored locally with evidence references.
- May retain minimal action history after raw data deletion only if the user chooses an audit-preserving mode.

Logs:

- Must not contain raw message text by default.
- Must use structured error categories rather than message bodies.

## Encryption and Key Handling

Recommended baseline:

- Store local data in an app-owned database.
- Encrypt sensitive fields or the database using a key protected by the macOS Keychain.
- Use Keychain for cloud provider API keys, OAuth tokens, and encryption material.
- Avoid storing secrets in preferences, logs, or crash reports.

Backups:

- Document whether local data participates in Time Machine or other Mac backups.
- Provide a setting to exclude local sensitive stores from backups if technically feasible.

## Cloud AI Consent

Cloud AI is optional.

Before enabling it, the app must explain:

- What data may be sent.
- Which provider receives it.
- Whether snippets, summaries, or raw text are sent.
- Whether data is retained by the provider.
- How to disable cloud AI.
- How existing cloud-derived artifacts are deleted locally.

Cloud AI requests should use the smallest sufficient context. Responses must be validated before creating suggestions.

## Deletion and Export

Deletion controls:

- Delete all local data.
- Delete one source.
- Delete one thread.
- Delete suggestions and action history.
- Delete derived data while keeping connector configuration.

Deletion must cover:

- Raw messages.
- Summaries.
- Embeddings.
- Suggestions.
- Action records where possible.
- Audit events unless retained by explicit user choice.

Export controls:

- Export user-visible local data in a readable format.
- Export should not include secrets.
- Export should clearly distinguish raw data from derived data.

## Auditability

Nudge should keep a privacy-preserving audit log for:

- Permission state changes.
- Connector sync runs.
- Suggestion creation.
- User confirmation, dismissal, snooze, and completion.
- Calendar/reminder write attempts and outcomes.
- Cloud AI requests without raw prompt bodies by default.
- Data deletion events.

Audit events should help debug trust and product quality without exposing message content.

## Threat Model

Primary risks:

- Overcollection of personal conversations.
- Accidental cloud transmission of raw text.
- Sensitive data appearing in logs or crash reports.
- Local database theft from the user's Mac.
- Misleading UI around active monitoring.
- Broken connector reading incorrect data after macOS changes.
- OAuth token mishandling.

Controls:

- Local-first defaults.
- Consent-gated cloud AI.
- Permission health transparency.
- Encrypted sensitive storage.
- Keychain token storage.
- Minimal logs.
- Deletion/export controls.
- Read-only source connectors.

## Trust Requirements

- The app must explain why each permission is requested.
- The app must identify when a feature is degraded.
- The app must avoid dark patterns in permission onboarding.
- The app must not block basic app use because optional permissions are denied.
- The app must provide a direct path to disable monitoring.
- The app must provide a direct path to delete data.

## Legal and Policy Notes

This document is not legal advice. Before launch, Nudge needs review of:

- Privacy policy.
- Terms of service.
- macOS permission copy.
- Direct distribution update mechanism.
- Any cloud AI subprocessors.
