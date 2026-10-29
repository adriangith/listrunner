import Foundation
import SwiftData

enum GroceryStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case added = "Added"
    case skipped = "Skipped"
}

@Model
final class GroceryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var searchTerm: String
    var quantityAmount: Double?
    var quantityUnit: String?
    var statusRawValue: String
    var position: Int
    var listID: UUID? = nil
    var paprikaReminderID: String? = nil

    var status: GroceryStatus {
        get { GroceryStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(name: String, amount: Double? = nil, unit: String? = nil, position: Int = 0, listID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.searchTerm = name
        self.quantityAmount = amount
        self.quantityUnit = unit
        self.statusRawValue = GroceryStatus.pending.rawValue
        self.position = position
        self.listID = listID
    }

    var displayQuantity: String {
        let amount = quantityAmount.map(Self.formatAmount) ?? "1"
        return [amount, quantityUnit].compactMap { $0 }.joined(separator: " ")
    }

    private static func formatAmount(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

struct ParsedGrocery {
    var name: String
    var amount: Double?
    var unit: String?
}

enum GroceryParser {
    private static let units: Set<String> = [
        "g", "kg", "mg", "ml", "l", "oz", "lb", "lbs", "cans", "can", "tins", "tin",
        "packs", "pack", "packets", "bunches", "bunch", "bags", "bag", "bottles", "bottle",
        "dozen", "pieces", "piece", "cartons", "carton", "jars", "jar",
        "cups", "cup"
    ]

    static func parse(_ input: String) -> [ParsedGrocery] {
        input
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",;\t")))
            .compactMap(parseEntry)
    }

    private static func parseEntry(_ raw: String) -> ParsedGrocery? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^[\s•·\-–—]+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !text.isEmpty else { return nil }

        let multiplier = text.range(of: #"^(\d+(?:\.\d+)?)\s*x\s+(.+)$"#, options: [.regularExpression, .caseInsensitive])
        if let range = multiplier, let match = text[range].range(of: #"^\d+(?:\.\d+)?"#, options: .regularExpression),
           let amount = Double(text[match]) {
            let remainder = String(text[match.upperBound...]).dropFirst().trimmingCharacters(in: .whitespaces)
            return ParsedGrocery(name: String(remainder), amount: amount, unit: nil)
        }

        if let captures = captures(in: text, pattern: #"^(\d+(?:\.\d+)?)\s+(.+)$"#),
           let amount = Double(captures[0]) {
            let remainder = captures[1].trimmingCharacters(in: .whitespaces)
            let firstSpace = remainder.firstIndex(where: \.isWhitespace)
            let firstWord = firstSpace.map { String(remainder[..<$0]).lowercased() } ?? remainder.lowercased()
            if units.contains(firstWord), let firstSpace {
                let name = remainder[remainder.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return ParsedGrocery(name: name, amount: amount, unit: firstWord) }
            }
            return ParsedGrocery(name: remainder, amount: amount, unit: nil)
        }

        // Compact measure forms, e.g. 500g mince or 1.5L milk.
        if let captures = captures(in: text, pattern: #"^(\d+(?:\.\d+)?)(g|kg|mg|ml|l|oz|lbs?|cans?|tins?|packs?)\s+(.+)$"#),
           let amount = Double(captures[0]) {
            return ParsedGrocery(name: captures[2].trimmingCharacters(in: .whitespaces), amount: amount, unit: captures[1].lowercased())
        }

        return ParsedGrocery(name: text, amount: nil, unit: nil)
    }

    private static func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}

func sentenceCase(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return trimmed }
    var result = String(first).uppercased() + String(trimmed.dropFirst())
    result = result.replacingOccurrences(of: #"\bbbq\b"#, with: "BBQ", options: [.regularExpression, .caseInsensitive])
    return result
}
