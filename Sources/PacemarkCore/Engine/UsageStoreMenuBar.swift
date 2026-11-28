import Foundation

extension Preferences {
    /// The old values remain available to earlier builds, captured demos and the Ledger.
    func migrateLegacyMenuBarSelection(
        projections: [DisplayAccountsProjection], tracked: [AccountKey], enabled: Set<ProviderID>
    ) -> MenuBarMeterSelection {
        if let saved = menuBarMeterSelection { return saved }
        let ordered = (menuBarProviderOrder + projections.map(\.providerID)).uniqued()
        let selection = menuBarFillSource.providerIDs
        func item(_ key: AccountKey) -> MenuBarMeterSelection.Item {
            let window = hasChosenMenuBarWindow(for: key.providerID)
                ? MenuBarMeterWindow(legacyChoice: menuBarWindowChoice(for: key.providerID)) : .auto
            return .init(account: key, window: window, label: menuBarAccountBadges[key] ?? "")
        }
        let shown = ordered.flatMap { id -> [AccountKey] in
            guard selection?.contains(id) ?? enabled.contains(id),
                  let projection = projections.first(where: { $0.providerID == id }) else { return [] }
            if selection == nil || showAllProviderAccountsInMenuBar {
                return projection.rows.filter { !$0.isRemembered }.flatMap { row in
                    [row.key] + tracked.filter { projection.mergeMap[$0] == row.key }
                }
            }
            return projection.primaryKey.map { [$0] } ?? []
        }.uniqued()
        let shownKeys = Set(shown)
        let result = MenuBarMeterSelection(mode: .chosen, items: shown.map(item),
                                           hidden: tracked.filter { enabled.contains($0.providerID) && !shownKeys.contains($0) }.map(item))
        menuBarMeterSelection = result
        return result
    }
}

public enum MenuBarMeterResolver {
    public struct ResolvedMeter: Sendable {
        public let account: DisplayAccount
        public let item: MenuBarMeterSelection.Item
        public let isShown: Bool
        public var key: AccountKey { account.key }
    }

    public static func resolve(
        _ selection: MenuBarMeterSelection, projections: [DisplayAccountsProjection], enabled: Set<ProviderID>
    ) -> [ResolvedMeter] {
        let projections = projections.filter { enabled.contains($0.providerID) }
        let rows = projections.flatMap(\.rows)
        let accounts = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let merges = projections.reduce(into: [AccountKey: AccountKey]()) {
            $0.merge($1.mergeMap, uniquingKeysWith: { first, _ in first })
        }
        var shown = Set<AccountKey>()
        let active = selection.items.compactMap { item -> ResolvedMeter? in
            let key = merges[item.account] ?? item.account
            guard let account = accounts[key], !account.isRemembered, shown.insert(key).inserted else { return nil }
            return ResolvedMeter(account: account, item: item, isShown: true)
        }
        let hidden = Dictionary(selection.hidden.map { (merges[$0.account] ?? $0.account, $0) },
                                uniquingKeysWith: { first, _ in first })
        return active + rows.filter { !shown.contains($0.key) }.map { account in
            ResolvedMeter(account: account, item: hidden[account.key] ?? .init(account: account.key), isShown: false)
        }
    }
}

@MainActor
extension UsageStore {
    var menuBarTrackedAccounts: [AccountKey] {
        registeredProviderOrder.flatMap { accounts(for: $0).map(\.key) }
    }

    var menuBarProjections: [DisplayAccountsProjection] {
        registeredProviderOrder.map { displayProjection(for: $0) }
    }

    private var menuBarEnabledProviders: Set<ProviderID> { Set(providerOrder) }

    public var menuBarMeterRows: [MenuBarMeterResolver.ResolvedMeter] {
        MenuBarMeterResolver.resolve(menuBarMeterSelection, projections: menuBarProjections, enabled: menuBarEnabledProviders)
    }

