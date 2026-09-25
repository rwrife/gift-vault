import Foundation

// Money display and input parsing (issue #4).
//
// Money is integer cents end to end (`BudgetMinorUnits`); the UI must
// never route a value through `Float`/`Double` (issue #4 acceptance
// criteria — "never floating-point artifacts"). `Decimal` is exact for
// the base-10 cent shifts used here, and the parser does pure integer
// arithmetic, so there is no binary-float path anywhere in this file.

public enum MoneyFormatting {
    /// Exact decimal-string form of a cent count, always two fraction
    /// digits: `0 → "0.00"`, `123456 → "1234.56"`, `-2500 → "-25.00"`.
    /// Correct at `Int64.min` (the unsigned magnitude avoids the `abs`
    /// overflow trap). Pure integer math — no floats.
    public static func decimalString(_ cents: BudgetMinorUnits) -> String {
        let negative = cents < 0
        // Two's-complement negation via wrapping subtract; for `Int64.min`
        // the bit pattern *is* the correct unsigned magnitude (2^63).
        let magnitude = UInt64(bitPattern: negative ? 0 &- cents : cents)
        let whole = magnitude / 100
        let fraction = magnitude % 100
        return String(format: "%@%llu.%02llu", negative ? "-" : "", whole, fraction)
    }

    /// The "$" display form used by the app: `"$\(decimalString(cents))"`.
    public static func usdString(_ cents: BudgetMinorUnits) -> String {
        "$" + decimalString(cents)
    }
}

public enum MoneyParsing {
    /// Parse user-entered decimal money text into integer cents.
    ///
    /// Accepted shape: optional `-`, digits, optionally `.` + one or two
    /// digits (e.g. `"40"`, `"40.00"`, `"-3.5"`, `"0.05"`), with any
    /// surrounding whitespace stripped. Everything else — empty, letters,
    /// thousands separators, scientific notation, three or more fraction
    /// digits — returns `nil`. Overflow past `Int64` returns `nil`.
    /// The computation is pure integer arithmetic; no floating point.
    public static func parseCents(_ text: String) -> BudgetMinorUnits? {
        var input = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !input.isEmpty else { return nil }

        var negative = false
        if input.first == "-" {
            negative = true
            input = input.dropFirst()
        } else if input.first == "+" {
            input = input.dropFirst()
        }
        guard !input.isEmpty else { return nil }

        var wholeDigits = Substring("")
        var fractionDigits = Substring("")
        if let dot = input.firstIndex(of: ".") {
            wholeDigits = input[..<dot]
            fractionDigits = input[input.index(after: dot)...]
            guard !fractionDigits.isEmpty, fractionDigits.count <= 2 else { return nil }
        } else {
            wholeDigits = input
        }
        guard !wholeDigits.isEmpty || !fractionDigits.isEmpty else { return nil }
        guard wholeDigits.allSatisfy({ $0.isASCII && $0.isNumber }),
              fractionDigits.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        let whole = UInt64(wholeDigits.isEmpty ? "0" : String(wholeDigits)) ?? (UInt64(Int64.max) + 1)
        let scale: UInt64 = fractionDigits.count == 1 ? 10 : 1
        let fractionValue = fractionDigits.isEmpty
            ? UInt64(0)
            : (UInt64(String(fractionDigits)) ?? (UInt64(Int64.max) + 1)) * scale
        // 100_000_000_000_000_000 == Int64.max / 100 rounded up bound:
        // keep `whole * 100 + fraction` inside Int64.
        let limit = UInt64(Int64.max)
        guard whole <= limit / 100 else { return nil }
        var cents = whole * 100
        guard cents + fractionValue >= cents, cents + fractionValue <= limit else { return nil }
        cents += fractionValue
        if negative {
            // `-Int64.min` is unrepresentable, but `cents <= Int64.max`
            // makes the negate safe.
            return -BudgetMinorUnits(cents)
        }
        return BudgetMinorUnits(cents)
    }
}

// MARK: - Display vocabulary for domain enums

extension BudgetComparison {
    /// UI label for the budget-vs-price-hint outcome.
    public var label: String {
        switch self {
        case .under: "Within budget"
        case .over: "Over budget"
        case .unknownPrice: "No price hint"
        }
    }
}

extension OccasionStatus {
    /// Display name for a status step ("idea" → "Idea").
    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

extension LedgerDirection {
    /// Display name for a ledger direction.
    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}
