import Foundation

/// A user-facing validation message for one field.
struct FieldError: Error, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

enum TextRules {
    /// Trims outer whitespace and collapses inner whitespace runs into one space.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Comparison key for names: cleaned and case-insensitive.
    static func nameKey(_ text: String) -> String {
        clean(text).folding(options: [.caseInsensitive], locale: nil)
    }

    /// Optional note: trimmed, nil when empty.
    static func cleanNote(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func validateRequired(_ text: String, field: String, range: ClosedRange<Int>) -> FieldError? {
        let cleaned = clean(text)
        if cleaned.isEmpty { return FieldError("Enter \(field.lowercased()).") }
        if cleaned.count > range.upperBound { return FieldError("\(field) can be up to \(range.upperBound) characters.") }
        if cleaned.count < range.lowerBound { return FieldError("\(field) is too short.") }
        return nil
    }

    static func validateNote(_ text: String?, maxLength: Int) -> FieldError? {
        guard let note = cleanNote(text) else { return nil }
        return note.count > maxLength ? FieldError("Note can be up to \(maxLength) characters.") : nil
    }

    /// Initials for avatars: first letters of the first two words.
    static func initials(_ name: String) -> String {
        let words = clean(name).split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

enum PersonRules {
    static func validateName(_ name: String, eventPeople: [Person], editingID: UUID?) -> FieldError? {
        if let error = TextRules.validateRequired(name, field: "Name", range: DomainLimits.personNameLength) {
            return error
        }
        let key = TextRules.nameKey(name)
        let duplicate = eventPeople.contains { $0.id != editingID && TextRules.nameKey($0.name) == key }
        return duplicate ? FieldError("Someone in this event already has this name.") : nil
    }
}
