#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct LedgerSummaryColumns<Content: View>: View {
    var count = 2
    var spacing = PDS.Space.s
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: count)) {
            content()
        }
    }
}

struct LedgerSummaryStrip: View {
    let recipe: PopoverSummaryRecipe
    let period: APISpendPeriod
    let mode: UsagePercentageMode
    let now: Date
    var spacing = PDS.Space.s
    let onAccount: (AccountKey) -> Void
    let onSpend: () -> Void

    var body: some View {
        if !recipe.tiles.isEmpty {
            LedgerSummaryColumns(count: recipe.tiles.count, spacing: spacing) {
                ForEach(Array(recipe.tiles.enumerated()), id: \.offset) { _, tile in
                    Button {
                        switch tile {
                        case .tightest(let reading), .nextReset(let reading): onAccount(reading.candidate.key)
                        case .apiSpend: onSpend()
                        }
                    } label: {
                        LedgerSummaryTile(tile: tile, period: period, mode: mode, now: now)
                    }
                    .buttonStyle(LedgerTileButtonStyle())
                }
            }
        }
    }
}

struct LedgerSummaryTile: View {
    let tile: PopoverSummaryRecipe.Tile
    let period: APISpendPeriod
    let mode: UsagePercentageMode
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch tile {
        case .tightest(let reading), .nextReset(let reading):
            let window = reading.candidate.window
            let readingMode: UsagePercentageMode = tile.slot == .tightest ? mode : .remaining
            let amount = UsageMeterReading(window: window).roundedPercentage(for: readingMode)
            let unit = readingMode == .used ? "used" : "left"
            let spoken = [
                tile.slot == .tightest ? "Tightest" : tile.slot.label,
                reading.candidate.key.providerID.displayName, reading.candidate.title,
                window.displayLabel ?? LedgerRowRecipe.column(for: window.kind),
                amount.map { "\($0) percent \(unit)" }, reading.pace.tier?.label.lowercased(),
                reading.countdown.map(Countdown.spokenReset), reading.projection?.emptyLine
            ].compactMap { $0 }.joined(separator: ", ")
            card.accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        case .apiSpend:
            card
        }
    }

    private var card: some View {
        PDSCard(accessory: { EmptyView() }) {
            VStack(alignment: .leading, spacing: PDS.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PDS.Space.xs) {
                    PDSCapsHeader(tile.slot == .tightest ? "Tightest" : tile.slot.label).fixedSize()
                    Spacer(minLength: 0)
                    switch tile {
                    case .tightest(let reading), .nextReset(let reading):
                        ProviderLogoView(providerID: reading.candidate.key.providerID, size: PDS.Metrics.rowMark)
                            .accessibilityLabel(reading.candidate.key.providerID.displayName)
                        Text(reading.candidate.title)
                    case .apiSpend:
                        Text(period.displayLabel(now: now).uppercased())
                    }
                }
                .font(PDS.Typography.caps)
                .foregroundStyle(PDS.Ink.inkSecondary)
                switch tile {
                case .tightest(let reading):
                    let window = reading.candidate.window
                    let amount = UsageMeterReading(window: window).roundedPercentage(for: mode)
                    let fallback = UsageMeterReading(window: window).severity
                    let band = reading.pace.tier?.severity ?? fallback
                    let ink = band == .healthy ? ProviderStyle.severityColor(for: .healthy, scheme: scheme)
                        : LedgerInk.usage(reading.pace.tier, fallback: fallback, scheme: scheme)
                    value(amount.map { "\($0)%" } ?? "—", unit: mode == .used ? "used" : "left", ink: ink)
                    paceBar(reading, mode: mode)
                    footnote(reading.tightestCaption)
                        .ledgerResetHelp(deadline: window.resetSchedule.deadline, window: window, now: now)
                case .nextReset(let reading):
                    value(reading.countdown ?? "—")
                        .ledgerResetHelp(deadline: reading.candidate.window.resetSchedule.deadline,
                                         window: reading.candidate.window, now: now)
                    paceBar(reading, mode: .remaining)
                    footnote(reading.nextResetCaption)
                case .apiSpend(let snapshots):
                    value(spend(snapshots))
                    Color.clear.frame(height: PDS.Space.s)
                    footnote(period.label)
                }
            }
            .lineLimit(1)
            .frame(height: LedgerMetrics.summaryHeight - 2 * PDS.Space.xs)
        }
    }

    private func paceBar(_ reading: PopoverSummaryRecipe.Reading, mode: UsagePercentageMode) -> some View {
        GeometryReader { proxy in
            LedgerPaceBar(remaining: reading.pace.remaining, pace: reading.pace,
                          severity: UsageMeterReading(window: reading.candidate.window).severity ?? .healthy,
                          width: proxy.size.width, mode: mode)
                .frame(maxHeight: .infinity)
        }.frame(height: PDS.Space.s)
    }

    private func spend(_ snapshots: [APISpendSnapshot]) -> String {
        let periodRows = snapshots.filter { $0.kind == .periodSpend && $0.freshness == .live }
        let currency = periodRows.first(where: { $0.amount != nil })?.currency
        let amounts = periodRows.filter { $0.currency == currency }.compactMap(\.amount).filter(\.isFinite)
        guard Set(periodRows.compactMap(\.currency)).count <= 1, !amounts.isEmpty else { return "—" }
        return APISpendPresentation.amountText(amount: amounts.reduce(0, +), currency: currency) ?? "—"
    }

    private func value(_ amount: String, unit: String? = nil, ink: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PDS.Space.xs) {
            Text(amount).font(PopoverLedgerType.hero).foregroundStyle(ink).lineLimit(1).truncationMode(.tail)
            if let unit {
                Text(unit).font(PopoverLedgerType.unit).foregroundStyle(PDS.Ink.inkSecondary)
            }
        }
        .frame(height: 21, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(PopoverLedgerType.sentence)
            .foregroundStyle(PDS.Ink.inkSecondary)
            .lineLimit(1).truncationMode(.tail)
            .frame(height: 13, alignment: .leading)
    }
}

private struct LedgerTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? PacemarkMotion.pressScale : 1)
            .animation(PacemarkMotion.resolved(PacemarkMotion.pressDown, .movement, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}
