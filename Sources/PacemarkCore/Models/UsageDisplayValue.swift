import Foundation

/// KTD6.2 presentation only: normalize once before classifying, without changing
/// provider precision. Consumers of remaining-only projections cannot invent utilization.
public struct UsageDisplayValue: Equatable, Sendable {
    public let percentRemaining: Double
    public let sourceUtilization: Double?
    public var severity: UsageSeverity { UsageSeverity(percentRemaining: percentRemaining) }
    private static let decimalLocale = Locale(identifier: "en_US_POSIX")

    public init?(window: UsageWindow) {
        self.init(utilization: window.utilization)
    }

    public init?(utilization: Double) {
        guard utilization.isFinite, let decimal = Self.decimalPercentage(utilization) else { return nil }
        // Convert source precision before subtracting: binary 100 - 84.95 falls
        // below the intended 15.05 tie and would make the display falsely Critical.
        percentRemaining = Self.normalize(100 - decimal)
        sourceUtilization = utilization
    }

    /// Fraction-only callers scale the source decimal before subtracting from 100,
    /// so e.g. 0.0505 does not turn into 5.050000000000001 percent used.
    init?(usedFraction: Double) {
        guard usedFraction.isFinite else { return nil }
        let clamped = min(1, max(0, usedFraction))
        // Fractions below this floor display as 100% remaining. Skip conversion of subnormals.
        let fraction = clamped < 0.0005 ? Decimal.zero : Decimal(string: String(clamped), locale: Self.decimalLocale)
        guard let fraction else { return nil }
        percentRemaining = Self.normalize(100 - fraction * 100)
        sourceUtilization = nil
    }

    /// For resolved projections. Provider windows should use the window/utilization
    /// initializer so decimal subtraction happens before normalization.
    public init?(percentRemaining: Double) {
        guard percentRemaining.isFinite, let decimal = Self.decimalPercentage(percentRemaining) else { return nil }
        self.percentRemaining = Self.normalize(decimal)
        sourceUtilization = nil
    }

    private static func decimalPercentage(_ value: Double) -> Decimal? {
        // Clamp before conversion so finite Double extremes cannot overflow Decimal.
        let clamped = min(100, max(0, value))
        // Values below half a displayed tenth round to zero (or their complement
        // to 100). This also handles Double subnormals below Decimal's exponent range.
        if clamped < 0.05 { return 0 }
        // Interpret the shortest round-trippable source decimal explicitly; POSIX
        // parsing never depends on the user's locale.
        return Decimal(string: String(clamped), locale: decimalLocale)
    }

    private static func normalize(_ value: Decimal) -> Double {
        var clamped = min(100, max(0, value))
        var rounded = Decimal()
        // All clamped values are nonnegative: .plain is nearest with ties away from zero.
        NSDecimalRound(&rounded, &clamped, 1, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }
}
