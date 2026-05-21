# Loop macOS Documentation

## Purpose

This directory contains the product and technical documentation package for Loop, a macOS-first assistant that monitors user-authorized Apple Messages locally, then turns conversational commitments into actionable suggestions.

The v1 product is designed as a direct-distribution Mac app, not a Mac App Store-first app. This lets Loop prioritize explicit setup, local permissions, and a background helper while keeping raw conversation data local by default.

## Canonical Product Decisions

- Platform: macOS first.
- Distribution: Developer ID signed, notarized, direct distribution.
- Primary surface: menu bar suggestion inbox with lightweight supporting windows.
- Background behavior: user-approved Login Item or LaunchAgent.
- Apple Messages: read-only local ingestion where available, gated by Full Disk Access and treated as schema-sensitive.
- AI processing: hybrid local-first. Raw message text stays on-device by default; cloud AI is optional and consent-gated.
- Action model: Loop may draft suggestions automatically, but user confirmation is required before creating calendar/reminder items or opening/sending replies.

## Document Map

- [Product Brief](./product-brief.md): product vision, audience, positioning, success metrics, and non-goals.
- [PRD](./prd.md): product requirements, user flows, functional requirements, and acceptance scenarios.
- [UX Spec](./ux-spec.md): menu bar UI, onboarding, suggestion review, confirmation, settings, and notification behavior.
- [Technical Architecture](./technical-architecture.md): app architecture, background agent, connectors, database, AI pipeline, permissions, and distribution.
- [Privacy and Security Spec](./privacy-security-spec.md): data handling, permissions, local storage, encryption, deletion, cloud consent, and auditability.
- [AI Behavior Spec](./ai-behavior-spec.md): suggestion taxonomy, confidence rules, state model, evidence requirements, and quality safeguards.
- [Platform Feasibility Appendix](./platform-feasibility-appendix.md): macOS, Apple Messages, distribution, and permission constraints.

## V1 Product Boundary

Loop v1 is a personal Mac utility for power users who are willing to complete a deliberate setup in exchange for less manual conversation tracking afterward. It is not a messaging client, and it is not an autonomous agent that sends messages without confirmation.

The product should feel useful even when some permissions are missing. Every permission-gated feature must have a visible health state and a graceful fallback.

## Reference Links

- Apple App Sandbox: https://developer.apple.com/documentation/security/app_sandbox
- Apple Events entitlement: https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.automation.apple-events
- SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Accessibility trust check: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
