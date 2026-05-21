import Combine
import AppKit
import Foundation
import MinderCore

protocol AppleMessagesImporting {
    func importRecent(into store: MinderStore, since cutoff: Date) async throws -> ImportResult
    func textDiagnostics(since cutoff: Date) throws -> AppleMessagesTextDiagnostics
}

extension AppleMessagesConversationImporter: AppleMessagesImporting {}

enum LoopMainTab: String, CaseIterable, Identifiable {
    case queue
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue:
            return "Queue"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .queue:
            return "checklist"
        case .settings:
            return "gearshape"
        }
    }
}

struct LoopSuggestionCard: Identifiable {
    var suggestion: Suggestion
    var recentMessages: [Message] = []
    var isExpanded: Bool = false

    var id: String {
        suggestion.id
    }
}

enum LoopQueueItem: Identifiable {
    case suggestion(LoopSuggestionCard)
    case manual(ManualQueueItem)

    var id: String {
        switch self {
        case .suggestion(let card):
            return "suggestion:\(card.id)"
        case .manual(let item):
            return "manual:\(item.id)"
        }
    }

    var updatedAt: Date {
        switch self {
        case .suggestion(let card):
            return card.suggestion.updatedAt
        case .manual(let item):
            return item.updatedAt
        }
    }
}

enum LoopCompletedQueueItem: Identifiable {
    case suggestion(Suggestion)
    case manual(ManualQueueItem)

    var id: String {
        switch self {
        case .suggestion(let suggestion):
            return "suggestion:\(suggestion.id)"
        case .manual(let item):
            return "manual:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .suggestion(let suggestion):
            return suggestion.evidence.threadTitle
        case .manual(let item):
            return item.title
        }
    }

    var updatedAt: Date {
        switch self {
        case .suggestion(let suggestion):
            return suggestion.updatedAt
        case .manual(let item):
            return item.completedAt ?? item.updatedAt
        }
    }
}

enum LoopSuggestionSyncReason: Equatable {
    case manual
    case periodic

    var inProgressMessage: String {
        switch self {
        case .manual:
            return "Checking Messages..."
        case .periodic:
            return "Background check in progress..."
        }
    }
}

