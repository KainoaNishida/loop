import XCTest
@testable import Loop
@testable import MinderCore

@MainActor
final class MinderViewModelTests: XCTestCase {
    func testOpenSettingsSwitchesToSettingsTab() throws {
        let model = makeModel(store: try makeStore())

        XCTAssertEqual(model.selectedTab, .queue)

        model.openSettings()

        XCTAssertEqual(model.selectedTab, .settings)
    }

    func testToggleSettingsSwitchesBetweenSettingsAndQueue() throws {
        let model = makeModel(store: try makeStore())

        XCTAssertEqual(model.selectedTab, .queue)

        model.toggleSettings()

        XCTAssertEqual(model.selectedTab, .settings)

        model.toggleSettings()

        XCTAssertEqual(model.selectedTab, .queue)
    }

    func testQueuePresentationIncludesSuggestionsAndManualItems() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", sentAt: Date().addingTimeInterval(-8 * 60 * 60), body: "Can you send the notes?", isFromUser: false)
            ]
        )
        _ = try store.upsertSuggestions([
            testDraft(messageId: "message-apple-ask")
        ])
        let manualItem = try store.createManualQueueItem(kind: .todo, title: "Buy coffee")

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.activeQueueCount, 2)
        XCTAssertEqual(model.queueItems.count, 1)
        guard case .suggestion(let card) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected the generated suggestion to rank before manual items.")
        }
        XCTAssertEqual(card.recentMessages.map(\.externalId), ["ask"])

        model.goToNextQueuePage()

        guard case .manual(let queuedManualItem) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected manual item in mixed queue.")
        }
        XCTAssertEqual(queuedManualItem.id, manualItem.id)
    }

    func testQueuePresentationPaginatesActiveItems() throws {
        let store = try makeStore()
        for index in 1...7 {
            _ = try store.createManualQueueItem(kind: .todo, title: "Task \(index)")
        }

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.activeQueueCount, 7)
        XCTAssertEqual(model.queueItems.count, MinderViewModel.queuePageSize)
        XCTAssertEqual(model.queuePageIndex, 0)
        XCTAssertEqual(model.queuePageNumber, 1)
        XCTAssertEqual(model.queuePageCount, 7)
        XCTAssertEqual(model.queuePageRangeText, "1 of 7")
        XCTAssertFalse(model.canGoToPreviousQueuePage)
        XCTAssertTrue(model.canGoToNextQueuePage)

        model.goToNextQueuePage()

        XCTAssertEqual(model.queuePageIndex, 1)
        XCTAssertEqual(model.queueItems.count, MinderViewModel.queuePageSize)
        XCTAssertEqual(model.queuePageNumber, 2)
        XCTAssertEqual(model.queuePageRangeText, "2 of 7")
        XCTAssertTrue(model.canGoToPreviousQueuePage)
        XCTAssertTrue(model.canGoToNextQueuePage)

        model.goToLastQueuePage()

        XCTAssertEqual(model.queuePageIndex, 6)
        XCTAssertEqual(model.queueItems.count, 1)
        XCTAssertEqual(model.queuePageNumber, 7)
        XCTAssertEqual(model.queuePageRangeText, "7 of 7")
        XCTAssertTrue(model.canGoToPreviousQueuePage)
        XCTAssertFalse(model.canGoToNextQueuePage)
    }

    func testQueuePaginationClampsWhenCurrentPageBecomesEmpty() throws {
        let store = try makeStore()
        for index in 1...4 {
            _ = try store.createManualQueueItem(kind: .todo, title: "Task \(index)")
        }

        let model = makeModel(store: store)
        model.refresh()
        model.goToLastQueuePage()

        XCTAssertEqual(model.queuePageIndex, 3)
        XCTAssertEqual(model.queueItems.count, 1)
        guard case .manual(let lastPageItem) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected a manual item on the last page.")
        }

        model.complete(lastPageItem)
        waitForModelWorkToFinish(model)

        XCTAssertEqual(model.activeQueueCount, 3)
        XCTAssertEqual(model.queuePageIndex, 2)
        XCTAssertEqual(model.queuePageNumber, 3)
        XCTAssertEqual(model.queuePageCount, 3)
        XCTAssertEqual(model.queuePageRangeText, "3 of 3")
        XCTAssertEqual(model.queueItems.count, 1)
    }

    func testCompletedManualItemsMoveOutOfActiveQueueAndCanBeUndone() throws {
        let store = try makeStore()
        let manualItem = try store.createManualQueueItem(kind: .note, title: "Ask Avery")
        try store.updateManualQueueItemState(id: manualItem.id, state: .completed)

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertTrue(model.queueItems.isEmpty)
        XCTAssertEqual(model.recentCompletedQueueItems.count, 1)
        XCTAssertEqual(model.recentCompletedQueueItems.first?.title, "Ask Avery")

        model.undoCompleted(try XCTUnwrap(model.recentCompletedQueueItems.first))
        waitForModelWorkToFinish(model)

        XCTAssertEqual(model.queueItems.count, 1)
        guard case .manual(let restored) = model.queueItems[0] else {
            return XCTFail("Expected restored manual item.")
        }
        XCTAssertEqual(restored.state, .active)
    }

    func testSavingManualNoteThroughViewModelPersistsAndClearsComposer() throws {
        let store = try makeStore()
        let model = makeModel(store: store)

        model.beginManualItem(kind: .note)
        model.saveManualItem(kind: .note, title: "  Launch checklist  ", body: "  Confirm tester notes work.  ")

        XCTAssertFalse(model.isComposingManualItem)
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.manualDraftKind, .todo)
        XCTAssertEqual(model.manualDraftTitle, "")
        XCTAssertEqual(model.manualDraftBody, "")

        let saved = try XCTUnwrap(try store.fetchManualQueueItems().first)
        XCTAssertEqual(saved.kind, .note)
        XCTAssertEqual(saved.title, "Launch checklist")
        XCTAssertEqual(saved.body, "Confirm tester notes work.")

        guard case .manual(let queuedItem) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected saved note to appear in the queue.")
        }
        XCTAssertEqual(queuedItem.id, saved.id)
    }

    func testGenerateSuggestionsRunsEvenWhenOtherWorkFlagIsActive() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", body: "Can you send the notes?", isFromUser: false)
            ]
        )
        let importer = FakeAppleMessagesImporter(
            result: ImportResult(insertedSources: 0, insertedThreads: 0, insertedMessages: 0, skippedMessages: 1)
        )
        let model = makeModel(store: store, messagesImporter: importer)
        model.refresh()
        model.isWorking = true

        XCTAssertTrue(model.canGenerateSuggestions)

        model.generateSuggestions()
        waitForModelSyncToFinish(model)

        XCTAssertTrue(model.isWorking)
        XCTAssertFalse(model.isGeneratingSuggestions)
        XCTAssertEqual(importer.importCallCount, 1)
        XCTAssertTrue(model.statusMessage.contains("Checked Messages"))
    }

