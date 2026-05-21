import Foundation

public struct AppRuntimeContext: Equatable {
    public var bundleURL: URL

    public init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
    }

    public var isAppBundle: Bool {
        bundleURL.pathExtension.lowercased() == "app"
    }

    public var supportsUserNotifications: Bool {
        isAppBundle
    }

    public var supportsDirectPermissionPrompts: Bool {
        isAppBundle
    }
}
