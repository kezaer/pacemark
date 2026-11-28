import Foundation
import PacemarkCore

struct SettingsPreviewFixtures {
    let now: Date
    let entries: [ProviderAccountEntry]
    let providerOrder: [ProviderID] = [.claude, .codex]

    init(now: Date = DemoFixture.now) {
        self.now = now
        entries = [
            Self.entry(.claude, name: "Personal", plan: "Max", weeklyUsed: 50, sessionUsed: 50, offset: 3600, now: now),
            Self.entry(.claude, name: "Work", plan: "Pro", weeklyUsed: 60, sessionUsed: 75, offset: 0, now: now),
            Self.entry(.codex, name: "Pro 200", plan: "Pro", weeklyUsed: 40, sessionUsed: 50, offset: 7200, now: now),
            Self.entry(.codex, name: "100", plan: "Pro Lite", weeklyUsed: 75, sessionUsed: 50, offset: 10800, now: now),
        ]
    }

    var candidates: [PopoverSummaryRecipe.Candidate] {
        entries.flatMap { entry in
            PopoverSummaryRecipe.Candidate.readings(
                key: entry.account.key, title: entry.account.label,
                row: LedgerSectionView.recipe(for: entry, percentageMode: .remaining, now: now)
            )
        }
    }

    func summary(slots: [PopoverSummarySlot]) -> PopoverSummaryRecipe {
        PopoverSummaryRecipe(slots: slots, candidates: candidates,
                                    spend: [DemoFixture.anthropicSpend, DemoFixture.openAISpend], now: now)
    }

    private static func entry(
        _ provider: ProviderID, name: String, plan: String,
        weeklyUsed: Double, sessionUsed: Double, offset: TimeInterval, now: Date
    ) -> ProviderAccountEntry {
        let account = ProviderAccount(id: AccountID("settings-preview-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"), providerID: provider, label: name, isBuiltIn: false)
        let windows = [
            UsageWindow(kind: .fiveHour, utilization: sessionUsed, resetsAt: now.addingTimeInterval(9000 + offset / 24)),
            UsageWindow(kind: .weekly, utilization: weeklyUsed, resetsAt: now.addingTimeInterval(302400 + offset)),
        ]
        return ProviderAccountEntry(account: account, snapshot: UsageSnapshot(
            providerID: provider, windows: windows, planLabel: plan, capturedAt: now, freshness: .live
        ))
    }
}
