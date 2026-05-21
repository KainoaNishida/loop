# AI Behavior Spec

## Purpose

The AI system turns conversations into evidence-backed suggestions. It should help users notice likely obligations while avoiding overconfident or unsupported claims.

Loop's AI behavior should be useful, conservative, inspectable, and easy to correct.

## Processing Modes

### Local Mode

Default mode. Uses local parsing, classification, heuristics, and locally available models where implemented.

Local mode supports:

- Deadline and date extraction.
- Question detection.
- Reply gap detection.
- Commitment phrase detection.
- Suggestion ranking.
- Duplicate suppression.

### Hybrid Mode

Optional mode. Local processing still runs first, then selected snippets or summaries may be sent to a cloud LLM after user consent.

Hybrid mode supports:

- Better ambiguity resolution.
- Better action wording.
- Better multi-message reasoning.
- More nuanced task extraction.

Cloud results must be validated against local evidence before becoming suggestions.

## Suggestion Taxonomy

| Type | Description | Example Action |
| --- | --- | --- |
| Stale reply | User likely owes a response after an unresolved inbound message. | Remind me to reply today. |
| Unanswered question | Someone asked a direct or implied question. | Open thread and draft reply. |
| Deadline | A due date or deadline appears in conversation. | Create reminder for Friday. |
| Calendar event | A meeting, appointment, plan, or scheduled event appears. | Add event to Calendar. |
| Reminder | A task should be remembered but may not be calendar-specific. | Add reminder. |
| Promised task | User appears to commit to doing something. | Track as task. |
| Important context | A detail may be useful later but is not an action. | Save context. |
| Follow-up nudge | A future check-in or conversation follow-up seems useful. | Snooze until next week. |

## Evidence Requirements

Every suggestion must include evidence:

- Source app.
- Thread or participant label.
- Source timestamp.
- Message snippet or local summary.
- Message range or source reference.

The AI must not create a suggestion if it cannot point to evidence. If evidence is weak, the suggestion should be low confidence or suppressed.

## Confidence Levels

Confidence should be represented as both a numeric score and a user-facing label.

- High: 0.85 and above. Clear evidence and low ambiguity.
- Medium: 0.60 to 0.84. Plausible but may need user review.
- Low: 0.40 to 0.59. Useful only as a quiet suggestion, not a notification.
- Suppressed: below 0.40. Do not show unless debugging.

Notification eligibility:

- High-confidence deadline, event, and reminder suggestions may notify.
- Medium-confidence suggestions may appear in the inbox.
- Low-confidence suggestions should be batched or hidden behind a review filter.

## Suggestion State Model

States:

- New: generated and unseen.
- Viewed: opened by user.
- Confirmed: user approved the suggested action.
- Dismissed: user rejected it.
- Snoozed: hidden until a future time.
- Completed: user marked it done or the linked action completed.
- Failed: action could not be completed.
- Needs permission: action is blocked by missing permission.

State transitions must be logged as audit events.

## Deadline Extraction

Deadline extraction should consider:

- Explicit dates.
- Relative dates.
- Times.
- Time zones where inferable.
- Sender intent.
- Whether the message is asking, proposing, or committing.

When a date is ambiguous, Loop should:

- Prefer asking for confirmation in the action sheet.
- Avoid creating an exact calendar event without user review.
- Preserve the original text in notes.

## Stale Reply Detection

Stale reply detection should consider:

- Direction of last meaningful message.
- Whether the last message asks a question.
- User-configured response windows.
- Thread importance.
- Recent user activity in the same thread.
- Dismissal history.

The system should avoid nudging for:

- Obvious conversation closers.
- Reactions only.
- Spam or unknown senders if configured.
- Threads the user recently dismissed.

## Duplicate Suppression

Loop must avoid repeated suggestions for the same underlying obligation.

Deduplication inputs:

- Source app.
- Thread identifier.
- Message identifiers or message range.
- Normalized action title.
- Date/time.
- Action target.
- User decision history.

Confirmed calendar/reminder actions must store an idempotency fingerprint.

## Dismissal Learning

Dismissals are product feedback.

The system should use dismissals to:

- Reduce priority for similar suggestions.
- Suppress repeated suggestions from the same message range.
- Learn user preferences by suggestion type and thread.
- Avoid immediately regenerating a dismissed suggestion unchanged.

Dismissal learning must remain local unless the user opts into sharing diagnostics or model-improvement data.

## Hallucination Safeguards

The AI must not:

- Invent participants.
- Invent dates or times.
- Invent commitments without evidence.
- Claim a message was sent or received if the connector cannot verify it.
- Send messages automatically.
- Create calendar/reminder items without confirmation.

Cloud AI outputs must be checked against local source evidence. Suggestions with unsupported fields should be downgraded, corrected, or rejected.

## Ranking

Ranking inputs:

- Urgency.
- Confidence.
- Source recency.
- User-configured source priority.
- Thread importance.
- Action type.
- Dismissal history.
- Permission availability.

High-priority suggestions should be rare enough that the menu bar count remains meaningful.

## Evaluation

Quality review should measure:

- Precision by suggestion type.
- Dismissal rate.
- Confirmation rate.
- Duplicate rate.
- Missed deadline reports.
- User-perceived helpfulness.
- Cloud AI lift over local mode.

Test sets should include messy conversation snippets, ambiguous dates, casual language, jokes, completed tasks, and multi-message context.
