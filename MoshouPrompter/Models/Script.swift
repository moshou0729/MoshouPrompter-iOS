import Foundation

struct Script: Codable, Equatable {
    var id: String
    var title: String
    var text: String
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String, text: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名文稿" : trimmed
    }

    var previewText: String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "（空文稿）" : trimmed
    }

    var wordCount: Int {
        return text.count
    }
}
