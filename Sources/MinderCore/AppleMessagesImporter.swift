import CSQLite
import Foundation

public struct AppleMessagesSchemaValidation: Equatable {
    public var missingItems: [String]

    public init(missingItems: [String]) {
        self.missingItems = missingItems
    }

    public var isCompatible: Bool {
        missingItems.isEmpty
    }
}

public enum AppleMessagesImportError: Error, LocalizedError, Equatable {
    case databaseMissing(URL)
    case databaseOpenFailed(String)
    case incompatibleSchema([String])

    public var errorDescription: String? {
        switch self {
        case .databaseMissing(let url):
            return "The Apple Messages database was not found at \(url.path)."
        case .databaseOpenFailed(let message):
            return "Loop could not open the Apple Messages database read-only: \(message)"
        case .incompatibleSchema(let missing):
            return "The Apple Messages database schema is missing: \(missing.joined(separator: ", "))."
        }
    }
}

public struct AppleMessagesTextDiagnostics: Equatable {
    public var checkedSince: Date
    public var outgoingWithPlainText: Int
    public var outgoingWithoutPlainText: Int
    public var outgoingWithAttributedBody: Int
    public var outgoingWithoutPlainTextWithAttributedBody: Int
    public var attachmentRows: Int
    public var visibleNonTextRows: Int

    public init(
        checkedSince: Date,
        outgoingWithPlainText: Int,
        outgoingWithoutPlainText: Int,
        outgoingWithAttributedBody: Int,
        outgoingWithoutPlainTextWithAttributedBody: Int,
        attachmentRows: Int,
        visibleNonTextRows: Int
    ) {
        self.checkedSince = checkedSince
        self.outgoingWithPlainText = outgoingWithPlainText
        self.outgoingWithoutPlainText = outgoingWithoutPlainText
        self.outgoingWithAttributedBody = outgoingWithAttributedBody
        self.outgoingWithoutPlainTextWithAttributedBody = outgoingWithoutPlainTextWithAttributedBody
        self.attachmentRows = attachmentRows
        self.visibleNonTextRows = visibleNonTextRows
    }
}

public enum AppleMessagesSchemaValidator {
    public static func validate(databaseURL: URL) throws -> AppleMessagesSchemaValidation {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw AppleMessagesImportError.databaseMissing(databaseURL)
        }

        let database = try SQLiteReadOnlyDatabase(url: databaseURL)
        let required: [String: Set<String>] = [
            "message": ["guid", "text", "date", "is_from_me", "handle_id"],
            "chat": ["display_name", "guid"],
            "chat_message_join": ["chat_id", "message_id"],
            "handle": ["id"]
        ]

        var missing: [String] = []
        for (table, columns) in required.sorted(by: { $0.key < $1.key }) {
            let available = try database.tableColumns(table)
            if available.isEmpty {
                missing.append("\(table) table")
                continue
            }
            for column in columns.sorted() where !available.contains(column) {
                missing.append("\(table).\(column)")
            }
        }

        return AppleMessagesSchemaValidation(missingItems: missing)
    }
}

public final class AppleMessagesConversationImporter: ConversationImporting {
    public let sourceKind: SourceKind = .appleMessages
    public let sourceName = "Apple Messages"

