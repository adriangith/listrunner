import Foundation

struct IngredientSearchContext: Equatable {
    let countryCode: String?
    let enabled: Bool

    static let unchanged = IngredientSearchContext(countryCode: nil, enabled: false)
}

struct RegionalIngredientNames: Codable {
    struct Entry: Codable {
        let ingredientID: String
        let sourceNames: [String]
        let countryNames: [String: String]
    }

    let version: Int
    let entries: [Entry]
    static let supportedCountries: Set<String> = ["AU", "NZ", "GB", "US"]

    init(data: Data, dictionary: IngredientDictionary) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        guard version == 1 else { throw ValidationError.invalidVersion }
        var ids = Set<String>()
        var sources = Set<String>()
        // Regional rewriting must not inherit every broad parser alias. All
        // selected sources and targets must belong to this exact ingredient.
        let owners = dictionary.ingredients.reduce(into: [String: Set<String>]()) { result, entry in
            for term in [entry.name] + entry.aliases {
                result[Self.key(term), default: []].insert(entry.id)
            }
        }
        for entry in entries {
            guard ids.insert(entry.ingredientID).inserted, !entry.sourceNames.isEmpty,
                  !entry.countryNames.isEmpty else { throw ValidationError.invalidEntry }
            for source in entry.sourceNames {
                let key = Self.key(source)
                guard !key.isEmpty, owners[key] == [entry.ingredientID], sources.insert(key).inserted else {
                    throw ValidationError.invalidEntry
                }
            }
            for (country, target) in entry.countryNames {
                guard Self.supportedCountries.contains(country),
                      entry.sourceNames.contains(where: { Self.key($0) == Self.key(target) }) else {
                    throw ValidationError.invalidEntry
                }
            }
        }
    }

    static func key(_ text: String) -> String {
        IngredientDictionary.normalize(text).folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
    }

    enum ValidationError: Error { case invalidVersion, invalidEntry }
}

/// Search-only adaptation. Never rebuild a query from the parser's display
/// result: doing so could drop qualifiers, quantities or unknown source words.
struct RegionalIngredientSearchResolver {
    struct Resolution: Equatable {
        let query: String
        let ingredientID: String?
    }

    let dictionary: IngredientDictionary?
    let catalogue: RegionalIngredientNames?

    static let application: RegionalIngredientSearchResolver = {
        let dictionary = IngredientParser.application.dictionary
        let catalogue = dictionary.flatMap { dictionary in
            Bundle.main.url(forResource: "ingredient-regional-names", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? RegionalIngredientNames(data: $0, dictionary: dictionary) }
        }
        return RegionalIngredientSearchResolver(dictionary: dictionary, catalogue: catalogue)
    }()

    private struct Match {
        let ingredientID: String
        let range: Range<String.Index>
    }

    func resolve(_ source: String, context: IngredientSearchContext) -> Resolution {
        let unchanged = Resolution(query: source, ingredientID: nil)
        guard context.enabled, let country = context.countryCode,
              RegionalIngredientNames.supportedCountries.contains(country),
              let dictionary, let catalogue else { return unchanged }

        // Search every dictionary term, not just mapped names, so a longer
        // compound or a second ingredient blocks a misleading short match.
        var matches: [Match] = []
        for entry in dictionary.ingredients {
            for term in [entry.name] + entry.aliases {
                for range in Self.ranges(of: term, in: source) where !matches.contains(where: {
                    $0.ingredientID == entry.id && $0.range == range
                }) {
                    matches.append(Match(ingredientID: entry.id, range: range))
                }
            }
        }
        let longest = matches.filter { candidate in
            !matches.contains { other in
                other.range != candidate.range && other.range.lowerBound <= candidate.range.lowerBound
                    && other.range.upperBound >= candidate.range.upperBound
            }
        }
        guard longest.count == 1, let match = longest.first,
              let entry = catalogue.entries.first(where: { $0.ingredientID == match.ingredientID }),
              let target = entry.countryNames[country],
              entry.sourceNames.contains(where: {
                  RegionalIngredientNames.key($0) == RegionalIngredientNames.key(String(source[match.range]))
              }) else { return unchanged }

        // Only explicitly safe descriptors may surround an ingredient. Unknown
        // brands, sauces, seeds, recipes, alternatives and conjunctions are not
        // assumed equivalent to the raw ingredient.
        let contextText = String(source[..<match.range.lowerBound]) + " " + String(source[match.range.upperBound...])
        let safeWords: Set<String> = ["fresh", "frozen", "organic", "red", "green", "yellow", "orange",
                                      "small", "medium", "large", "baby", "whole", "gluten-free"]
        let words = contextText.lowercased().split { $0.isWhitespace || "()[]".contains($0) }
        guard words.allSatisfy({ safeWords.contains(String($0)) }) else { return unchanged }

        var query = source
        query.replaceSubrange(match.range, with: target)
        return Resolution(query: query, ingredientID: match.ingredientID)
    }

    private static func ranges(of term: String, in source: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = source.startIndex
        while start < source.endIndex,
              let range = source.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: start..<source.endIndex) {
            let leftOK = range.lowerBound == source.startIndex || !isWord(source[source.index(before: range.lowerBound)])
            let rightOK = range.upperBound == source.endIndex || !isWord(source[range.upperBound])
            if leftOK && rightOK { result.append(range) }
            start = range.upperBound
        }
        return result
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}
