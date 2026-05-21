import Foundation

public struct ConversationRecommendationPolicy: Equatable {
    public var now: Date
    public var normalUnrepliedDelay: TimeInterval
    public var urgentQuietBuffer: TimeInterval
    public var maximumAlertAge: TimeInterval
    public var minimumConfidence: Double

    public init(
        now: Date = Date(),
        normalUnrepliedDelay: TimeInterval = 0,
        urgentQuietBuffer: TimeInterval = 0,
        maximumAlertAge: TimeInterval = 30 * 86_400,
        minimumConfidence: Double = 0.15
    ) {
        self.now = now
        self.normalUnrepliedDelay = normalUnrepliedDelay
        self.urgentQuietBuffer = urgentQuietBuffer
        self.maximumAlertAge = maximumAlertAge
        self.minimumConfidence = minimumConfidence
    }

    public func rankedDrafts(_ drafts: [SuggestionDraft], context: SuggestionContext) -> [SuggestionDraft] {
        let messagesByThread = Dictionary(grouping: context.messages, by: \.threadId)
        return Dictionary(grouping: drafts, by: \.threadId)
            .compactMap { threadId, threadDrafts -> SuggestionDraft? in
                guard let messages = messagesByThread[threadId], isThreadEligible(messages, context: context) else {
                    return nil
                }
                let lastUserReplyAt = messages.filter(\.isFromUser).map(\.sentAt).max()
                let eligibleDrafts = threadDrafts.filter { draft in
                    draft.confidence >= minimumConfidence && lastUserReplyAt.map { draft.sourceTimestamp >= $0.addingTimeInterval(-1) } ?? true
                }
                return eligibleDrafts.max { lhs, rhs in
                    isLowerRank(lhs, than: rhs)
                }
            }
            .sorted { rankingScore(for: $0) == rankingScore(for: $1) ? $0.sourceTimestamp > $1.sourceTimestamp : rankingScore(for: $0) > rankingScore(for: $1) }
    }