    private let databaseURL: URL
    private let maxMessages: Int
    private let contactResolver: ContactResolving

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db"),
        maxMessages: Int = 500,
        contactResolver: ContactResolving = NoOpContactResolver()
    ) {
        self.databaseURL = databaseURL
        self.maxMessages = maxMessages
        self.contactResolver = contactResolver
    }

    public static func health(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")) -> PermissionHealth {
        do {
            let validation = try AppleMessagesSchemaValidator.validate(databaseURL: databaseURL)
            if validation.isCompatible {
                return PermissionHealth(kind: .appleMessages, state: .available, detail: "Apple Messages is readable and the local schema looks compatible.")
            }
            return PermissionHealth(kind: .appleMessages, state: .degraded, detail: "Apple Messages is readable, but this schema is missing \(validation.missingItems.joined(separator: ", ")).")
        } catch AppleMessagesImportError.databaseMissing {
            return PermissionHealth(kind: .appleMessages, state: .unsupported, detail: "The local Messages database was not found on this Mac.")
        } catch {
            return PermissionHealth(kind: .appleMessages, state: .missing, detail: "Apple Messages cannot be read yet. Grant Full Disk Access, then check again.")
        }
    }

    public func importRecent(into store: MinderStore, since cutoff: Date) async throws -> ImportResult {
        try performImport(into: store, since: cutoff)
    }

    public func textDiagnostics(since cutoff: Date) throws -> AppleMessagesTextDiagnostics {
        let validation = try AppleMessagesSchemaValidator.validate(databaseURL: databaseURL)
        guard validation.isCompatible else {
            throw AppleMessagesImportError.incompatibleSchema(validation.missingItems)
        }

        let database = try SQLiteReadOnlyDatabase(url: databaseURL)
        let importSchema = try AppleMessagesImportSchema(database: database)
        let rows = try database.query(
            diagnosticsSQL(schema: importSchema),
            [.int(Int(AppleMessagesDateCodec.messageDateValue(from: cutoff)))]
        )
        let row = rows.first ?? [:]
        return AppleMessagesTextDiagnostics(
            checkedSince: cutoff,
            outgoingWithPlainText: diagnosticInt(row, "outgoing_with_plain_text"),
            outgoingWithoutPlainText: diagnosticInt(row, "outgoing_without_plain_text"),
            outgoingWithAttributedBody: diagnosticInt(row, "outgoing_with_attributed_body"),
            outgoingWithoutPlainTextWithAttributedBody: diagnosticInt(row, "outgoing_without_plain_text_with_attributed_body"),
            attachmentRows: diagnosticInt(row, "attachment_rows"),
            visibleNonTextRows: diagnosticInt(row, "visible_non_text_rows")
        )
    }

    func performImport(into store: MinderStore, since cutoff: Date) throws -> ImportResult {
        let validation = try AppleMessagesSchemaValidator.validate(databaseURL: databaseURL)
        guard validation.isCompatible else {
            throw AppleMessagesImportError.incompatibleSchema(validation.missingItems)
        }

        let database = try SQLiteReadOnlyDatabase(url: databaseURL)
        let importSchema = try AppleMessagesImportSchema(database: database)
        let rows = try database.query(
            importSQL(schema: importSchema),
            [
                .int(Int(AppleMessagesDateCodec.messageDateValue(from: cutoff))),
                .int(maxMessages)
            ]
        )

        let sourceId = ImportIDs.sourceID(for: .appleMessages)
        var threadBuilders: [String: AppleMessagesThreadBuilder] = [:]
        var messages: [Message] = []

        for row in rows {
            guard
                let chatGUID = row["chat_guid"] ?? nil,
                let rawDate = row["date_value"] ?? nil,
                let dateValue = Int64(rawDate)
            else {
                continue
            }

            let threadId = ImportIDs.stableID(prefix: "thread", sourceId: sourceId, externalId: chatGUID)
            let messageGUID = (row["message_guid"] ?? nil)?.nilIfEmpty
            let rowID = (row["message_rowid"] ?? nil) ?? UUID().uuidString
            let externalMessageId = messageGUID ?? "\(rowID)-\(rawDate)"
            let sentAt = AppleMessagesDateCodec.date(fromMessageDateValue: dateValue)
            let isFromUser = (row["is_from_me"] ?? nil) == "1"
            guard let body = messageBody(from: row, isFromUser: isFromUser) else {
                continue
            }
            let rawHandle = (row["handle_id"] ?? nil)?.nilIfEmpty
            let senderLabel = isFromUser
                ? "Me"
                : rawHandle.flatMap { contactResolver.displayName(for: $0) } ?? rawHandle ?? "Unknown sender"

            messages.append(Message(
                id: ImportIDs.stableID(prefix: "message", sourceId: sourceId, externalId: externalMessageId),
                sourceId: sourceId,
                threadId: threadId,
                externalId: externalMessageId,
                senderLabel: senderLabel,
                sentAt: sentAt,
                body: body,
                isFromUser: isFromUser
            ))

            var builder = threadBuilders[threadId] ?? AppleMessagesThreadBuilder(
                id: threadId,
                externalId: chatGUID,
                title: (row["chat_title"] ?? nil)?.nilIfEmpty,
                participants: [],
                lastMessageAt: sentAt
            )
            if !isFromUser {
                builder.participants.insert(senderLabel)
            }
            builder.lastMessageAt = max(builder.lastMessageAt, sentAt)
            threadBuilders[threadId] = builder
        }

        let threads = threadBuilders.values.map { builder in
            ConversationThread(
                id: builder.id,
                sourceId: sourceId,
                externalId: builder.externalId,
                title: builder.resolvedTitle,
                participantLabels: Array(builder.participants).sorted(),
                lastMessageAt: builder.lastMessageAt,
                isActive: true
            )
        }

        let source = ConversationSource(
            id: sourceId,
            name: sourceName,
            kind: .appleMessages,
            health: .available,
            lastSyncAt: Date()
        )

        return try store.saveImport(source: source, threads: threads, messages: messages)
    }

    private func messageBody(from row: [String: String?], isFromUser: Bool) -> String? {
        if let body = (row["body"] ?? nil)?.collapsedWhitespace.nilIfEmpty {
            return body
        }

        if let attributedBody = AppleMessagesAttributedBodyDecoder.decodeText(fromHex: row["attributed_body_hex"] ?? nil) {
            return attributedBody
        }

        if let attachmentLabel = attachmentBody(from: row) {
            return attachmentLabel
        }

        // Some visible sent replies are stored by Messages without a plain text value.
        // A local marker is enough for ranking to know the user replied.
        if isFromUser {
            return "[Sent reply without plain text]"
        }

        if isVisibleNonTextMessage(row) {
            return "Message without plain text"
        }

        return nil
    }

    private func diagnosticInt(_ row: [String: String?], _ column: String) -> Int {
        Int((row[column] ?? nil) ?? "0") ?? 0
    }

    private func importSQL(schema: AppleMessagesImportSchema) -> String {
        """
        SELECT *
        FROM (
        SELECT
            chat.guid AS chat_guid,
            chat.display_name AS chat_title,
            message.ROWID AS message_rowid,
            message.guid AS message_guid,
            message.text AS body,
            message.date AS date_value,
            message.is_from_me AS is_from_me,
            handle.id AS handle_id,
            \(schema.attributedBodyHexSelect),
            \(schema.cacheHasAttachmentsSelect),
            \(schema.associatedMessageTypeSelect),
            \(schema.balloonBundleIDSelect),
            \(schema.attachmentSummarySelect)
        FROM message
        JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
        JOIN chat ON chat.ROWID = chat_message_join.chat_id
        LEFT JOIN handle ON handle.ROWID = message.handle_id
        \(schema.attachmentJoinSQL)
        WHERE message.date >= ?
            AND (
                (message.text IS NOT NULL AND length(trim(message.text)) > 0)
                OR message.is_from_me = 1
                OR \(schema.visibleNonTextCondition)
            )
        ORDER BY message.date DESC
        LIMIT ?
        )
        ORDER BY date_value ASC
        """
    }

    private func diagnosticsSQL(schema: AppleMessagesImportSchema) -> String {
        let textPresent = "(message.text IS NOT NULL AND length(trim(message.text)) > 0)"
        let textMissing = "(message.text IS NULL OR length(trim(message.text)) = 0)"
        return """
        SELECT
            SUM(CASE WHEN message.is_from_me = 1 AND \(textPresent) THEN 1 ELSE 0 END) AS outgoing_with_plain_text,
            SUM(CASE WHEN message.is_from_me = 1 AND \(textMissing) THEN 1 ELSE 0 END) AS outgoing_without_plain_text,
            SUM(CASE WHEN message.is_from_me = 1 AND \(schema.attributedBodyPresentCondition) THEN 1 ELSE 0 END) AS outgoing_with_attributed_body,
            SUM(CASE WHEN message.is_from_me = 1 AND \(textMissing) AND \(schema.attributedBodyPresentCondition) THEN 1 ELSE 0 END) AS outgoing_without_plain_text_with_attributed_body,
            SUM(CASE WHEN \(schema.attachmentPresentCondition) THEN 1 ELSE 0 END) AS attachment_rows,
            SUM(CASE WHEN \(schema.visibleNonTextCondition) THEN 1 ELSE 0 END) AS visible_non_text_rows
        FROM message
        \(schema.attachmentJoinSQL)
        WHERE message.date >= ?
        """
    }

    private func attachmentBody(from row: [String: String?]) -> String? {
        let summary = (row["attachment_summary"] ?? nil)?.lowercased().nilIfEmpty
        let hasAttachment = (row["cache_has_attachments"] ?? nil) == "1" || summary != nil
        guard hasAttachment else { return nil }

        guard let summary else {
            return "File attachment"
        }

        if summary.contains("image") || summary.contains("jpeg") || summary.contains("jpg") || summary.contains("png") || summary.contains("gif") || summary.contains("heic") {
            return "Image attachment"
        }
        if summary.contains("video") || summary.contains("movie") || summary.contains("mp4") || summary.contains("mov") {
            return "Video attachment"
        }
        if summary.contains("audio") || summary.contains("voice") || summary.contains("m4a") || summary.contains("caf") || summary.contains("mp3") {
            return "Audio message"
        }
        return "File attachment"
    }

    private func isVisibleNonTextMessage(_ row: [String: String?]) -> Bool {
        if
            let rawType = (row["associated_message_type"] ?? nil)?.nilIfEmpty,
            rawType != "0"
        {
            return true
        }
        if (row["balloon_bundle_id"] ?? nil)?.collapsedWhitespace.nilIfEmpty != nil {
            return true
        }
        return false
    }
}

