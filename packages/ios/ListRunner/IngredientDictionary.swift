import Foundation

struct IngredientDictionary: Decodable {
    struct Entry: Decodable {
        let id: String
        let name: String
        let aliases: [String]
        let modifiers: [String]
    }

    let version: Int
    let ingredients: [Entry]

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode(IngredientDictionary.self, from: data)
        try decoded.validate()
        self = decoded
    }

    func validate() throws {
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
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    enum DictionaryError: Error { case invalidEntry, ambiguousAlias(String) }
}