    public func rankedDrafts(
        _ decisions: [ConversationRankingDecision],
        candidates: [ConversationRankingCandidate],
        context: SuggestionContext
    ) -> [SuggestionDraft] {
        let candidateByThread = Dictionary(uniqueKeysWithValues: candidates.map { ($0.threadId, $0) })
        let messagesByThread = Dictionary(grouping: context.messages, by: \.threadId)
        var ranked: [(draft: SuggestionDraft, score: Double)] = []

        for (threadId, threadDecisions) in Dictionary(grouping: decisions, by: \.threadId) {
            guard
                let candidate = candidateByThread[threadId],
                let messages = messagesByThread[threadId],
                isThreadEligible(messages, context: context)
            else {
                continue
            }

            let messageById = Dictionary(uniqueKeysWithValues: candidate.recentMessages.map { ($0.id, $0) })
            let lastUserReplyAt = messages.filter(\.isFromUser).map(\.sentAt).max()
            let eligible = threadDecisions.compactMap { decision -> (decision: ConversationRankingDecision, message: Message, score: Double)? in
                guard
                    decision.shouldAlert,
                    decision.confidence >= minimumConfidence,
                    let message = messageById[decision.evidenceMessageId] ?? context.messageById[decision.evidenceMessageId],
                    message.threadId == threadId,
                    lastUserReplyAt.map({ message.sentAt >= $0.addingTimeInterval(-1) }) ?? true
                else {
                    return nil
                }
                return (decision, message, rankingScore(for: decision, candidate: candidate, message: message))
            }

            guard let best = eligible.max(by: { $0.score < $1.score }) else {
                continue
            }
            ranked.append((draft(from: best.decision, candidate: candidate, message: best.message), best.score))
        }

        return ranked
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.draft.sourceTimestamp > rhs.draft.sourceTimestamp : lhs.score > rhs.score
            }
            .map(\.draft)
    }

    public func isThreadEligible(_ messages: [Message]) -> Bool {
        isThreadEligible(messages, context: nil)
    }

    public func isThreadEligible(_ messages: [Message], context: SuggestionContext?) -> Bool {
        guard let latest = messages.sorted(by: { $0.sentAt < $1.sentAt }).last else {
            return false
        }
        guard !isClosureOnly(latest.body) else {
            return false
        }
        let age = now.timeIntervalSince(latest.sentAt)
        guard age >= 0, age <= maximumAlertAge else {
            return false
        }
        if isUrgentOrActionable(latest.body) {
            return age >= urgentQuietBuffer
        }
        return age >= normalUnrepliedDelay
    }

    public func isClosureOnly(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return true }
        if containsActionRequest(normalized) || containsUrgentSignal(normalized) {
            return false
        }
        if isEmojiOnly(text) {
            return true
        }

        let closurePhrases: Set<String> = [
            "thanks",
            "thank you",
            "thx",
            "ty",
            "ok",
            "okay",
            "k",
            "kk",
            "yes",
            "yeah",
            "yep",
            "yup",
            "no",
            "nope",
            "sounds good",
            "sg",
            "got it",
            "great",
            "perfect",
            "cool",
            "awesome",
            "nice",
            "love it",
            "will do",
            "done",
            "all good"
        ]
        return closurePhrases.contains(normalized)
    }

    public func isUrgentOrActionable(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        return containsUrgentSignal(normalized) || containsActionRequest(normalized)
    }

    public func containsUrgentSignal(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        let signals = [
            "by ",
            "deadline",
            "due",
            "today",
            "tonight",
            "tomorrow",
            "this week",
            "next week",
            "monday",
            "tuesday",
            "wednesday",
            "thursday",
            "friday",
            "saturday",
            "sunday",
            "noon",
            "morning",
            "afternoon",
            "evening",
            "pm",
            "am",
            "schedule",
            "calendar",
            "meeting",
            "call",
            "reservation",
            "appointment",
            "walkthrough"
        ]
        return signals.contains { normalized.contains($0) }
    }

    public func containsActionPhrase(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        let signals = [
            "can you",
            "could you",
            "would you",
            "will you",
            "please",
            "pls",
            "send me",
            "send the",
            "let me know",
            "remind me",
            "are we",
            "do you",
            "did you",
            "what time",
            "where should",
            "can i",
            "should we",
            "need you",
            "need this",
            "help me",
            "can someone",
            "could someone",
            "does anyone",
            "anyone able",
            "who can"
        ]
        return signals.contains { normalized.contains($0) }
    }

    public func containsActionRequest(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        return normalized.contains("?") || containsActionPhrase(normalized)
    }

    public func containsGroupDecisionSignal(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        let signals = [
            "should we",
            "are we",
            "can we",
            "do we",
            "does anyone",
            "can someone",
            "who can",
            "anyone able",
            "vote",
            "decide",
            "plan for",
            "which day",
            "what time works"
        ]
        return signals.contains { normalized.contains($0) }
    }

    public func containsUserAlias(_ text: String, aliases: [String]) -> Bool {
        let normalized = " \(normalizedText(text)) "
        return aliases
            .map(UserIdentityAliases.normalizeAlias)
            .filter { !$0.isEmpty && $0 != "you" }
            .contains { normalized.contains(" \($0) ") }
    }

    public func isAddressedToSomeoneElse(_ text: String, aliases: [String]) -> Bool {
        let knownAliases = Set(aliases.map(UserIdentityAliases.normalizeAlias).filter { !$0.isEmpty })
        guard !knownAliases.isEmpty else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            #"(?i)^\s*@?([A-Z][A-Za-z'\-]{1,30})\s*[,:\-]"#,
            #"(?i)^\s*@?([A-Z][A-Za-z'\-]{1,30})\s+(?:how|what|when|where|why|can|could|would|will|did|do|are|is)\b"#,
            #"(?i)(?:^|[^A-Za-z])([A-Z][A-Za-z'\-]{1,30})(?:\s+and\s+([A-Z][A-Za-z'\-]{1,30}))?\s*,"#
        ]

        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: trimmed)
            else {
                continue
            }
            let addressee = UserIdentityAliases.normalizeAlias(String(trimmed[range]))
            if isGenericGreeting(addressee) {
                return false
            }
            var addressees = [addressee]
            if match.numberOfRanges > 2, let secondRange = Range(match.range(at: 2), in: trimmed) {
                addressees.append(UserIdentityAliases.normalizeAlias(String(trimmed[secondRange])))
            }
            let meaningfulAddressees = addressees.filter { !$0.isEmpty && !isGenericGreeting($0) }
            guard !meaningfulAddressees.isEmpty else {
                return false
            }
            return meaningfulAddressees.allSatisfy { !knownAliases.contains($0) }
        }
        return false
    }

    public func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s'?]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func isLowerRank(_ lhs: SuggestionDraft, than rhs: SuggestionDraft) -> Bool {
        let leftPriority = priority(for: lhs.type)
        let rightPriority = priority(for: rhs.type)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence < rhs.confidence
        }
        return lhs.sourceTimestamp < rhs.sourceTimestamp
    }

    private func priority(for type: SuggestionType) -> Int {
        switch type {
        case .deadline, .calendarEvent:
            return 5
        case .reminder:
            return 4
        case .unansweredQuestion:
            return 3
        case .promisedTask:
            return 2
        case .staleReply, .followUpNudge, .importantContext:
            return 1
        }
    }

    private func rankingScore(for draft: SuggestionDraft) -> Double {
        let age = max(0, now.timeIntervalSince(draft.sourceTimestamp))
        let recency = max(0, 1 - min(age, maximumAlertAge) / maximumAlertAge)
        return Double(priority(for: draft.type)) + draft.confidence + (recency * 0.25)
    }

    private func rankingScore(
        for decision: ConversationRankingDecision,
        candidate: ConversationRankingCandidate,
        message: Message
    ) -> Double {
        let age = max(0, now.timeIntervalSince(message.sentAt))
        let recency = max(0, 1 - min(age, maximumAlertAge) / maximumAlertAge)
        let urgency = containsUrgentSignal(message.body) ? 0.75 : 0
        return Double(decision.priority.rank * 10) + decision.confidence + urgency + (recency * 0.25)
    }

    private func draft(
        from decision: ConversationRankingDecision,
        candidate: ConversationRankingCandidate,
        message: Message
    ) -> SuggestionDraft {
        let confidence = min(max(max(decision.confidence, decision.priority.confidenceFloor), 0), 1)
        return SuggestionDraft(
            type: decision.suggestionType,
            title: decision.title.nilIfEmpty ?? "Review \(candidate.threadTitle)",
            actionText: decision.actionText.nilIfEmpty ?? "Open the conversation and decide whether it needs your attention.",
            confidence: confidence,
            sourceId: candidate.sourceId,
            threadId: candidate.threadId,
            messageId: message.id,
            sourceApp: candidate.sourceName,
            threadTitle: candidate.threadTitle,
            evidenceSnippet: decision.evidenceSnippet.nilIfEmpty ?? message.body,
            sourceTimestamp: message.sentAt,
            dueDate: decision.dueDate
        )
    }

    private func isEmojiOnly(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty, scalars.count <= 8 else { return false }
        return scalars.allSatisfy { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }

    private func isGenericGreeting(_ token: String) -> Bool {
        [
            "actually",
            "also",
            "anyway",
            "btw",
            "but",
            "hey",
            "hi",
            "hello",
            "just",
            "ok",
            "okay",
            "so",
            "wait",
            "well",
            "yo"
        ].contains(token)
    }
}