private struct AppleMessagesImportSchema {
    var messageColumns: Set<String>
    var chatMessageJoinColumns: Set<String>
    var attachmentColumns: Set<String>

    init(database: SQLiteReadOnlyDatabase) throws {
        self.messageColumns = try database.tableColumns("message")
        self.chatMessageJoinColumns = try database.tableColumns("message_attachment_join")
        self.attachmentColumns = try database.tableColumns("attachment")
    }

    var cacheHasAttachmentsSelect: String {
        messageColumns.contains("cache_has_attachments")
            ? "message.cache_has_attachments AS cache_has_attachments"
            : "0 AS cache_has_attachments"
    }

    var associatedMessageTypeSelect: String {
        messageColumns.contains("associated_message_type")
            ? "message.associated_message_type AS associated_message_type"
            : "0 AS associated_message_type"
    }

    var balloonBundleIDSelect: String {
        messageColumns.contains("balloon_bundle_id")
            ? "message.balloon_bundle_id AS balloon_bundle_id"
            : "NULL AS balloon_bundle_id"
    }

    var attachmentSummarySelect: String {
        canJoinAttachments ? "attachment_info.attachment_summary AS attachment_summary" : "NULL AS attachment_summary"
    }

    var attributedBodyHexSelect: String {
        messageColumns.contains("attributedBody")
            ? "hex(message.attributedBody) AS attributed_body_hex"
            : "NULL AS attributed_body_hex"
    }

