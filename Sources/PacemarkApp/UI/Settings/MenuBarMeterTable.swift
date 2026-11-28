#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct MenuBarMeterTable: View {
    let store: UsageStore
    let tuning: MenuBarMeterTuning
    let date: Date
    @Binding var hoveredAccount: AccountKey?
    let onOpenAccounts: () -> Void

    @Environment(\.colorScheme) private var scheme
    @GestureState private var drag: Drag?
    private let rowHeight = PDS.Metrics.control + 2 * PDS.Space.s
    private let gripWidth: CGFloat = 15
    private let glyphWidth: CGFloat = 24
    private let windowWidth: CGFloat = 142
    private let labelWidth = 5 * PDS.Space.l - PDS.Space.s
    private let nowWidth: CGFloat = 104
    private let actionWidth: CGFloat = 20

    private struct Drag {
        let key: AccountKey
        let offset: CGFloat
    }

    var body: some View {
        let rows = store.menuBarMeterRows
        let shown = rows.filter(\.isShown)
        let hidden = rows.filter { !$0.isShown }
        SettingsLedgerTile(title: "Meters") {
            SettingsCapsLabel("In menu bar \(shown.count)")
        } content: {
            PDSPickerRow("Show", help: store.menuBarMeterSelection.mode == .chosen
                ? "Chosen meters shows the accounts below in order." : "Follows whichever account will run out first.") {
                Picker("Show", selection: Binding(get: { store.menuBarMeterSelection.mode }, set: store.setMenuBarMode)) {
                    Text("Chosen meters").tag(MenuBarMeterSelection.Mode.chosen)
                    Text("Tightest only").tag(MenuBarMeterSelection.Mode.tightest)
                }
                .pdsSegmented()
                .accessibilityIdentifier("menuBar.mode")
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: .zero) {
                headings
                if shown.isEmpty {
                    HStack {
                        SettingsLedgerHelp(store.menuBarMeterSelection.mode == .chosen
                            ? "No meters. The menu bar shows the Pacemark mark." : "No meters are chosen.")
                        Spacer()
                        Button("Add main accounts", action: store.addMainMenuBarAccounts)
                            .buttonStyle(SetupChipButtonStyle(size: .small))
                            .disabled(!hidden.contains { !$0.account.isRemembered })
                    }
                    .padding(.vertical, PDS.Space.xs)
                } else {
                    shownRows(shown)
                }
                if !hidden.isEmpty {
                    SettingsCapsLabel("Not shown \(hidden.count)")
                        .frame(height: LedgerMetrics.sectionHeaderHeight, alignment: .leading)
                    PDSTableRows {
                        ForEach(hidden, id: \.key) { row in meterRow(row) }
                    }
                }
                disabledProviders
            }
            .pdsTableStart()
            .opacity(store.menuBarMeterSelection.mode == .tightest ? 0.72 : 1)
        }
    }

    private var headings: some View {
        HStack(spacing: PDS.Space.xs) {
            Color.clear.frame(width: gripWidth + glyphWidth + PDS.Space.xs)
            columnTitle("Account").pdsColumnGuide("pds.heading.text.account").padding(.leading, PDS.Metrics.providerMark + LedgerMetrics.nameGap).frame(maxWidth: .infinity, alignment: .leading)
            PDSColumns.menu(width: windowWidth).cell(columnTitle("Window")).padding(.trailing, PDS.Space.xs)
            if store.showMenuBarLabels { columnTitle("Label").frame(width: labelWidth, alignment: .leading) }
            HStack(spacing: PDS.Space.m) {
                columnTitle("Left").pdsColumnGuide("pds.heading.number.left")
                columnTitle("Resets").pdsColumnGuide("pds.heading.number.resets").frame(width: LedgerMetrics.resetWidth, alignment: .trailing)
            }.frame(width: nowWidth, alignment: .trailing)
            Color.clear.frame(width: actionWidth)
        }
        .padding(.vertical, PDS.Space.s)
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(PopoverLedgerType.column)
            .foregroundStyle(PDS.Ink.inkTertiary)
    }

    private func shownRows(_ rows: [MenuBarMeterResolver.ResolvedMeter]) -> some View {
        let origin = drag.flatMap { drag in rows.firstIndex { $0.key == drag.key } }
        let offset = drag?.offset ?? 0
        let destination = origin.map { landing(from: $0, offset: offset, count: rows.count) }
        return MeterRowsLayout(height: rowHeight, dragOrigin: origin, destination: destination, offset: offset) {
            PDSTableRows(followsHeadings: true) {
                ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                    meterRow(row) {
                        grip(for: row, index: index, count: rows.count)
                    }
                    .zIndex(drag?.key == row.key ? 1 : 0)
                }
            }
        }
    }

    private func landing(from origin: Int, offset: CGFloat, count: Int) -> Int {
        min(count - 1, max(0, origin + Int((offset / rowHeight).rounded())))
    }

    private func grip(for row: MenuBarMeterResolver.ResolvedMeter, index: Int, count: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(PDS.Typography.caps)
            .foregroundStyle(PDS.Ink.inkSecondary)
            .frame(width: gripWidth, height: rowHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .global).updating($drag) { value, state, _ in
                state = Drag(key: row.key, offset: value.translation.height)
            }.onEnded { value in
                store.moveMenuBarMeter(row.key, by: landing(from: index, offset: value.translation.height, count: count) - index)
            })
            .focusable()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                move(row.key, by: press.key == .upArrow ? -1 : 1, modifiers: press.modifiers)
            }
            .accessibilityLabel("Reorder \(row.account.label)")
            .accessibilityAction(named: "Move up") { store.moveMenuBarMeter(row.key, by: -1) }
            .accessibilityAction(named: "Move down") { store.moveMenuBarMeter(row.key, by: 1) }
            .help("Drag to reorder, or use Option-Command-Up Arrow and Option-Command-Down Arrow.")
    }

    private func move(_ key: AccountKey, by offset: Int, modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.contains([.option, .command]) else { return .ignored }
        store.moveMenuBarMeter(key, by: offset)
        return .handled
    }

    private func meterRow(_ row: MenuBarMeterResolver.ResolvedMeter) -> some View {
        meterRow(row) { Color.clear.frame(width: gripWidth) }
    }

    private func meterRow<Grip: View>(
        _ row: MenuBarMeterResolver.ResolvedMeter, @ViewBuilder grip: () -> Grip
    ) -> some View {
        let reading = store.menuBarReading(for: row, at: date)
        let meter = store.menuBarMeter(for: row, cell: reading.selected)
        let accountName = store.desktopAccountName(for: row.account.account)
        return HStack(spacing: PDS.Space.xs) {
            grip()
            MenuBarMeterGlyph(meter: meter, tuning: tuning)
                .frame(width: glyphWidth)
                .opacity(row.isShown ? 1 : 0.55)
            HStack(spacing: LedgerMetrics.nameGap) {
                ProviderLogoView(providerID: row.key.providerID, size: PDS.Metrics.providerMark)
                let name = Text(accountName).font(PopoverLedgerType.name).lineLimit(1).truncationMode(.tail).pdsColumnGuide("pds.cell.text.account")
                ViewThatFits(in: .horizontal) {
                    if let plan = PlanLabelPresentation.displayName(store.snapshot(for: row.key).planLabel, provider: row.key.providerID) {
                        HStack(spacing: LedgerMetrics.nameGap) {
                            name
                            LedgerChip(text: plan).pdsColumnGuide("pds.table.chip")
                        }.fixedSize()
                    }
                    name
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, PDS.Space.xs)
            .help("\(row.key.providerID.displayName) · \(accountName)")
            if row.account.isRemembered {
                SettingsLedgerHelp("Remembered · unavailable in menu bar")
                    .lineLimit(1)
                    .help("Remembered accounts never appear in the menu bar.")
                    .frame(width: windowWidth + (store.showMenuBarLabels ? labelWidth + PDS.Space.xs : 0) + nowWidth + actionWidth + 2 * PDS.Space.xs,
                           alignment: .trailing)
            } else {
                windowMenu(for: row, reading: reading).frame(width: windowWidth, alignment: .leading).padding(.trailing, PDS.Space.xs)
                if store.showMenuBarLabels {
                    MenuBarMeterLabelField(
                        value: row.item.label ?? "", accountLabel: accountName
                    ) { store.setMeterLabel($0 ?? "", for: row) }
                        .frame(width: labelWidth, alignment: .leading)
                }
                nowReading(reading).frame(width: nowWidth, alignment: .trailing)
                Button {
                    store.setMenuBarShown(!row.isShown, for: row)
                } label: {
                    Image(systemName: row.isShown ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(PDS.Ink.inkSecondary)
                .frame(width: actionWidth, alignment: .trailing)
                .help(row.isShown ? "Hide \(accountName) from the menu bar" : "Show \(accountName) in the menu bar")
                .accessibilityLabel(row.isShown ? "Hide \(accountName)" : "Show \(accountName)")
            }
        }
        .frame(height: rowHeight)
        .background {
            Rectangle().fill(.primary.opacity(hoveredAccount == row.key ? 0.05 : 0))
        }
        .onHover { inside in
            if inside { hoveredAccount = row.key }
            else if hoveredAccount == row.key { hoveredAccount = nil }
        }
    }

    private func windowMenu(for row: MenuBarMeterResolver.ResolvedMeter, reading: MenuBarWindowResolver) -> some View {
        let automatic = reading.selected.map { "Runs out first · \($0.column)" } ?? "Runs out first"
        let title = switch row.item.window {
        case .auto: automatic
        case .limit(let id):
            if let reported = reading.reportedLimit {
                reported.detailLabel + (reading.isMissingLimit ? " (unavailable)" : "")
            } else {
                (WindowKind(persistentID: id).map { kind in
                    AntigravityOtherModels.displayLabel(for: kind, showsOtherModels: store.showsAntigravityOtherModels) ?? LedgerRowRecipe.column(for: kind)
                } ?? "Limit") + " (not reported)"
            }
        }
        return Menu {
            Button { store.setMenuBarWindow(.auto, for: row) } label: {
                Text("Runs out first")
                Text("Empties soonest at your pace")
            }
            if !reading.ledger.windows.isEmpty {
                Divider()
                ForEach(reading.ledger.windows, id: \.value.window.kind.persistentID) { cell in
                    Button(cell.detailLabel) {
                        store.setMenuBarWindow(.limit(cell.value.window.kind.persistentID), for: row)
                    }
                }
            }
        } label: {
            PDSMenuValue(width: windowWidth) {
                if row.item.window == .auto, let cell = reading.selected {
                    Text("Runs out first \(Text("· \(cell.column)").foregroundStyle(PDS.Ink.inkSecondary))")
                } else { Text(title) }
            }.font(PopoverLedgerType.sentence)
        }
        .pdsCellMenu()
        .help(row.item.window == .auto ? reading.selected.map { "Runs out first · \($0.detailLabel)" } ?? title : title)
        .accessibilityLabel("Window for \(row.account.label), \(title)")
    }

    private func nowReading(_ reading: MenuBarWindowResolver) -> some View {
        let cell = reading.selected
        let percentage = cell?.value.displayedPercentage
        let tier = cell?.pace?.tier
        let fallback = cell.flatMap { UsageMeterReading(window: $0.value.window).severity }
        let isLive = !reading.ledger.isDimmed && cell?.value.window.freshness.isLive == true
        let ink = isLive ? LedgerInk.usage(tier, fallback: fallback, scheme: scheme) : PDS.Ink.inkTertiary
        let tooltip = [tier?.label, cell?.countdown.map(Countdown.spokenReset)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: PDS.Space.m) {
            Text(percentage.map { "\($0)%" } ?? "—")
                .font(PopoverLedgerType.value).fixedSize()
                .foregroundStyle(ink)
                .pdsColumnGuide("pds.cell.number.left")
            Text(cell?.countdown ?? "—")
                .font(PopoverLedgerType.countdown)
                .pdsColumnGuide("pds.cell.number.resets")
                .foregroundStyle(PDS.Ink.inkTertiary)
                .lineLimit(1)
                .frame(width: LedgerMetrics.resetWidth, alignment: .trailing)
        }
        .help(tooltip.isEmpty ? "No reset countdown" : tooltip.prefix(1).uppercased() + tooltip.dropFirst())
    }

    @ViewBuilder
    private var disabledProviders: some View {
        let enabled = Set(store.providerOrder)
        let off = store.registeredProviderOrder.filter { !enabled.contains($0) }
        HStack {
            SettingsLedgerHelp("Hidden here still shows in the popover.")
            if !off.isEmpty {
                SettingsLedgerHelp(off.map(\.displayName).joined(separator: ", ") + (off.count == 1 ? " is off" : " are off"))
            }
            Spacer()
            Button("Reset order", action: store.resetMenuBarOrder)
                .buttonStyle(SetupChipButtonStyle(size: .small))
                .disabled(store.menuBarMeterRows.filter(\.isShown).count < 2)
            if !off.isEmpty {
                Button("Turn on in Accounts", action: onOpenAccounts)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
            }
        }
        .padding(.vertical, PDS.Space.xs)
    }
}

/// Layout owns the dragged row and its neighbors, so the drop lands at the same position as its preview.
private struct MeterRowsLayout: Layout {
    let height: CGFloat
    let dragOrigin: Int?
    let destination: Int?
    let offset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0,
               height: height * CGFloat(subviews.count))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            var y = CGFloat(index) * height
            if let dragOrigin, let destination {
                if index == dragOrigin {
                    y = min(bounds.height - height, max(0, y + offset))
                } else if dragOrigin < index, index <= destination {
                    y -= height
                } else if destination <= index, index < dragOrigin {
                    y += height
                }
            }
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
        }
    }
}
