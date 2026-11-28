import Foundation
import Testing
@testable import PacemarkCore

struct MenuBarGlyphTests {
    @Test func badgesAreShortAndKeepTrailingSubscriptionNumbers() {
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro100", index: 0) == "100")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro200", index: 1) == "200")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Work", index: 0) == "W")
        #expect(MenuBarAccountBadge.defaultBadge(for: "  🟩 ", index: 1) == "2")
        #expect(MenuBarAccountBadge.sanitize("  x+2000 ") == "X200")
        #expect(MenuBarAccountBadge.sanitize("  ") == nil)
    }

    @Test(arguments: UsagePercentageMode.allCases)
    func tickAndSpokenPaceFollowTheReadingInEitherPercentageMode(mode: UsagePercentageMode) throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let pace = try #require(MenuBarPace(usedFraction: 0.15, duration: 100, reset: now.addingTimeInterval(75), now: now))
        let summary = MenuBarSummary(text: mode == .used ? "15%" : "85%", providerID: .codex,
                                     detail: "Codex Weekly", isNeutral: false, percentageMode: mode)
        let meter = MenuBarMeter(summary: summary, fill: nil, isLiveReading: true, pace: pace, countdown: "3d")
        #expect(meter.expectedFill == (mode == .used ? 0.25 : 0.75))
        #expect(meter.accessibilityReading == (mode == .used
            ? "Codex Weekly, 15 percent used, using slowly, resets in 3 days"
            : "Codex Weekly, 85 percent left, using slowly, resets in 3 days"))

        let unknown = MenuBarMeter(summary: summary, fill: nil, isLiveReading: true)
        #expect(unknown.expectedFill == nil)
        #expect(unknown.accessibilityReading == (mode == .used
            ? "Codex Weekly, 15 percent used" : "Codex Weekly, 85 percent left"))
    }

    @Test func refreshingOneSubscriptionDoesNotAnimateTheOtherAccountsPill() {
        let main = AccountKey(providerID: .codex, accountID: AccountID("pro100"))
        let other = AccountKey(providerID: .codex, accountID: AccountID("pro200"))
        let meters = [main, other].map { key in
            MenuBarMeter(
                summary: .init(text: "50%", providerID: .codex, detail: nil, isNeutral: false),
                fill: 0.5, sourceAccountKey: key, glyph: .providerMark(.codex), badge: key == main ? "100" : "200"
            )
        }
        let now = Date()
        let recipe = ReprintRecipe(
            meters: meters, automatic: false, currentMains: [.codex: main], run: nil,
            probingAccounts: [other], probeEndTimes: [:], spendInFlightProviders: [],
            visibleWork: .init(clearedAt: now), now: now
        )
        #expect(recipe.pills.map(\.id) == [main.description, other.description])
        #expect(recipe.pills.map(\.isSloshing) == [false, true])
    }
}
