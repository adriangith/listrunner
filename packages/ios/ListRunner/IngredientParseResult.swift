import Foundation

struct ParsedGrocery {
    var name: String
    var amount: Double?
    var unit: String?
    var parseResult: IngredientParseResult? = nil

    // Manual entry only separates products; ingredient/quantity interpretation
    // belongs to imports. Preserve each product's wording after trimming edges.
    static func productEntries(in text: String) -> [ParsedGrocery] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",;\t")))
            .compactMap { segment in
                let name = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return ParsedGrocery(name: name, amount: nil, unit: nil)
            }
    }
}

struct IngredientParseResult: Codable, Equatable {
    enum Disposition: String, Codable { case recognized, partial, unknown, ambiguous }
    struct Range: Codable, Equatable { let location: Int; let length: Int }

    let originalText: String
    let ingredientID: String?
    let ingredientRange: Range?
    let displayName: String
    let searchTerm: String
    let quantity: GroceryQuantity
    let omittedPreparation: [String]
    let unmatchedText: [String]
    let parserVersion: Int
    let dictionaryVersion: Int?
    let disposition: Disposition
    let explanation: [String]

    var grocery: ParsedGrocery {
        var projected = projectedGrocery
        projected.parseResult = self
        return projected
    }

    private var projectedGrocery: ParsedGrocery {
        func amount(_ value: GroceryRational?) -> Double? {
            value.map { Double($0.numerator) / Double($0.denominator) }
        }

        switch quantity {
        case .unspecified:
            return ParsedGrocery(name: displayName, amount: nil, unit: nil)
        case .count(let value):
            return ParsedGrocery(name: displayName, amount: amount(value), unit: nil)
        case .measure(let value, let unit):
            let numericAmount = amount(value)
            let displayUnit = unit == "cup" && (numericAmount ?? 0) > 1 ? "cups" : unit
            return ParsedGrocery(name: displayName, amount: numericAmount, unit: displayUnit)
        case .packages(let count, let size, let sizeUnit, let container):
            let numericCount = amount(count)
            let sizeDescription = size.map { value in
                let formatted = value.denominator == 1 ? value.description : formatGroceryAmount(Double(value.numerator) / Double(value.denominator))
                return [formatted, sizeUnit].compactMap { $0 }.joined(separator: " ")
            }
            let displayedContainer = container.map { value in
                if value == "box", (numericCount ?? 0) > 1 { return "boxes" }
                return numericCount.map { $0 > 1 } == true && !value.hasSuffix("s") ? value + "s" : value
            }
            let packageDescription = [sizeDescription, displayedContainer].compactMap { $0 }.joined(separator: " ")
            let unit = packageDescription.isEmpty ? nil : packageDescription
            return ParsedGrocery(name: displayName, amount: numericCount, unit: unit)
        }
    }
}