@MainActor
final class MinderViewModel: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var suggestionCards: [LoopSuggestionCard] = []
    @Published private(set) var queueItems: [LoopQueueItem] = []
    @Published private(set) var manualItems: [ManualQueueItem] = []
    @Published private(set) var sources: [ConversationSource] = []
    @Published private(set) var threads: [ConversationThread] = []
    @Published private(set) var messages: [Message] = []
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var geminiDiagnostics: [GeminiDiagnosticRun] = []
    @Published private(set) var appleMessagesTextDiagnostics: AppleMessagesTextDiagnostics?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var permissionHealth: [PermissionHealth] = []
    @Published private(set) var lastSyncAt: Date?
    @Published var selectedSuggestion: Suggestion?
    @Published var isShowingGeminiDiagnostics = false
    @Published var isComposingManualItem = false
    @Published var manualDraftKind: ManualQueueItemKind = .todo
    @Published var manualDraftTitle = ""
    @Published var manualDraftBody = ""
    @Published var expandedQueueItemID: String?
    @Published var selectedTab: LoopMainTab = .queue
    @Published var statusMessage: String = "Ready."
    @Published var isWorking = false
    @Published private(set) var isGeneratingSuggestions = false
    var showQueueWindow: (() -> Void)?

    private let store: MinderStore
    private let permissionCoordinator: OnboardingPermissionCoordinator
    private let importer = ConversationImporter()
    private let messagesImporter: any AppleMessagesImporting
    private static let prototypeSourceKinds: Set<SourceKind> = [.appleMessages]

    init(
        store: MinderStore,
        permissionService: PermissionServicing,
        messagesImporter: any AppleMessagesImporting = AppleMessagesConversationImporter()
    ) {
        self.store = store
        self.permissionCoordinator = OnboardingPermissionCoordinator(store: store, service: permissionService)
        self.messagesImporter = messagesImporter
    }

    var canGenerateSuggestions: Bool {
        !isGeneratingSuggestions
    }

    var isShowingProgress: Bool {
        isWorking || isGeneratingSuggestions
    }

    var cloudAIStatusText: String {
        guard let config = GeminiConfig.fromEnvironment(), profile?.cloudAIEnabled == true else {
            return "Cloud AI is off. Local suggestions are active."
        }
        return "Gemini is enabled with \(config.model)."
    }

    var aiModeLabel: String {
        GeminiConfig.fromEnvironment() != nil && profile?.cloudAIEnabled == true ? "Gemini" : "Local AI"
    }

    var activeSuggestions: [Suggestion] {
        suggestions
            .filter { isPrototypeSuggestion($0) }
            .filter { $0.state != .completed && $0.state != .dismissed && $0.state != .superseded }
            .sorted(by: isHigherPriorityAlert)
    }

    var recentCompletedSuggestions: [Suggestion] {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        return suggestions
            .filter { isPrototypeSuggestion($0) }
            .filter { $0.state == .completed && $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { $0 }
    }

    var activeManualItems: [ManualQueueItem] {
        manualItems
            .filter { $0.state == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeQueueCount: Int {
        activeSuggestions.count + activeManualItems.count
    }

    var recentCompletedQueueItems: [LoopCompletedQueueItem] {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        let completedSuggestions = recentCompletedSuggestions.map(LoopCompletedQueueItem.suggestion)
        let completedManualItems = manualItems
            .filter { $0.state == .completed && ($0.completedAt ?? $0.updatedAt) >= cutoff }
            .map(LoopCompletedQueueItem.manual)
        return (completedSuggestions + completedManualItems)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { $0 }
    }

    var canSaveManualItem: Bool {
        !manualDraftTitle.loopCollapsedWhitespace.isEmpty
    }

    var appleMessagesSource: ConversationSource? {
        sources.first { $0.kind == .appleMessages }
    }

    var appleMessagesCount: Int {
        guard let sourceId = appleMessagesSource?.id else { return 0 }
        return messages.filter { $0.sourceId == sourceId }.count
    }

    var needsAttentionCount: Int {
        activeSuggestions.filter { suggestion in
            suggestion.state == .new || suggestion.state == .failed || suggestion.state == .needsPermission || suggestion.confidence >= 0.85
        }.count
    }

    func refresh() {
        do {
            profile = try store.fetchUserProfile()
            sources = try store.fetchSources()
            threads = try store.fetchThreads()
            messages = try store.fetchMessages(limit: 200)
            suggestions = try store.fetchSuggestions(includeCompleted: true)
            manualItems = try store.fetchManualQueueItems(includeCompleted: true)
            auditEvents = try store.fetchAuditEvents(limit: 12)
            geminiDiagnostics = try store.fetchGeminiDiagnosticRuns(limit: 20)
            permissionHealth = try store.fetchPermissionHealth()
            if
                let selected = selectedSuggestion,
                let match = suggestions.first(where: { $0.id == selected.id }),
                isPrototypeSuggestion(match),
                match.state != .completed,
                match.state != .dismissed,
                match.state != .superseded
            {
                selectedSuggestion = match
            } else {
                selectedSuggestion = activeSuggestions.first
            }
            if suggestions.isEmpty && statusMessage == "Ready." {
                statusMessage = messages.isEmpty ? "Generate suggestions to check Messages." : "Generate suggestions from Messages."
            }
            suggestionCards = try makeSuggestionCards(from: activeSuggestions)
            queueItems = try makeQueueItems()
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshPermissionHealth() {
        perform("Refreshing permission health...") {
            self.permissionHealth = try await self.refreshAllHealth()
            self.refresh()
        }
    }

    func openSetup() {
        selectedTab = .settings
    }

    func openSettings() {
        selectedTab = .settings
    }

    func openQueueWindow() {
        selectedTab = .queue
        showQueueWindow?()
    }

    func quitLoop() {
        NSApp.terminate(nil)
    }

    func openGeminiDiagnostics() {
        refreshGeminiDiagnostics()
        isShowingGeminiDiagnostics = true
    }

    func refreshGeminiDiagnostics() {
        do {
            geminiDiagnostics = try store.fetchGeminiDiagnosticRuns(limit: 20)
        } catch {
            statusMessage = "Gemini diagnostics refresh failed: \(error.localizedDescription)"
        }
    }

    func runAppleMessagesTextDiagnostic() {
        perform("Checking Messages text storage...") {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86_400)
            let diagnostics = try self.messagesImporter.textDiagnostics(since: cutoff)
            self.appleMessagesTextDiagnostics = diagnostics
            self.statusMessage = "Messages text check: \(diagnostics.outgoingWithoutPlainTextWithAttributedBody) sent rows can be recovered from attributed bodies; \(diagnostics.outgoingWithoutPlainText) sent rows have no plain text."
        }
    }

    func replayLatestGeminiRun() {
        perform("Replaying latest Gemini candidate set...") {
            let latest = try self.latestGeminiDiagnosticRun()
            let replay = try await self.replayGeminiRun(latest)
            self.statusMessage = "Replay \(replay.outcome.rawValue): \(replay.detail)"
            self.refreshGeminiDiagnostics()
        }
    }

    func copyLatestGeminiDiagnostics() {
        do {
            let latest = try latestGeminiDiagnosticRun()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(redactedDiagnosticsText(for: latest), forType: .string)
            statusMessage = "Copied redacted Gemini diagnostics."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearGeminiDiagnostics() {
        perform("Clearing Gemini diagnostics...") {
            try self.store.clearGeminiDiagnosticRuns()
            self.geminiDiagnostics = []
            self.statusMessage = "Cleared Gemini diagnostics. Messages, suggestions, profile, and permissions were left untouched."
        }
    }

    func buildMockInbox() {
        perform("Building mock inbox...") {
            let importResult = try self.importer.importSampleConversations(into: self.store)
            let (generated, mode, fallbackError) = try await self.generateStoredSuggestions()
            let importSummary = importResult.insertedMessages > 0
                ? "Imported \(importResult.insertedMessages) sample messages"
                : "Sample messages already imported"
            let aiSummary = self.generationSummary(generated, mode: mode)
            if let fallbackError {
                self.statusMessage = "\(importSummary). \(aiSummary) after cloud fallback: \(fallbackError.localizedDescription)"
            } else {
                self.statusMessage = "\(importSummary). \(aiSummary)."
            }
            self.refresh()
        }
    }

    func importSampleConversations() {
        perform("Importing sample conversations...") {
            let result = try self.importer.importSampleConversations(into: self.store)
            self.statusMessage = "Imported \(result.insertedMessages) messages; skipped \(result.skippedMessages) duplicates."
            self.refresh()
        }
    }

    func importAppleMessagesRecent() {
        syncAndGenerateSuggestions(reason: .manual)
    }

    func generateSuggestions() {
        syncAndGenerateSuggestions(reason: .manual)
    }

    func syncAndGenerateSuggestions(reason: LoopSuggestionSyncReason) {
        guard !isGeneratingSuggestions else {
            if reason == .manual {
                statusMessage = "Loop is already checking Messages."
            }
            return
        }

        isGeneratingSuggestions = true
        statusMessage = reason.inProgressMessage
        Task { @MainActor in
            defer {
                self.isGeneratingSuggestions = false
            }
            do {
                let importResult = try await self.importRecentMessages()
                let (generated, mode, fallbackError) = try await self.generateStoredSuggestions()
                self.lastSyncAt = Date()
                self.statusMessage = "Checked Messages: \(importResult.insertedMessages) new, \(importResult.skippedMessages) unchanged. \(self.generationSummary(generated, mode: mode))."
                if generated.rankedDraftCount == 0 {
                    self.statusMessage += " Nothing needs attention right now."
                } else if generated.activeSavedCount == 0 {
                    self.statusMessage += " Everything found is already completed or dismissed."
                }
                if let fallbackError {
                    self.statusMessage += " Cloud AI fell back locally: \(fallbackError.localizedDescription)"
                }
                self.refresh()
            } catch {
                self.statusMessage = "Generate failed: \(error.localizedDescription)"
                self.refresh()
            }
        }
    }

    func regenerateSuggestions() {
        perform("Regenerating suggestions...") {
            try self.store.deleteSuggestions()
            let (generated, mode, fallbackError) = try await self.generateStoredSuggestions()
            self.statusMessage = "Cleared old suggestions. \(self.generationSummary(generated, mode: mode))."
            if generated.rankedDraftCount == 0 {
                self.statusMessage += " No recent Messages threads matched the lenient Messages rules."
            }
            if let fallbackError {
                self.statusMessage += " Cloud AI fell back locally: \(fallbackError.localizedDescription)"
            }
            self.refresh()
        }
    }

    func reimportSourcesAndRegenerate() {
        perform("Reimporting Messages...") {
            var summaries: [String] = []
            do {
                let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86_400)
                let result = try await self.messagesImporter.importRecent(into: self.store, since: cutoff)
                summaries.append("Messages +\(result.insertedMessages)/\(result.skippedMessages) skipped")
            } catch {
                summaries.append("Messages failed: \(error.localizedDescription)")
            }

            try self.store.deleteSuggestions()
            let (generated, mode, fallbackError) = try await self.generateStoredSuggestions()
            self.statusMessage = "\(summaries.joined(separator: ". ")). \(self.generationSummary(generated, mode: mode))."
            if let fallbackError {
                self.statusMessage += " Cloud AI fell back locally: \(fallbackError.localizedDescription)"
            }
            self.refresh()
        }
    }

    func clearSuggestions() {
        perform("Clearing suggestions...") {
            try self.store.deleteSuggestions()
            self.statusMessage = "Cleared generated suggestions. Click Generate to create new alerts."
            self.refresh()
        }
    }

    func clearImportedCache() {
        perform("Clearing imported cache...") {
            try self.store.deleteImportedConversationCache()
            self.statusMessage = "Cleared imported Messages and suggestions. Reimport Messages to continue."
            self.refresh()
        }
    }

    func complete(_ suggestion: Suggestion) {
        update(suggestion, to: .completed)
    }

    func complete(_ manualItem: ManualQueueItem) {
        perform("Completing item...") {
            try self.store.updateManualQueueItemState(id: manualItem.id, state: .completed)
            self.statusMessage = "Completed \(manualItem.title)."
            self.refresh()
        }
    }

    func undoCompleted(_ suggestion: Suggestion) {
        perform("Restoring suggestion...") {
            try self.store.updateSuggestionState(id: suggestion.id, state: .new)
            self.statusMessage = "Restored \(suggestion.evidence.threadTitle) to the inbox."
            self.refresh()
        }
    }

    func undoCompleted(_ item: LoopCompletedQueueItem) {
        switch item {
        case .suggestion(let suggestion):
            undoCompleted(suggestion)
        case .manual(let manualItem):
            undoCompleted(manualItem)
        }
    }

    func undoCompleted(_ manualItem: ManualQueueItem) {
        perform("Restoring item...") {
            try self.store.updateManualQueueItemState(id: manualItem.id, state: .active)
            self.statusMessage = "Restored \(manualItem.title) to the queue."
            self.refresh()
        }
    }

    func beginManualItem(kind: ManualQueueItemKind = .todo) {
        manualDraftKind = kind
        manualDraftTitle = ""
        manualDraftBody = ""
        isComposingManualItem = true
    }

    func cancelManualItem() {
        isComposingManualItem = false
        manualDraftTitle = ""
        manualDraftBody = ""
    }

    func saveManualItem() {
        saveManualItem(kind: manualDraftKind, title: manualDraftTitle, body: manualDraftBody)
    }

    func saveManualItem(kind: ManualQueueItemKind, title: String, body: String) {
        guard !title.loopCollapsedWhitespace.isEmpty else {
            statusMessage = "Add a title before saving."
            return
        }

        do {
            let item = try store.createManualQueueItem(
                kind: kind,
                title: title,
                body: body
            )
            isComposingManualItem = false
            manualDraftKind = .todo
            manualDraftTitle = ""
            manualDraftBody = ""
            statusMessage = "Added \(item.kind.displayName.lowercased())."
            refresh()
        } catch {
            statusMessage = "Could not save item: \(error.localizedDescription)"
        }
    }

    func toggleExpanded(_ item: LoopQueueItem) {
        guard case .suggestion(let card) = item else { return }
        let itemID = item.id
        if expandedQueueItemID == itemID {
            expandedQueueItemID = nil
        } else {
            expandedQueueItemID = itemID
        }
        do {
            suggestionCards = try makeSuggestionCards(from: activeSuggestions)
            queueItems = try makeQueueItems()
        } catch {
            statusMessage = "Could not load conversation preview: \(error.localizedDescription)"
        }
        selectedSuggestion = card.suggestion
    }

    func update(_ suggestion: Suggestion, to state: SuggestionState) {
        perform("Updating suggestion...") {
            try self.store.updateSuggestionState(id: suggestion.id, state: state)
            self.statusMessage = "Marked \(state.displayName.lowercased())."
            self.refresh()
        }
    }

    func snooze(_ suggestion: Suggestion) {
        perform("Snoozing suggestion...") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
            try self.store.updateSuggestionState(id: suggestion.id, state: .snoozed, snoozedUntil: tomorrow)
            self.statusMessage = "Snoozed until tomorrow."
            self.refresh()
        }
    }

    func eraseAllData() {
        perform("Deleting local dev data...") {
            try self.store.eraseAllData()
            self.statusMessage = "Deleted local LoopDev data."
            self.refresh()
        }
    }

    private func perform(_ message: String, operation: @MainActor @escaping () async throws -> Void) {
        isWorking = true
        statusMessage = message
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                statusMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func refreshAllHealth() async throws -> [PermissionHealth] {
        let health = try await permissionCoordinator.refresh()
        return health.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private func importRecentMessages() async throws -> ImportResult {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86_400)
        return try await messagesImporter.importRecent(into: store, since: cutoff)
    }

    private func makeSuggestionCards(from suggestions: [Suggestion], limit: Int = 6) throws -> [LoopSuggestionCard] {
        try suggestions.prefix(limit).map { suggestion in
            let itemID = "suggestion:\(suggestion.id)"
            let isExpanded = expandedQueueItemID == itemID
            return LoopSuggestionCard(
                suggestion: suggestion,
                recentMessages: isExpanded ? try store.fetchRecentMessages(threadId: suggestion.threadId, limit: 4) : [],
                isExpanded: isExpanded
            )
        }
    }

    private func makeQueueItems(limit: Int = 8) throws -> [LoopQueueItem] {
        let suggestionItems = try makeSuggestionCards(from: activeSuggestions, limit: 6)
            .map(LoopQueueItem.suggestion)
        let manualItems = activeManualItems.map(LoopQueueItem.manual)
        let sorted = (suggestionItems + manualItems).sorted(by: isHigherPriorityQueueItem)
        if let expandedQueueItemID, !sorted.contains(where: { $0.id == expandedQueueItemID }) {
            self.expandedQueueItemID = nil
        }
        return sorted.prefix(limit).map { $0 }
    }

    private func generateStoredSuggestions() async throws -> (generated: SuggestionGenerationReport, mode: String, fallbackError: Error?) {
        let config = GeminiConfig.fromEnvironment()
        let inputs = try storedRankingInputs()

        guard profile?.cloudAIEnabled == true else {
            let report = try await localFallbackReport()
            saveGeminiDiagnosticRun(
                model: config?.model ?? "Gemini",
                start: Date(),
                outcome: .skipped,
                category: .disabled,
                fallbackUsed: false,
                httpStatus: nil,
                candidates: inputs.candidates,
                decisionCount: 0,
                rankedCount: report.rankedDraftCount,
                savedCount: report.savedCount,
                detail: "Cloud AI is disabled; local ranking generated suggestions."
            )
            return (report, SuggestionGenerationMode.localFallback.displayName, nil)
        }

        guard let config else {
            let report = try await localFallbackReport()
            saveGeminiDiagnosticRun(
                model: "Gemini",
                start: Date(),
                outcome: .skipped,
                category: .missingConfig,
                fallbackUsed: true,
                httpStatus: nil,
                candidates: inputs.candidates,
                decisionCount: 0,
                rankedCount: report.rankedDraftCount,
                savedCount: report.savedCount,
                detail: "Cloud AI is enabled but GEMINI_API_KEY is missing; local fallback generated suggestions."
            )
            return (report, SuggestionGenerationMode.localFallback.displayName, GeminiDebugError.missingGeminiConfig)
        }

        let start = Date()
        guard !inputs.candidates.isEmpty else {
            let saved = try store.replaceActiveSuggestions(with: [])
            let report = SuggestionGenerationReport(
                messageCount: inputs.context.messages.count,
                rawDraftCount: 0,
                decisionCount: 0,
                rankedDraftCount: 0,
                savedSuggestions: saved
            )
            saveGeminiDiagnosticRun(
                model: config.model,
                start: start,
                outcome: .skipped,
                category: .noCandidates,
                fallbackUsed: false,
                httpStatus: nil,
                candidates: [],
                decisionCount: 0,
                rankedCount: 0,
                savedCount: report.savedCount,
                detail: "Local gates found no plausible candidate threads, so Gemini was not called."
            )
            return (report, SuggestionGenerationMode.cloudAI.displayName, nil)
        }

        do {
            let service = GeminiConversationRankingService(config: config)
            let response = try await service.rankCandidatesWithMetadata(inputs.candidates, context: inputs.context)
            let rankedDrafts = inputs.policy.rankedDrafts(response.decisions, candidates: inputs.candidates, context: inputs.context)
            let saved = try store.replaceActiveSuggestions(with: rankedDrafts)
            let report = SuggestionGenerationReport(
                messageCount: inputs.context.messages.count,
                rawDraftCount: inputs.candidates.count,
                decisionCount: response.decisions.count,
                rankedDraftCount: rankedDrafts.count,
                savedSuggestions: saved
            )
            saveGeminiDiagnosticRun(
                model: config.model,
                start: start,
                outcome: .success,
                category: .success,
                fallbackUsed: false,
                httpStatus: response.httpStatus,
                candidates: inputs.candidates,
                decisionCount: response.decisions.count,
                rankedCount: rankedDrafts.count,
                savedCount: report.savedCount,
                detail: "Gemini ranked candidate threads successfully."
            )
            return (report, SuggestionGenerationMode.cloudAI.displayName, nil)
        } catch {
            let geminiDuration = max(0, Int(Date().timeIntervalSince(start) * 1000))
            let report = try await localFallbackReport()
            saveGeminiDiagnosticRun(
                model: config.model,
                start: start,
                durationMilliseconds: geminiDuration,
                outcome: .failure,
                category: diagnosticCategory(for: error),
                fallbackUsed: true,
                httpStatus: diagnosticHTTPStatus(for: error),
                candidates: inputs.candidates,
                decisionCount: 0,
                rankedCount: report.rankedDraftCount,
                savedCount: report.savedCount,
                detail: redactedDiagnosticDetail(for: error)
            )
            return (report, SuggestionGenerationMode.localFallback.displayName, error)
        }
    }

    private func localFallbackReport() async throws -> SuggestionGenerationReport {
        let engine = SuggestionEngine(
            store: store,
            rankingService: LocalConversationRankingService(),
            enabledSourceKinds: Self.prototypeSourceKinds
        )
        return try await engine.generateReportFromStoredMessages()
    }

    private func storedRankingInputs() throws -> StoredRankingInputs {
        let context = SuggestionContext(
            sources: try store.fetchSources(),
            threads: try store.fetchThreads(),
            messages: try store.fetchMessages(limit: 500),
            userProfile: try store.fetchUserProfile()
        )
        let policy = ConversationRecommendationPolicy()
        let candidates = ConversationCandidateBuilder(
            policy: policy,
            enabledSourceKinds: Self.prototypeSourceKinds
        ).candidates(from: context)
        return StoredRankingInputs(context: context, policy: policy, candidates: candidates)
    }

    private func latestGeminiDiagnosticRun() throws -> GeminiDiagnosticRun {
        if let latest = geminiDiagnostics.first {
            return latest
        }
        guard let latest = try store.fetchGeminiDiagnosticRuns(limit: 1).first else {
            throw GeminiDebugError.noDiagnostics
        }
        return latest
    }

    private func replayGeminiRun(_ run: GeminiDiagnosticRun) async throws -> GeminiDiagnosticRun {
        let config = GeminiConfig.fromEnvironment()
        let inputs = try storedRankingInputs()
        let existingMessageIds = Set(inputs.context.messages.map(\.id))
        let missingMessageIds = Set(run.candidateMessageIds).subtracting(existingMessageIds)
        let start = Date()
        let model = config?.model ?? run.model

        guard let config else {
            return saveAndReturnGeminiDiagnosticRun(
                model: model,
                start: start,
                outcome: .skipped,
                category: .missingConfig,
                fallbackUsed: false,
                httpStatus: nil,
                candidates: [],
                decisionCount: 0,
                rankedCount: 0,
                savedCount: 0,
                detail: "Replay skipped because GEMINI_API_KEY is missing."
            )
        }

        guard missingMessageIds.isEmpty else {
            return saveAndReturnGeminiDiagnosticRun(
                model: model,
                start: start,
                outcome: .failure,
                category: .invalidEvidence,
                fallbackUsed: false,
                httpStatus: nil,
                candidates: [],
                decisionCount: 0,
                rankedCount: 0,
                savedCount: 0,
                detail: "Replay unavailable; \(missingMessageIds.count) referenced message IDs no longer exist in the local cache."
            )
        }

        let targetThreadIds = Set(run.candidateThreadIds)
        let replayCandidates = inputs.candidates.filter { targetThreadIds.contains($0.threadId) }
        guard !replayCandidates.isEmpty else {
            return saveAndReturnGeminiDiagnosticRun(
                model: model,
                start: start,
                outcome: .skipped,
                category: .noCandidates,
                fallbackUsed: false,
                httpStatus: nil,
                candidates: [],
                decisionCount: 0,
                rankedCount: 0,
                savedCount: 0,
                detail: run.candidateThreadIds.isEmpty
                    ? "Replay skipped because the latest diagnostic run had no candidate thread IDs."
                    : "Referenced messages exist, but no replayable candidates currently pass local gates."
            )
        }

        do {
            let service = GeminiConversationRankingService(config: config)
            let response = try await service.rankCandidatesWithMetadata(replayCandidates, context: inputs.context)
            let ranked = inputs.policy.rankedDrafts(response.decisions, candidates: replayCandidates, context: inputs.context)
            return saveAndReturnGeminiDiagnosticRun(
                model: config.model,
                start: start,
                outcome: .success,
                category: .success,
                fallbackUsed: false,
                httpStatus: response.httpStatus,
                candidates: replayCandidates,
                decisionCount: response.decisions.count,
                rankedCount: ranked.count,
                savedCount: 0,
                detail: "Replay completed; suggestions were not saved."
            )
        } catch {
            return saveAndReturnGeminiDiagnosticRun(
                model: config.model,
                start: start,
                outcome: .failure,
                category: diagnosticCategory(for: error),
                fallbackUsed: false,
                httpStatus: diagnosticHTTPStatus(for: error),
                candidates: replayCandidates,
                decisionCount: 0,
                rankedCount: 0,
                savedCount: 0,
                detail: redactedDiagnosticDetail(for: error)
            )
        }
    }

    @discardableResult
    private func saveAndReturnGeminiDiagnosticRun(
        model: String,
        start: Date,
        durationMilliseconds: Int? = nil,
        outcome: GeminiDiagnosticOutcome,
        category: GeminiDiagnosticErrorCategory,
        fallbackUsed: Bool,
        httpStatus: Int?,
        candidates: [ConversationRankingCandidate],
        decisionCount: Int,
        rankedCount: Int,
        savedCount: Int,
        detail: String
    ) -> GeminiDiagnosticRun {
        let run = makeGeminiDiagnosticRun(
            model: model,
            start: start,
            durationMilliseconds: durationMilliseconds,
            outcome: outcome,
            category: category,
            fallbackUsed: fallbackUsed,
            httpStatus: httpStatus,
            candidates: candidates,
            decisionCount: decisionCount,
            rankedCount: rankedCount,
            savedCount: savedCount,
            detail: detail
        )
        do {
            try store.saveGeminiDiagnosticRun(run)
            geminiDiagnostics = try store.fetchGeminiDiagnosticRuns(limit: 20)
        } catch {
            statusMessage = "Gemini diagnostics save failed: \(error.localizedDescription)"
        }
        return run
    }

    private func saveGeminiDiagnosticRun(
        model: String,
        start: Date,
        durationMilliseconds: Int? = nil,
        outcome: GeminiDiagnosticOutcome,
        category: GeminiDiagnosticErrorCategory,
        fallbackUsed: Bool,
        httpStatus: Int?,
        candidates: [ConversationRankingCandidate],
        decisionCount: Int,
        rankedCount: Int,
        savedCount: Int,
        detail: String
    ) {
        _ = saveAndReturnGeminiDiagnosticRun(
            model: model,
            start: start,
            durationMilliseconds: durationMilliseconds,
            outcome: outcome,
            category: category,
            fallbackUsed: fallbackUsed,
            httpStatus: httpStatus,
            candidates: candidates,
            decisionCount: decisionCount,
            rankedCount: rankedCount,
            savedCount: savedCount,
            detail: detail
        )
    }

    private func makeGeminiDiagnosticRun(
        model: String,
        start: Date,
        durationMilliseconds: Int?,
        outcome: GeminiDiagnosticOutcome,
        category: GeminiDiagnosticErrorCategory,
        fallbackUsed: Bool,
        httpStatus: Int?,
        candidates: [ConversationRankingCandidate],
        decisionCount: Int,
        rankedCount: Int,
        savedCount: Int,
        detail: String
    ) -> GeminiDiagnosticRun {
        let messageIds = Set(candidates.flatMap { candidate in
            candidate.recentMessages.map(\.id) + [candidate.latestMessage.id]
        })
        return GeminiDiagnosticRun(
            model: model,
            durationMilliseconds: durationMilliseconds ?? max(0, Int(Date().timeIntervalSince(start) * 1000)),
            outcome: outcome,
            errorCategory: category,
            fallbackUsed: fallbackUsed,
            httpStatus: httpStatus,
            candidateCount: candidates.count,
            decisionCount: decisionCount,
            rankedCount: rankedCount,
            savedCount: savedCount,
            candidateThreadIds: candidates.map(\.threadId),
            candidateMessageIds: Array(messageIds).sorted(),
            detail: redacted(detail)
        )
    }

    private func diagnosticCategory(for error: Error) -> GeminiDiagnosticErrorCategory {
        if let geminiError = error as? GeminiError {
            switch geminiError {
            case .requestFailed:
                return .http
            case .missingOutputText:
                return .missingOutput
            case .invalidJSON:
                return .invalidJSON
            case .invalidEvidenceReference:
                return .invalidEvidence
            }
        }
        if error is URLError {
            return .network
        }
        return .network
    }

    private func diagnosticHTTPStatus(for error: Error) -> Int? {
        (error as? GeminiError)?.httpStatus
    }

    private func redactedDiagnosticDetail(for error: Error) -> String {
        if let geminiError = error as? GeminiError {
            switch geminiError {
            case .requestFailed(let statusCode, _):
                if statusCode == 429 {
                    return "Gemini rate limit or quota was exceeded. Wait before generating again, or use a Gemini key/model with more available quota. Local fallback generated suggestions."
                }
                return statusCode.map { "Gemini returned HTTP \($0). Check the API key, model name, and request schema." }
                    ?? "Gemini request failed before an HTTP status was available."
            case .missingOutputText:
                return "Gemini responded without a text output field."
            case .invalidJSON(let detail, _):
                return "Gemini output could not be decoded as JSON: \(detail)"
            case .invalidEvidenceReference(let id, _):
                return "Gemini referenced a thread or message ID that was not in the candidate set: \(id)"
            }
        }
        if let urlError = error as? URLError {
            return "Network error: \(urlError.localizedDescription)"
        }
        return "Gemini failed: \(error.localizedDescription)"
    }

    private func redacted(_ detail: String) -> String {
        let flattened = detail
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(flattened.prefix(320))
    }

    private func redactedDiagnosticsText(for run: GeminiDiagnosticRun) -> String {
        """
        Gemini Diagnostics
        id: \(run.id)
        createdAt: \(ISO8601DateFormatter().string(from: run.createdAt))
        model: \(run.model)
        outcome: \(run.outcome.rawValue)
        errorCategory: \(run.errorCategory.rawValue)
        httpStatus: \(run.httpStatus.map(String.init) ?? "none")
        durationMs: \(run.durationMilliseconds)
        fallbackUsed: \(run.fallbackUsed)
        candidateCount: \(run.candidateCount)
        decisionCount: \(run.decisionCount)
        rankedCount: \(run.rankedCount)
        savedCount: \(run.savedCount)
        candidateThreadIds: \(run.candidateThreadIds.joined(separator: ", "))
        candidateMessageIds: \(run.candidateMessageIds.joined(separator: ", "))
        detail: \(run.detail)
        """
    }

    private func generationSummary(_ report: SuggestionGenerationReport, mode: String) -> String {
        "\(mode) read \(report.messageCount) messages, drafted \(report.rawDraftCount), judged \(report.decisionCount), ranked \(report.rankedDraftCount), saved \(report.savedCount) (\(report.activeSavedCount) active)"
    }

    private func isHigherPriorityAlert(_ lhs: Suggestion, than rhs: Suggestion) -> Bool {
        let leftPriority = priorityRank(for: lhs)
        let rightPriority = priorityRank(for: rhs)
        if leftPriority != rightPriority {
            return leftPriority > rightPriority
        }

        let leftUrgent = lhs.type == .deadline || lhs.type == .calendarEvent || lhs.action.dueDate != nil
        let rightUrgent = rhs.type == .deadline || rhs.type == .calendarEvent || rhs.action.dueDate != nil
        if leftUrgent != rightUrgent {
            return leftUrgent
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        return lhs.evidence.sourceTimestamp > rhs.evidence.sourceTimestamp
    }

    private func isHigherPriorityQueueItem(_ lhs: LoopQueueItem, than rhs: LoopQueueItem) -> Bool {
        switch (lhs, rhs) {
        case (.suggestion(let left), .suggestion(let right)):
            return isHigherPriorityAlert(left.suggestion, than: right.suggestion)
        case (.suggestion, .manual):
            return true
        case (.manual, .suggestion):
            return false
        case (.manual(let left), .manual(let right)):
            return left.updatedAt > right.updatedAt
        }
    }

    private func priorityRank(for suggestion: Suggestion) -> Int {
        if suggestion.confidence >= 0.85 { return 3 }
        if suggestion.confidence >= 0.65 { return 2 }
        if suggestion.confidence >= 0.15 { return 1 }
        return 0
    }

    private func isPrototypeSuggestion(_ suggestion: Suggestion) -> Bool {
        guard let source = sources.first(where: { $0.id == suggestion.sourceId }) else {
            return suggestion.evidence.sourceApp.localizedCaseInsensitiveContains("messages")
        }
        return Self.prototypeSourceKinds.contains(source.kind)
    }
}

private extension String {
    var loopCollapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private struct StoredRankingInputs {
    var context: SuggestionContext
    var policy: ConversationRecommendationPolicy
    var candidates: [ConversationRankingCandidate]
}

private enum GeminiDebugError: Error, LocalizedError {
    case noDiagnostics
    case missingGeminiConfig

    var errorDescription: String? {
        switch self {
        case .noDiagnostics:
            return "No Gemini diagnostics are available yet. Click Generate with Gemini enabled first."
        case .missingGeminiConfig:
            return "GEMINI_API_KEY is missing."
        }
    }
}

private extension HealthState {
    var displayName: String {
        switch self {
        case .available: return "Available"
        case .missing: return "Missing"
        case .degraded: return "Degraded"
        case .revoked: return "Revoked"
        case .unsupported: return "Unsupported"
        }
    }
}
