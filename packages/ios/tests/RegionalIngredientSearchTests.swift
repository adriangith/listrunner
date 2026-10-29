import Foundation

@main
struct RegionalIngredientSearchTests {
    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let dictionary = try IngredientDictionary(data: Data(contentsOf: resources.appendingPathComponent("ingredients.json")))
        let data = try Data(contentsOf: resources.appendingPathComponent("ingredient-regional-names.json"))
        let catalogue = try RegionalIngredientNames(data: data, dictionary: dictionary)
        let resolver = RegionalIngredientSearchResolver(dictionary: dictionary, catalogue: catalogue)
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        func context(_ country: String? = "NZ", enabled: Bool = true) -> IngredientSearchContext {
            IngredientSearchContext(countryCode: country, enabled: enabled)
        }
        for entry in catalogue.entries {
            for (country, target) in entry.countryNames {
                for source in entry.sourceNames {
                    let result = resolver.resolve(source, context: context(country))
                    check(result.query == target && result.ingredientID == entry.ingredientID, "every reviewed source/country keeps identity")
                    check(resolver.resolve(result.query, context: context(country)) == result, "local names are idempotent")
                }
            }
        }
        for (source, expected, country) in [
            ("ZUCCHINI", "courgette", "NZ"),
            ("Courgettes", "zucchini", "AU"),
            ("cOurGeTte", "zucchini", "US"),
            ("Fresh Zucchini", "Fresh courgette", "GB"),
            ("  frozen Zucchini  ", "  frozen courgette  ", "NZ"),
            ("gluten-free zucchini", "gluten-free courgette", "NZ"),
            ("red capsicum (frozen)", "red bell pepper (frozen)", "US"),
            ("[organic aubergine]", "[organic eggplant]", "NZ"),
            ("béétroot", "beet", "US")
        ] {
            check(resolver.resolve(source, context: context(country)).query == expected, "preserve qualifiers, case outside span and Unicode: \(source)")
        }
        for source in ["mystery vegetable", "coriander", "coriander seeds", "coriander leaves", "yam", "sweet potato",
                       "pumpkin", "butternut squash", "zucchini sauce", "Brand zucchini", "zucchini seeds",
                       "zucchini and eggplant", "zucchini, courgette", "zucchini zucchini", "zucchinibread", "myzucchini",
                       "zucchini2", "zucchini_bread", "zucchini-flavoured", "rocket fuel", "zucchini & beans", ""] {
            check(resolver.resolve(source, context: context()).query == source, "uncertain/compound input is untouched: \(source)")
        }
        for inputContext in [context(nil), context("CA"), context("ZZ"), context("nz"), context("NZ", enabled: false)] {
            check(resolver.resolve("Zucchini", context: inputContext).query == "Zucchini", "unsupported/disabled context is unchanged")
        }
        let missingCatalogue = RegionalIngredientSearchResolver(dictionary: dictionary, catalogue: nil)
        let missingDictionary = RegionalIngredientSearchResolver(dictionary: nil, catalogue: catalogue)
        check(missingCatalogue.resolve("zucchini", context: context()).query == "zucchini", "catalogue failure preserves original search")
        check(missingDictionary.resolve("zucchini", context: context()).query == "zucchini", "dictionary failure preserves original search")

        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func rejects(_ object: [String: Any]) -> Bool {
            (try? RegionalIngredientNames(data: JSONSerialization.data(withJSONObject: object), dictionary: dictionary)) == nil
        }
        root["version"] = 2
        check(rejects(root), "unknown catalogue schema rejected")
        check((try? RegionalIngredientNames(data: Data("invalid".utf8), dictionary: dictionary)) == nil, "malformed catalogue rejected")
        func entry(_ id: String = "zucchini", sources: [String] = ["zucchini"], countries: [String: String] = ["NZ": "zucchini"]) -> [String: Any] {
            ["ingredientID": id, "sourceNames": sources, "countryNames": countries]
        }
        for entries in [
            [entry("missing")], [entry(sources: [])], [entry(sources: [" "])],
            [entry(sources: ["zucchini", "ZUCCHINI"])], [entry(), entry()],
            [entry(sources: ["pepper"])], [entry(countries: ["UK": "zucchini"])],
            [entry(countries: ["NZ": "yam"])], [entry(countries: [:])]
        ] {
            check(rejects(["version": 1, "entries": entries]), "invalid or identity-changing mapping rejected")
        }
        let partialData = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": [entry()]])
        let partial = try RegionalIngredientNames(data: partialData, dictionary: dictionary)
        let partialResolver = RegionalIngredientSearchResolver(dictionary: dictionary, catalogue: partial)
        check(partialResolver.resolve("zucchini", context: context("GB")).query == "zucchini", "missing country target never falls back to another country")

        // A future dictionary may add a specific composite product. It must
        // block the shorter regional rewrite even without a catalogue entry.
        var dictionaryJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dictionary)) as! [String: Any]
        var ingredients = dictionaryJSON["ingredients"] as! [[String: Any]]
        ingredients.append(["id": "zucchini-bread", "name": "Zucchini bread", "aliases": [], "modifiers": []])
        dictionaryJSON["ingredients"] = ingredients
        let extended = try IngredientDictionary(data: JSONSerialization.data(withJSONObject: dictionaryJSON))
        let extendedResolver = RegionalIngredientSearchResolver(dictionary: extended, catalogue: catalogue)
        check(extendedResolver.resolve("zucchini bread", context: context()).query == "zucchini bread", "longer dictionary compound wins")
        print("PASS: \(checks) regional ingredient search checks")
    }
}