#if LOOP_INTERNAL_DIAGNOSTICS
    func testRunAppleMessagesDecodeTraceStoresReportAndStatus() throws {
        let store = try makeStore()
        let trace = AppleMessagesDecodeTraceReport(
            checkedSince: Date(timeIntervalSince1970: 1_800_000_000 - 86_400),
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
            targetTitles: ["Mom", "Hunter", "ksm"],
            unmatchedTitles: [],
            threadMatches: [
                AppleMessagesDecodeTraceThread(
                    requestedTitle: "Mom",
                    chatTitle: "Mom",
                    chatGUID: "iMessage;-;+15555550100",
                    chatKind: .direct,
                    outgoingRows: [
                        AppleMessagesDecodeTraceRow(
                            messageGUID: "message-mom-out",
                            sentAt: Date(timeIntervalSince1970: 1_800_000_000),
                            messageTextExists: false,
                            messageTextLength: 0,
                            messageTextSnippet: nil,
                            attributedBody: AppleMessagesBlobDecodeTrace(isPresent: false, byteLength: 0, hexPrefix: nil, decodedSnippet: nil),
                            payloadData: AppleMessagesBlobDecodeTrace(isPresent: false, byteLength: 0, hexPrefix: nil, decodedSnippet: nil),
                            messageSummaryInfo: AppleMessagesBlobDecodeTrace(isPresent: false, byteLength: 0, hexPrefix: nil, decodedSnippet: nil),
                            finalBody: "[Sent reply without plain text]",
                            failureReason: "No message.text or supported blob columns had data."
                        )
                    ]
                )
            ]
        )
        let importer = FakeAppleMessagesImporter(
            result: ImportResult(insertedSources: 0, insertedThreads: 0, insertedMessages: 0, skippedMessages: 0),
            decodeTraceReport: trace
        )
        let model = makeModel(store: store, messagesImporter: importer)

        model.runAppleMessagesDecodeTrace()
        waitForModelWorkToFinish(model)

        XCTAssertEqual(importer.decodeTraceCallCount, 1)
        XCTAssertEqual(model.appleMessagesDecodeTraceReport, trace)
        XCTAssertTrue(model.statusMessage.contains("1 chat matches"))
        XCTAssertTrue(model.statusMessage.contains("1 placeholders"))
    }

    func testRunAppleMessagesDecodeTracePassesStoredDirectChatAliases() throws {
        let store = try makeStore()
        let source = ConversationSource(id: "apple", name: "Apple Messages", kind: .appleMessages, lastSyncAt: Date())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try store.saveImport(
            source: source,
            threads: [
                ConversationThread(
                    id: "thread-mom",
                    sourceId: source.id,
                    externalId: "iMessage;-;+15555550100",
                    title: "Mom",
                    participantLabels: ["Mom"],
                    lastMessageAt: now
                ),
                ConversationThread(
                    id: "thread-hunter",
                    sourceId: source.id,
                    externalId: "iMessage;-;+15555550101",
                    title: "Hunter Matsukubo",
                    participantLabels: ["Hunter Matsukubo"],
                    lastMessageAt: now
                )
            ],
            messages: []
        )
        let importer = FakeAppleMessagesImporter(
            result: ImportResult(insertedSources: 0, insertedThreads: 0, insertedMessages: 0, skippedMessages: 0)
        )
        let model = makeModel(store: store, messagesImporter: importer)

        model.runAppleMessagesDecodeTrace()
        waitForModelWorkToFinish(model)

        XCTAssertEqual(importer.decodeTraceCallCount, 1)
        XCTAssertEqual(importer.decodeTraceAliasesByTitle["Mom"]?.contains("iMessage;-;+15555550100"), true)
        XCTAssertEqual(importer.decodeTraceAliasesByTitle["Hunter"]?.contains("iMessage;-;+15555550101"), true)
        XCTAssertEqual(importer.decodeTraceAliasesByTitle["Hunter"]?.contains("Hunter Matsukubo"), true)
    }
