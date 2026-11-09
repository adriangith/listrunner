import Foundation

struct IngredientParser {
    let dictionary: IngredientDictionary?
    static let version = 1

    static let application = IngredientParser(dictionary: {
        guard let url = Bundle.main.url(forResource: "ingredients", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return IngredientDictionary.loadOrNil(data)
    }())

    private struct Match { let entry: IngredientDictionary.Entry; let range: Range<String.Index>; let term: String }
    private struct UnknownParse { let name: String; let quantity: GroceryQuantity }
    private let units: [String: String] = [
        "g":"g", "gram":"g", "grams":"g", "kg":"kg", "ml":"ml", "l":"l", "litre":"l", "litres":"l",
        "oz":"oz", "ounce":"oz", "ounces":"oz", "lb":"lb", "lbs":"lb", "cup":"cup", "cups":"cup",
        "tbsp":"tbsp", "tbs":"tbsp", "tablespoon":"tbsp", "tablespoons":"tbsp", "tsp":"tsp", "teaspoon":"tsp", "teaspoons":"tsp"
    ]
    private let containers: Set<String> = ["can", "cans", "tin", "tins", "bottle", "bottles", "jar", "jars", "pack", "packs", "packet", "packets", "carton", "cartons", "bag", "bags", "bunch", "bunches", "box", "boxes"]
    private let countedUnits: Set<String> = ["clove", "cloves", "spear", "spears", "stalk", "stalks", "piece", "pieces", "sprig", "sprigs"]
    private let preparations = [
        "woody ends trimmed", "halved lengthways", "ends trimmed", "stems removed and cut into thirds",
        "peeled and diced", "peeled and sliced", "thinly sliced", "finely chopped", "roughly chopped",
        "drained and rinsed", "rinsed and drained", "whisked", "beaten", "divided", "melted", "softened",
        "thawed and squeezed dry", "thawed and drained", "squeezed dry", "thawed",
        "at room temperature", "to taste", "minced", "diced"
    ]

    func parseRecord(_ text: String) -> IngredientParseResult? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        var clean = original.replacingOccurrences(of: #"^[\s•·\-–—]+"#, with: "", options: .regularExpression)
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var removed: [String] = []
        let betweenQuantityAndNamePreparation = try! NSRegularExpression(pattern: #"(?i)\bcooked\s+and\s+chilled\b"#)
        let preparationRange = NSRange(clean.startIndex..., in: clean)
        if let match = betweenQuantityAndNamePreparation.firstMatch(in: clean, range: preparationRange),
           let range = Range(match.range, in: clean) {
            removed.append(String(clean[range]))
            clean.replaceSubrange(range, with: " ")
            clean = clean.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        let (matchResult, isAmbiguous) = resolve(in: clean)
        let unknownParse = matchResult == nil ? parseUnknown(clean) : nil
        var remaining = clean
        for note in preparations {
            let regex = try! NSRegularExpression(pattern: #"(?i)(?:,?\s+)"# + NSRegularExpression.escapedPattern(for: note) + #"\b.*$"#)
            if let m = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
               let r = Range(m.range, in: remaining),
               matchResult.map({ r.lowerBound >= $0.range.upperBound }) ?? true {
                removed.append(String(remaining[r]).trimmingCharacters(in: CharacterSet(charactersIn: ", ")))
                remaining.removeSubrange(r)
            }
        }

        let target = matchResult.map { $0.entry.name } ?? unknownParse?.name ?? remaining
        let quantity = matchResult.map { parseQuantity(in: remaining, match: $0) } ?? unknownParse?.quantity ?? .unspecified
        let name = matchResult.map { displayName(for: $0, in: remaining) } ?? target.trimmingCharacters(in: .whitespacesAndNewlines)
        let unmatched: [String]
        if let match = matchResult {
            let before = String(remaining[..<match.range.lowerBound])
            let after = String(remaining[match.range.upperBound...])
            let withoutParentheticalNotes = after.replacingOccurrences(of: #"\([^()]*\)"#, with: " ", options: .regularExpression)
            let unmatchedSource = before + " " + withoutParentheticalNotes
            let modifierWords = Set(match.entry.modifiers.flatMap { $0.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) })
            unmatched = unmatchedSource.split(whereSeparator: \.isWhitespace)
                .map(String.init).filter { token in
                    let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[],")).lowercased()
                    return !isQuantityToken(normalized) && quantityPattern(normalized) == nil && !modifierWords.contains(normalized)
                }
        } else {
            unmatched = []
        }
        return IngredientParseResult(originalText: original, ingredientID: matchResult?.entry.id,
            ingredientRange: matchResult.map { .init(location: clean.distance(from: clean.startIndex, to: $0.range.lowerBound), length: $0.term.count) },
            displayName: name, searchTerm: name, quantity: quantity, omittedPreparation: removed,
            unmatchedText: unmatched, parserVersion: Self.version, dictionaryVersion: dictionary?.version,
            disposition: isAmbiguous ? .ambiguous : (matchResult == nil ? .unknown : (unmatched.isEmpty ? .recognized : .partial)),
            explanation: matchResult.map { ["matched \($0.term) → \($0.entry.name)"] } ?? ["no dictionary match; preserved source wording"])
    }

    func parseList(_ text: String) -> [IngredientParseResult] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";\t")))
            .flatMap { line -> [IngredientParseResult] in
                let parts = line.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
                guard parts.count > 1, parts.allSatisfy({ bestMatch(in: $0) != nil }) else { return parseRecord(line).map { [$0] } ?? [] }
                return parts.compactMap(parseRecord)
            }
    }

