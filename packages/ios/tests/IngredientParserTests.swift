import Foundation

private struct Fixture: Decodable {
    let input: String
    let expectedName: String
    let expectedQuantity: String
    let expectedIngredientID: String?
    let expectedDisposition: String?
    let expectedPreparation: [String]?
    let expectedUnmatched: [String]?
    let expectedGroceryAmount: Double?
    let expectedGroceryUnit: String?
}

@main
struct IngredientParserTests {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            fputs("usage: IngredientParserTests <dictionary.json> <fixtures.json> [more-fixtures.json ...]\n", stderr)
            exit(2)
        }
        let dictionaryData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixtures = try CommandLine.arguments.dropFirst(2).flatMap { path in
            try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let dictionary = try IngredientDictionary(data: dictionaryData)
        let parser = IngredientParser(dictionary: dictionary)
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        check((try? decoder.decode(IngredientDictionary.self, from: encoder.encode(dictionary))) == dictionary,
              "dictionary Codable round trip")
        if let result = parser.parseRecord("1/3 cup freshly grated romano") {
            check((try? decoder.decode(IngredientParseResult.self, from: encoder.encode(result))) == result,
                  "parse result Codable round trip")
            check(result.parserVersion == IngredientParser.version && result.dictionaryVersion == dictionary.version,
                  "result carries parser and dictionary versions")
        } else {
            check(false, "parse result Codable round trip")
        }

        let fallback = IngredientParser(dictionary: IngredientDictionary.loadOrNil(Data("not json".utf8)))
        if let result = fallback.parseRecord("250 g mystery ingredient") {
            check(result.dictionaryVersion == nil && result.ingredientID == nil
                && result.displayName == "mystery ingredient"
                && quantityDescription(result.quantity) == "measure:250:g",
                  "invalid dictionary falls back to quantity-only parsing and preserves unknown name")
        } else {
            check(false, "invalid dictionary falls back to quantity-only parsing and preserves unknown name")
        }

        let invalidModifier = Data(#"{"version":1,"ingredients":[{"id":"x","name":"X","aliases":[],"modifiers":[" "]}]}"#.utf8)
        check(IngredientDictionary.loadOrNil(invalidModifier) == nil, "empty modifier rejected")
        let duplicateModifier = Data(#"{"version":1,"ingredients":[{"id":"x","name":"X","aliases":[],"modifiers":["low salt","LOW   SALT"]}]}"#.utf8)
        check(IngredientDictionary.loadOrNil(duplicateModifier) == nil, "duplicate normalized modifier rejected")
        check(IngredientDictionary.loadOrNil(Data(#"{"version":0,"ingredients":[]}"#.utf8)) == nil,
              "nonpositive dictionary version rejected")
        let preservationCases: [(String, String, Double?)] = [
            ("taco shells", "taco shells", nil), ("12 taco shells", "taco shells", 12),
            ("rice cakes", "rice cakes", nil), ("gluten-free bread", "gluten-free bread", nil),
            ("lemon detergent", "lemon detergent", nil), ("soy  milk", "Soy milk", nil),
            ("2% lactose-free milk", "2% lactose-free milk", nil),
            ("lactose-free 2% milk", "Lactose-free 2% milk", nil),
            ("gluten-free wholemeal penne", "Gluten-free wholemeal penne", nil),
            ("wholemeal gluten-free penne", "Wholemeal gluten-free penne", nil),
            ("500 g diced jackfruit", "diced jackfruit", 500),
            ("250 g minced seitan", "minced seitan", 250),
            ("500 g unmelted candy", "unmelted candy", 500),
            ("2x apples", "Apples", 2), ("2 x apples", "Apples", 2),
            ("1.5 apples", "Apples", 1.5), ("½ apples", "Apples", 0.5),
            ("2 chairs", "chairs", 2), ("2 large eggs", "large eggs", 2),
            ("2 organic apples", "organic apples", 2),
            ("2 x 400 g cans organic tomatoes", "organic tomatoes", 2),
            ("1/0 g milk", "1/0 g milk", nil),
            ("999999999999999999999 g milk", "999999999999999999999 g milk", nil),
            ("milkshake milk", "milkshake milk", nil)
        ]
        for (source, name, amount) in preservationCases {
            let result = parser.parseRecord(source)
            check(result?.grocery.name == name && result?.grocery.amount == amount,
                  "source preservation: \(source) → \(result?.grocery.name ?? "nil")")
            check(result?.originalText == source && result?.displayName.isEmpty == false,
                  "nonempty name and original source retained: \(source)")
        }
        for source in ["500 g diced jackfruit", "250 g minced seitan", "2 chairs"] {
            check(fallback.parseRecord(source)?.grocery.name == parser.parseRecord(source)?.grocery.name,
                  "dictionary-free preservation: \(source)")
        }
        for (source, name) in [("2 eggs, beaten with milk", "Eggs"), ("1 onion, diced with garlic", "Onion")] {
            check(parser.parseList(source).map(\.displayName) == [name], "recipe clause stays attached: \(source)")
            check(parser.parseRecord(source)?.grocery.amount == (name == "Eggs" ? 2 : 1), "recipe quantity: \(source)")
        }
        check(parser.parseList("milk, mystery fizz").map(\.displayName) == ["Milk", "mystery fizz"], "mixed Reminder list preserved")
        check(parser.parseList("milk, minced beef").map(\.displayName) == ["Milk", "Beef mince"], "leading preparation modifier starts a real item")
        check(parser.parseRecord("rice diced tomatoes")?.displayName == "rice diced tomatoes", "unseparated product references are not discarded as preparation")
        check(parser.parseRecord("1 dozen eggs")?.grocery.unit == "dozen", "dozen quantity is retained without unit conversion")
        check(parser.parseRecord("milk (lactose-free)")?.displayName == "Milk (lactose-free)", "parenthetical qualifiers are not duplicated")
        check(parser.parseProductEntry("taco shells, pasta shells").map(\.name) == ["taco shells", "Pasta shells"], "distinct shell products survive add adapter")
        check(parser.parseRecord("coconut cream")?.displayName == "Coconut cream", "cream is not milk")
        check(parser.parseRecord("cinnamon stick")?.displayName != parser.parseRecord("ground cinnamon")?.displayName, "whole and ground cinnamon distinct")
        check(parser.parseRecord("milkshake milk")?.ingredientID == "milk", "later boundary-valid occurrence found")
        check(parser.parseRecord("milkshake milk")?.ingredientRange?.location == 10, "range metadata identifies the boundary-valid occurrence")
        let largePackage = parser.parseRecord("1 x 9223372036854775807 g cans tomatoes")
        check(largePackage?.grocery.unit?.contains("g can") == true, "large package conversion does not trap")
        check(largePackage?.grocery.parseResult == largePackage, "add adapter retains parse provenance")
        check(formatGroceryAmount(Double(Int64.max)).isEmpty == false
              && !formatGroceryAmount(.infinity).isEmpty, "amount formatting handles numeric boundaries without trapping")
        for fixture in fixtures {
            guard let result = parser.parseRecord(fixture.input) else {
                print("FAIL \(fixture.input) → no result")
                failures += 1
                continue
            }
            let actual = quantityDescription(result.quantity)
            let passed = result.displayName == fixture.expectedName && actual == fixture.expectedQuantity
                && (fixture.expectedIngredientID.map { result.ingredientID == $0 } ?? true)
                && (fixture.expectedDisposition.map { result.disposition.rawValue == $0 } ?? true)
                && (fixture.expectedPreparation.map { result.omittedPreparation == $0 } ?? true)
                && (fixture.expectedUnmatched.map { result.unmatchedText == $0 } ?? true)
                && (fixture.expectedGroceryAmount.map { result.grocery.amount == $0 } ?? true)
                && (fixture.expectedGroceryUnit.map { result.grocery.unit == $0 } ?? true)
            print("\(passed ? "PASS" : "FAIL") \(fixture.input) → \(result.displayName) [\(actual)] (\(result.disposition.rawValue))")
            if !passed {
                print("  expected: \(fixture.expectedName) [\(fixture.expectedQuantity)]")
                print("  explanation: \(result.explanation.joined(separator: "; "))")
                print("  preparation: \(result.omittedPreparation); unmatched: \(result.unmatchedText); grocery: \(String(describing: result.grocery.amount)) \(String(describing: result.grocery.unit))")
                failures += 1
            }
        }

        let paste = parser.parseList("milk, bread, eggs")
        if paste.map(\.displayName) != ["Milk", "Bread", "Eggs"] {
            print("FAIL comma-separated recognized paste list → \(paste.map(\.displayName))")
            failures += 1
        } else { print("PASS comma-separated recognized paste list") }

        for source in ["toaster, chair", "toaster,chair", "toaster,, chair,", "toaster; chair", "toaster\tchair", "toaster\nchair"] {
            let products = parser.parseProductEntry(source)
            if products.map(\.name) != ["toaster", "chair"] {
                print("FAIL explicit product-entry separators: \(source) → \(products.map(\.name))")
                failures += 1
            } else { print("PASS explicit product-entry separators: \(source)") }
        }
        let noDictionary = IngredientParser(dictionary: nil).parseProductEntry("toaster, chair")
        if noDictionary.map(\.name) != ["toaster", "chair"] {
            print("FAIL comma separators must not depend on a loaded dictionary")
            failures += 1
        } else { print("PASS dictionary-free product-entry separators") }
        let mixedProducts = parser.parseProductEntry("milk, toaster, 2 eggs")
        if mixedProducts.map(\.name) != ["Milk", "toaster", "Eggs"] || mixedProducts.last?.amount != 2 {
            print("FAIL mixed known/unknown product entry retains quantities")
            failures += 1
        } else { print("PASS mixed known/unknown product entry retains quantities") }
        let lemonProducts = parser.parseProductEntry("lemon, Lemon tree, 2 lemon trees")
        check(lemonProducts.map(\.name) == ["Lemon", "Lemon Tree", "Lemon Tree"]
              && lemonProducts.last?.amount == 2,
              "product entry keeps Lemon Tree distinct from Lemon and retains tree quantities")
        if !parser.parseProductEntry(" , ;\t\n, ").isEmpty {
            print("FAIL empty product segments must be ignored")
            failures += 1
        } else { print("PASS empty product segments are ignored") }
        if parser.parseGroceries("2 cans beans, drained and rinsed").count != 1 {
            print("FAIL recipe/import preparation comma handling changed")
            failures += 1
        } else { print("PASS recipe/import preparation comma handling preserved") }

        let reminder = parser.parseRecord("2 cans beans, drained and rinsed")
        if reminder?.displayName != "Beans" {
            print("FAIL one Reminder remains one ingredient")
            failures += 1
        } else { print("PASS one Reminder remains one ingredient") }

        if parser.parseRecord("milk and bread")?.disposition != .ambiguous {
            print("FAIL multiple ingredient matches are ambiguous")
            failures += 1
        } else { print("PASS multiple ingredient matches are ambiguous") }

        if [" •  ", "---", "  ", "·"].contains(where: { parser.parseRecord($0) != nil }) {
            print("FAIL blank or bullet-only entries must not create empty groceries")
            failures += 1
        } else { print("PASS blank and bullet-only entries are ignored") }

        // Every bundled name/alias must
        // resolve to that ingredient, not merely survive the unknown-name fallback.
        var aliasChecks = 0
        for entry in dictionary.ingredients {
            for term in [entry.name] + entry.aliases {
                aliasChecks += 1
                let result = parser.parseRecord("500 g " + term)
                if result?.ingredientID != entry.id || result?.displayName.isEmpty != false
                    || result.map({ quantityDescription($0.quantity) }) != "measure:500:g" {
                    print("FAIL ingredient alias \(term) should resolve to \(entry.name) with 500 g")
                    failures += 1
                }
                let qualified = parser.parseRecord("500 g special-brand " + term)
                check(qualified?.displayName == "special-brand " + term && qualified?.grocery.amount == 500,
                      "unknown brand/qualifier preserved for \(term)")
            }
        }
        if failures == 0 { print("PASS all \(aliasChecks) ingredient name/alias identity and quantity checks") }

        if failures > 0 { exit(1) }
        print("All \(fixtures.count) parser fixtures, \(aliasChecks) dictionary aliases and focused parser regressions passed.")
    }

    private static func quantityDescription(_ quantity: GroceryQuantity) -> String {
        switch quantity {
        case .unspecified: return "unspecified"
        case .count(let amount): return "count:\(amount.description)"
        case .measure(let amount, let unit): return "measure:\(amount?.description ?? "unspecified"):\(unit)"
        case .packages(let count, let size, let sizeUnit, let container):
            return "packages:\(count?.description ?? "unspecified"):\(size?.description ?? "unspecified"):\(sizeUnit ?? "unspecified"):\(container ?? "unspecified")"
        }
    }
}