#endif

    func testSuggestionMessagesLoadByDefaultAndExpandForMoreHistory() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "m1", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 600), body: "First older message.", isFromUser: false),
                testMessage(id: "m2", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 500), body: "Second older message.", isFromUser: true),
                testMessage(id: "m3", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 400), body: "Third older message.", isFromUser: false),
                testMessage(id: "m4", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 300), body: "Fourth recent message.", isFromUser: true),
                testMessage(id: "m5", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 200), body: "Fifth recent message.", isFromUser: false),
                testMessage(id: "m6", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 100), body: "Sixth recent message.", isFromUser: true)
            ]
        )
        _ = try store.upsertSuggestions([
            testDraft(messageId: "message-apple-m6")
        ])

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.suggestionCards.count, 1)
        XCTAssertEqual(try XCTUnwrap(model.suggestionCards.first).recentMessages.map(\.externalId), ["m4", "m5", "m6"])
        let queueItem = try XCTUnwrap(model.queueItems.first)
        guard case .suggestion(let collapsedCard) = queueItem else {
            return XCTFail("Expected suggestion queue item.")
        }
        XCTAssertFalse(collapsedCard.isExpanded)
        XCTAssertEqual(collapsedCard.recentMessages.map(\.externalId), ["m4", "m5", "m6"])

        model.toggleExpanded(queueItem)

        guard case .suggestion(let expandedCard) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected expanded suggestion queue item.")
        }
        XCTAssertTrue(expandedCard.isExpanded)
        XCTAssertEqual(expandedCard.recentMessages.map(\.externalId), ["m1", "m2", "m3", "m4", "m5", "m6"])
    }

    func testActiveAlertCountExcludesManualAndInactiveSuggestions() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", body: "Can you send the notes?", isFromUser: false)
            ]
        )
        let saved = try store.upsertSuggestions([
            testDraft(type: .deadline, threadId: "active-deadline", messageId: "message-apple-ask"),
            testDraft(type: .followUpNudge, threadId: "active-follow-up", messageId: "message-apple-ask"),
            testDraft(type: .reminder, threadId: "completed-reminder", messageId: "message-apple-ask"),
            testDraft(type: .unansweredQuestion, threadId: "dismissed-question", messageId: "message-apple-ask"),
            testDraft(type: .staleReply, threadId: "superseded-stale", messageId: "message-apple-ask")
        ])
        try store.updateSuggestionState(id: saved[2].id, state: .completed)
        try store.updateSuggestionState(id: saved[3].id, state: .dismissed)
        try store.updateSuggestionState(id: saved[4].id, state: .superseded)
        _ = try store.createManualQueueItem(kind: .todo, title: "Manual item")

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.activeAlertCount, 2)
        XCTAssertEqual(model.activeQueueCount, 3)
    }

    func testAlertLegendItemsCountActiveSuggestionsByType() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", body: "Can you send the notes?", isFromUser: false)
            ]
        )
        let saved = try store.upsertSuggestions([
            testDraft(type: .deadline, threadId: "deadline", messageId: "message-apple-ask"),
            testDraft(type: .followUpNudge, threadId: "follow-up", messageId: "message-apple-ask"),
            testDraft(type: .unansweredQuestion, threadId: "inactive-question", messageId: "message-apple-ask")
        ])
        try store.updateSuggestionState(id: saved[2].id, state: .completed)

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.alertLegendItems.map(\.type), SuggestionType.allCases)
        let counts = Dictionary(uniqueKeysWithValues: model.alertLegendItems.map { ($0.type, $0.count) })
        XCTAssertEqual(counts[.deadline], 1)
        XCTAssertEqual(counts[.followUpNudge], 1)
        XCTAssertEqual(counts[.unansweredQuestion], 0)
        XCTAssertEqual(counts[.calendarEvent], 0)
    }

    func testSettingsPrivacyDeleteActionsClearImportedCacheButKeepManualItemsAndProfile() throws {
        let store = try makeStore()
        try store.saveUserProfile(UserProfile(displayName: "Kainoa", completedOnboardingAt: Date()))
        let manualItem = try store.createManualQueueItem(kind: .todo, title: "Keep this")
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", body: "Can you send the notes?", isFromUser: false)
            ]
        )
        _ = try store.upsertSuggestions([
            testDraft(messageId: "message-apple-ask")
        ])

        let model = makeOnboardingModel(store: store)
        model.clearImportedConversationCache()
        waitForOnboardingWorkToFinish(model)

        XCTAssertTrue(try store.fetchSources().isEmpty)
        XCTAssertTrue(try store.fetchMessages().isEmpty)
        XCTAssertTrue(try store.fetchSuggestions().isEmpty)
        XCTAssertEqual(try store.fetchManualQueueItems().first?.id, manualItem.id)
        XCTAssertEqual(try store.fetchUserProfile()?.displayName, "Kainoa")
    }

    func testCloudAIInputValidationAcceptsGeminiSettingsValues() throws {
        let store = try makeStore()
        let model = makeOnboardingModel(store: store)
        model.geminiAPIKeyInput = "stored-gemini-key"
        model.geminiModelInput = "gemini-2.5-flash"

        XCTAssertTrue(model.geminiInputValidation.isValid)
        XCTAssertEqual(model.geminiAPIKeyInput, "stored-gemini-key")
        XCTAssertEqual(model.geminiModelInput, "gemini-2.5-flash")
    }
}

