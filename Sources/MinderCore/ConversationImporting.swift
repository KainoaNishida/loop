import Foundation

public protocol ConversationImporting {
    var sourceKind: SourceKind { get }
    var sourceName: String { get }

    func importRecent(into store: MinderStore, since cutoff: Date) async throws -> ImportResult
}

enum ImportIDs {
    static func sourceID(for kind: SourceKind) -> String {
        switch kind {
        case .sample:
            return "sample-messages"
        case .appleMessages:
            return "apple-messages-local"
        }
    }

    static func stableID(prefix: String, sourceId: String, externalId: String) -> String {
        "\(prefix)-\(sourceId)-\(externalId.stableHash)"
    }
}

extension String {
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    var stableHash: String {
        let offset: UInt64 = 1_469_598_103_934_665_603
        let prime: UInt64 = 1_099_511_628_211
        let hash = utf8.reduce(offset) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(hash, radix: 16)
    }
}
