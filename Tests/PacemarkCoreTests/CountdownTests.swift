import Foundation
import Testing
@testable import PacemarkCore

struct CountdownTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func approvedCountdownPrecision() {
        #expect(text(after: 6 * 86_400 + 4 * 3_600 + 37 * 60) == "Resets in 6d 4h")
        #expect(text(after: 6 * 86_400 + 37 * 60) == "Resets in 6d")
        #expect(text(after: 13 * 3_600 + 37 * 60) == "Resets in 13h 37m")
        #expect(text(after: 37 * 60) == "Resets in 37m")
    }

    @Test func spokenResetJoinsUnitsAndPreservesUnknownCopy() {
        #expect(Countdown.spokenReset("1d 2h") == "resets in 1 day and 2 hours")
        #expect(Countdown.spokenReset("2h 1m") == "resets in 2 hours and 1 minute")
        #expect(Countdown.spokenReset("later today") == "later today")
    }

    @Test func immediateResetCopyStartsAtTheSourceBoundary() {
        #expect(text(after: 61) == "Resets in 1m")
        #expect(text(after: 60) == "Resets now")
        #expect(text(after: -60) == "Resets now")
    }

    @Test func resetClockShowsTimeForBothNearAndDistantDeadlines() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        let now = try #require(DateParsing.iso8601("2025-12-01T08:00:00Z"))
        let tomorrow = now.addingTimeInterval(25 * 3_600)
        let distant = now.addingTimeInterval(7 * 86_400 + 8 * 3_600)
        func clockText(_ deadline: Date, windowName: String) -> String? {
            Countdown.resetClockText(deadline: deadline, windowName: windowName, now: now, timeZone: utc, locale: locale)?
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(clockText(tomorrow, windowName: "Weekly") == "Weekly resets tomorrow at 9:00 AM")
        #expect(clockText(distant, windowName: "Monthly") == "Monthly resets Mon, Dec 8 at 4:00 PM")
        #expect(Countdown.resetClockText(deadline: nil, windowName: "Monthly", now: now, timeZone: utc, locale: locale) == nil)
    }

    /// R2M3: past the deadline the countdown holds "now" rather than blanking — the
    /// pre-reset percentage is still on screen until a fresh capture lands, and a missing
    /// label beside a stale number reads as a bug.
    @Test func countdownHoldsNowPastTheDeadline() {
        #expect(text(after: -61) == "Resets now")
        #expect(text(after: -37 * 60) == "Resets now")
        #expect(text(after: -4 * 3_600) == "Resets now")

        let elapsed = Countdown.resetLine(resetsAt: now.addingTimeInterval(-3_600), now: now)
        #expect(elapsed?.countdown == "now")
        #expect(elapsed?.shortCountdown == "now")
        #expect(elapsed?.tooltip == "Resets now")
    }

    /// A new capture is what ends the hold: a later deadline resumes the countdown.
    @Test func aFreshCaptureResumesTheCountdown() {
        #expect(text(after: 5 * 3_600) == "Resets in 5h")
    }

    @Test func availableRequiresFreshSameCaptureEvidence() {
        let liveZeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent)
        )
        let liveZeroElapsed = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.elapsed)
        )
        let liveNonzeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 12,
            resetSchedule: .unresolved(.absent)
        )
        let staleZeroAbsent = UsageWindow(
            kind: .fiveHour,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            freshness: .stale(observedAt: now.addingTimeInterval(-300))
        )

        #expect(Countdown.resetText(for: liveZeroAbsent, now: now) == "Available")
        #expect(Countdown.resetText(for: liveZeroElapsed, now: now) == "Available")
        #expect(Countdown.resetText(for: liveNonzeroAbsent, now: now) == "Reset info unavailable")
        #expect(Countdown.resetText(for: staleZeroAbsent, now: now) == "Reset info unavailable")
    }

    private func text(after interval: TimeInterval) -> String {
        let window = UsageWindow(
            kind: .weekly,
            utilization: 20,
            resetSchedule: .scheduled(now.addingTimeInterval(interval))
        )
        return Countdown.resetText(for: window, now: now)
    }
}