    var attachmentJoinSQL: String {
        guard canJoinAttachments else { return "" }
        return """
        LEFT JOIN (
            SELECT
                message_attachment_join.message_id AS joined_message_id,
                group_concat(\(attachmentDetailExpression), ' ') AS attachment_summary
            FROM message_attachment_join
            JOIN attachment ON attachment.ROWID = message_attachment_join.attachment_id
            GROUP BY message_attachment_join.message_id
        ) attachment_info ON attachment_info.joined_message_id = message.ROWID
        """
    }

    var visibleNonTextCondition: String {
        let conditions = [
            messageColumns.contains("cache_has_attachments") ? "message.cache_has_attachments = 1" : nil,
            messageColumns.contains("associated_message_type") ? "(message.associated_message_type IS NOT NULL AND message.associated_message_type != 0)" : nil,
            messageColumns.contains("balloon_bundle_id") ? "(message.balloon_bundle_id IS NOT NULL AND length(trim(message.balloon_bundle_id)) > 0)" : nil,
            canJoinAttachments ? "attachment_info.attachment_summary IS NOT NULL" : nil
        ].compactMap { $0 }

        return conditions.isEmpty ? "0" : conditions.joined(separator: " OR ")
    }

    var attributedBodyPresentCondition: String {
        messageColumns.contains("attributedBody")
            ? "(message.attributedBody IS NOT NULL AND length(message.attributedBody) > 0)"
            : "0"
    }

    var attachmentPresentCondition: String {
        let conditions = [
            messageColumns.contains("cache_has_attachments") ? "message.cache_has_attachments = 1" : nil,
            canJoinAttachments ? "attachment_info.attachment_summary IS NOT NULL" : nil
        ].compactMap { $0 }

        return conditions.isEmpty ? "0" : conditions.joined(separator: " OR ")
    }

    private var canJoinAttachments: Bool {
        chatMessageJoinColumns.contains("message_id")
            && chatMessageJoinColumns.contains("attachment_id")
            && !attachmentColumns.isEmpty
    }

