import Foundation

enum FileSearchMatcher {
    static func matches(_ item: FileItem, query: String, caseSensitive: Bool = false) -> Bool {
        let normalizedQuery = normalize(query, caseSensitive: caseSensitive)
        guard !normalizedQuery.isEmpty else { return true }

        let name = item.name
        if normalize(name, caseSensitive: caseSensitive).contains(normalizedQuery) {
            return true
        }

        let pinyin = pinyinText(for: name, caseSensitive: caseSensitive)
        if pinyin.contains(normalizedQuery) {
            return true
        }

        let compactPinyin = pinyin.filter { !$0.isWhitespace && $0 != "-" && $0 != "_" && $0 != "." }
        if compactPinyin.contains(normalizedQuery) {
            return true
        }

        return pinyinInitials(for: pinyin).contains(normalizedQuery)
    }

    private static func normalize(_ text: String, caseSensitive: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return caseSensitive ? trimmed : trimmed.localizedLowercase
    }

    private static func pinyinText(for text: String, caseSensitive: Bool) -> String {
        let mutableText = NSMutableString(string: text)
        CFStringTransform(mutableText, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableText, nil, kCFStringTransformStripCombiningMarks, false)
        return normalize(mutableText as String, caseSensitive: caseSensitive)
    }

    private static func pinyinInitials(for pinyin: String) -> String {
        pinyin
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}
