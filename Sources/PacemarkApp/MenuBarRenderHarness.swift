import AppKit
import PacemarkCore

@MainActor
enum MenuBarRenderHarness {
    static func fixtureStore(preferences: Preferences, warmUpSample: Bool = false, review: Bool = false) -> UsageStore {
        let now = DemoFixture.now
        let hour: TimeInterval = 3600
        let day = 24 * hour
        func reading(_ kind: WindowKind, left: Double, in time: TimeInterval) -> UsageWindow {
            UsageWindow(kind: kind, utilization: 100 - left, resetsAt: now.addingTimeInterval(time))
        }
        let sources: [(provider: ProviderID, id: AccountID, title: String, plan: String?,
                       label: String?, windows: [UsageWindow], choice: MenuBarMeterWindow)] = [
            (.claude, .primary, "Personal", "Max", "P", [
                reading(.weekly, left: 62, in: 4 * day + 3 * hour),
                reading(.fiveHour, left: 85, in: 3 * hour),
            ], .auto),
            (.claude, AccountID("preview-work"), review ? "Research and development" : "Work", "Pro", review ? "Research" : "W", [
                reading(.weekly, left: 74, in: 5 * day),
                reading(.fiveHour, left: 18, in: 112 * 60 + 20),
            ], .limit(WindowKind.fiveHour.persistentID)),
            (.codex, .primary, "Pro 200", "Pro", "200", [reading(.weekly, left: 75, in: day + 4 * hour)], .auto),
            (.codex, AccountID("preview-prolite"), "100", "Prolite", review ? nil : "100", [reading(.weekly, left: 96, in: 6 * day + 22 * hour)], .auto),
            (.antigravity, .primary, "Main", nil, nil, [reading(.other("Gemini weekly"), left: 100, in: 5 * day + 18 * hour)], .auto),
            (.copilot, .primary, "Main", nil, nil, [
                reading(.billingPeriod(label: "Monthly", duration: 30 * day), left: 41, in: 19 * day)
            ], .auto),
        ]
        let accounts = sources.map { id, accountID, title, _, _, _, _ in
            ProviderAccount(id: accountID, providerID: id, label: title, isBuiltIn: accountID == .primary)
        }
        let providers = sources.map { id, key, _, plan, _, windows, _ in
            DemoUsageProvider(id: id, displayName: id.displayName,
                              snapshot: UsageSnapshot(providerID: id, windows: windows, planLabel: plan,
                                                      bankedResets: review && id == .codex && key == .primary ? 101 : nil, capturedAt: now, freshness: .live),
                              accountID: key)
        }
        let off = [ProviderID.grok, .cursor, .opencode].map {
            DemoUsageProvider(id: $0, displayName: $0.displayName, snapshot: .pending(for: $0))
        }
        preferences.setSurfaceEnabled(!(review && warmUpSample), for: .antigravitySubscription)
        preferences.setSurfaceEnabled(true, for: .copilotSubscription)
        let items = zip(accounts, sources).map { MenuBarMeterSelection.Item(account: $0.key, window: $1.choice, label: $1.label ?? "") }
        preferences.menuBarMeterSelection = .init(items: Array(items.dropLast()), hidden: Array(items.suffix(1)))
        preferences.menuBarAccountBadges = Dictionary(uniqueKeysWithValues: zip(accounts, sources).compactMap { account, source in
            source.label.map { (account.key, $0) }
        })
        let records = DemoFixture.multiFixture(for: .remembered).makeDefaultLoginRecordStore()
        let store = UsageStore(providers: providers + off, preferences: preferences, accounts: accounts,
                               defaultLoginRecords: records,
                               warmUp: warmUpSample ? WarmUpRenderFixture.make(for: accounts, paused: review) : nil)
        for id in [ProviderID.claude, .codex] {
            for row in store.displayAccounts(for: id) where row.isRemembered {
                if id == .codex && row.label == "Work" {
                    store.renameRememberedAccount(row.key, to: "200")
                } else {
                    store.removeRememberedAccount(row.key)
                }
            }
        }
        return store
    }

    static func writeStrip(_ image: NSImage, dark: Bool, to url: URL) throws {
        let plate = NSImage(size: NSSize(width: image.size.width + 24, height: 44), flipped: false) { bounds in
            NSColor(white: dark ? 0.15 : 0.92, alpha: 1).setFill()
            bounds.fill()
            image.draw(at: NSPoint(x: 12, y: (bounds.height - image.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        guard let rep = plate.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }

    static func run(outputDirectory: String) throws {
        let dir = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let arguments = CommandLine.arguments
        let paceStates = DemoFixture.scenarioRequest(arguments: arguments) == .multiAccount(.paceStates)
            || arguments.firstIndex(of: "--render-scenario").map {
                arguments.dropFirst($0 + 1).first == DemoFixture.MultiAccountScenario.paceStates.rawValue
            } == true
        let defaults = DemoMemoryDefaults()
        let store = paceStates ? AppComposition.demoMultiAccountStore(scenario: .paceStates, defaults: defaults)
            : fixtureStore(preferences: Preferences(defaults: defaults))
        var tuning = MenuBarMeterTuning.defaults
        if paceStates { tuning.showNumber = true }
        // Running the NSApp loop lets the mocked providers publish before writing the PNGs.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await store.refreshAll()
            do {
                for dark in [false, true] {
                    let palette = MenuBarPalette(isDarkMenuBar: dark)
                    let renderer = MenuBarGaugeRenderer(palette: palette, tuning: tuning)
                    let image = renderer.image(meters: store.menuBarMeters)
                    let url = dir.appendingPathComponent("menu-bar-strip-\(dark ? "dark" : "light").png")
                    try writeStrip(image, dark: dark, to: url)
                    print("✓ \(url.path)")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Could not render menu bar strip: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }
}