    private var attachmentDetailExpression: String {
        let expressions = [
            attachmentColumns.contains("mime_type") ? "NULLIF(attachment.mime_type, '')" : nil,
            attachmentColumns.contains("uti") ? "NULLIF(attachment.uti, '')" : nil,
            attachmentColumns.contains("transfer_name") ? "NULLIF(attachment.transfer_name, '')" : nil,
            attachmentColumns.contains("filename") ? "NULLIF(attachment.filename, '')" : nil
        ].compactMap { $0 }

        if expressions.isEmpty {
            return "'attachment'"
        }
        if expressions.count == 1 {
            return expressions[0]
        }
        return "COALESCE(\(expressions.joined(separator: ", ")))"
    }
}

public enum AppleMessagesAttributedBodyDecoder {
    public static func decodeText(fromHex hex: String?) -> String? {
        guard let hex = hex?.nilIfEmpty, let data = Data(hexEncoded: hex) else {
            return nil
        }
        return decodeText(from: data)
    }

    public static func decodeText(from data: Data) -> String? {
        if let attributed = decodeArchivedObject(from: data) as? NSAttributedString {
            return attributed.string.collapsedWhitespace.nilIfEmpty
        }
        if let string = decodeArchivedObject(from: data) as? String {
            return string.collapsedWhitespace.nilIfEmpty
        }
        if let string = decodeArchivedObject(from: data) as? NSString {
            return (string as String).collapsedWhitespace.nilIfEmpty
        }
        return nil
    }

    private static func decodeArchivedObject(from data: Data) -> Any? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        } catch {
            return nil
        }
    }
}

private extension Data {
    init?(hexEncoded hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum AppleMessagesDateCodec {
    private static let appleEpochOffset: TimeInterval = 978_307_200

    public static func messageDateValue(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 - appleEpochOffset) * 1_000_000_000)
    }

    public static func date(fromMessageDateValue value: Int64) -> Date {
        let absolute = Double(value)
        if abs(absolute) > 10_000_000_000_000 {
            return Date(timeIntervalSince1970: absolute / 1_000_000_000 + appleEpochOffset)
        }
        if abs(absolute) > 10_000_000_000 {
            return Date(timeIntervalSince1970: absolute / 1_000 + appleEpochOffset)
        }
        return Date(timeIntervalSince1970: absolute + appleEpochOffset)
    }
}

private struct AppleMessagesThreadBuilder {
    var id: String
    var externalId: String
    var title: String?
    var participants: Set<String>
    var lastMessageAt: Date

    var resolvedTitle: String {
        if let title = title?.collapsedWhitespace.nilIfEmpty {
            return title
        }
        if !participants.isEmpty {
            return participants.sorted().joined(separator: ", ")
        }
        return "Messages Chat"
    }
}

final class SQLiteReadOnlyDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(database)
            throw AppleMessagesImportError.databaseOpenFailed(message)
        }
        handle = database
    }

    deinit {
        sqlite3_close(handle)
    }

    func tableColumns(_ table: String) throws -> Set<String> {
        let rows = try query("PRAGMA table_info(\(try quotedIdentifier(table)))")
        return Set(rows.compactMap { $0["name"] ?? nil })
    }

    func query(_ sql: String, _ values: [SQLiteValue] = []) throws -> [[String: String?]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }

        var rows: [[String: String?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            guard result == SQLITE_ROW else {
                throw SQLiteError.stepFailed(lastErrorMessage)
            }

            var row: [String: String?] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, column) else { continue }
                let key = String(cString: name)
                if sqlite3_column_type(statement, column) == SQLITE_NULL {
                    row[key] = nil
                } else if let text = sqlite3_column_text(statement, column) {
                    row[key] = String(cString: text)
                } else {
                    row[key] = nil
                }
            }
            rows.append(row)
        }
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .text(let string):
                result = sqlite3_bind_text(statement, position, string, -1, SQLITE_TRANSIENT)
            case .int(let int):
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(int))
            case .double(let double):
                result = sqlite3_bind_double(statement, position, double)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            }

            if result != SQLITE_OK {
                throw SQLiteError.bindFailed(lastErrorMessage)
            }
        }

        return statement
    }

    private func quotedIdentifier(_ value: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SQLiteError.prepareFailed("Invalid SQLite identifier \(value)")
        }
        return "\"\(value)\""
    }

    private var lastErrorMessage: String {
        guard let handle else { return "Database handle is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }
}
