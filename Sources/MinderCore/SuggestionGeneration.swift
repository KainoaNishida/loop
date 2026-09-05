import Foundation

public struct SuggestionContext {
    public var sources: [ConversationSource]
    public var threads: [ConversationThread]
    public var messages: [Message]
    public var userProfile: UserProfile?

    public init(sources: [ConversationSource], threads: [ConversationThread], messages: [Message], userProfile: UserProfile? = nil) {
        self.sources = sources
        self.threads = threads
        self.messages = messages
        self.userProfile = userProfile
    }

    public var userAliases: [String] {
        UserIdentityAliases.aliases(for: userProfile)
    }

    var sourceById: [String: ConversationSource] {
        Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    }

    var threadById: [String: ConversationThread] {
        Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
    }

    var messageById: [String: Message] {
        Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }
}

public struct SuggestionGenerationReport: Equatable {
    public var messageCount: Int
    public var rawDraftCount: Int
    public var decisionCount: Int
    public var rankedDraftCount: Int
    public var savedSuggestions: [Suggestion]

    public var savedCount: Int {
        savedSuggestions.count
    }

    public var activeSavedCount: Int {
        savedSuggestions.filter { suggestion in
            suggestion.state != .completed && suggestion.state != .dismissed && suggestion.state != .superseded
        }.count
    }

    public init(messageCount: Int, rawDraftCount: Int, decisionCount: Int = 0, rankedDraftCount: Int, savedSuggestions: [Suggestion]) {
        self.messageCount = messageCount
        self.rawDraftCount = rawDraftCount
        self.decisionCount = decisionCount
        self.rankedDraftCount = rankedDraftCount
        self.savedSuggestions = savedSuggestions
    }
}

public final class SuggestionEngine {
    private let store: MinderStore
    private let rankingService: ConversationRankingService
    private let recommendationPolicy: ConversationRecommendationPolicy
    private let candidateBuilder: ConversationCandidateBuilder

    public init(
        store: MinderStore,
        rankingService: ConversationRankingService,
        recommendationPolicy: ConversationRecommendationPolicy = ConversationRecommendationPolicy(),
        enabledSourceKinds: Set<SourceKind>? = nil
    ) {
        self.store = store
        self.rankingService = rankingService
        self.recommendationPolicy = recommendationPolicy
        self.candidateBuilder = ConversationCandidateBuilder(policy: recommendationPolicy, enabledSourceKinds: enabledSourceKinds)
    }

    public func generateFromStoredMessages() async throws -> [Suggestion] {
        try await generateReportFromStoredMessages().savedSuggestions
    }

    public func generateReportFromStoredMessages() async throws -> SuggestionGenerationReport {
        let context = SuggestionContext(
            sources: try store.fetchSources(),
            threads: try store.fetchThreads(),
            messages: try store.fetchMessages(limit: 500),
            userProfile: try store.fetchUserProfile()
        )
        let candidates = candidateBuilder.candidates(from: context)
        let decisions = try await rankingService.rankCandidates(candidates, context: context)
        let rankedDrafts = recommendationPolicy.rankedDrafts(decisions, candidates: candidates, context: context)
        let saved = try store.replaceActiveSuggestions(with: rankedDrafts)
        return SuggestionGenerationReport(
            messageCount: context.messages.count,
            rawDraftCount: candidates.count,
            decisionCount: decisions.count,
            rankedDraftCount: rankedDrafts.count,
            savedSuggestions: saved
        )
    }
}

public enum SuggestionGenerationMode: String, Equatable {
    case localFallback
    case cloudAI

    public var displayName: String {
        switch self {
        case .localFallback: return "local fallback"
        case .cloudAI: return "Cloud AI"
        }
    }
}

public enum SuggestionGeneratorFactory {
    public static func mode(profile: UserProfile?, geminiConfig: GeminiConfig?) -> SuggestionGenerationMode {
        guard profile?.cloudAIEnabled == true, geminiConfig != nil else {
            return .localFallback
        }
        return .cloudAI
    }

