import Foundation

public enum LoopReleaseChannel: String, Equatable {
    case dev
    case alpha

    public static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LoopReleaseChannel {
        if let raw = environment["LOOP_RELEASE_CHANNEL"]?.nilIfEmpty, let channel = LoopReleaseChannel(rawValue: raw.lowercased()) {
            return channel
        }
        if let raw = bundle.object(forInfoDictionaryKey: "LoopReleaseChannel") as? String,
           let channel = LoopReleaseChannel(rawValue: raw.lowercased()) {
            return channel
        }
        return .dev
    }

    public var bundleIdentifier: String {
        switch self {
        case .dev:
            return "com.kainoanishida.loop.dev"
        case .alpha:
            return "com.kainoanishida.loop.alpha"
        }
    }

    public var appSupportDirectoryName: String {
        switch self {
        case .dev:
            return "LoopDev"
        case .alpha:
            return "LoopAlpha"
        }
    }

    public var displayName: String {
        switch self {
        case .dev:
            return "Development"
        case .alpha:
            return "Alpha"
        }
    }
}
