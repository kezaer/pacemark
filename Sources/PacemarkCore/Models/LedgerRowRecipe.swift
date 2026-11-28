import Foundation

/// Estimate depletion after a tenth of the window has elapsed. An already empty window
/// is due now, including during that initial interval.
public struct PaceProjection: Sendable, Equatable {
    public let timeToEmpty: TimeInterval

    public init?(window: UsageWindow, pace: MenuBarPace, now: Date) {
        guard window.freshness.isLive else { return nil }
        if pace.remaining == 0 {
            timeToEmpty = 0
            return
        }
        guard let deadline = window.resetSchedule.deadline, deadline > now,
              let duration = MenuBarPace.duration(for: window.kind), let expected = pace.expectedRemaining,
              expected <= 0.9, pace.remaining < 1 else { return nil }
        let estimate = duration * (1 - expected) * pace.remaining / (1 - pace.remaining)
        guard estimate < deadline.timeIntervalSince(now) else { return nil }
        timeToEmpty = estimate
    }

    public var approximateTime: String {
        let minutes = Int((timeToEmpty / 60).rounded())
        if minutes < 1 { return "now" }
        if minutes < 60 { return "~\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "~\(hours)h" }
        return "~\(hours / 24)d \(hours % 24)h"
    }

    public var emptyLine: String {
        timeToEmpty < 60 ? "empty now" : "empty in \(approximateTime)"
    }
}

public struct LedgerRowRecipe: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        public let value: CompactAccountRowWindow
        public let pace: MenuBarPace?
        public let countdown: String?
        public let resetDeadline: Date?
        public let passedReset: String?
        public let bankedResets: Int?

        public var column: String {
            if value.window.displayLabel == "Weekly" { return "Week" }
            return value.window.displayLabel ?? LedgerRowRecipe.column(for: value.window.kind)
        }

        public var detailLabel: String {
            if let label = value.window.displayLabel { return label }
            if case .other(let label) = value.window.kind, AntigravityRowLabels.parse(label) != nil {
                return label
            }
            return value.window.kind.compactName
        }

