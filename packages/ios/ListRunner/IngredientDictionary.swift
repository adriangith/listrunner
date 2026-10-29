import Foundation

struct IngredientDictionary: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: String
        let name: String
        let aliases: [String]
        let modifiers: [String]
    }

    let version: Int
    let ingredients: [Entry]

    init(data: Data) throws {
        self = try JSONDecoder().decode(IngredientDictionary.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        ingredients = try container.decode([Entry].self, forKey: .ingredients)
        do {
            try validate()
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .ingredients, in: container,
                debugDescription: "Ingredient dictionary validation failed: \(error)")
        }
    }

    private enum CodingKeys: String, CodingKey { case version, ingredients }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(ingredients, forKey: .ingredients)
    }

    func validate() throws {
        guard version > 0 else { throw DictionaryError.invalidVersion }
        var ids = Set<String>()
        var aliases: [String: String] = [:]
        for item in ingredients {
            guard !item.id.isEmpty, !item.name.isEmpty, ids.insert(item.id).inserted else {
                throw DictionaryError.invalidEntry
            }
            for term in [item.name] + item.aliases {
                let key = Self.normalize(term)
                guard !key.isEmpty else { throw DictionaryError.invalidEntry }
                if let owner = aliases[key], owner != item.id { throw DictionaryError.ambiguousAlias(key) }
                aliases[key] = item.id
            }
            var modifiers = Set<String>()
            for modifier in item.modifiers {
                let key = Self.normalize(modifier)
                guard !key.isEmpty, modifiers.insert(key).inserted else {
                    throw DictionaryError.invalidModifier(item.id)
                }
            }
        }
    }

    static func loadOrNil(_ data: Data) -> IngredientDictionary? {
        try? IngredientDictionary(data: data)
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    enum DictionaryError: Error { case invalidVersion, invalidEntry, ambiguousAlias(String), invalidModifier(String) }
}
