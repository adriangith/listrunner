import Foundation

private struct Fixture: Decodable {
    let input: String
    let expectedName: String
    let expectedQuantity: String
}

@main
struct IngredientParserTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: IngredientParserTests <dictionary.json> <fixtures.json>\n", stderr)
            exit(2)
        }
        let dictionaryData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let parser = IngredientParser(dictionary: try IngredientDictionary(data: dictionaryData))
        var failures = 0
        for fixture in fixtures {
            guard let result = parser.parseRecord(fixture.input) else {
                print("FAIL \(fixture.input) → no result")
                failures += 1
                continue
            }
            let actual = quantityDescription(result.quantity)
            let passed = result.displayName == fixture.expectedName && actual == fixture.expectedQuantity
            print("\(passed ? "PASS" : "FAIL") \(fixture.input) → \(result.displayName) [\(actual)] (\(result.disposition.rawValue))")
            if !passed {
                print("  expected: \(fixture.expectedName) [\(fixture.expectedQuantity)]")
                print("  explanation: \(result.explanation.joined(separator: "; "))")
                failures += 1
            }
        }

        let paste = parser.parseList("milk, bread, eggs")
        if paste.map(\.displayName) != ["Milk", "Bread", "Eggs"] {
            print("FAIL comma-separated recognized paste list → \(paste.map(\.displayName))")
            failures += 1
        } else { print("PASS comma-separated recognized paste list") }

        let reminder = parser.parseRecord("2 cans beans, drained and rinsed")
        if reminder?.displayName != "Beans" {
            print("FAIL one Reminder remains one ingredient")
            failures += 1
        } else { print("PASS one Reminder remains one ingredient") }

        if parser.parseRecord("milk and bread")?.disposition != .ambiguous {
            print("FAIL multiple ingredient matches are ambiguous")
            failures += 1
        } else { print("PASS multiple ingredient matches are ambiguous") }

        if failures > 0 { exit(1) }
        print("All parser fixtures passed (\(fixtures.count + 2) checks).")
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
