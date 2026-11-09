import Foundation

// Observation-only probe. Compiles with the unmodified production parser.
@main
struct ParserAudit {
    static func main() throws {
        let dictionary = try IngredientDictionary(data: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        let parser = IngredientParser(dictionary: dictionary)
        if CommandLine.arguments.contains("--large-package") {
            let result = parser.parseRecord("1 x 9223372036854775807 g cans tomatoes")!
            print("About to project valid Int64 package size into grocery", terminator: "\n")
            fflush(stdout)
            print(result.grocery)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sources = [
            "taco shells", "12 taco shells", "pasta shells", "large taco shells",
            "almond milk", "rice cakes", "lemon detergent", "sugar-free chocolate",
            "gluten-free bread", "gluten-free wholemeal penne", "wholemeal gluten-free penne",
            "lactose-free 2% milk", "2% lactose-free milk",
            "coconut cream", "coconut milk", "cinnamon stick", "ground cinnamon",
            "chicken stock cube", "beef stock cube",
            "2x apples", "2 x apples", "2 apples", "2 chairs", "1.5 apples", "½ apples",
            "3 garlic cloves", "3 cloves garlic", "2 large eggs", "2 organic apples",
            "500 g organic apples", "2 x 400 g cans organic tomatoes", "1 dozen eggs",
            "500 g diced mystery greens", "500 g diced jackfruit", "250 g minced seitan",
            "500 g unmelted candy", "diced mystery greens",
            "2 eggs, beaten with milk", "1 onion, diced with garlic", "rice (or pasta)",
            "milkshake milk", "milk milk", "soy  milk", "soy milk",
            "1/0 g milk", "999999999999999999999 g milk"
        ]
        for source in sources {
            guard let result = parser.parseRecord(source) else { continue }
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
            print("GROCERY \(source.debugDescription) => \(grocery(result.grocery))")
        }
        for source in ["2 eggs, beaten with milk", "1 onion, diced with garlic",
                       "milk, mystery fizz", "milk, bread, eggs", "taco shells, pasta shells"] {
            print("LIST \(source.debugDescription) => \(parser.parseList(source).map { grocery($0.grocery) })")
            print("ENTRY \(source.debugDescription) => \(parser.parseProductEntry(source).map(grocery))")
        }
        let fallback = IngredientParser(dictionary: nil)
        for source in ["2 apples", "500 g diced mystery greens", "diced mystery greens"] {
            print("NO_DICTIONARY \(source.debugDescription) => \(fallback.parseRecord(source).map { grocery($0.grocery) } ?? "nil")")
        }
        var aliasCount = 0
        var identityFailures = 0
        for entry in dictionary.ingredients {
            for term in [entry.name] + entry.aliases {
                aliasCount += 1
                let result = parser.parseRecord("500 g " + term)
                if result?.ingredientID != entry.id {
                    identityFailures += 1
                    print("ALIAS_IDENTITY_FAILURE \(term.debugDescription) expected=\(entry.id) actual=\(result?.ingredientID ?? "nil")")
                }
            }
        }
        print("ALL_DICTIONARY_IDENTITIES checked=\(aliasCount) failures=\(identityFailures)")
    }

    private static func grocery(_ value: ParsedGrocery) -> String {
        "name=\(value.name.debugDescription) amount=\(value.amount.map(String.init(describing:)) ?? "nil") unit=\(value.unit ?? "nil")"
    }
}