    public func setMenuBarMode(_ mode: MenuBarMeterSelection.Mode) {
        menuBarMeterSelection.mode = mode
    }

    public func setMenuBarWindow(_ window: MenuBarMeterWindow, for row: MenuBarMeterResolver.ResolvedMeter) {
        guard let current = menuBarMeterRows.first(where: { $0.key == row.key }), !current.account.isRemembered else { return }
        let keys = menuBarMergeGroup(for: current.key)
        var selection = menuBarMeterSelection
        let shown = selection.items.indices.filter { keys.contains(selection.items[$0].account) }
        let hidden = selection.hidden.indices.filter { keys.contains(selection.hidden[$0].account) }
        for index in shown { selection.items[index].window = window }
        for index in hidden { selection.hidden[index].window = window }
        if shown.isEmpty, hidden.isEmpty {
            selection.hidden.append(.init(account: current.key, window: window))
        }
        menuBarMeterSelection = selection
    }

    public func setMeterLabel(_ label: String, for row: MenuBarMeterResolver.ResolvedMeter) {
        guard let row = menuBarMeterRows.first(where: { $0.key == row.key }), !row.account.isRemembered else { return }
        let keys = menuBarMergeGroup(for: row.key)
        var selection = menuBarMeterSelection
        let value = MenuBarMeterSelection.Item.trimmedLabel(label)
        if !(selection.items + selection.hidden).contains(where: { keys.contains($0.account) }) {
            selection.hidden.append(.init(account: row.key, label: value))
        }
        for i in selection.items.indices where keys.contains(selection.items[i].account) { selection.items[i].label = value }
        for i in selection.hidden.indices where keys.contains(selection.hidden[i].account) { selection.hidden[i].label = value }
        menuBarMeterSelection = selection
    }

    public func setMenuBarShown(_ shown: Bool, for row: MenuBarMeterResolver.ResolvedMeter) {
        guard let row = menuBarMeterRows.first(where: { $0.key == row.key }),
              !row.account.isRemembered, shown != row.isShown else { return }
        var selection = menuBarMeterSelection
        let keys = menuBarMergeGroup(for: row.key)
        let group = (selection.items + selection.hidden).filter { keys.contains($0.account) }
        var seen = Set<AccountKey>()
        let items = ([row.item] + group).filter { seen.insert($0.account).inserted }
        selection.items.removeAll { keys.contains($0.account) }
        selection.hidden.removeAll { keys.contains($0.account) }
        if shown {
            selection.items.append(contentsOf: items)
        } else {
            selection.hidden.append(contentsOf: items)
        }
        menuBarMeterSelection = selection
    }

    private func menuBarMergeGroup(for key: AccountKey) -> Set<AccountKey> {
        let merges = displayProjection(for: key.providerID).mergeMap
        return Set([key] + merges.keys.filter { merges[$0] == key })
    }

    public func menuBarLabelOverride(for key: AccountKey) -> String? {
        menuBarBadgeOverrides[key]
    }

    public func addMainMenuBarAccounts() {
        let mains = Set(providerOrder.compactMap { displayPrimaryKey(for: $0) })
        for row in menuBarMeterRows where mains.contains(row.key) && !row.isShown {
            setMenuBarShown(true, for: row)
        }
    }

    public func resetMenuBarOrder() {
        let canonical = providerOrder.flatMap { displayAccounts(for: $0).filter { !$0.isRemembered }.map(\.key) }
        let grouped = Dictionary(grouping: menuBarMeterSelection.items) { item in
            displayMergeMaps[item.account.providerID]?[item.account] ?? item.account
        }
        let ordered = canonical.flatMap { grouped[$0] ?? [] }
        let orderedKeys = Set(ordered.map(\.account))
        menuBarMeterSelection.items = ordered + menuBarMeterSelection.items.filter { !orderedKeys.contains($0.account) }
    }