@MainActor
private func makeModel(
    store: MinderStore,
    messagesImporter: any AppleMessagesImporting = AppleMessagesConversationImporter()
) -> MinderViewModel {
    MinderViewModel(store: store, permissionService: FakePermissionService(), messagesImporter: messagesImporter)
}

@MainActor
private func makeOnboardingModel(
    store: MinderStore,
    geminiConfigStore: GeminiConfigStore = GeminiConfigStore()
) -> OnboardingViewModel {
    OnboardingViewModel(
        store: store,
        permissionService: FakePermissionService(),
        geminiConfigStore: geminiConfigStore,
        onComplete: {},
        onChange: {}
    )
}

private func makeStore() throws -> MinderStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MinderAppTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try MinderStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
}

private func saveMessagesImport(store: MinderStore, messages: [Message]) throws {
    let source = ConversationSource(id: "apple", name: "Apple Messages", kind: .appleMessages, lastSyncAt: Date())
    let thread = ConversationThread(
        id: "thread-1",
        sourceId: source.id,
        externalId: "thread-1",
        title: "Avery",
        participantLabels: ["Avery"],
        lastMessageAt: messages.map(\.sentAt).max() ?? Date()
    )
    _ = try store.saveImport(source: source, threads: [thread], messages: messages)
}

