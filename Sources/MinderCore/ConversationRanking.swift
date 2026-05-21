import Foundation

public enum SuggestionPriority: String, Codable, CaseIterable, Hashable {
    case high
    case medium
    case low

    var rank: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    var confidenceFloor: Double {
        switch self {
        case .high: return 0.85
        case .medium: return 0.65
        case .low: return 0.15
        }
    }
}

public struct ConversationRankingCandidate: Identifiable, Codable, Equatable {
    public var id: String { threadId }
    public var sourceId: String
    public var sourceName: String
    public var threadId: String
    public var threadTitle: String
    public var participantLabels: [String]
    public var userDisplayName: String
    public var userAliases: [String]
    public var latestMessage: Message
    public var recentMessages: [Message]
    public var lastUserReplyAt: Date?
    public var reasonHints: [String]

    public init(
        sourceId: String,
        sourceName: String,
        threadId: String,
        threadTitle: String,
        participantLabels: [String],
        userDisplayName: String,
        userAliases: [String],
        latestMessage: Message,
        recentMessages: [Message],
        lastUserReplyAt: Date?,
        reasonHints: [String]
    ) {
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.threadId = threadId
        self.threadTitle = threadTitle
        self.participantLabels = participantLabels
        self.userDisplayName = userDisplayName
        self.userAliases = userAliases
        self.latestMessage = latestMessage
        self.recentMessages = recentMessages
        self.lastUserReplyAt = lastUserReplyAt
        self.reasonHints = reasonHints
    }
}

public struct ConversationRankingDecision: Codable, Equatable {
    public var shouldAlert: Bool
    public var priority: SuggestionPriority
    public var confidence: Double
    public var reasonCode: String
    public var suggestionType: SuggestionType
    public var title: String
    public var actionText: String
    public var threadId: String
    public var evidenceMessageId: String
    public var evidenceSnippet: String
    public var dueDate: Date?

    public init(
        shouldAlert: Bool,
        priority: SuggestionPriority,
        confidence: Double,
        reasonCode: String,
        suggestionType: SuggestionType,
        title: String,
        actionText: String,
        threadId: String,
        evidenceMessageId: String,
        evidenceSnippet: String,
        dueDate: Date? = nil
    ) {
        self.shouldAlert = shouldAlert
        self.priority = priority
        self.confidence = confidence
        self.reasonCode = reasonCode
        self.suggestionType = suggestionType
        self.title = title
        self.actionText = actionText
        self.threadId = threadId
        self.evidenceMessageId = evidenceMessageId
        self.evidenceSnippet = evidenceSnippet
        self.dueDate = dueDate
    }
}

public protocol ConversationRankingService {
    func rankCandidates(_ candidates: [ConversationRankingCandidate], context: SuggestionContext) async throws -> [ConversationRankingDecision]
}

public struct ConversationCandidateBuilder: Equatable {
    public var policy: ConversationRecommendationPolicy
    public var contextMessageLimit: Int
    public var enabledSourceKinds: Set<SourceKind>?

    public init(
        policy: ConversationRecommendationPolicy = ConversationRecommendationPolicy(),
        contextMessageLimit: Int = 6,
        enabledSourceKinds: Set<SourceKind>? = nil
    ) {
        self.policy = policy
        self.contextMessageLimit = contextMessageLimit
        self.enabledSourceKinds = enabledSourceKinds
    }

