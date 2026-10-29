import Foundation

struct GroceryRational: Codable, Equatable, Hashable {
    let numerator: Int64
    let denominator: Int64

    init?(_ numerator: Int64, _ denominator: Int64 = 1) {
        guard denominator != 0 else { return nil }
        let sign: Int64 = denominator < 0 ? -1 : 1
        let n = numerator.multipliedReportingOverflow(by: sign)
        guard !n.overflow, denominator != Int64.min else { return nil }
        let d = denominator < 0 ? -denominator : denominator
        let divisor = Self.gcd(n.partialValue.magnitude, UInt64(d))
        self.numerator = n.partialValue / Int64(divisor)
        self.denominator = d / Int64(divisor)
    }

    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }

    var description: String {
        denominator == 1 ? String(numerator) : "\(numerator)/\(denominator)"
    }
}

enum GroceryQuantity: Codable, Equatable {
    case unspecified
    case count(GroceryRational)
    case measure(amount: GroceryRational?, unit: String)
    case packages(count: GroceryRational?, size: GroceryRational?, sizeUnit: String?, container: String?)
}