    public static func makeRankingService(profile: UserProfile?, geminiConfig: GeminiConfig?) -> ConversationRankingService {
        switch mode(profile: profile, geminiConfig: geminiConfig) {
        case .cloudAI:
            return GeminiConversationRankingService(config: geminiConfig!)
        case .localFallback:
            return LocalConversationRankingService()
        }
    }
}

public struct GeminiConfig: Equatable {
    public var apiKey: String
    public var model: String

    public init(apiKey: String, model: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.model = model
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> GeminiConfig? {
        fromEnvironment(environment, dotenvURLs: DotenvLoader.defaultDotenvURLs())
    }

    public static func fromEnvironment(_ environment: [String: String], dotenvURLs: [URL]) -> GeminiConfig? {
        let dotenv = DotenvLoader.load(from: dotenvURLs)
        guard let apiKey = environment["GEMINI_API_KEY"]?.nilIfEmpty ?? dotenv["GEMINI_API_KEY"]?.nilIfEmpty else {
            return nil
        }
        return GeminiConfig(apiKey: apiKey, model: environment["GEMINI_MODEL"]?.nilIfEmpty ?? dotenv["GEMINI_MODEL"]?.nilIfEmpty ?? "gemini-2.5-flash")
    }
}

public final class GeminiConversationRankingService: ConversationRankingService {
    private let config: GeminiConfig
    private let session: URLSession

    public init(config: GeminiConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func rankCandidates(_ candidates: [ConversationRankingCandidate], context: SuggestionContext) async throws -> [ConversationRankingDecision] {
        try await rankCandidatesWithMetadata(candidates, context: context).decisions
    }

    public func rankCandidatesWithMetadata(
        _ candidates: [ConversationRankingCandidate],
        context: SuggestionContext
    ) async throws -> GeminiRankingResponse {
        guard !candidates.isEmpty else {
            return GeminiRankingResponse(decisions: [], httpStatus: nil)
        }
        let request = try GeminiRequestBuilder(config: config).makeRequest(candidates: candidates, context: context)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw GeminiError.requestFailed(statusCode: statusCode, body: body)
        }

        do {
            let decisions = try GeminiResponseParser.parseRankingDecisions(from: data, candidates: candidates, context: context)
            return GeminiRankingResponse(decisions: decisions, httpStatus: httpResponse.statusCode)
        } catch let error as GeminiError {
            throw error.withHTTPStatus(httpResponse.statusCode)
        }
    }
}

public struct GeminiRankingResponse: Equatable {
    public var decisions: [ConversationRankingDecision]
    public var httpStatus: Int?

    public init(decisions: [ConversationRankingDecision], httpStatus: Int?) {
        self.decisions = decisions
        self.httpStatus = httpStatus
    }
}

public enum GeminiError: Error, LocalizedError, Equatable {
    case requestFailed(statusCode: Int?, body: String)
    case missingOutputText(statusCode: Int?)
    case invalidJSON(String, statusCode: Int?)
    case invalidEvidenceReference(String, statusCode: Int?)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let body):
            let status = statusCode.map { "HTTP \($0)" } ?? "non-HTTP response"
            if statusCode == 429 {
                return "Gemini rate limit or quota was exceeded (\(status))."
            }
            return "Gemini request failed (\(status)): \(body)"
        case .missingOutputText(_):
            return "Gemini response did not include output text."
        case .invalidJSON(let detail, _):
            return "Gemini returned invalid JSON: \(detail)"
        case .invalidEvidenceReference(let id, _):
            return "Gemini response referenced an unknown message: \(id)"
        }
    }

    public var httpStatus: Int? {
        switch self {
        case .requestFailed(let statusCode, _),
             .missingOutputText(let statusCode),
             .invalidJSON(_, let statusCode),
             .invalidEvidenceReference(_, let statusCode):
            return statusCode
        }
    }

    public func withHTTPStatus(_ statusCode: Int?) -> GeminiError {
        switch self {
        case .requestFailed(_, let body):
            return .requestFailed(statusCode: statusCode, body: body)
        case .missingOutputText:
            return .missingOutputText(statusCode: statusCode)
        case .invalidJSON(let detail, _):
            return .invalidJSON(detail, statusCode: statusCode)
        case .invalidEvidenceReference(let id, _):
            return .invalidEvidenceReference(id, statusCode: statusCode)
        }
    }
}

