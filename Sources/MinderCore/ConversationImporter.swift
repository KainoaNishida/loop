import Foundation

public final class ConversationImporter {
    public init() {}

    public func importSampleConversations(into store: MinderStore) throws -> ImportResult {
        guard let url = Self.sampleConversationsURL() else {
            throw ConversationImporterError.missingSampleResource
        }
        return try importConversationFile(at: url, into: store)
    }

    public func importConversationFile(at url: URL, into store: MinderStore) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let fixture = try DateCoding.jsonDecoder.decode(SampleConversationFile.self, from: data)

        let source = ConversationSource(
            id: fixture.source.id,
            name: fixture.source.name,
            kind: fixture.source.kind,
            health: .available,
            lastSyncAt: Date()
        )

        var threads: [ConversationThread] = []
        var messages: [Message] = []

        for fixtureThread in fixture.threads {
            let threadId = stableID(sourceId: source.id, externalId: fixtureThread.id, prefix: "thread")
            let threadMessages = fixtureThread.messages.map { fixtureMessage in
                Message(
                    id: stableID(sourceId: source.id, externalId: "\(fixtureThread.id)-\(fixtureMessage.id)", prefix: "message"),
                    sourceId: source.id,
                    threadId: threadId,
                    externalId: fixtureMessage.id,
                    senderLabel: fixtureMessage.sender,
                    sentAt: fixtureMessage.sentAt,
                    body: fixtureMessage.body,
                    isFromUser: fixtureMessage.isFromUser
                )
            }
            let lastMessageAt = threadMessages.map(\.sentAt).max() ?? Date()
            threads.append(ConversationThread(
                id: threadId,
                sourceId: source.id,
                externalId: fixtureThread.id,
                title: fixtureThread.title,
                participantLabels: fixtureThread.participants,
                lastMessageAt: lastMessageAt,
                isActive: true
            ))
            messages.append(contentsOf: threadMessages)
        }

        return try store.saveImport(source: source, threads: threads, messages: messages)
    }

    private static func sampleConversationsURL() -> URL? {
        let bundleNames = ["Nudge_MinderCore.bundle", "Loop_MinderCore.bundle", "Minder_MinderCore.bundle"]
        let fileName = "sample-conversations.json"

        let searchRoots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }

        for root in searchRoots {
            for bundleName in bundleNames {
                let url = root.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return Bundle.module.url(forResource: "sample-conversations", withExtension: "json")
    }
}

public enum ConversationImporterError: Error, LocalizedError {
    case missingSampleResource

    public var errorDescription: String? {
        switch self {
        case .missingSampleResource: return "Missing bundled sample-conversations.json resource."
        }
    }
}

private struct SampleConversationFile: Decodable {
    struct Source: Decodable {
        var id: String
        var name: String
        var kind: SourceKind
    }

    struct Thread: Decodable {
        var id: String
        var title: String
        var participants: [String]
        var messages: [Message]
    }

    struct Message: Decodable {
        var id: String
        var sender: String
        var sentAt: Date
        var body: String
        var isFromUser: Bool
    }

    var source: Source
    var threads: [Thread]
}

private func stableID(sourceId: String, externalId: String, prefix: String) -> String {
    "\(prefix)-\(sourceId)-\(externalId)".replacingOccurrences(of: " ", with: "-")
}
