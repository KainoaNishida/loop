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
        XCTAssertEqual(model.queueItems.count, 2)
        guard case .suggestion(let card) = model.queueItems[0] else {
            return XCTFail("Expected the generated suggestion to rank before manual items.")
        }
        XCTAssertTrue(card.recentMessages.isEmpty)
        guard case .manual(let queuedManualItem) = model.queueItems[1] else {
            return XCTFail("Expected manual item in mixed queue.")
        }
        XCTAssertEqual(queuedManualItem.id, manualItem.id)
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

    func testSuggestionMessagesLoadOnlyAfterExpansion() throws {
        let store = try makeStore()
        try saveMessagesImport(
            store: store,
            messages: [
                testMessage(id: "ask", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 600), body: "Can you send the notes?", isFromUser: false),
                testMessage(id: "reply", sentAt: Date(timeIntervalSince1970: 1_800_000_000 - 300), body: "I can send them tonight.", isFromUser: true)
            ]
        )
        _ = try store.upsertSuggestions([
            testDraft(messageId: "message-apple-ask")
        ])

        let model = makeModel(store: store)
        model.refresh()

        XCTAssertEqual(model.suggestionCards.count, 1)
        XCTAssertTrue(try XCTUnwrap(model.suggestionCards.first).recentMessages.isEmpty)
        let queueItem = try XCTUnwrap(model.queueItems.first)
        guard case .suggestion(let collapsedCard) = queueItem else {
            return XCTFail("Expected suggestion queue item.")
        }
        XCTAssertFalse(collapsedCard.isExpanded)
        XCTAssertTrue(collapsedCard.recentMessages.isEmpty)

        model.toggleExpanded(queueItem)

        guard case .suggestion(let expandedCard) = try XCTUnwrap(model.queueItems.first) else {
            return XCTFail("Expected expanded suggestion queue item.")
        }
        XCTAssertTrue(expandedCard.isExpanded)
        XCTAssertEqual(expandedCard.recentMessages.map(\.externalId), ["ask", "reply"])
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

private func testDraft(messageId: String) -> SuggestionDraft {
    SuggestionDraft(
        type: .unansweredQuestion,
        title: "Reply to Avery",
        actionText: "Send the notes.",
        confidence: 0.84,
        sourceId: "apple",
        threadId: "thread-1",
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
    private(set) var importCallCount = 0

    init(result: ImportResult) {
        self.result = result
    }

    func importRecent(into store: MinderStore, since cutoff: Date) async throws -> ImportResult {
        importCallCount += 1
        return result
    }

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
}