        init(value: CompactAccountRowWindow, dimmed: Bool, remembered: Bool, bankedResets: Int?, now: Date) {
            self.value = value
            let window = value.window
            self.bankedResets = PlanCapsulePresentation.resetsWithBankedCredit(window.kind) ? bankedResets : nil
            let reportedDeadline = window.resetSchedule.deadline
            // Antigravity can report an elapsed reset for a full pool with no active usage.
            // A later reported deadline remains valid, even when the pool is full.
            let unusedPool = AntigravityRowLabels.parse(window.kind) != nil
                && window.utilization == 0
                && !(reportedDeadline.map { $0 > now } ?? false)
            let deadline = unusedPool ? nil : reportedDeadline
            let pace = !unusedPool && !dimmed && window.freshness.isLive
                && (deadline.map { $0 > now } ?? true) ? MenuBarPace(window: window, now: now) : nil
            self.pace = pace
            resetDeadline = value.displayedPercentage == nil ? nil : deadline
            countdown = value.displayedPercentage == nil || unusedPool ? nil : deadline.map {
                Countdown.string(to: $0, now: now)
            } ?? (Countdown.resetText(for: window, now: now) == "Available" ? "Available" : nil)
            passedReset = remembered ? RememberedRowRecipe.resetNotReadLine(for: window, now: now, compact: true) : nil
        }
    }

    public let windows: [Window]
    public let primary: Window?
    public let message: String?
    public let accessibilityHint: String?
    public let isDimmed: Bool
    public var canExpand: Bool { windows.count > 1 }

    public init(
        snapshot: UsageSnapshot, percentageMode: UsagePercentageMode, now: Date,
        windowChoice: MenuBarWindowChoice = .weekly,
        attention: String? = nil, showsCodexSparkCounters: Bool = false,
        showsAntigravityFiveHourWindows: Bool = true, isRemembered: Bool = false, lastReadAt: Date? = nil
    ) {
        let dimmed = isRemembered || snapshot.freshness != .live && snapshot.freshness != .pending
        isDimmed = dimmed
        let visible = CompactAccountRowRecipe.visibleWindows(
            in: snapshot, showsCodexSparkCounters: showsCodexSparkCounters,
            showsAntigravityFiveHourWindows: showsAntigravityFiveHourWindows
        )
        let bankedResets = snapshot.providerID == .codex ? snapshot.bankedResets.flatMap { $0 > 0 ? $0 : nil } : nil
        let cells = visible.sorted(by: Self.detailOrder).map { original in
            let window: UsageWindow
            if isRemembered, let deadline = original.resetSchedule.deadline, !(deadline > now) {
                window = original.withFreshness(.unavailable(since: deadline))
            } else {
                window = original
            }
            let value = CompactAccountRowWindow(
                window: window, shortLabel: Self.column(for: window.kind),
                displayedPercentage: UsageMeterReading(window: window).roundedPercentage(for: percentageMode)
            )
            return Window(value: value, dimmed: dimmed, remembered: isRemembered, bankedResets: bankedResets, now: now)
        }
        windows = cells
        primary = Self.collapsedWindow(in: cells, providerID: snapshot.providerID, choice: windowChoice)
        let lastRead = isRemembered ? Countdown.lastReadLabel(capturedAt: lastReadAt ?? snapshot.capturedAt, now: now) : nil
        message = Self.status(snapshot: snapshot, attention: attention, remembered: isRemembered,
                              lastRead: lastRead, hasReading: cells.contains { $0.value.displayedPercentage != nil })
        let age = dimmed && !isRemembered ? Countdown.updatedLabel(capturedAt: snapshot.capturedAt, now: now)
            .map { "Last good read \($0)" } : nil
        let limited = UsageLimitSentence(snapshot: snapshot, now: now)?.text
        let hints = [limited, age].compactMap { $0 }
        accessibilityHint = hints.isEmpty ? nil : hints.joined(separator: ". ")
    }

    private static func collapsedWindow(in windows: [Window], providerID: ProviderID, choice: MenuBarWindowChoice) -> Window? {
        if choice != .weekly {
            let available = windows.filter { $0.value.displayedPercentage != nil }
            if let chosen = available.first(where: { choice.matches($0.value.window.kind) })
                ?? available.min(by: { $0.value.window.percentRemaining < $1.value.window.percentRemaining }) {
                return chosen
            }
        }

        let weekly = windows.filter { isWeekly($0.value.window.kind) }
        if providerID == .antigravity, !weekly.isEmpty {
            return weekly.max { isTighter($1, $0) }
        }
        if let weekly = weekly.first { return weekly }
        let nonSession = windows.compactMap { window -> (window: Window, duration: TimeInterval)? in
            guard case .billingPeriod(_, let duration) = window.value.window.kind, duration > 0
            else { return nil }
            return (window, duration)
        }
        return nonSession.max { $0.duration < $1.duration }?.window ?? windows.first
    }

    private static func isWeekly(_ kind: WindowKind) -> Bool {
        switch kind {
        case .weekly, .billingPeriod(label: "Weekly", duration: _): true
        case .other(let label): AntigravityRowLabels.parse(label)?.window == .weekly
        default: false
        }
    }

    private static func detailOrder(_ first: UsageWindow, _ second: UsageWindow) -> Bool {
        let firstRank = detailRank(first.kind)
        let secondRank = detailRank(second.kind)
        if firstRank != secondRank { return firstRank < secondRank }
        return first.kind.persistentID < second.kind.persistentID
    }

    private static func detailRank(_ kind: WindowKind) -> Int {
        if kind == .fiveHour || AntigravityRowLabels.parse(kind)?.window == .fiveHour { return 0 }
        if isWeekly(kind) { return 1 }
        if case .billingPeriod = kind { return 3 }
        return 2
    }

    private static func status(
        snapshot: UsageSnapshot, attention: String?, remembered: Bool,
        lastRead: String?, hasReading: Bool
    ) -> String? {
        if let attention { return attention }
        if remembered { return lastRead ?? "No retained reading" }
        if let recovery = snapshot.planStatusRecovery { return recovery.status }
        if snapshot.freshness == .pending { return "Reading for the first time…" }
        if case .stale(let reason) = snapshot.freshness, !hasReading || reason.isPermanent {
            return reason.message
        }
        if hasReading { return nil }
        return snapshot.providerID == .copilot ? "No reading yet this month" : "No usage data"
    }

    private static func isTighter(_ first: Window, _ second: Window) -> Bool {
        if (first.value.displayedPercentage != nil) != (second.value.displayedPercentage != nil) {
            return first.value.displayedPercentage != nil
        }
        if first.value.window.freshness.isLive != second.value.window.freshness.isLive {
            return first.value.window.freshness.isLive
        }
        func rank(_ tier: MenuBarPace.Tier?) -> Int {
            switch tier {
            case .farOffPace: 2
            case .offPace: 1
            case .onPace, nil: 0
            }
        }
        let firstRank = rank(first.pace?.tier)
        let secondRank = rank(second.pace?.tier)
        if firstRank != secondRank { return firstRank > secondRank }
        let firstIsFast = first.pace?.direction == .fast
        let secondIsFast = second.pace?.direction == .fast
        if firstIsFast != secondIsFast { return firstIsFast }
        let firstGap = abs(first.pace?.deviationTenths ?? 0)
        let secondGap = abs(second.pace?.deviationTenths ?? 0)
        if firstGap != secondGap { return firstGap > secondGap }
        let firstRemaining = first.value.window.percentRemaining
        let secondRemaining = second.value.window.percentRemaining
        if firstRemaining != secondRemaining { return firstRemaining < secondRemaining }
        return first.value.window.kind.persistentID < second.value.window.kind.persistentID
    }

    /// Compact labels share the pace column with the section heading.
    public static func column(for kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return "5h"
        case .weekly: return "Week"
        case .other(let label):
            if let pool = AntigravityRowLabels.parse(label) {
                return AntigravityRowLabels.short(pool.pool, pool.window)
            }
            if let model = WindowKind.modelAndPeriod(in: label) {
                let period = model.period == .weekly ? "wk" : "5h"
                let title = kind.isCodexSparkCounter ? "Spark" : String(model.model.prefix(6))
                return "\(title) \(period)"
            }
            return String(CompactAccountRowRecipe.shortLabel(for: kind).prefix(9))
        case .billingPeriod(let label, _):
            switch label {
            case "Weekly": return "Week"
            case "Monthly": return "Month"

            default: return kind.poolDisplayName(grouped: true) ?? String(CompactAccountRowRecipe.shortLabel(for: kind).prefix(9))
            }
        }
    }
}
