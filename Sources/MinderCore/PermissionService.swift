import Foundation

public protocol PermissionServicing {
    func refreshPermissionHealth() async -> [PermissionHealth]
    func requestNotifications() async -> PermissionHealth
    func requestContactsAccess() async -> PermissionHealth
    func requestCalendarAccess() async -> PermissionHealth
    func requestRemindersAccess() async -> PermissionHealth
    func openSystemSettings(for kind: PermissionKind) async -> Bool
}

public final class OnboardingPermissionCoordinator {
    private let store: MinderStore
    private let service: PermissionServicing

    public init(store: MinderStore, service: PermissionServicing) {
        self.store = store
        self.service = service
    }

    @discardableResult
    public func refresh() async throws -> [PermissionHealth] {
        let health = await service.refreshPermissionHealth()
        try store.upsertPermissionHealth(health)
        return health
    }

    @discardableResult
    public func request(_ kind: PermissionKind) async throws -> PermissionHealth {
        let health: PermissionHealth
        switch kind {
        case .contacts:
            health = await service.requestContactsAccess()
        case .notifications:
            health = await service.requestNotifications()
        case .calendar:
            health = await service.requestCalendarAccess()
        case .reminders:
            health = await service.requestRemindersAccess()
        case .fullDiskAccess, .appleMessages, .cloudAI:
            let refreshed = try await refresh()
            return refreshed.first { $0.kind == kind } ?? PermissionHealth(
                kind: kind,
                state: .unsupported,
                detail: "\(kind.displayName) does not support an in-app permission prompt."
            )
        }

        try store.upsertPermissionHealth(health)
        return health
    }

    @discardableResult
    public func openSystemSettings(for kind: PermissionKind) async -> Bool {
        await service.openSystemSettings(for: kind)
    }
}