    public func moveMenuBarMeter(_ key: AccountKey, by offset: Int) {
        let visible = menuBarMeterRows.filter(\.isShown)
        guard let origin = visible.firstIndex(where: { $0.key == key }), offset != 0,
              offset >= -origin, offset < visible.count - origin else { return }
        let keys = menuBarMergeGroup(for: visible[origin].key)
        let target = visible[origin + offset].item.account
        var items = menuBarMeterSelection.items
        let moved = items.filter { keys.contains($0.account) }
        items.removeAll { keys.contains($0.account) }
        guard let destination = items.firstIndex(where: { $0.account == target }) else { return }
        items.insert(contentsOf: moved, at: offset > 0 ? destination + 1 : destination)
        menuBarMeterSelection.items = items
    }

    /// The legacy provider setting still controls the Ledger. Per-meter overrides never change it.
    public func menuBarWindowChoice(for id: ProviderID) -> MenuBarWindowChoice {
        preferences.menuBarWindowChoice(for: id)
    }

    public func menuBarReading(for row: MenuBarMeterResolver.ResolvedMeter, at date: Date) -> MenuBarWindowResolver {
        menuBarReading(for: row.key, choice: row.item.window, at: date)
    }

    private func menuBarReading(for key: AccountKey, choice: MenuBarMeterWindow, at date: Date) -> MenuBarWindowResolver {
        MenuBarWindowResolver(
            snapshot: appDisplaySnapshot(for: key), choice: choice, ledgerChoice: menuBarWindowChoice(for: key.providerID),
            percentageMode: usagePercentageMode, now: date,
            showsCodexSparkCounters: false, showsAntigravityFiveHourWindows: true
        )
    }

    public func summaryCandidates(at date: Date) -> [PopoverSummaryRecipe.Candidate] {
        providerOrder.flatMap { id in
            displayAccounts(for: id).flatMap { row -> [PopoverSummaryRecipe.Candidate] in
                guard !row.isRemembered, snapshot(for: row.key).freshness == .live,
                      accountRemovalStates[row.key] == nil,
                      setupCoordinator?.state(for: row.key).holdsDisplayMerge != true else { return [] }
                let reading = menuBarReading(for: row.key, choice: .auto, at: date)
                return PopoverSummaryRecipe.Candidate.readings(
                    key: row.key, title: desktopAccountName(for: row.account), row: reading.ledger)
            }
        }
    }

    /// The Standard and Compact refresh button retains its legacy provider animation.
    /// Menu Bar visibility and ordering have no effect on this popover control.
    public var refreshAnimationIsAutomatic: Bool { preferences.menuBarFillSource == .auto }

    public func refreshAnimationMeters() -> [MenuBarMeter] {
        guard let selected = preferences.menuBarFillSource.providerIDs else {
            return [MenuBarMeter(summary: .neutral, fill: nil)]
        }
        let date = now()
        let enabled = Set(providerOrder)
        let order = (preferences.menuBarProviderOrder + providerOrder).uniqued()
        return order.filter { enabled.contains($0) && selected.contains($0) }.flatMap { id in
            let rows = displayAccounts(for: id).filter { !$0.isRemembered }
            let participants = preferences.showAllProviderAccountsInMenuBar ? rows : Array(rows.prefix(1))
            let choice = MenuBarMeterWindow(legacyChoice: menuBarWindowChoice(for: id))
            return participants.map { account in
                let row = MenuBarMeterResolver.ResolvedMeter(account: account, item: .init(account: account.key), isShown: true)
                let cell = menuBarReading(for: row.key, choice: choice, at: date).selected
                return menuBarMeter(for: row, cell: cell)
            }
        }
    }

    public var menuBarMeters: [MenuBarMeter] { menuBarMeters(at: nil) }

