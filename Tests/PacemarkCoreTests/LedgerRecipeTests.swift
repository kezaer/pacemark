import Foundation
import Observation
import Testing
@testable import PacemarkCore

struct LedgerRecipeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func window(
        _ kind: WindowKind = .fiveHour, used: Double, resetsIn: TimeInterval,
        freshness: UsageWindowFreshness = .live
    ) -> UsageWindow {
        UsageWindow(kind: kind, utilization: used, resetsAt: now.addingTimeInterval(resetsIn), freshness: freshness)
    }

    private func row(
        _ windows: [UsageWindow], freshness: Freshness = .live, capturedMinutesAgo: Double = 42,
        attention: String? = nil, remembered: Bool = false, providerID: ProviderID = .claude,
        choice: MenuBarWindowChoice = .weekly, showsAntigravityFiveHourWindows: Bool = true,
        bankedResets: Int? = nil
    ) -> LedgerRowRecipe {
        let snapshot = UsageSnapshot(
            providerID: providerID, windows: windows, planLabel: nil, bankedResets: bankedResets,
            capturedAt: now.addingTimeInterval(-capturedMinutesAgo * 60), freshness: freshness
        )
        return LedgerRowRecipe(snapshot: snapshot, percentageMode: .remaining, now: now, windowChoice: choice,
                               attention: attention, showsCodexSparkCounters: true,
                               showsAntigravityFiveHourWindows: showsAntigravityFiveHourWindows,
                               isRemembered: remembered)
    }

    @Test func inlineMessagesReplaceOnlyRowsThatNeedWords() {
        let critical = window(used: 80, resetsIn: 8_960)
        #expect(row([critical]).message == nil)
        #expect(row([critical], attention: "Signed out").message == "Signed out")
        #expect(row([critical], attention: "Waiting in Terminal").message == "Waiting in Terminal")
        let stale = row([critical], freshness: .stale(.transient("Offline")))
        #expect(stale.message == nil)
        #expect(stale.isDimmed)
        #expect(stale.primary?.value.displayedPercentage == 20)
        #expect(stale.accessibilityHint == "Last good read 42 min ago")
        #expect(row([critical], freshness: .stale(.transient("Offline")), remembered: true).message == "Last read 42 min ago")
        #expect(row([], freshness: .pending).message == "Reading for the first time…")
        #expect(row([], providerID: .copilot).message == "No reading yet this month")
        let noPlan = UsageSnapshot(providerID: .opencode, windows: [], planLabel: nil, capturedAt: now,
                                   freshness: .live, planStatus: .noActivePlan)
        #expect(LedgerRowRecipe(snapshot: noPlan, percentageMode: .remaining, now: now).message
                == "No Go plan on this workspace")
    }

    @Test func weeklyWinsEvenWhenTheSessionRunsOutFirst() {
        let short = window(used: 97, resetsIn: 9_000)
        let week = window(.weekly, used: 15, resetsIn: 322_000)
        let month = window(.billingPeriod(label: "Monthly", duration: 2_592_000), used: 80, resetsIn: 1_296_000)
        let model = window(.other("Weekly (Fable)"), used: 60, resetsIn: 302_400)
        let recipe = row([month, model, week, short])
        #expect(recipe.message == nil)
        #expect(recipe.primary?.value.window.kind == .weekly)
        #expect(recipe.primary?.column == "Week")
        #expect(recipe.primary?.pace?.tier == .farOffPace(.slow))
        #expect(recipe.windows.map(\.value.window.kind) == [.fiveHour, .weekly, model.kind, month.kind])
        #expect(recipe.windows.map(\.detailLabel) == ["5h", "Weekly", "Fable", "Monthly"])
        #expect(recipe.windows.first { $0.detailLabel == "Fable" }?.pace?.expectedRemaining == 0.5)
        #expect(recipe.windows.first { $0.detailLabel == "Fable" }?.pace?.tier == .offPace(.fast))
        #expect(row([short, model]).primary?.value.window.kind == .fiveHour)
        #expect(recipe.canExpand)
        let unavailable = window(.weekly, used: 65, resetsIn: 9_000, freshness: .unavailable(since: now))
        #expect(row([short, unavailable]).primary?.value.window.kind == .weekly)
    }

    @Test func usesTheSavedWindowOrFallsBackToTheClosestReading() {
        let session = window(used: 80, resetsIn: 9_000)
        let week = window(.weekly, used: 30, resetsIn: 320_000)
        let fable = window(.other("Weekly (Fable)"), used: 50, resetsIn: 250_000)
        let windows = [session, week, fable]
        let choice = MenuBarWindowChoice.window(id: fable.kind.persistentID)
        let selected = row(windows, choice: choice)
        #expect(selected.primary?.column == "Fable")
        #expect(selected.primary?.value.displayedPercentage == 50)
        #expect(selected.primary?.resetDeadline == fable.resetSchedule.deadline)
        #expect(selected.windows.count == windows.count)
        #expect(row(windows, choice: .fiveHour).primary?.column == "5h")
        #expect(row(windows, choice: .closest).primary?.value.window == session)
        #expect(row([session, week], choice: choice).primary?.value.window == session)
        let unavailable = fable.withFreshness(.unavailable(since: now))
        #expect(row([session, week, unavailable], choice: choice).primary?.value.window == session)
    }

    @Test func prefersLongestNonSessionWindowThenAnyAvailableKind() {
        let month = WindowKind.billingPeriod(label: "Monthly", duration: 2_592_000)
        let pool = WindowKind.billingPeriod(label: "Cursor Models", duration: 1_209_600)
        let fiveHour = window(used: 10, resetsIn: 9_000)
        let monthly = window(month, used: 20, resetsIn: 1_296_000)
        #expect(row([fiveHour, monthly, window(pool, used: 95, resetsIn: 20_000)]).primary?.value.window.kind == month)
        #expect(row([window(.other("Fable"), used: 10, resetsIn: 500)]).primary?.detailLabel == "Fable")
        #expect(row([fiveHour]).primary?.value.window.kind == .fiveHour)
        #expect(!row([fiveHour]).canExpand)
        let billingWeek = window(.billingPeriod(label: "Weekly", duration: 604_800), used: 45, resetsIn: 300_000)
        #expect(row([monthly, billingWeek]).primary?.value.window.kind == billingWeek.kind)
    }

    @Test func openCodeShowsWeeklyAndKeepsLimitAccessible() {
        let limitedWeek = UsageWindow(kind: .weekly, utilization: 100,
                                      resetSchedule: .scheduled(now.addingTimeInterval(302_400)), isLimited: true)
        let limited = row([window(used: 10, resetsIn: 9_000), limitedWeek], providerID: .opencode)
        #expect(limited.primary?.value.window.kind == .weekly)
        #expect(limited.message == nil)
        #expect(limited.accessibilityHint?.contains("weekly limit is reached") == true)
    }

    @Test func antigravityChoosesTheTighterWeeklyPoolAndKeepsAllWindows() {
        let session = window(.other("Gemini 5h"), used: 98, resetsIn: 9_000)
        let other = window(.other("Other weekly"), used: 45, resetsIn: 500_000)
        let gemini = window(.other("Gemini weekly"), used: 60, resetsIn: 100_000)
        let pools = row([session, other, gemini], providerID: .antigravity)
        #expect(pools.windows.map(\.detailLabel) == ["Gemini 5h", "Gemini weekly", "Other weekly"])
        #expect(pools.primary?.column == "Other wk")
        let choice = MenuBarWindowChoice.window(id: gemini.kind.persistentID)
        #expect(row([session, other, gemini], providerID: .antigravity, choice: choice).primary?.column == "Gemini wk")
        let sessionChoice = MenuBarWindowChoice.window(id: session.kind.persistentID)
        #expect(row([session, other, gemini], providerID: .antigravity, choice: sessionChoice).primary?.value.window == session)
        #expect(row([session, other, gemini], providerID: .antigravity, choice: sessionChoice,
                    showsAntigravityFiveHourWindows: false).primary?.value.window == gemini)
        let replay = row([window(.weekly, used: 60, resetsIn: 302_400)], providerID: .antigravity)
        #expect(replay.windows.map(\.column) == ["Week"])
        #expect(replay.windows.first?.pace?.expectedRemaining == 0.5)
    }

    @Test func antigravityPoolRankingUsesBandDirectionAndAbsoluteDeviation() {
        let gemini = WindowKind.other("Gemini weekly")
        let other = WindowKind.other("Other weekly")
        let halfWeek: TimeInterval = 302_400
        let yellowSlow = window(gemini, used: 40, resetsIn: halfWeek)
        let redSlow = window(other, used: 15, resetsIn: halfWeek)
        #expect(row([yellowSlow, redSlow], providerID: .antigravity).primary?.value.window == redSlow)

        let lessRedSlow = window(gemini, used: 30, resetsIn: halfWeek)
        #expect(row([lessRedSlow, redSlow], providerID: .antigravity).primary?.value.window == redSlow)

        let redFast = window(gemini, used: 66, resetsIn: halfWeek)
        #expect(row([redFast, redSlow], providerID: .antigravity).primary?.value.window == redFast)

        let yellowFast = window(gemini, used: 60, resetsIn: halfWeek)
        #expect(row([yellowFast, redSlow], providerID: .antigravity).primary?.value.window == redSlow)
        let staleRed = redSlow.withFreshness(.stale(observedAt: now))
        #expect(row([yellowFast, staleRed], providerID: .antigravity).primary?.value.window == yellowFast)

        let sameReading = window(gemini, used: 15, resetsIn: halfWeek)
        #expect(row([redSlow, sameReading], providerID: .antigravity).primary?.value.window == sameReading)
    }

    @Test func redSlowNeverOutranksProjectedDepletionInTightestSummary() throws {
        let slowKey = ProviderAccount.builtIn(for: .claude).key
        let fastKey = ProviderAccount.builtIn(for: .codex).key
        let slow = window(used: 15, resetsIn: 9_000)
        let fast = window(used: 60, resetsIn: 9_000)
        #expect(row([slow]).primary?.pace?.tier == .farOffPace(.slow))
        let tightest = try #require(PopoverSummaryRecipe.tightest(candidates: [
            .init(key: slowKey, title: "Slow", window: slow),
            .init(key: fastKey, title: "Fast", window: fast)
        ], now: now))
        #expect(tightest.candidate.key == fastKey)
        #expect(tightest.projection != nil)
    }

    @Test func nextResetIncludesTheTightestWindowWhenItResetsFirst() throws {
        let claude = ProviderAccount.builtIn(for: .claude).key
        let session = window(used: 90, resetsIn: 3_600)
        let week = window(.weekly, used: 15, resetsIn: 250_000)
        let candidates = PopoverSummaryRecipe.Candidate.readings(
            key: claude, title: "Main", row: row([session, week]))
        let summary = PopoverSummaryRecipe(slots: [.nextReset, .tightest], candidates: candidates, spend: [], now: now)
        #expect(summary.tiles.count == 2)
        guard case .nextReset(let next) = summary.tiles[0], case .tightest(let tightest) = summary.tiles[1] else {
            Issue.record("Expected both summary tiles")
            return
        }
        #expect(tightest.candidate.window == session)
        #expect(next.candidate.key == claude)
        #expect(next.candidate.window == session)
        #expect(next.nextResetCaption == "5h · 10% left")
        #expect(tightest.tightestCaption == "5h · empty in ~27m")
    }

    @Test func creditsFollowTheAggregateCodexWindowsOnly() {
        let session = window(used: 80, resetsIn: 9_000)
        let week = window(.weekly, used: 30, resetsIn: 320_000)
        let spark = window(.other("Codex Spark Weekly"), used: 50, resetsIn: 250_000)
        let readings = [session, week, spark]
        let sparkChoice = MenuBarWindowChoice.window(id: spark.kind.persistentID)
        let selected = row(readings, providerID: .codex, choice: sparkChoice, bankedResets: 3)
        #expect(selected.primary?.value.window == spark)
        #expect(selected.primary?.bankedResets == nil)
        #expect(selected.windows.map(\.bankedResets) == [3, 3, nil])
        #expect(row(readings, providerID: .codex, choice: .fiveHour, bankedResets: 3).primary?.bankedResets == 3)
        #expect(row(readings, providerID: .codex, bankedResets: 3).primary?.bankedResets == 3)
        #expect(row(readings, providerID: .codex, bankedResets: 0).windows.allSatisfy { $0.bankedResets == nil })
        #expect(row([week], bankedResets: 3).primary?.bankedResets == nil)
    }

    @MainActor @Test func perMeterChoiceLeavesTheLedgerWindowAlone() throws {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.setMenuBarWindowChoice(.fiveHour, for: .claude)
        let fixture = DemoFixture.multiFixture(for: .menubar)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        let meter = try #require(store.menuBarMeterRows.first { $0.key.providerID == .claude })
        let readings = [window(used: 80, resetsIn: 9_000), window(.weekly, used: 30, resetsIn: 320_000)]
        store.setMenuBarWindow(.limit("weekly"), for: meter)
        #expect(row(readings, choice: store.menuBarWindowChoice(for: .claude)).primary?.column == "5h")
    }

    @Test func unusedAntigravityPoolShowsOnlyAGenuineFutureReset() {
        let kind = WindowKind.other("Other weekly")
        let elapsed = row([window(kind, used: 0, resetsIn: -30)], providerID: .antigravity)
        #expect(elapsed.primary?.value.displayedPercentage == 100)
        #expect(elapsed.primary?.countdown == nil)
        #expect(elapsed.primary?.resetDeadline == nil)
        #expect(elapsed.primary?.pace == nil)
        let future = row([window(kind, used: 0, resetsIn: 10_800)], providerID: .antigravity)
        #expect(future.primary?.countdown == "3h")
        #expect(future.primary?.resetDeadline == now.addingTimeInterval(10_800))
        #expect(future.primary?.pace?.expectedRemaining != nil)
    }

    @Test func unavailableReadingsHaveNoPercentageOrPace() {
        let unavailable = window(used: 95, resetsIn: 9_000, freshness: .unavailable(since: now))
        let recipe = row([unavailable])
        #expect(recipe.windows.first?.value.displayedPercentage == nil)
        #expect(recipe.windows.first?.resetDeadline == nil)
        #expect(recipe.windows.first?.pace == nil)
        let remembered = row([window(used: 70, resetsIn: -100)], remembered: true)
        #expect(remembered.windows.first?.value.displayedPercentage == nil)
        #expect(remembered.windows.first?.passedReset?.contains("not read since") == true)
    }

    @Test func tightestPrioritizesRunoutAndNextResetUsesTheSoonestDeadline() {
        let keys = [ProviderAccount.builtIn(for: .grok).key, ProviderAccount.builtIn(for: .claude).key]
        let lowButOnPace = window(used: 90, resetsIn: 1_700)
        let ahead = window(used: 65, resetsIn: 9_000)
        let snapshot = [
            PopoverSummaryRecipe.Candidate(key: keys[0], title: "Main", window: lowButOnPace),
            .init(key: keys[1], title: "Work", window: ahead)
        ]
        let result = PopoverSummaryRecipe(slots: [.tightest, .nextReset], candidates: snapshot, spend: [], now: now)
        guard result.tiles.count == 2, case .tightest(let tightest) = result.tiles[0],
              case .nextReset(let next) = result.tiles[1] else {
            Issue.record("Expected tightest and next reset tiles")
            return
        }
        #expect(tightest.candidate.key == keys[1])
        #expect(tightest.projection != nil)
        #expect(next.candidate.key == keys[0])
        #expect(next.countdown == "28m")
        #expect(next.tightestCaption == "5h · resets in 28m")
    }

    @Test func aWindowAlreadyEmptyBeatsAnyProjectedRunout() throws {
        let claude = ProviderAccount.builtIn(for: .claude).key
        let codex = ProviderAccount.builtIn(for: .codex).key
        let earlyEmpty = window(used: 100, resetsIn: 17_900)
        let laterRunout = window(used: 65, resetsIn: 9_000)
        let result = try #require(PopoverSummaryRecipe.tightest(candidates: [
            .init(key: codex, title: "Work", window: laterRunout),
            .init(key: claude, title: "Main", window: earlyEmpty)
        ], now: now))
        #expect(result.candidate.key == claude)
        #expect(result.projection?.timeToEmpty == 0)
    }

    @Test func anEmptyWindowWithoutAResetDeadlineStillWinsTightest() throws {
        let empty = UsageWindow(kind: .weekly, utilization: 100, resetSchedule: .unresolved(.absent))
        let projectedRunout = window(used: 65, resetsIn: 9_000)
        let key = ProviderAccount.builtIn(for: .claude).key
        let candidates = PopoverSummaryRecipe.Candidate.readings(
            key: key, title: "Main", row: row([projectedRunout, empty]))
        let tightest = try #require(PopoverSummaryRecipe.tightest(candidates: candidates, now: now))
        #expect(tightest.candidate.window.kind == .weekly)
        #expect(tightest.projection?.timeToEmpty == 0)
        #expect(tightest.countdown == nil)
    }

    @Test func nextResetAppearsWhenOnlyTightestHasAReset() throws {
        let key = ProviderAccount.builtIn(for: .claude).key
        let session = window(used: 90, resetsIn: 3_600)
        let week = UsageWindow(kind: .weekly, utilization: 25, resetSchedule: .unresolved(.absent))
        let candidates = PopoverSummaryRecipe.Candidate.readings(
            key: key, title: "Main", row: row([session, week]))
        let summary = PopoverSummaryRecipe(slots: [.tightest, .nextReset], candidates: candidates, spend: [], now: now)
        #expect(summary.tiles.count == 2)
        guard case .tightest(let tightest) = try #require(summary.tiles.first) else {
            Issue.record("Expected the Tightest tile")
            return
        }
        #expect(tightest.candidate.window.kind == .fiveHour)
    }

    @Test func summarySlotSwapsOnlyOccupiedOptions() {
        #expect(PopoverSummarySlot.tightest.otherSlot(afterSelecting: .apiSpend, opposite: .apiSpend) == .tightest)
        #expect(PopoverSummarySlot.off.otherSlot(afterSelecting: .nextReset, opposite: .nextReset) == .off)
        #expect(PopoverSummarySlot.tightest.otherSlot(afterSelecting: .off, opposite: .off) == .off)
    }

    @Test func absentSpendAndOffSlotsLeaveOnlyAvailableTiles() {
        let key = ProviderAccount.builtIn(for: .claude).key
        let candidate = PopoverSummaryRecipe.Candidate(key: key, title: "Main", window: window(used: 20, resetsIn: 9_000))
        let candidates = [candidate, .init(key: key, title: "Main", window: window(used: 5, resetsIn: 9_000))]
        let result = PopoverSummaryRecipe(slots: [.apiSpend, .tightest], candidates: candidates, spend: [], now: now)
        guard result.tiles.count == 1, case .tightest(let tightest) = result.tiles.first else {
            Issue.record("Expected only the tightest account tile")
            return
        }
        #expect(tightest.candidate.window == candidate.window)
        #expect(PopoverSummaryRecipe(slots: [.off, .off], candidates: candidates, spend: [], now: now).tiles.isEmpty)
        let spend = APISpendSnapshot.pending(providerID: .claude, displayName: "Anthropic API", periodLabel: "November")
        let withSpend = PopoverSummaryRecipe(slots: [.off, .apiSpend], candidates: [], spend: [spend], now: now)
        guard case .apiSpend(let rows) = withSpend.tiles.first else {
            Issue.record("Expected a configured spend source while it is pending")
            return
        }
        #expect(rows == [spend])
    }

    @Test func slotPreferencesPersistIndependently() {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.popoverSummarySlot1 == .off)
        #expect(preferences.popoverSummarySlot2 == .off)
        preferences.popoverSummarySlot1 = .off
        preferences.popoverSummarySlot2 = .nextReset
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.popoverSummarySlot1 == .off)
        #expect(reloaded.popoverSummarySlot2 == .nextReset)
    }

    @MainActor @Test func accountExpansionPersistsAndPrunesRemovedKeys() {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        let fixture = DemoFixture.multiFixture(for: .menubar)
        let tracked = fixture.accounts[0].key
        let removed = AccountKey(providerID: tracked.providerID, accountID: AccountID("removed"))
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(store.popoverExpandedAccounts.isEmpty)
        store.togglePopoverAccountExpansion(tracked)
        #expect(Preferences(defaults: defaults).popoverExpandedAccounts == [tracked])

        preferences.popoverExpandedAccounts = [tracked, removed]
        let reopened = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(reopened.popoverExpandedAccounts == [tracked])
        #expect(preferences.popoverExpandedAccounts == [tracked])
        reopened.togglePopoverAccountExpansion(tracked)
        #expect(preferences.popoverExpandedAccounts.isEmpty)
    }

    @MainActor @Test func removingRememberedAccountClearsItsSavedExpansion() throws {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let fixture = DemoFixture.multiFixture(for: .remembered)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts,
                               defaultLoginRecords: fixture.makeDefaultLoginRecordStore())
        let key = try #require(store.rememberedAccounts(for: .claude).first?.key)
        store.togglePopoverAccountExpansion(key)
        #expect(store.removeRememberedAccount(key))
        #expect(preferences.popoverExpandedAccounts.isEmpty)
    }
}
