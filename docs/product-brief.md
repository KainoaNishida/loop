# Product Brief

## Overview

Loop is a macOS-first personal conversation assistant. It watches user-authorized Apple Messages locally, detects commitments and follow-up opportunities, and presents simple suggestions in a menu bar inbox.

The product exists for people who receive important requests in Messages and do not want those requests to disappear into history. Loop turns conversations into reminders, calendar drafts, reply nudges, and lightweight follow-up actions without becoming another heavyweight inbox.

## Problem

Important obligations often arrive through informal conversations:

- A friend mentions a dinner date.
- A teammate asks for something "by Friday."
- A family member sends an address or appointment detail.
- A conversation goes stale because the user forgot to reply.
- A user promises to do something but never turns it into a task.

Messaging and email apps are good at communication, but weak at cross-thread memory. Calendar and reminder apps are good at commitments, but require manual translation. Loop fills that gap by watching approved sources locally and surfacing action candidates.

## Target User

The initial target user is a Mac-heavy individual who:

- Uses Apple Messages heavily.
- Has enough inbound conversation volume to miss things.
- Is comfortable granting advanced macOS permissions after a clear explanation.
- Prefers automation and local privacy over a polished App Store-style setup.
- Wants useful nudges, not a full CRM or shared team inbox.

Secondary users include freelancers, founders, operators, students, and anyone whose personal and work obligations arrive through mixed informal channels.

## Product Promise

"Loop quietly watches the conversations you approve and turns important follow-ups into a small list of things worth doing next."

The promise has three parts:

- Capture: import permitted conversation sources with minimal ongoing user input.
- Understand: detect deadlines, unanswered questions, promised tasks, and stale replies.
- Assist: show evidence-backed suggestions that the user can confirm, snooze, dismiss, or complete.

## Why macOS First

macOS offers a larger automation surface than iOS. A direct Mac app can guide users through Full Disk Access, Login Items, Apple Events, notifications, Calendar/Reminders, and optional supporting permissions. This makes the product more technically ambitious but better aligned with the user's goal: maximize automation and minimize ongoing manual input.

The tradeoff is setup friction. Loop should treat onboarding as a serious product surface, not a small permissions dialog. The user should always know which automations are active, missing, degraded, or revoked.

## Core Experience

1. The user installs a notarized Mac app.
2. Loop walks the user through an onboarding checklist.
3. The user grants selected permissions, especially Full Disk Access for local Apple Messages ingestion.
4. Loop runs from the menu bar and imports recent Messages data read-only.
5. When Loop detects something useful, it creates a suggestion.
6. The user opens the menu bar inbox, reviews the evidence, and confirms, snoozes, dismisses, or completes the suggestion.
7. For calendar/reminder actions, Loop creates the item only after confirmation.

## V1 Scope

V1 includes:

- Menu bar app.
- Guided onboarding checklist.
- Messages health dashboard.
- Background monitoring through a user-approved Login Item or LaunchAgent.
- Read-only Apple Messages local ingestion where available.
- Local-first AI extraction and suggestion generation.
- Optional cloud AI path for consented snippets.
- Suggestion inbox.
- Evidence-backed suggestion detail view.
- Calendar and reminder draft confirmation.
- Snooze, dismiss, complete, and deletion workflows.

## Non-Goals

V1 does not include:

- Sending messages automatically.
- Sending email automatically.
- A mobile companion app.
- Team collaboration.
- Shared inbox workflows.
- CRM-style pipeline management.
- Full historical analytics.
- Guaranteed support for every macOS Messages database schema.
- Mac App Store distribution.

## Success Metrics

Activation:

- Percentage of installed users who complete the core onboarding checklist.
- Percentage of users with Apple Messages ingestion active.
- Time from first launch to first useful suggestion.

Engagement:

- Weekly active menu bar users.
- Suggestions reviewed per week.
- Confirmed suggestions per week.
- Snooze and dismissal rates by suggestion type.

Quality:

- User-reported helpfulness per suggestion type.
- False-positive dismissal rate.
- Duplicate suggestion rate.
- Percentage of suggestions with clear evidence.

Trust:

- Permission revocation rate.
- Cloud AI opt-in rate.
- Data deletion completion rate.
- Support issues related to privacy confusion.

## Product Principles

- Evidence first: every suggestion must explain why it exists.
- Local by default: raw conversation text stays on the Mac unless the user opts into cloud AI for a specific scope.
- User remains in control: Loop drafts actions, but the user confirms external writes.
- Degrade honestly: missing permissions should be visible and understandable.
- Be honest about source access: Apple Messages is read locally without modifying the source database, and Loop should not imply an official Messages integration.
- Keep the UI small: the product should feel like a reliable assistant, not another inbox to maintain.

## Strategic Risks

- Apple Messages local access is unsupported and may break across macOS versions.
- Users may hesitate to grant Full Disk Access unless onboarding is exceptionally clear.
- Local AI may underperform cloud AI on nuanced conversation understanding.
- Direct distribution adds trust, update, and support burdens.

The product should embrace these risks explicitly in documentation, onboarding, and marketing language.