    func parseGroceries(_ text: String) -> [ParsedGrocery] {
        parseList(text).map(\.grocery)
    }

    private func bestMatch(in text: String) -> Match? {
        resolve(in: text).0
    }

    private func resolve(in text: String) -> (Match?, Bool) {
        guard let dictionary else { return (nil, false) }
        let candidates = dictionary.ingredients.flatMap { entry in
            ([entry.name] + entry.aliases).compactMap { term -> Match? in
                guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]),
                      isBoundary(text, range.lowerBound, before: true), isBoundary(text, range.upperBound, before: false) else { return nil }
                return Match(entry: entry, range: range, term: term)
            }
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.term.count != rhs.term.count { return lhs.term.count > rhs.term.count }
            if lhs.entry.name == lhs.term && rhs.entry.name != rhs.term { return true }
            return lhs.entry.id < rhs.entry.id
        }
        var independent: [Match] = []
        for candidate in sorted where !independent.contains(where: { $0.range.overlaps(candidate.range) }) {
            independent.append(candidate)
        }
        guard independent.count <= 1 else { return (nil, true) }
        return (independent.first, false)
    }

    private func isBoundary(_ text: String, _ index: String.Index, before: Bool) -> Bool {
        if before {
            guard index > text.startIndex else { return true }
            return !text[text.index(before: index)].isLetter && !text[text.index(before: index)].isNumber
        }
        guard index < text.endIndex else { return true }
        return !text[index].isLetter && !text[index].isNumber
    }

    private func parseQuantity(in text: String, match: Match?) -> GroceryQuantity {
        let prefix = match.map { String(text[..<$0.range.lowerBound]).trimmingCharacters(in: .whitespaces) } ?? ""
        let suffix = match.map { String(text[$0.range.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
        let sides = [prefix, suffix].filter { !$0.isEmpty }.map { side in
            var normalized = side
            for modifier in match?.entry.modifiers ?? [] {
                normalized = normalized.replacingOccurrences(of: #"(?i)\b"# + NSRegularExpression.escapedPattern(for: modifier) + #"\b"#, with: " ", options: .regularExpression)
            }
            normalized = normalized.replacingOccurrences(of: #"(?i)\bfreshly grated\b"#, with: " ", options: .regularExpression)
            normalized = removingParentheticalQuantities(from: normalized)
            return normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        for side in sides {
            if let q = quantityPattern(side) { return q }
        }
        return .unspecified
    }

    private func displayName(for match: Match, in text: String) -> String {
        let modifiers = match.entry.modifiers.compactMap { modifier -> (String, String.Index)? in
            guard let range = text.range(of: modifier, options: [.caseInsensitive, .diacriticInsensitive]),
                  isBoundary(text, range.lowerBound, before: true), isBoundary(text, range.upperBound, before: false) else { return nil }
            return (modifier, range.lowerBound)
        }
        let base: String
        if let modifier = modifiers.sorted(by: {
            $0.1 == $1.1 ? $0.0.count > $1.0.count : $0.1 < $1.1
        }).first {
            let capitalized = modifier.0.prefix(1).uppercased() + modifier.0.dropFirst()
            let lowerName = match.entry.name.prefix(1).lowercased() + match.entry.name.dropFirst()
            base = modifier.1 < match.range.lowerBound ? "\(capitalized) \(lowerName)" : "\(match.entry.name) \(modifier.0)"
        } else {
            base = match.entry.name
        }

        let suffix = String(text[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard let noteRange = suffix.range(of: #"\([^()]*\)\s*$"#, options: .regularExpression) else { return base }
        let note = String(suffix[noteRange]).trimmingCharacters(in: .whitespaces)
        let noteContents = String(note.dropFirst().dropLast())
        return quantityPattern(noteContents) == nil ? "\(base) \(note)" : base
    }

    private func quantityPattern(_ source: String) -> GroceryQuantity? {
        let text = source.replacingOccurrences(of: #"[(),]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let package = captures(text, #"^(\d+)\s*[x×]\s*(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*(oz|ounce|ounces|g|kg|ml|l)\s*(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)$"#),
           let unit = units[package[2].lowercased()] {
            return .packages(count: rational(package[0]), size: rational(package[1]), sizeUnit: unit, container: singularContainer(package[3]))
        }
        if let package = captures(text, #"^(\d+)\s+(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)\s+(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*(oz|ounce|ounces|g|kg|ml|l)$"#),
           let unit = units[package[3].lowercased()] {
            return .packages(count: rational(package[0]), size: rational(package[2]), sizeUnit: unit, container: singularContainer(package[1]))
        }
        if let package = captures(text, #"^(?:(\d+)\s+)?(?:(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*(oz|ounce|ounces|g|kg|ml|l))?\s*(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)$"#),
           let container = package[3].isEmpty ? nil : package[3].lowercased() {
            return .packages(count: package[0].isEmpty ? nil : rational(package[0]), size: package[1].isEmpty ? nil : rational(package[1]), sizeUnit: package[2].isEmpty ? nil : units[package[2].lowercased()], container: singularContainer(container))
        }
        let number = #"(?:\d+\s+)?\d+\s*/\s*\d+|\d*[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+(?:\.\d+)?"#
        if let measure = captures(text, #"^("# + number + #")?\s*(g|grams?|kg|ml|l|litres?|oz|ounces?|lb|lbs|cups?|tbsp|tbs|tablespoons?|tsp|teaspoons?)$"#),
           let unit = units[measure[1].lowercased()] {
            return .measure(amount: measure[0].isEmpty ? nil : rational(measure[0]), unit: unit)
        }
        if let compact = captures(text, #"^((?:\d+\s+)?\d+\s*/\s*\d+|\d+(?:\.\d+)?|[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])(g|kg|ml|l|oz)$"#), let unit = units[compact[1].lowercased()] {
            return .measure(amount: rational(compact[0]), unit: unit)
        }
        if let counted = captures(text, #"^(\d+)\s+(cloves?|spears?|stalks?|pieces?|sprigs?)$"#),
           let amount = rational(counted[0]) { return .count(amount) }
        if let count = captures(text, #"^(\d+)$"#), let value = rational(count[0]) { return .count(value) }
        let leadingNumber = #"(?:\d+\s+)?\d+\s*/\s*\d+|\d*[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+(?:\.\d+)?"#
        let leadingMeasure = #"^((?:"# + leadingNumber + #")\s*(?:g|grams?|kg|ml|l|litres?|oz|ounces?|lb|lbs|cups?|tbsp|tbs|tablespoons?|tsp|teaspoons?))(?=\s|$)"#
        if let leading = captures(text, leadingMeasure), let quantity = quantityPattern(leading[0]) { return quantity }
        return nil
    }

    private func removingParentheticalQuantities(from source: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\([^()]+\)"#)
        let fullRange = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: fullRange)
        var result = source
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let originalRange = Range(match.range, in: source) else { continue }
            let contents = String(source[originalRange].dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            let preceding = String(source[..<originalRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let trailing = String(source[originalRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let isPackageSize = captures(trailing, #"^(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)\b"#) != nil
                || captures(preceding, #"\b(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)$"#) != nil
            if !isPackageSize && quantityPattern(contents) != nil { result.replaceSubrange(range, with: " ") }
        }
        return result
    }

    private func parseUnknown(_ source: String) -> UnknownParse? {
        let packagePattern = #"^(\d+)\s+(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)\s+(.+)$"#
        if let c = captures(source, packagePattern), let count = rational(c[0]) {
            return UnknownParse(name: cleanUnknown(c[2]), quantity: .packages(count: count, size: nil, sizeUnit: nil, container: singularContainer(c[1])))
        }
        let number = #"(?:\d+\s+)?\d+\s*/\s*\d+|\d*[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+(?:\.\d+)?"#
        let unitPattern = #"^("# + number + #")\s*(g|grams?|kg|ml|l|litres?|oz|ounces?|lb|lbs|cups?|tbsp|tbs|tablespoons?|tsp|teaspoons?)\s+(.+)$"#
        if let c = captures(source, unitPattern), let amount = rational(c[0]), let unit = units[c[1].lowercased()] {
            return UnknownParse(name: cleanUnknown(c[2]), quantity: .measure(amount: amount, unit: unit))
        }
        return nil
    }

    private func cleanUnknown(_ value: String) -> String {
        var name = value
        for note in preparations {
            name = name.replacingOccurrences(of: #"(?i)\s*,?\s*"# + NSRegularExpression.escapedPattern(for: note) + #"\b.*$"#, with: "", options: .regularExpression)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rational(_ text: String) -> GroceryRational? {
        let fractions: [Character: (Int64, Int64)] = ["½":(1,2), "⅓":(1,3), "⅔":(2,3), "¼":(1,4), "¾":(3,4), "⅕":(1,5), "⅖":(2,5), "⅗":(3,5), "⅘":(4,5), "⅙":(1,6), "⅚":(5,6), "⅛":(1,8), "⅜":(3,8), "⅝":(5,8), "⅞":(7,8)]
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.count == 1, let pair = fractions[value.first!] { return GroceryRational(pair.0, pair.1) }
        if let last = value.last, let pair = fractions[last], value.count > 1,
           let whole = Int64(value.dropLast()) {
            let (scaled, overflow1) = whole.multipliedReportingOverflow(by: pair.1)
            let (sum, overflow2) = scaled.addingReportingOverflow(pair.0)
            guard !overflow1, !overflow2 else { return nil }
            return GroceryRational(sum, pair.1)
        }
        if let space = value.firstIndex(of: " "), let whole = Int64(value[..<space]), let fractional = rational(String(value[value.index(after: space)...])) {
            let (scaledWhole, overflow1) = whole.multipliedReportingOverflow(by: fractional.denominator)
            let (sum, overflow2) = scaledWhole.addingReportingOverflow(fractional.numerator)
            guard !overflow1, !overflow2 else { return nil }
            return GroceryRational(sum, fractional.denominator)
        }
        if let slash = value.firstIndex(of: "/"), let n = Int64(value[..<slash].trimmingCharacters(in: .whitespaces)), let d = Int64(value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)) { return GroceryRational(n, d) }
        if let integer = Int64(value) { return GroceryRational(integer) }
        guard let dot = value.firstIndex(of: "."), let whole = Int64(value[..<dot]), let fraction = Int64(value[value.index(after: dot)...]) else { return nil }
        let digits = value.distance(from: value.index(after: dot), to: value.endIndex)
        guard digits <= 9 else { return nil }
        let denominator = Int64(pow(10.0, Double(digits)))
        let (scaled, overflow1) = whole.multipliedReportingOverflow(by: denominator)
        let (sum, overflow2) = scaled.addingReportingOverflow(fraction)
        guard !overflow1, !overflow2 else { return nil }
        return GroceryRational(sum, denominator)
    }

    private func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }

    private func singularContainer(_ source: String) -> String {
        let value = source.lowercased()
        let plurals = ["cans":"can", "tins":"tin", "bottles":"bottle", "jars":"jar", "packs":"pack", "packets":"packet", "cartons":"carton", "bags":"bag", "bunches":"bunch", "boxes":"box"]
        return plurals[value] ?? value
    }

    private func isQuantityToken(_ token: String) -> Bool {
        Int(token) != nil || rational(token) != nil || units[token.lowercased()] != nil
            || containers.contains(token.lowercased()) || countedUnits.contains(token.lowercased())
    }
}
