import Foundation

public protocol ContactResolving {
    func displayName(for handle: String) -> String?
}

public struct NoOpContactResolver: ContactResolving {
    public init() {}

    public func displayName(for handle: String) -> String? {
        nil
    }
}

public enum ContactHandleNormalizer {
    public static func lookupKeys(for handle: String) -> [String] {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var keys: [String] = []
        if let email = emailKey(for: trimmed) {
            keys.append(email)
        }
        keys.append(contentsOf: phoneKeys(for: trimmed))
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    public static func looksLikeRawHandle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if emailKey(for: trimmed) != nil {
            return true
        }
        return digits(in: trimmed).count >= 7
    }

    private static func emailKey(for handle: String) -> String? {
        let lowered = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lowered.contains("@"), lowered.contains(".") else { return nil }
        return "email:\(lowered)"
    }

    private static func phoneKeys(for handle: String) -> [String] {
        let onlyDigits = digits(in: handle)
        guard onlyDigits.count >= 7 else { return [] }

        var values = [onlyDigits]
        if onlyDigits.count == 11, onlyDigits.hasPrefix("1") {
            values.append(String(onlyDigits.dropFirst()))
        }
        if onlyDigits.count >= 10 {
            values.append(String(onlyDigits.suffix(10)))
        }
        return values.map { "phone:\($0)" }
    }

    private static func digits(in value: String) -> String {
        value.filter(\.isNumber)
    }
}