private func testMessage(
    id: String,
    sentAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    body: String,
    isFromUser: Bool
) -> Message {
    Message(
        id: "message-apple-\(id)",
        sourceId: "apple",
        threadId: "thread-1",
        externalId: id,
        senderLabel: isFromUser ? "Me" : "Avery",
        sentAt: sentAt,
        body: body,
        isFromUser: isFromUser
    )
}

private func testDraft(
    type: SuggestionType = .unansweredQuestion,
    threadId: String = "thread-1",
    messageId: String
) -> SuggestionDraft {
    SuggestionDraft(
        type: type,
        title: "Reply to Avery",
        actionText: "Send the notes.",
        confidence: 0.84,
        sourceId: "apple",
        threadId: threadId,
        messageId: messageId,
        sourceApp: "Apple Messages",
        threadTitle: "Avery",
        evidenceSnippet: "Can you send the notes?",
        sourceTimestamp: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

@MainActor
private func waitForModelWorkToFinish(_ model: MinderViewModel) {
    let deadline = Date().addingTimeInterval(2)
    while model.isWorking && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private func waitForModelSyncToFinish(_ model: MinderViewModel) {
    let deadline = Date().addingTimeInterval(2)
    while model.isGeneratingSuggestions && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

@MainActor
private func waitForOnboardingWorkToFinish(_ model: OnboardingViewModel) {
    let deadline = Date().addingTimeInterval(2)
    while model.isWorking && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

private struct FakePermissionService: PermissionServicing {
    func refreshPermissionHealth() async -> [PermissionHealth] { [] }
    func requestNotifications() async -> PermissionHealth {
        PermissionHealth(kind: .notifications, state: .available, detail: "ok")
    }
    func requestContactsAccess() async -> PermissionHealth {
        PermissionHealth(kind: .contacts, state: .available, detail: "ok")
    }
    func requestCalendarAccess() async -> PermissionHealth {
        PermissionHealth(kind: .calendar, state: .available, detail: "ok")
    }
    func requestRemindersAccess() async -> PermissionHealth {
        PermissionHealth(kind: .reminders, state: .available, detail: "ok")
    }
    func openSystemSettings(for kind: PermissionKind) async -> Bool { true }
}

private final class FakeAppleMessagesImporter: AppleMessagesImporting {
    private let result: ImportResult
#if LOOP_INTERNAL_DIAGNOSTICS
    private let decodeTraceReport: AppleMessagesDecodeTraceReport
#endif
    private(set) var importCallCount = 0
#if LOOP_INTERNAL_DIAGNOSTICS
    private(set) var decodeTraceCallCount = 0
    private(set) var decodeTraceAliasesByTitle: [String: [String]] = [:]
#endif

#if LOOP_INTERNAL_DIAGNOSTICS
    init(
        result: ImportResult,
        decodeTraceReport: AppleMessagesDecodeTraceReport = AppleMessagesDecodeTraceReport(
            checkedSince: Date(timeIntervalSince1970: 0),
            checkedAt: Date(timeIntervalSince1970: 0),
            targetTitles: [],
            unmatchedTitles: [],
            threadMatches: []
        )
    ) {
        self.result = result
        self.decodeTraceReport = decodeTraceReport
    }
#else
    init(result: ImportResult) {
        self.result = result
    }
#endif

    func importRecent(into store: MinderStore, since cutoff: Date) async throws -> ImportResult {
        importCallCount += 1
        return result
    }

#if LOOP_INTERNAL_DIAGNOSTICS
    func textDiagnostics(since cutoff: Date) throws -> AppleMessagesTextDiagnostics {
        AppleMessagesTextDiagnostics(
            checkedSince: cutoff,
            outgoingWithPlainText: 0,
            outgoingWithoutPlainText: 0,
            outgoingWithAttributedBody: 0,
            outgoingWithoutPlainTextWithAttributedBody: 0,
            attachmentRows: 0,
            visibleNonTextRows: 0
        )
    }

    func decodeTrace(threadTitleMatches: [String], aliasesByTitle: [String: [String]], since cutoff: Date, limitPerThread: Int) throws -> AppleMessagesDecodeTraceReport {
        decodeTraceCallCount += 1
        decodeTraceAliasesByTitle = aliasesByTitle
        return decodeTraceReport
    }
#endif
}
