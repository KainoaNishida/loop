import Foundation

public enum UserIdentityAliases {
    public static func aliases(for profile: UserProfile?) -> [String] {
        var aliases: [String] = ["you"]
        let displayName = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            aliases.append(displayName)
            let parts = displayName
                .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
                .map(String.init)
            if let first = parts.first {
                aliases.append(first)
                let lowered = first.lowercased()
                if lowered == "kainoa" || lowered.hasPrefix("kai") {
                    aliases.append("kai")
                }
            }
        }

        var seen = Set<String>()
        return aliases
            .map(normalizeAlias)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    public static func normalizeAlias(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
