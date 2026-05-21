# Platform Feasibility Appendix

## Purpose

This appendix captures platform realities that affect Loop's design. It should be updated whenever implementation research proves a source, permission, or distribution assumption wrong.

## macOS Distribution

Loop v1 is designed for direct distribution rather than the Mac App Store.

Reasoning:

- The product needs deeper automation than a conservative sandboxed App Store app is likely to support well.
- The setup flow depends on permissions and background behavior that require careful user consent.
- Direct distribution allows a Developer ID signed, hardened, notarized app with a custom update mechanism.

Implications:

- The app still needs strong security posture.
- Users need a clear trust story.
- Updates must be signed.
- The app should avoid root privileges and kernel/system extensions.
- The app should document why it requests sensitive permissions.

Reference:

- Apple App Sandbox: https://developer.apple.com/documentation/security/app_sandbox

## Full Disk Access and Local Files

Full Disk Access is the key permission for local Apple Messages ingestion. It is powerful and should be presented honestly.

Implementation assumptions:

- Apple Messages keeps local data on the Mac when Messages is configured and synced.
- Local storage shape may vary by macOS version, user settings, and iCloud Messages behavior.
- Access may fail even when the app appears correctly configured.
- The connector must validate schema and permissions at runtime.

Product implications:

- Apple Messages ingestion is a best-effort connector.
- The app must show connector health.
- The app must degrade gracefully.
- The app must not promise complete historical coverage.

Reference:

- Accessing files from the macOS App Sandbox: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox

## Apple Messages Local Ingestion

Loop's Apple Messages connector is read-only and local.

Allowed product behavior:

- Read local messages where user permission and system state allow.
- Normalize conversation data into Loop's local store.
- Generate suggestions from local data.
- Open Messages or a related target where feasible.

Disallowed v1 behavior:

- Modify Messages data.
- Delete conversations.
- Send messages automatically.
- Promise support across all macOS versions.

Risks:

- Apple does not provide a stable public API for consumer Messages history ingestion.
- Local database schema can change.
- User privacy expectations are extremely sensitive.
- Direct database access may break after OS updates.

Mitigations:

- Runtime schema checks.
- Connector health states.
- Read-only file access.
- Graceful failure.
- Explicit onboarding copy.
- No marketing claim that implies official Apple Messages integration.

## Login Items and Background Monitoring

Loop needs a user-approved background component to scan sources and generate suggestions while the main window is closed.

Recommended mechanism:

- Use SMAppService for Login Item or LaunchAgent registration on modern macOS.
- Keep helper executables inside the app bundle.
- Provide a visible toggle in settings.
- Report helper health in the menu bar and settings.

Reference:

- SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice

## Apple Events and Automation

Apple Events can support controlled app-to-app automation where target apps expose scripting support.

V1 use:

- Optional opening or navigating actions where feasible.
- Not required for core suggestion generation.

Requirements:

- Use the Apple Events entitlement where applicable.
- Explain automation permission when requested.
- Avoid using automation to bypass product or platform access limits.

Reference:

- Apple Events entitlement: https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.automation.apple-events

## Accessibility

Accessibility APIs may enable optional UI automation or deep-link repair flows, but they are sensitive and should not be core to v1.

V1 posture:

- Do not require Accessibility for baseline product value.
- Check trust state only if a feature needs it.
- Explain why it is requested before prompting.

Reference:

- AXIsProcessTrustedWithOptions: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

## Calendar and Reminders

Loop can create calendar events and reminders after user confirmation.

Requirements:

- Request permission only when needed or during explicit onboarding.
- Show an editable confirmation sheet.
- Store idempotency fingerprints to avoid duplicates.
- Handle denied permission with a needs-permission suggestion state.

## Feasibility Summary

- Strong fit: macOS menu bar app, background helper, local storage, notifications, Calendar/Reminders, explicit onboarding.
- Feasible but fragile: Apple Messages local ingestion with Full Disk Access.
- Excluded from v1: any source outside Apple Messages and bundled developer samples.