    public func candidates(from context: SuggestionContext) -> [ConversationRankingCandidate] {
        let sourceById = context.sourceById
        let threadById = context.threadById
        let messagesByThread = Dictionary(grouping: context.messages, by: \.threadId)

        return messagesByThread.compactMap { threadId, messages -> ConversationRankingCandidate? in
            let sorted = messages.sorted { $0.sentAt < $1.sentAt }
            guard
                let thread = threadById[threadId],
                let latest = latestMeaningfulMessage(in: sorted),
                let source = sourceById[latest.sourceId],
                enabledSourceKinds.map({ $0.contains(source.kind) }) ?? true,
                !policy.isClosureOnly(latest.body)
            else {
                return nil
            }

            let aliases = context.userAliases

            let lastUserReplyAt = sorted.filter(\.isFromUser).map(\.sentAt).max()
            if let lastUserReplyAt, lastUserReplyAt > latest.sentAt.addingTimeInterval(1) {
                return nil
            }

            let age = policy.now.timeIntervalSince(latest.sentAt)
            guard age >= 0, age <= policy.maximumAlertAge else {
                return nil
            }

            var reasonHints = latest.isFromUser
                ? ["repliedThread"]
                : reasonHints(for: latest, previousMessages: sorted, aliases: aliases)
            if !latest.isFromUser, age >= policy.normalUnrepliedDelay, !reasonHints.contains("unrepliedInbound") {
                reasonHints.append("unrepliedInbound")
            }
            guard !reasonHints.isEmpty else {
                return nil
            }

            let canUseShortBuffer = reasonHints.contains("deadline") || reasonHints.contains("directAsk") || reasonHints.contains("groupDecision")
            guard age >= (canUseShortBuffer ? policy.urgentQuietBuffer : policy.normalUnrepliedDelay) else {
                return nil
            }

            return ConversationRankingCandidate(
                sourceId: source.id,
                sourceName: source.name,
                threadId: thread.id,
                threadTitle: thread.title,
                participantLabels: thread.participantLabels,
                userDisplayName: context.userProfile?.displayName ?? "",
                userAliases: aliases,
                latestMessage: latest,
                recentMessages: nearbyMessages(endingAt: latest, in: sorted),
                lastUserReplyAt: lastUserReplyAt,
                reasonHints: reasonHints
            )
        }
        .sorted { $0.latestMessage.sentAt > $1.latestMessage.sentAt }
    }