    public func menuBarMeters(at date: Date?) -> [MenuBarMeter] {
        let date = date ?? now()
        let rows = menuBarMeterRows
        if menuBarMeterSelection.mode == .tightest {
            if let reading = PopoverSummaryRecipe.tightest(candidates: summaryCandidates(at: date), now: date),
               let row = rows.first(where: { $0.key == reading.candidate.key }) {
                let cell = menuBarReading(for: row.key, choice: .limit(reading.candidate.window.kind.persistentID), at: date).selected
                return [menuBarMeter(for: row, cell: cell)]
            }
            return tightestFallback(in: rows, at: date).map { [$0] } ?? []
        }

        let chosen = rows.filter(\.isShown)
        return chosen.map { row in
            menuBarMeter(for: row, cell: menuBarReading(for: row, at: date).selected)
        }
    }

    public func popoverMeter(for account: DisplayAccount, at date: Date) -> MenuBarMeter {
        let item = MenuBarMeterSelection.Item(account: account.key)
        let row = MenuBarMeterResolver.ResolvedMeter(account: account, item: item, isShown: false)
        let cell = menuBarReading(for: account.key, choice: .auto, at: date).ledger.primary
        return menuBarMeter(for: row, cell: cell)
    }

    private func tightestFallback(
        in rows: [MenuBarMeterResolver.ResolvedMeter], at date: Date
    ) -> MenuBarMeter? {
        let accounts = rows.filter { !$0.account.isRemembered }
        let stale = accounts.flatMap { row in
            let snapshot = snapshot(for: row.key)
            let reading = menuBarReading(for: row, at: date)
            return reading.ledger.windows.filter { cell in
                guard cell.value.displayedPercentage != nil else { return false }
                if case .stale = snapshot.freshness { return true }
                return !cell.value.window.freshness.isLive
            }.map { (row: row, cell: $0) }
        }.min { $0.cell.value.window.percentRemaining < $1.cell.value.window.percentRemaining }
        if let stale {
            return menuBarMeter(for: stale.row, cell: stale.cell)
        }
        let fallback = accounts.first { row in
            let snapshot = snapshot(for: row.key)
            return snapshot.freshness == .pending || menuBarNeedsAttention(snapshot)
        }
        guard let row = fallback ?? accounts.first else { return nil }
        let cell = fallback.flatMap { menuBarReading(for: $0, at: date).selected }
        return menuBarMeter(for: row, cell: cell)
    }

    private func menuBarNeedsAttention(_ snapshot: UsageSnapshot) -> Bool {
        if case .stale(let reason) = snapshot.freshness { return reason.isPermanent }
        return snapshot.planStatusRecovery != nil
    }

    public func menuBarMeter(
        for row: MenuBarMeterResolver.ResolvedMeter, cell: LedgerRowRecipe.Window?
    ) -> MenuBarMeter {
        let key = row.key
        let snapshot = snapshot(for: key)
        let reading = cell.map { UsageMeterReading(window: $0.value.window) }
        let number = reading?.roundedPercentage(for: usagePercentageMode)
        let windowName = cell.map { " \($0.value.window.kind.menuBarTerm)" } ?? ""
        let name = refreshReceiptTitle(for: key)
        let badge = showMenuBarLabels ? row.item.label.flatMap { $0.isEmpty ? nil : $0 } : nil
        return MenuBarMeter(
            summary: MenuBarSummary(text: number.map { "\($0)%" } ?? "—", providerID: key.providerID,
                                    detail: name + windowName, isNeutral: number == nil,
                                    percentageMode: usagePercentageMode, severity: reading?.severity ?? .healthy,
                                    needsAttention: menuBarNeedsAttention(snapshot)),
            fill: number == nil ? nil : reading?.fraction(for: usagePercentageMode), awaitingFirstReading: snapshot.freshness == .pending,
            isLiveReading: snapshot.freshness == .live && cell?.value.window.freshness.isLive == true,
            sourceAccountKey: key, glyph: .providerMark(key.providerID), badge: badge, pace: cell?.pace, countdown: cell?.countdown
        )
    }
}
