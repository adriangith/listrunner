import SwiftUI

/// Store colours taken from the app's bundled store definitions (`addedColor`
/// / brand primary), so Previews match real lists.
struct DemoStore: Identifiable, Hashable {
    let id: String
    let name: String
    let tint: Color

    static let coles = DemoStore(id: "coles", name: "Coles", tint: Color(red: 224 / 255, green: 26 / 255, blue: 34 / 255))
    static let woolworths = DemoStore(id: "woolworths", name: "Woolworths", tint: Color(red: 0, green: 114 / 255, blue: 61 / 255))
    static let bunnings = DemoStore(id: "bunnings", name: "Bunnings", tint: Color(red: 13 / 255, green: 82 / 255, blue: 87 / 255))
    static let inbox = DemoStore(id: "inbox", name: "Inbox", tint: Color(red: 25 / 255, green: 132 / 255, blue: 94 / 255))

    static let all = [coles, woolworths, bunnings, inbox]
}

struct DemoItem: Identifiable, Hashable {
    let id: String
    let name: String
    let quantity: String
    /// Stores the item is on, in store order. More than one = shared.
    let stores: [DemoStore]
}

enum DemoData {
    static let items = [
        DemoItem(id: "milk", name: "Milk", quantity: "2 L", stores: [.coles, .woolworths]),
        DemoItem(id: "bread", name: "Bread", quantity: "1 loaf", stores: [.coles]),
        DemoItem(id: "eggs", name: "Eggs", quantity: "12", stores: [.coles]),
        DemoItem(id: "bananas", name: "Bananas", quantity: "6", stores: [.woolworths]),
        DemoItem(id: "yoghurt", name: "Yoghurt", quantity: "1 kg", stores: [.woolworths])
    ]

    static let lists: [DemoStore] = [.coles, .woolworths]

    static func items(on store: DemoStore) -> [DemoItem] {
        items.filter { $0.stores.contains(store) }
    }
}
