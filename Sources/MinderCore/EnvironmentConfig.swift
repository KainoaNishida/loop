import Foundation

public enum DotenvLoader {
    public static func repoDotenvURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
    }

    public static func userDotenvURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".loop.env")
    }

    public static func legacyUserDotenvURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minder.env")
    }

    public static func defaultDotenvURLs() -> [URL] {
        [
            repoDotenvURL(),
            legacyUserDotenvURL(),
            userDotenvURL()
        ]
    }

    public static func load(from urls: [URL] = defaultDotenvURLs()) -> [String: String] {
        var values: [String: String] = [:]
        for url in urls {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for rawLine in contents.components(separatedBy: .newlines) {
                var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                if line.hasPrefix("export ") {
                    line.removeFirst("export ".count)
                }
                guard let separator = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty {
                    values[key] = value
                }
            }
        }
        return values
    }
}

public enum GeminiConfigValidationResult: Equatable {
    case missingAPIKey
    case placeholderAPIKey
    case valid(GeminiConfig)

    public static func validate(_ config: GeminiConfig?) -> GeminiConfigValidationResult {
        guard let config, !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingAPIKey
        }

        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = apiKey.lowercased()
        if lowercased.contains("your-gemini")
            || lowercased.contains("placeholder")
            || lowercased == "..."
            || lowercased == "test-key" {
            return .placeholderAPIKey
        }

        return .valid(GeminiConfig(
            apiKey: apiKey,
            model: config.model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "gemini-2.5-flash"
        ))
    }

    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    public var config: GeminiConfig? {
        if case .valid(let config) = self {
            return config
        }
        return nil
    }

    public var userFacingMessage: String {
        switch self {
        case .missingAPIKey:
            return "Add a Gemini API key to enable Cloud AI."
        case .placeholderAPIKey:
            return "Replace the placeholder with a real Gemini API key."
        case .valid(let config):
            return "Gemini is configured with \(config.model)."
        }
    }
}

public struct GeminiConfigStore {
    public var url: URL

    public init(url: URL = DotenvLoader.userDotenvURL()) {
        self.url = url
    }

    public func load() -> GeminiConfig? {
        GeminiConfig.fromEnvironment([:], dotenvURLs: [url])
    }

    public func validation() -> GeminiConfigValidationResult {
        GeminiConfigValidationResult.validate(load())
    }

    public func save(_ config: GeminiConfig) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var lines: [String]
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        } else {
            lines = []
        }

        upsert("GEMINI_API_KEY", value: config.apiKey, into: &lines)
        upsert("GEMINI_MODEL", value: config.model, into: &lines)

        let output = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func upsert(_ key: String, value: String, into lines: inout [String]) {
        let assignment = "\(key)=\(dotenvValue(value))"
        if let index = lines.firstIndex(where: { dotenvKey(in: $0) == key }) {
            lines[index] = assignment
            return
        }
        if lines.last == "" {
            lines.removeLast()
        }
        lines.append(assignment)
    }

    private func dotenvKey(in line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        if trimmed.hasPrefix("export ") {
            trimmed.removeFirst("export ".count)
        }
        guard let separator = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func dotenvValue(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.rangeOfCharacter(from: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#\"'"))) == nil {
            return sanitized
        }
        let escaped = sanitized
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
