#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct PopoverSettingsPane: View {
    let store: UsageStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.loadingDate) private var pinnedDate
    private let fixture = SettingsPreviewFixtures()

    var body: some View {
        let _ = BenchCounters.hit("PopoverSettingsPane")
        SettingsPaneScaffold(SettingsPane.appearance.label, subtitle: "Choose how usage looks when you open the popover.") {
            SettingsLedgerTile("Preview") { preview.frame(maxWidth: .infinity) }
            SettingsLedgerTile("Account display") {
                numbers.padding(.vertical, PDS.Space.s)
                PDSSwatchGroup("Long lists") {
                    longLists
                }.padding(.vertical, PDS.Space.s)
            }
            summaryTiles
        }
    }

    private var summarySlot1: PopoverSummarySlot {
        get { store.popoverSummarySlot1 }
        nonmutating set {
            store.popoverSummarySlot2 = summarySlot1.otherSlot(afterSelecting: newValue, opposite: summarySlot2)
            store.popoverSummarySlot1 = newValue
        }
    }

    private var summarySlot2: PopoverSummarySlot {
        get { store.popoverSummarySlot2 }
        nonmutating set {
            store.popoverSummarySlot1 = summarySlot2.otherSlot(afterSelecting: newValue, opposite: summarySlot1)
            store.popoverSummarySlot2 = newValue
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: CGFloat(LedgerMetrics.columns.cardGap)) {
            ForEach(fixture.providerOrder, id: \.self) { provider in
                LedgerSectionView(provider: provider, name: provider.displayName,
                                  entries: fixture.entries.filter { $0.account.providerID == provider },
                                  fragment: nil, capability: nil, percentageMode: store.usagePercentageMode,
                                  now: fixture.now)
            }
        }
        .frame(width: CGFloat(LedgerMetrics.columns.columnWidth))
        .padding(PDS.Space.s)
        .overlay {
            // An extra wash beneath the sample cards makes the dark usage numerals harder to read.
            RoundedRectangle(cornerRadius: PDS.Radius.card).strokeBorder(PDS.Ink.cardStroke)
        }
        .environment(\.accountTitleInk, store.accountTitleInk)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Popover preview")
    }

    private var numbers: some View {
        let percentage = Binding(get: { store.usagePercentageMode }, set: store.setUsagePercentageMode)
        return PDSSwatchGroup("Count") {
            HStack(spacing: PDS.Space.s) {
                ForEach(UsagePercentageMode.allCases) { mode in
                    swatch(mode == .used ? "What’s used" : "What’s left", value: mode, selection: percentage) {
                        percentageSample(mode)
                    }
                }
            }
            .settingsSelectionGroup(value: percentage.wrappedValue)
            .padding(.bottom, PDS.Space.xs)
        }
    }

    @ViewBuilder
    private func percentageSample(_ mode: UsagePercentageMode) -> some View {
        if let window = fixture.entries
            .first(where: { $0.account.providerID == .codex })?.snapshot.windows.first(where: { $0.kind == .weekly }),
           let pace = MenuBarPace(window: window, now: fixture.now) {
            let reading = UsageMeterReading(window: window)
            HStack(spacing: PDS.Space.xs) {
                LedgerPaceBar(remaining: pace.remaining, pace: pace, severity: reading.severity ?? .healthy,
                              width: 32, mode: mode)
                Text("\(reading.roundedPercentage(for: mode) ?? 0)%")
                    .font(PopoverLedgerType.value).fixedSize()
                    .foregroundStyle(LedgerInk.usage(pace.tier, fallback: reading.severity, scheme: scheme))
                Text(mode == .used ? "Used" : "Left").font(PopoverLedgerType.unit)
            }
        }
    }

    /// Align each picker with the summary tile it controls.
    private var summaryTiles: some View {
        SettingsLedgerTile("Summary tiles") {
            VStack(alignment: .leading, spacing: PDS.Space.s) {
                summaryPreview.frame(height: summarySlot1 == .off && summarySlot2 == .off ? PDS.Metrics.row : LedgerMetrics.summaryHeight)
                LedgerSummaryColumns {
                    summarySlot("First tile", slot: Binding(get: { summarySlot1 }, set: { summarySlot1 = $0 }))
                    summarySlot("Second tile", slot: Binding(get: { summarySlot2 }, set: { summarySlot2 = $0 }))
                }
                .padding(.vertical, PDS.Space.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, PDS.Space.s)
        }
    }

    private var longLists: some View {
        let expands = Binding(get: { store.expandAccountsHorizontally }, set: store.setExpandAccountsHorizontally)
        return Group {
            HStack(spacing: PDS.Space.s) {
                swatch("Two columns", value: true, selection: expands) {
                    Image(systemName: "rectangle.split.2x1")
                }
                swatch("Scroll", value: false, selection: expands) {
                    Image(systemName: "rectangle.portrait")
                }
            }
            .settingsSelectionGroup(value: expands.wrappedValue)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("appearance.longLists")
            .padding(.bottom, PDS.Space.xs)
        }
    }

    private func swatch<Value: Hashable, Art: View>(
        _ label: String, value: Value, selection: Binding<Value>, @ViewBuilder art: () -> Art
    ) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            VStack(spacing: PDS.Space.xs) {
                art()
                    .padding(.horizontal, PDS.Space.s)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: PDS.Radius.control))
                Text(label).font(SettingsType.swatchLabel).lineLimit(1)
            }
            .padding(PDS.Space.s)
            .selectionChrome(isSelected: selection.wrappedValue == value)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection.wrappedValue == value ? [.isSelected] : [])
        .buttonStyle(SettingsSwatchButtonStyle())
        .frame(width: 142)
    }

    private func summarySlot(_ label: String, slot: Binding<PopoverSummarySlot>) -> some View {
        VStack(alignment: .leading, spacing: PDS.Space.xs) {
            PDSCapsHeader(label)
            SummarySlotPicker(label: label, selection: slot)
                .frame(maxWidth: .infinity)
        }
    }

    private var summaryPreview: some View {
        let slots = [summarySlot1, summarySlot2].filter { $0 != .off }
        let now = pinnedDate ?? .now
        let recipe = PopoverSummaryRecipe(slots: slots, candidates: store.summaryCandidates(at: now),
                                          spend: store.apiSpendProviderOrder.map { store.apiSpendSnapshot(for: $0) }, now: now)
        return Group {
            if slots.isEmpty {
                PDSHelpText("No summary tiles").frame(maxWidth: .infinity)
            } else {
                LedgerSummaryColumns(count: slots.count) {
                    ForEach(slots) { slot in
                        if let tile = recipe.tiles.first(where: { $0.slot == slot }) {
                            LedgerSummaryTile(tile: tile, period: store.apiSpendPeriod,
                                              mode: store.usagePercentageMode, now: now)
                        } else {
                            PDSCard(slot == .tightest ? "Tightest" : slot.label, accessory: { EmptyView() }) {
                                PDSHelpText("No data yet")
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }.frame(height: LedgerMetrics.summaryHeight)
                        }
                    }
                }
            }
        }
        .id(slots)
        // A slot edit can halve a bar’s width in one layout pass. Keep the sample
        // and the menu selections together while SwiftUI dismisses the menu.
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        .accessibilityIdentifier("summary.preview")
    }
}

/// NSPopUpButton accepts the width proposed by its grid column. SwiftUI's
/// bordered menu picker otherwise caps the native control at its intrinsic width.
private struct SummarySlotPicker: NSViewRepresentable {
    let label: String
    @Binding var selection: PopoverSummarySlot

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.addItems(withTitles: PopoverSummarySlot.allCases.map(\.label))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectSlot(_:))
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier("summary.\(label)")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        button.selectItem(withTitle: selection.label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor final class Coordinator {
        var selection: Binding<PopoverSummarySlot>
        init(selection: Binding<PopoverSummarySlot>) { self.selection = selection }
        @objc func selectSlot(_ button: NSPopUpButton) {
            let slots = PopoverSummarySlot.allCases
            if slots.indices.contains(button.indexOfSelectedItem) {
                selection.wrappedValue = slots[button.indexOfSelectedItem]
            }
        }
    }
}