public struct GeminiRequestBuilder {
    private let config: GeminiConfig

    public init(config: GeminiConfig) {
        self.config = config
    }

    public func makeRequest(candidates: [ConversationRankingCandidate], context: SuggestionContext) throws -> URLRequest {
        let encodedModel = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")!)
        request.timeoutInterval = 12
        request.httpMethod = "POST"
        request.addValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(candidates: candidates, context: context), options: [])
        return request
    }

    func requestBody(candidates: [ConversationRankingCandidate], context: SuggestionContext) -> [String: Any] {
        [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": """
                    You are Nudge, a privacy-first assistant that ranks conversation threads for whether the local user needs to act.
                    Judge each candidate thread as a whole conversation. Return one decision per candidate thread.
                    Use shouldAlert=false for closed threads, completed asks, or messages directed to another person.
                    Use shouldAlert=true when the local user plausibly needs to reply, schedule, remember, follow through, decide, or simply review a still-open recent thread.
                    If reasonHints contains repliedThread, the latest meaningful message is from the local user; these can be low-priority review alerts when the thread is not clearly closed.
                    Be broad and inclusive: unreplied inbound messages and recent replied threads can be low-priority alerts even without an explicit task.
                    Low-priority uncertain alerts are allowed only when there is a plausible action for the local user.
                    Do not invent people, deadlines, or commitments. Ground every alert in an input evidenceMessageId.

                    \(conversationPayload(candidates: candidates, context: context))
                    """
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.15,
                "candidateCount": 1,
                "responseMimeType": "application/json",
                "responseSchema": responseSchema()
            ]
        ]
    }

    private func conversationPayload(candidates: [ConversationRankingCandidate], context: SuggestionContext) -> String {
        let payload: [String: Any] = [
            "currentTime": DateCoding.iso8601.string(from: Date()),
            "localUser": [
                "displayName": context.userProfile?.displayName ?? "",
                "aliases": context.userAliases
            ],
            "instructions": [
                "minimalContext": true,
                "oneDecisionPerCandidate": true,
                "suppressAmbientSocialChatter": true,
                "lowPriorityAllowedWhenPlausible": true,
                "includePlausibleUnrepliedInbound": true,
                "includeRecentRepliedThreads": true,
                "minimumConfidence": 0.15
            ],
            "candidates": candidates.map(candidatePayload)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "Conversation ranking payload as JSON:\n\(json)"
    }

    private func candidatePayload(_ candidate: ConversationRankingCandidate) -> [String: Any] {
        [
            "candidateId": candidate.id,
            "sourceId": candidate.sourceId,
            "sourceName": candidate.sourceName,
            "threadId": candidate.threadId,
            "threadTitle": candidate.threadTitle,
            "participantLabels": candidate.participantLabels,
            "reasonHints": candidate.reasonHints,
            "lastUserReplyAt": candidate.lastUserReplyAt.map(DateCoding.iso8601.string(from:)) as Any,
            "latestMessage": messagePayload(candidate.latestMessage),
            "recentMessages": candidate.recentMessages.map(messagePayload)
        ]
    }

    private func messagePayload(_ message: Message) -> [String: Any] {
        [
            "messageId": message.id,
            "sender": message.senderLabel,
            "sentAt": DateCoding.iso8601.string(from: message.sentAt),
            "isFromUser": message.isFromUser,
            "body": message.body
        ]
    }

    private func responseSchema() -> [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "decisions": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "shouldAlert": ["type": "BOOLEAN"],
                            "priority": ["type": "STRING", "enum": SuggestionPriority.allCases.map(\.rawValue)],
                            "confidence": ["type": "NUMBER"],
                            "reasonCode": ["type": "STRING"],
                            "suggestionType": ["type": "STRING", "enum": SuggestionType.allCases.map(\.rawValue)],
                            "title": ["type": "STRING"],
                            "actionText": ["type": "STRING"],
                            "threadId": ["type": "STRING"],
                            "evidenceMessageId": ["type": "STRING"],
                            "evidenceSnippet": ["type": "STRING"],
                            "dueDate": ["type": "STRING"]
                        ],
                        "propertyOrdering": [
                            "shouldAlert",
                            "priority",
                            "confidence",
                            "reasonCode",
                            "suggestionType",
                            "title",
                            "actionText",
                            "threadId",
                            "evidenceMessageId",
                            "evidenceSnippet",
                            "dueDate"
                        ],
                        "required": [
                            "shouldAlert",
                            "priority",
                            "confidence",
                            "reasonCode",
                            "suggestionType",
                            "title",
                            "actionText",
                            "threadId",
                            "evidenceMessageId",
                            "evidenceSnippet"
                        ]
                    ]
                ]
            ],
            "propertyOrdering": ["decisions"],
            "required": ["decisions"]
        ]
    }
}

public enum GeminiResponseParser {
    public static func parseRankingDecisions(
        from data: Data,
        candidates: [ConversationRankingCandidate],
        context: SuggestionContext
    ) throws -> [ConversationRankingDecision] {
        let outputText = try extractOutputText(from: data)
        guard let outputData = normalizedJSONText(outputText).data(using: .utf8) else {
            throw GeminiError.missingOutputText(statusCode: nil)
        }
        let payload: GeminiStructuredRankingDecisions
        do {
            payload = try JSONDecoder().decode(GeminiStructuredRankingDecisions.self, from: outputData)
        } catch {
            throw GeminiError.invalidJSON(error.localizedDescription, statusCode: nil)
        }
        let candidateByThread = Dictionary(uniqueKeysWithValues: candidates.map { ($0.threadId, $0) })

        return try payload.decisions.map { item in
            guard let candidate = candidateByThread[item.threadId] else {
                throw GeminiError.invalidEvidenceReference(item.threadId, statusCode: nil)
            }
            let candidateMessageIds = Set(candidate.recentMessages.map(\.id))
            if item.shouldAlert && !candidateMessageIds.contains(item.evidenceMessageId) && context.messageById[item.evidenceMessageId] == nil {
                throw GeminiError.invalidEvidenceReference(item.evidenceMessageId, statusCode: nil)
            }
            return ConversationRankingDecision(
                shouldAlert: item.shouldAlert,
                priority: item.priority,
                confidence: item.confidence,
                reasonCode: item.reasonCode,
                suggestionType: item.suggestionType,
                title: item.title,
                actionText: item.actionText,
                threadId: item.threadId,
                evidenceMessageId: item.evidenceMessageId,
                evidenceSnippet: item.evidenceSnippet,
                dueDate: DateCoding.date(from: item.dueDate)
            )
        }
    }

    public static func extractOutputText(from data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw GeminiError.invalidJSON(error.localizedDescription, statusCode: nil)
        }
        if let text = findOutputText(in: object) {
            return text
        }
        throw GeminiError.missingOutputText(statusCode: nil)
    }

    private static func findOutputText(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }
            for value in dictionary.values {
                if let found = findOutputText(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = findOutputText(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private static func normalizedJSONText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }
        if let object = jsonSubstring(in: trimmed, opening: "{", closing: "}") {
            return object
        }
        if let array = jsonSubstring(in: trimmed, opening: "[", closing: "]") {
            return array
        }
        return trimmed
    }

    private static func jsonSubstring(in text: String, opening: Character, closing: Character) -> String? {
        var depth = 0
        var start: String.Index?
        var isInString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
            } else if character == opening {
                if depth == 0 {
                    start = index
                }
                depth += 1
            } else if character == closing, depth > 0 {
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                }
            }
        }
        return nil
    }
}

private struct GeminiStructuredRankingDecisions: Decodable {
    struct Item: Decodable {
        var shouldAlert: Bool
        var priority: SuggestionPriority
        var confidence: Double
        var reasonCode: String
        var suggestionType: SuggestionType
        var title: String
        var actionText: String
        var threadId: String
        var evidenceMessageId: String
        var evidenceSnippet: String
        var dueDate: String?
    }

    var decisions: [Item]
}
