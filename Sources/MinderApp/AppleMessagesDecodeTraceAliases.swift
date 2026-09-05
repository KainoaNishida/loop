#if NUDGE_INTERNAL_DIAGNOSTICS
import Foundation
import MinderCore

func appleMessagesDecodeTraceAliases(for targets: [String], store: MinderStore) -> [String: [String]] {
    do {
        let sources = try store.fetchSources()
        let appleSourceIDs = Set(sources.filter { $0.kind == .appleMessages }.map(\.id))
        let threads = try store.fetchThreads()
        var aliasesByTitle: [String: Set<String>] = [:]

        for thread in threads where appleSourceIDs.contains(thread.sourceId) || looksLikeAppleMessagesChatGUID(thread.externalId) {
            let values = uniqueAliasValues([thread.title, thread.externalId] + thread.participantLabels)
            for target in targets.map(collapsedWhitespace).filter({ !$0.isEmpty }) {
                guard values.contains(where: { aliasValue($0, matches: target) }) else {
                    continue
                }
                aliasesByTitle[target, default: []].formUnion(values)
            }
        }

        return aliasesByTitle.mapValues { $0.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    } catch {
        return [:]
    }
}

private func looksLikeAppleMessagesChatGUID(_ value: String) -> Bool {
    value.contains(";-;") || value.contains(";+;")
}

private func aliasValue(_ value: String, matches target: String) -> Bool {
    let normalizedValue = collapsedWhitespace(value).lowercased()
    let normalizedTarget = collapsedWhitespace(target).lowercased()
    guard !normalizedValue.isEmpty, !normalizedTarget.isEmpty else {
        return false
    }
    return normalizedValue == normalizedTarget || normalizedValue.contains(normalizedTarget)
}

private func uniqueAliasValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
        let collapsed = collapsedWhitespace(value)
        guard !collapsed.isEmpty else {
            return nil
        }
        let key = collapsed.lowercased()
        guard seen.insert(key).inserted else {
            return nil
        }
        return collapsed
    }
}

private func collapsedWhitespace(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
#endif