    private func latestMeaningfulMessage(in messages: [Message]) -> Message? {
        messages.last { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func nearbyMessages(endingAt latest: Message, in messages: [Message]) -> [Message] {
        let throughLatest = messages.prefix { $0.sentAt <= latest.sentAt.addingTimeInterval(1) }
        return Array(throughLatest.suffix(max(1, contextMessageLimit)))
    }

    private func reasonHints(for latest: Message, previousMessages: [Message], aliases: [String]) -> [String] {
        let body = latest.body
        var reasons: [String] = []
        if policy.containsUrgentSignal(body) {
            reasons.append("deadline")
        }
        if policy.containsActionPhrase(body) || (body.contains("?") && !isAmbientSocialChatter(body)) {
            reasons.append("directAsk")
        }
        if policy.containsGroupDecisionSignal(body) {
            reasons.append("groupDecision")
        }
        if policy.containsUserAlias(body, aliases: aliases) {
            reasons.append("userAlias")
        }
        if hasRecentUserPromise(before: latest, in: previousMessages), policy.isUrgentOrActionable(body) {
            reasons.append("promisedFollowUp")
        }
        return Array(Set(reasons)).sorted()
    }

    private func isAmbientSocialChatter(_ text: String) -> Bool {
        let normalized = policy.normalizedText(text)
        guard !normalized.isEmpty else { return true }
        if policy.containsActionPhrase(normalized) || policy.containsGroupDecisionSignal(normalized) {
            return false
        }
        let socialSignals = [
            "nice house",
            "looks amazing",
            "look amazing",
            "so blue",
            "so cute",
            "great photo",
            "great picture",
            "love a trip",
            "would love",
            "i'd love",
            "id love",
            "relax",
            "beautiful",
            "awesome pic",
            "awesome picture",
            "congrats",
            "congratulations",
            "haha",
            "lol",
            "looks great",
            "so fun",
            "super fun",
            "love that"
        ]
        return socialSignals.contains { normalized.contains($0) }
    }

    private func hasRecentUserPromise(before latest: Message, in messages: [Message]) -> Bool {
        let signals = ["i'll", "i will", "i can", "i’ll", "i can get", "i'll book", "i’ll book"]
        return messages.contains { message in
            message.isFromUser
                && message.sentAt < latest.sentAt
                && signals.contains { message.body.lowercased().contains($0) }
        }
    }
}

public final class LocalConversationRankingService: ConversationRankingService {
    private let policy: ConversationRecommendationPolicy

    public init(policy: ConversationRecommendationPolicy = ConversationRecommendationPolicy()) {
        self.policy = policy
    }

    public func rankCandidates(_ candidates: [ConversationRankingCandidate], context: SuggestionContext) async throws -> [ConversationRankingDecision] {
        candidates.map(decision(for:))
    }

    private func decision(for candidate: ConversationRankingCandidate) -> ConversationRankingDecision {
        let latest = candidate.latestMessage
        let body = latest.body
        if candidate.reasonHints.contains("repliedThread") {
            return decision(
                candidate: candidate,
                priority: .low,
                confidence: 0.16,
                reasonCode: "replied_thread_review",
                type: .followUpNudge,
                title: "Review \(candidate.threadTitle)",
                action: "Open the conversation and decide whether anything still needs a follow-up."
            )
        }

        if policy.containsUrgentSignal(body) {
            return decision(
                candidate: candidate,
                priority: .high,
                confidence: 0.90,
                reasonCode: "deadline_or_scheduling",
                type: .deadline,
                title: "Track request from \(candidate.threadTitle)",
                action: "Review the dated request and decide whether to add a calendar event, reminder, or reply."
            )
        }

        if candidate.reasonHints.contains("promisedFollowUp") {
            return decision(
                candidate: candidate,
                priority: .medium,
                confidence: 0.76,
                reasonCode: "promised_follow_up",
                type: .promisedTask,
                title: "Follow through with \(candidate.threadTitle)",
                action: "Review the latest follow-up and the task you promised in this conversation."
            )
        }

        if policy.containsActionPhrase(body) || body.contains("?") {
            let isConcreteAsk = policy.containsActionPhrase(body)
            return decision(
                candidate: candidate,
                priority: isConcreteAsk ? .medium : .low,
                confidence: isConcreteAsk ? 0.78 : 0.54,
                reasonCode: isConcreteAsk ? "direct_action_request" : "possible_question",
                type: .unansweredQuestion,
                title: "Review \(candidate.threadTitle)",
                action: "Open the conversation and answer the latest request if it still needs you."
            )
        }

        if candidate.reasonHints.contains("unrepliedInbound") {
            return decision(
                candidate: candidate,
                priority: .low,
                confidence: 0.51,
                reasonCode: "unreplied_inbound",
                type: .followUpNudge,
                title: "Check \(candidate.threadTitle)",
                action: "Open the conversation and decide whether the latest message needs a response."
            )
        }

        return decision(
            candidate: candidate,
            priority: .low,
            confidence: 0.52,
            reasonCode: "possible_user_mention",
            type: .followUpNudge,
            title: "Check \(candidate.threadTitle)",
            action: "Open the conversation and decide whether the latest message needs your attention."
        )
    }

    private func decision(
        candidate: ConversationRankingCandidate,
        priority: SuggestionPriority,
        confidence: Double,
        reasonCode: String,
        type: SuggestionType,
        title: String,
        action: String
    ) -> ConversationRankingDecision {
        ConversationRankingDecision(
            shouldAlert: true,
            priority: priority,
            confidence: confidence,
            reasonCode: reasonCode,
            suggestionType: type,
            title: title,
            actionText: action,
            threadId: candidate.threadId,
            evidenceMessageId: candidate.latestMessage.id,
            evidenceSnippet: candidate.latestMessage.body
        )
    }
}
