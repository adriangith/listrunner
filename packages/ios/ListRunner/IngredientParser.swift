import Foundation

struct IngredientParser {
    let dictionary: IngredientDictionary?
    static let version = 2

    static let application = IngredientParser(dictionary: {
        guard let url = Bundle.main.url(forResource: "ingredients", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return IngredientDictionary.loadOrNil(data)
    }())

    private struct Match { let entry: IngredientDictionary.Entry; let range: Range<String.Index>; let term: String }
    private struct QuantityExtraction { let name: String; let quantity: GroceryQuantity }
    private let units: [String: String] = [
        "g":"g", "gram":"g", "grams":"g", "kg":"kg", "ml":"ml", "l":"l", "litre":"l", "litres":"l",
        "oz":"oz", "ounce":"oz", "ounces":"oz", "lb":"lb", "lbs":"lb", "cup":"cup", "cups":"cup",
        "tbsp":"tbsp", "tbs":"tbsp", "tablespoon":"tbsp", "tablespoons":"tbsp", "tsp":"tsp", "teaspoon":"tsp", "teaspoons":"tsp"
    ]
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
        clean = normalized(clean)
        var removed: [String] = []
        let betweenQuantityAndNamePreparation = try! NSRegularExpression(pattern: #"(?i)\bcooked\s+and\s+chilled\b"#)
        let preparationRange = NSRange(clean.startIndex..., in: clean)
        if let match = betweenQuantityAndNamePreparation.firstMatch(in: clean, range: preparationRange),
           let range = Range(match.range, in: clean) {
            removed.append(String(clean[range]))
            clean.replaceSubrange(range, with: " ")
            clean = clean.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        // Strip proven recipe tails before resolving ingredients mentioned in them.
        // Leading descriptors of an unknown product are never preparation tails.
        var remaining = clean
        for note in preparations {
            let regex = try! NSRegularExpression(pattern: #"(?i)(?:,?\s+)"# + NSRegularExpression.escapedPattern(for: note) + #"\b.*$"#)
            if let m = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
               let r = Range(m.range, in: remaining),
               !String(remaining[..<r.lowerBound]).isEmpty {
                let head = String(remaining[..<r.lowerBound])
                let tail = String(remaining[r]).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                let headProduct = extractLeadingQuantity(head).name
                let fullMatch = resolve(in: remaining).0
                let overlapsIdentity = fullMatch.map { $0.range.overlaps(r) } ?? false
                let explicitClause = String(remaining[r]).trimmingCharacters(in: .whitespaces).hasPrefix(",")
                let withClause = tail.lowercased().hasPrefix(note + " with ") && resolve(in: head).0 != nil
                let preparationSequence = tail.components(separatedBy: ",").allSatisfy(isPreparationClause)
                guard !headProduct.isEmpty, quantityPattern(head) == nil, !overlapsIdentity,
                      preparationSequence || explicitClause || withClause else { continue }
                removed.append(String(remaining[r]).trimmingCharacters(in: CharacterSet(charactersIn: ", ")))
                remaining.removeSubrange(r)
            }
        }

        let extracted = extractLeadingQuantity(remaining)
        var product = extracted.name
        var quantity = extracted.quantity
        if product.lowercased().hasPrefix("freshly grated ") {
            product = String(product.dropFirst("freshly grated ".count))
        }
        var (matchResult, isAmbiguous) = resolve(in: product)
        // A suffix quantity is accepted only when the whole suffix is consumed.
        if case .unspecified = quantity, let match = matchResult {
            let suffix = String(product[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let parsed = quantityPattern(suffix) {
                quantity = parsed
                product = String(product[..<match.range.upperBound])
                (matchResult, isAmbiguous) = resolve(in: product)
            }
        }
        var unmatched: [String] = []
        var name = product
        if let match = matchResult {
            var residue = product
            let spans = [match.range] + modifierRanges(for: match, in: product).map(\.range).filter { !$0.overlaps(match.range) }
            for span in spans.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                // Overlapping modifier/alias spans are handled by modifierRanges.
                residue.replaceSubrange(span, with: " ")
            }
            residue = residue.replacingOccurrences(of: #"\([^()]*\)\s*$"#, with: " ", options: .regularExpression)
            if case .count = quantity {
                residue = residue.replacingOccurrences(of: #"(?i)^\s*(cloves?|spears?|stalks?|pieces?|sprigs?)\s*$"#, with: "", options: .regularExpression)
            }
            unmatched = residue.split(whereSeparator: \.isWhitespace).map(String.init)
            if unmatched.isEmpty {
                name = displayName(for: match, in: product)
            }
        }
        name = normalized(name)
        guard !name.isEmpty else { return nil }
        let range = matchResult.flatMap { match -> IngredientParseResult.Range? in
            // Report the actual source span, not a canonical alias's length.
            guard let productRange = clean.range(of: product) else { return nil }
            return .init(location: clean.distance(from: clean.startIndex, to: productRange.lowerBound) + product.distance(from: product.startIndex, to: match.range.lowerBound),
                         length: product.distance(from: match.range.lowerBound, to: match.range.upperBound))
        }
        return IngredientParseResult(originalText: original, ingredientID: matchResult?.entry.id,
            ingredientRange: range,
            displayName: name, searchTerm: name, quantity: quantity, omittedPreparation: removed,
            unmatchedText: unmatched, parserVersion: Self.version, dictionaryVersion: dictionary?.version,
            disposition: isAmbiguous ? .ambiguous : (matchResult == nil ? .unknown : (unmatched.isEmpty ? .recognized : .partial)),
            explanation: matchResult.map { [unmatched.isEmpty ? "matched \($0.term) → \($0.entry.name)" : "partial match; preserved product wording"] } ?? ["no unambiguous dictionary match; preserved product wording"])
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // Longest validated leading quantity span; independent of known ingredients.
    // Do not split numeric aliases (4 cheese ravioli) or numeric brand names.
    private func extractLeadingQuantity(_ text: String) -> QuantityExtraction {
        let identity = resolve(in: text).0
        let numericBrand = text.range(of: #"(?i)^7\s*up\b"#, options: .regularExpression) != nil
        guard !numericBrand else { return QuantityExtraction(name: text, quantity: .unspecified) }
        for end in text.indices.reversed() where text[end].isWhitespace {
            let prefix = String(text[..<end])
            let rest = String(text[end...]).trimmingCharacters(in: .whitespaces)
            if let identity, end > identity.range.lowerBound { continue }
            if let quantity = quantityPattern(removingParentheticalQuantities(from: prefix)) {
                // Never salvage only the count from a malformed measure/package.
                if case .count = quantity,
                   rest.range(of: #"(?i)^(?:[x×]|g|kg|ml|l|oz|cups?|cans?|boxes|packs?)\b|^[\d(]"#, options: .regularExpression) != nil { continue }
                return QuantityExtraction(name: rest, quantity: quantity)
            }
        }
        return QuantityExtraction(name: text, quantity: .unspecified)
    }

    private func isPreparationClause(_ source: String) -> Bool {
        let text = normalized(source).lowercased()
        return preparations.contains { text == $0 || text.hasPrefix($0 + " with ") }
    }

    func parseList(_ text: String) -> [IngredientParseResult] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";\t")))
            .flatMap { line -> [IngredientParseResult] in
                // Parenthetical notes may contain commas without being list syntax.
                var depth = 0
                var segments = [""]
                for character in line {
                    if character == "(" { depth += 1 }
                    if character == ")" { depth = max(0, depth - 1) }
                    if character == ",", depth == 0 { segments.append("") }
                    else { segments[segments.count - 1].append(character) }
                }
                var records: [String] = []
                for segment in segments where !normalized(segment).isEmpty {
                    if !records.isEmpty, isPreparationClause(segment) { records[records.count - 1] += "," + segment }
                    else { records.append(segment) }
                }
                return records.compactMap(parseRecord)
            }
    }

    func parseGroceries(_ text: String) -> [ParsedGrocery] {
        parseList(text).map(\.grocery)
    }

    // Direct product entry uses explicit list separators even for products
    // outside the ingredient dictionary. Keep recipe/Reminder comma handling
    // separate so preparation notes remain attached to their ingredient.
    func parseProductEntry(_ text: String) -> [ParsedGrocery] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",;\t")))
            .compactMap(parseRecord).map(\.grocery)
    }

    private func resolve(in text: String) -> (Match?, Bool) {
        guard let dictionary else { return (nil, false) }
        let candidates = dictionary.ingredients.flatMap { entry in
            ([entry.name] + entry.aliases).flatMap { term -> [Match] in
                ranges(of: term, in: text).map { Match(entry: entry, range: $0, term: term) }
            }
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.term.count != rhs.term.count { return lhs.term.count > rhs.term.count }
            if (lhs.entry.name == lhs.term) != (rhs.entry.name == rhs.term) { return lhs.entry.name == lhs.term }
            if lhs.range.lowerBound != rhs.range.lowerBound { return lhs.range.lowerBound < rhs.range.lowerBound }
            return lhs.entry.id < rhs.entry.id
        }
        var independent: [Match] = []
        for candidate in sorted where !independent.contains(where: { $0.range.overlaps(candidate.range) }) {
            independent.append(candidate)
        }
        guard Set(independent.map { $0.entry.id }).count <= 1 else { return (nil, true) }
        return (independent.first, false)
    }

    private func ranges(of term: String, in text: String) -> [Range<String.Index>] {
        var start = text.startIndex
        var result: [Range<String.Index>] = []
        while start < text.endIndex,
              let range = text.range(of: normalized(term), options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if isBoundary(text, range.lowerBound, before: true), isBoundary(text, range.upperBound, before: false) { result.append(range) }
            start = range.upperBound
        }
        return result
    }

    private func isBoundary(_ text: String, _ index: String.Index, before: Bool) -> Bool {
        if before {
            guard index > text.startIndex else { return true }
            return !text[text.index(before: index)].isLetter && !text[text.index(before: index)].isNumber
        }
        guard index < text.endIndex else { return true }
        return !text[index].isLetter && !text[index].isNumber
    }

    private func modifierRanges(for match: Match, in text: String) -> [(term: String, range: Range<String.Index>)] {
        let note = text.range(of: #"\([^()]*\)\s*$"#, options: .regularExpression)
        let candidates = match.entry.modifiers.flatMap { term in ranges(of: term, in: text).filter { range in
            !(note.map { $0.overlaps(range) } ?? false)
        }.map { (term: term, range: $0) } }
        var result: [(term: String, range: Range<String.Index>)] = []
        for candidate in candidates.sorted(by: { $0.term.count > $1.term.count }) {
            if !result.contains(where: { $0.range.overlaps(candidate.range) }) { result.append(candidate) }
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func displayName(for match: Match, in text: String) -> String {
        let modifiers = modifierRanges(for: match, in: text).filter {
            // A qualifier already present in the canonical name needs no duplication.
            ranges(of: $0.term, in: match.entry.name).isEmpty
        }
        let before = modifiers.filter { $0.range.lowerBound <= match.range.lowerBound }.map(\.term)
        let after = modifiers.filter { $0.range.lowerBound > match.range.lowerBound }.map(\.term)
        let canonical = before.isEmpty ? match.entry.name : match.entry.name.prefix(1).lowercased() + match.entry.name.dropFirst()
        var base = [before.joined(separator: " "), canonical, after.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: " ")
        base = base.prefix(1).uppercased() + base.dropFirst()

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
           let unit = units[package[2].lowercased()], let count = rational(package[0]), let size = rational(package[1]) {
            return .packages(count: count, size: size, sizeUnit: unit, container: singularContainer(package[3]))
        }
        if let package = captures(text, #"^(\d+)\s+(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)\s+(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*(oz|ounce|ounces|g|kg|ml|l)$"#),
           let unit = units[package[3].lowercased()], let count = rational(package[0]), let size = rational(package[2]) {
            return .packages(count: count, size: size, sizeUnit: unit, container: singularContainer(package[1]))
        }
        if let package = captures(text, #"^(?:(\d+)\s+)?(?:(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*(oz|ounce|ounces|g|kg|ml|l))?\s*(can|cans|tin|tins|bottle|bottles|jar|jars|pack|packs|packet|packets|carton|cartons|bag|bags|bunch|bunches|box|boxes)$"#),
           let container = package[3].isEmpty ? nil : package[3].lowercased() {
            guard package[0].isEmpty || rational(package[0]) != nil,
                  package[1].isEmpty || rational(package[1]) != nil else { return nil }
            return .packages(count: package[0].isEmpty ? nil : rational(package[0]), size: package[1].isEmpty ? nil : rational(package[1]), sizeUnit: package[2].isEmpty ? nil : units[package[2].lowercased()], container: singularContainer(container))
        }
        let number = #"(?:\d+\s+)?\d+\s*/\s*\d+|\d*[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+(?:\.\d+)?"#
        if let dozen = captures(text, #"^("# + number + #")\s+dozen$"#), let value = rational(dozen[0]) {
            return .measure(amount: value, unit: "dozen")
        }
        if let measure = captures(text, #"^("# + number + #")?\s*(g|grams?|kg|ml|l|litres?|oz|ounces?|lb|lbs|cups?|tbsp|tbs|tablespoons?|tsp|teaspoons?)$"#),
           let unit = units[measure[1].lowercased()] {
            guard measure[0].isEmpty || rational(measure[0]) != nil else { return nil }
            return .measure(amount: measure[0].isEmpty ? nil : rational(measure[0]), unit: unit)
        }
        if let compact = captures(text, #"^((?:\d+\s+)?\d+\s*/\s*\d+|\d+(?:\.\d+)?|[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])(g|kg|ml|l|oz)$"#), let unit = units[compact[1].lowercased()], let value = rational(compact[0]) {
            return .measure(amount: value, unit: unit)
        }
        if let counted = captures(text, #"^(\d+)\s+(cloves?|spears?|stalks?|pieces?|sprigs?)$"#),
           let amount = rational(counted[0]) { return .count(amount) }
        if let count = captures(text, #"^("# + number + #")\s*(?:[x×])?$"#), let value = rational(count[0]) { return .count(value) }
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

}
