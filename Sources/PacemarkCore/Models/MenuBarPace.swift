import Foundation

/// The remaining quota and its pace against a known reset interval.
public struct MenuBarPace: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case fast, slow
    }

    public enum Tier: Sendable, Equatable {
        case onPace
        case offPace(Direction)
        case farOffPace(Direction)

        public var severity: UsageSeverity {
            switch self {
            case .onPace: .healthy
            case .offPace: .low
            case .farOffPace: .critical
            }
        }

        public var direction: Direction? {
            switch self {
            case .onPace: nil
            case .offPace(let direction), .farOffPace(let direction): direction
            }
        }

        public var label: String {
            switch self {
            case .onPace: "On pace"
            case .offPace(.fast): "Using fast"
            case .offPace(.slow): "Using slowly"
            case .farOffPace(.fast): "Using very fast"
            case .farOffPace(.slow): "Using very slowly"
            }
        }

        public var isOffPace: Bool { direction != nil }
    }

    public let remaining: Double
    public let expectedRemaining: Double?
    /// Displayed remaining minus expected remaining, in tenths of a percentage point.
    public let deviationTenths: Int?

    public var direction: Direction? {
        guard let deviationTenths, deviationTenths != 0 else { return nil }
        return deviationTenths < 0 ? .fast : .slow
    }

    public var isOffPace: Bool { tier?.isOffPace == true }

    /// Unknown reset evidence leaves the tier unset so the meter can use its normal severity.
    public let tier: Tier?

    public init?(usedFraction: Double, duration: TimeInterval?, reset: Date?, now: Date) {
        guard usedFraction.isFinite else { return nil }
        let used = min(1, max(0, usedFraction))
        guard let displayed = UsageDisplayValue(usedFraction: used) else { return nil }
        self.init(usedFraction: used, displayed: displayed, duration: duration, reset: reset, now: now)
    }

    private init(usedFraction: Double, displayed: UsageDisplayValue, duration: TimeInterval?, reset: Date?, now: Date) {
        remaining = 1 - usedFraction
        let expected: UsageDisplayValue?
        if let duration, duration.isFinite, duration > 0,
           let timeToReset = reset?.timeIntervalSince(now), timeToReset.isFinite {
            let timeLeft = min(duration, max(0, timeToReset))
            let fraction = timeLeft / duration
            expectedRemaining = fraction
            // Scale before dividing so 1,899 seconds of 18,000 yields exactly 10.55%.
            let scaledTime = timeLeft * 100
            expected = UsageDisplayValue(
                percentRemaining: scaledTime.isFinite ? scaledTime / duration : fraction * 100
            )
        } else {
            expectedRemaining = nil
            expected = nil
        }

        guard let expected else {
            deviationTenths = nil
            tier = nil
            return
        }

        let delta = Int((displayed.percentRemaining * 10).rounded())
            - Int((expected.percentRemaining * 10).rounded())
        deviationTenths = delta
        let direction: Direction = delta < 0 ? .fast : .slow
        switch abs(delta) {
        case ...50: tier = .onPace
        case ...150: tier = .offPace(direction)
        default: tier = .farOffPace(direction)
        }
    }

    public init?(window: UsageWindow, now: Date) {
        guard let displayed = UsageDisplayValue(window: window) else { return nil }
        self.init(usedFraction: min(1, max(0, window.utilization / 100)), displayed: displayed,
                  duration: Self.duration(for: window.kind), reset: window.resetSchedule.deadline, now: now)
    }

    public static func duration(for kind: WindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: 18_000
        case .weekly: 604_800
        case .billingPeriod(_, let duration): duration
        case .other(let label):
            if WindowKind.weeklyModelName(in: label) != nil {
                duration(for: .weekly)
            } else {
                // Codex model counters and Antigravity pools carry their period as a suffix.
                WindowKind.modelAndPeriod(in: label).flatMap { duration(for: $0.period) }
            }
        }
    }
}
