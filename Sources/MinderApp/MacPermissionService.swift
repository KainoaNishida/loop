import AppKit
import Contacts
import EventKit
import Foundation
import MinderCore
import UserNotifications

final class MacPermissionService: PermissionServicing {
    private let eventStore = EKEventStore()
    private let messagesDatabaseURL: URL
    private let runtimeContext: AppRuntimeContext

    init(
        messagesDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db"),
        runtimeContext: AppRuntimeContext = AppRuntimeContext()
    ) {
        self.messagesDatabaseURL = messagesDatabaseURL
        self.runtimeContext = runtimeContext
    }

    func refreshPermissionHealth() async -> [PermissionHealth] {
        let messagesHealth = messagesPermissionHealth()
        let notificationHealth = await notificationPermissionHealth()
        return [
            messagesHealth.fullDiskAccess,
            messagesHealth.appleMessages,
            contactsPermissionHealth(),
            notificationHealth,
            calendarPermissionHealth(),
            remindersPermissionHealth(),
            cloudAIHealth()
        ]
    }

    func requestNotifications() async -> PermissionHealth {
        guard runtimeContext.supportsUserNotifications else {
            return notificationUnsupportedInCurrentLaunchMode()
        }

        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            if granted {
                return PermissionHealth(kind: .notifications, state: .available, detail: "Notifications are enabled for alerts, sounds, and badges.")
            }
            return PermissionHealth(kind: .notifications, state: .revoked, detail: "Notifications were denied. You can re-enable them in System Settings.")
        } catch {
            return PermissionHealth(
                kind: .notifications,
                state: .degraded,
                detail: "macOS could not show the notification prompt. Open Notification Settings, enable Loop, then click Check Again. \(error.localizedDescription)"
            )
        }
    }

    func requestContactsAccess() async -> PermissionHealth {
        guard runtimeContext.supportsDirectPermissionPrompts else {
            return PermissionHealth(
                kind: .contacts,
                state: .unsupported,
                detail: "Contacts permission prompts require a packaged .app bundle. Build Loop.app to enable contact names."
            )
        }

        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                CNContactStore().requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            if granted {
                return PermissionHealth(kind: .contacts, state: .available, detail: "Contacts access is enabled for local name matching.")
            }
            return PermissionHealth(kind: .contacts, state: .revoked, detail: "Contacts access was denied. Messages import will use phone numbers or emails when names are unavailable.")
        } catch {
            return PermissionHealth(kind: .contacts, state: .degraded, detail: "Contacts request failed: \(error.localizedDescription)")
        }
    }

    func requestCalendarAccess() async -> PermissionHealth {
        guard runtimeContext.supportsDirectPermissionPrompts else {
            return PermissionHealth(
                kind: .calendar,
                state: .unsupported,
                detail: "Calendar permission prompts require a packaged .app bundle. This SwiftPM launch can still show status and open System Settings."
            )
        }

        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                eventStore.requestWriteOnlyAccessToEvents { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            if granted {
                return PermissionHealth(kind: .calendar, state: .available, detail: "Calendar write access is enabled for confirmed event drafts.")
            }
            return PermissionHealth(kind: .calendar, state: .revoked, detail: "Calendar access was denied. Confirmed calendar drafts cannot be created yet.")
        } catch {
            return PermissionHealth(kind: .calendar, state: .degraded, detail: "Calendar request failed: \(error.localizedDescription)")
        }
    }

    func requestRemindersAccess() async -> PermissionHealth {
        guard runtimeContext.supportsDirectPermissionPrompts else {
            return PermissionHealth(
                kind: .reminders,
                state: .unsupported,
                detail: "Reminders permission prompts require a packaged .app bundle. This SwiftPM launch can still show status and open System Settings."
            )
        }

        do {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            if granted {
                return PermissionHealth(kind: .reminders, state: .available, detail: "Reminders access is enabled for confirmed reminder drafts.")
            }
            return PermissionHealth(kind: .reminders, state: .revoked, detail: "Reminders access was denied. Confirmed reminder drafts cannot be created yet.")
        } catch {
            return PermissionHealth(kind: .reminders, state: .degraded, detail: "Reminders request failed: \(error.localizedDescription)")
        }
    }

    func openSystemSettings(for kind: PermissionKind) async -> Bool {
        guard let url = settingsURL(for: kind) else { return false }
        return await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private func messagesPermissionHealth() -> (fullDiskAccess: PermissionHealth, appleMessages: PermissionHealth) {
        if FileManager.default.fileExists(atPath: messagesDatabaseURL.path) {
            do {
                let handle = try FileHandle(forReadingFrom: messagesDatabaseURL)
                try? handle.close()
                return (
                    PermissionHealth(kind: .fullDiskAccess, state: .available, detail: "Loop can read the local Messages database."),
                    AppleMessagesConversationImporter.health(databaseURL: messagesDatabaseURL)
                )
            } catch {
                return (
                    PermissionHealth(kind: .fullDiskAccess, state: .missing, detail: "Loop cannot read Messages yet. Grant Full Disk Access in System Settings."),
                    PermissionHealth(kind: .appleMessages, state: .missing, detail: "Apple Messages import is paused until Full Disk Access is available.")
                )
            }
        }

        return (
            PermissionHealth(kind: .fullDiskAccess, state: .missing, detail: "Full Disk Access has not been validated for Loop yet."),
            PermissionHealth(kind: .appleMessages, state: .unsupported, detail: "The local Messages database was not found on this Mac.")
        )
    }

    private func notificationPermissionHealth() async -> PermissionHealth {
        guard runtimeContext.supportsUserNotifications else {
            return notificationUnsupportedInCurrentLaunchMode()
        }

        let settings = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return PermissionHealth(kind: .notifications, state: .available, detail: "Notifications are enabled.")
        case .notDetermined:
            return PermissionHealth(kind: .notifications, state: .missing, detail: "Notifications have not been requested yet.")
        case .denied:
            return PermissionHealth(kind: .notifications, state: .revoked, detail: "Notifications are disabled in System Settings.")
        @unknown default:
            return PermissionHealth(kind: .notifications, state: .degraded, detail: "Notification authorization is in an unknown state.")
        }
    }

    private func notificationUnsupportedInCurrentLaunchMode() -> PermissionHealth {
        PermissionHealth(
            kind: .notifications,
            state: .unsupported,
            detail: "Notifications are unavailable in this launch mode. Open the packaged Loop app, then check again."
        )
    }

    private func contactsPermissionHealth() -> PermissionHealth {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return PermissionHealth(kind: .contacts, state: .available, detail: "Contacts access is available for local Messages name matching.")
        case .notDetermined:
            return PermissionHealth(kind: .contacts, state: .missing, detail: "Contacts access has not been requested yet. Messages import can still use phone numbers or emails.")
        case .denied:
            return PermissionHealth(kind: .contacts, state: .revoked, detail: "Contacts access is disabled in System Settings. Messages import will use phone numbers or emails.")
        case .restricted:
            return PermissionHealth(kind: .contacts, state: .unsupported, detail: "Contacts access is restricted on this Mac.")
        case .limited:
            return PermissionHealth(kind: .contacts, state: .available, detail: "Limited Contacts access is available for local Messages name matching.")
        @unknown default:
            return PermissionHealth(kind: .contacts, state: .degraded, detail: "Contacts authorization is in an unknown state.")
        }
    }

    private func calendarPermissionHealth() -> PermissionHealth {
        eventKitHealth(kind: .calendar, status: EKEventStore.authorizationStatus(for: .event), unavailableDetail: "Calendar access has not been granted yet.")
    }

    private func remindersPermissionHealth() -> PermissionHealth {
        eventKitHealth(kind: .reminders, status: EKEventStore.authorizationStatus(for: .reminder), unavailableDetail: "Reminders access has not been granted yet.")
    }

    private func eventKitHealth(kind: PermissionKind, status: EKAuthorizationStatus, unavailableDetail: String) -> PermissionHealth {
        switch status {
        case .notDetermined:
            return PermissionHealth(kind: kind, state: .missing, detail: unavailableDetail)
        case .restricted:
            return PermissionHealth(kind: kind, state: .unsupported, detail: "\(kind.displayName) access is restricted on this Mac.")
        case .denied:
            return PermissionHealth(kind: kind, state: .revoked, detail: "\(kind.displayName) access is disabled in System Settings.")
        case .authorized, .fullAccess, .writeOnly:
            return PermissionHealth(kind: kind, state: .available, detail: "\(kind.displayName) access is available.")
        @unknown default:
            return PermissionHealth(kind: kind, state: .degraded, detail: "\(kind.displayName) access is in an unknown state.")
        }
    }

    private func cloudAIHealth() -> PermissionHealth {
        if let config = GeminiConfig.fromEnvironment() {
            return PermissionHealth(kind: .cloudAI, state: .available, detail: "Gemini credentials are configured for \(config.model). Cloud AI still requires onboarding opt-in.")
        }
        return PermissionHealth(kind: .cloudAI, state: .missing, detail: "Gemini credentials are not configured. Local suggestions remain available.")
    }

    private func settingsURL(for kind: PermissionKind) -> URL? {
        let rawURL: String
        switch kind {
        case .fullDiskAccess, .appleMessages:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .cloudAI:
            return nil
        case .contacts:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .notifications:
            rawURL = "x-apple.systempreferences:com.apple.preference.notifications"
        case .calendar:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        }
        return URL(string: rawURL)
    }
}
