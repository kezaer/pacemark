import Foundation

public enum MenuBarIconStyle: String, Sendable, CaseIterable, Identifiable, Codable {
    case providerIcons, capsules
    public var id: String { rawValue }
}

public enum MenuBarGlyphKind: Sendable, Hashable {
    case capsule
    case providerMark(ProviderID)
}

public struct MenuBarGlyphSize: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum MenuBarGlyph {
    public static let minimumRingLogoClearance = 1.5

    /// Outward-rounded radial ink bounds of the trimmed monochrome SVGs, measured
    /// from their center and divided by the longer side. The capsule fits its circle.
    public static func normalizedRingInkRadius(of kind: MenuBarGlyphKind) -> Double {
        guard case .providerMark(let provider) = kind else { return 0.50 }
        switch provider {
        case .claude: return 0.56
        case .codex: return 0.53
        case .grok: return maximumNormalizedRingInkRadius
        case .cursor: return 0.52
        case .copilot: return 0.56
        case .opencode: return 0.65
        case .antigravity: return 0.685
        default: return 0.50
        }
    }

    public static let maximumNormalizedRingInkRadius = 0.70

    /// Fits the farthest corner of the trimmed ink box inside the clear radius.
    /// The longest dimension can also be bounded vertically where a badge sits under the mark.
    public static func ringLogoSize(
        of kind: MenuBarGlyphKind, preferredSize: Double, innerRadius: Double,
        verticalOffset: Double = 0, maximumInkHeight: Double = .infinity,
        minimumSize: Double = 0, usesRadialInkBounds: Bool = false
    ) -> MenuBarGlyphSize {
        let aspect: Double
        let opticalScale: Double
        switch kind {
        case let .providerMark(provider):
            aspect = PacemarkBrandMark.inkAspect(for: provider.raw)
            switch provider {
            case .antigravity: opticalScale = 0.78
            case .claude, .codex: opticalScale = 1
            default: opticalScale = 0.9
            }
        case .capsule:
            aspect = 11.0 / 18.0
            opticalScale = 0.9
        }

        let widthFactor = min(1, aspect)
        let heightFactor = 1 / max(1, aspect)
        let clearRadius = innerRadius - minimumRingLogoClearance
        let offset = abs(verticalOffset)
        guard clearRadius > offset else { return .init(width: 0, height: 0) }

        let halfWidth = widthFactor / 2
        let halfHeight = heightFactor / 2
        let cornerSquared = halfWidth * halfWidth + halfHeight * halfHeight
        let crossTerm = offset * halfHeight
        let boxLimit = (sqrt(crossTerm * crossTerm + cornerSquared * (clearRadius * clearRadius - offset * offset))
                           - crossTerm) / cornerSquared
        let radialLimit = usesRadialInkBounds ? (clearRadius - offset) / normalizedRingInkRadius(of: kind) : boxLimit
        let size = max(0, min(max(minimumSize, preferredSize * opticalScale), radialLimit, maximumInkHeight / heightFactor))
        return .init(width: size * widthFactor, height: size * heightFactor)
    }
}

public enum MenuBarAccountBadge {
    public static let maxLength = 4

    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let characters = raw.filter { character in
            guard let byte = character.asciiValue else { return false }
            return (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        let badge = String(characters.prefix(maxLength)).uppercased()
        return badge.isEmpty ? nil : badge
    }

    public static func defaultBadge(for label: String, index: Int) -> String {
        let digits = String(label.trimmingCharacters(in: .whitespacesAndNewlines).reversed()
            .prefix { $0.asciiValue.map { (48...57).contains($0) } == true }.reversed())
        if let badge = sanitize(digits) { return badge }
        if let letter = sanitize(label)?.first { return String(letter) }
        return String(index + 1)
    }
}

/// The meter's reading, provider identity and accessibility caption.
public struct MenuBarSummary: Sendable, Equatable {
    public let text: String            // e.g. "12%"
    public let providerID: ProviderID? // which provider the number is about
    public let detail: String?         // e.g. "Claude 5h"
    public let percentageMode: UsagePercentageMode?
    public let isNeutral: Bool         // true when no live data yet
    /// Health of the shown window — tints the glyph by urgency, not brand (UI-03).
    public let severity: UsageSeverity
    /// The account needs recovery and its gauge is dotted.
    public let needsAttention: Bool

    public init(
        text: String,
        providerID: ProviderID?,
        detail: String?,
        isNeutral: Bool,
        percentageMode: UsagePercentageMode? = nil,
        severity: UsageSeverity = .healthy,
        needsAttention: Bool = false
    ) {
        self.text = text
        self.providerID = providerID
        self.detail = detail
        self.isNeutral = isNeutral
        self.percentageMode = percentageMode
        self.severity = severity
        self.needsAttention = needsAttention
    }

    public static let neutral = MenuBarSummary(text: "—", providerID: nil, detail: nil, isNeutral: true)
}

/// One account and limit, ready to draw as a menu bar meter.
public struct MenuBarMeter: Sendable, Equatable {
    public let summary: MenuBarSummary
    /// 0...1 fill for the gauge, or nil when no numeric reading is available.
    public let fill: Double?
    public let awaitingFirstReading: Bool
    /// A stale retained reading has a number but cannot carry a pace tick.
    public let isLiveReading: Bool
    /// Identifies the row for Settings preview highlighting and refresh receipts.
    public let sourceAccountKey: AccountKey?
    public let glyph: MenuBarGlyphKind
    public let badge: String?
    public let pace: MenuBarPace?
    public let countdown: String?

    public var accessibilityReading: String? {
        guard let detail = summary.detail else { return nil }
        guard !summary.isNeutral else { return "\(detail), no reading" }
        let unit = summary.percentageMode == .used ? "used" : "left"
        let amount = summary.text.replacingOccurrences(of: "%", with: " percent \(unit)")
        let state = isLiveReading ? pace?.tier?.label.lowercased() : nil
        return [detail, amount, state, countdown.map(Countdown.spokenReset)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    public var expectedFill: Double? {
        pace?.expectedRemaining.map { summary.percentageMode == .used ? 1 - $0 : $0 }
    }

    public init(summary: MenuBarSummary, fill: Double?, awaitingFirstReading: Bool = false,
                isLiveReading: Bool = false, sourceAccountKey: AccountKey? = nil,
                glyph: MenuBarGlyphKind = .capsule, badge: String? = nil, pace: MenuBarPace? = nil,
                countdown: String? = nil) {
        self.summary = summary
        self.fill = fill
        self.awaitingFirstReading = awaitingFirstReading
        self.isLiveReading = isLiveReading
        self.sourceAccountKey = sourceAccountKey
        self.glyph = glyph
        self.badge = badge
        self.pace = pace
        self.countdown = countdown
    }
}
