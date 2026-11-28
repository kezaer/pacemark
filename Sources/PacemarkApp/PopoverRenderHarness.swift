#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import AppKit
import PacemarkCore

/// Hidden diagnostic (`--render-popover <dir>`): renders the real `PopoverView` — demo
/// fixture data, the current OS surface, real appearance — to PNGs for every onboarding state ×
/// appearance, headlessly. Exists so popover design changes can be visually reviewed
/// and diffed against the HTML design mockups without posing the live menu bar
/// (`Scripts/capture-demo-screenshots.sh` still covers the marketing hero shots).
@MainActor
enum PopoverRenderHarness {
    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outDir = URL(fileURLWithPath: (outputDirectory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            var failedPaths: [String] = []
            if CommandLine.arguments.contains("--render-design-system") {
                for dark in [false, true] {
                    let sheet = PDSGallery().environment(\.colorScheme, dark ? .dark : .light)
                    let url = outDir.appendingPathComponent("gallery-\(dark ? "dark" : "light").png")
                    if !(await captureSettings(sheet, width: 660, height: 860, dark: dark, to: url)) { failedPaths.append(url.path) }
                }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--ui-pass-settings") {
                for dark in [false, true] {
                    for pane in SettingsPane.allCases {
                        for pose in ["top", "bottom"] {
                            let name = "\(pane.rawValue)-\(pose)-\(dark ? "dark" : "light").png"
                            if !(await renderSettings(pane: pane, percentageMode: .remaining, dark: dark,
                                                      warmUpSample: pane == .warmUp, pose: pose, to: outDir.appendingPathComponent(name))) {
                                failedPaths.append(name)
                            }
                        }
                    }
                }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--pacemark-brand") {
                for dark in [false, true] {
                    let style = dark ? "dark" : "light"
                    let renderer = MenuBarGaugeRenderer(palette: MenuBarPalette(isDarkMenuBar: dark), tuning: .defaults)
                    let markURL = outDir.appendingPathComponent("empty-menu-bar-\(style).png")
                    do {
                        try MenuBarRenderHarness.writeStrip(renderer.image(meters: []), dark: dark, to: markURL)
                    } catch {
                        failedPaths.append(markURL.path)
                    }
                    let about = outDir.appendingPathComponent("about-sidebar-\(style).png")
                    if !(await renderSettings(pane: .about, percentageMode: .remaining, dark: dark, to: about)) { failedPaths.append(about.path) }
                    let store = MenuBarRenderHarness.fixtureStore(preferences: renderPreferences(mode: .remaining))
                    await store.refreshAll()
                    let header = outDir.appendingPathComponent("popover-\(style).png")
                    if !(await snapshotPopover(store: store, dark: dark, to: header)) { failedPaths.append(header.path) }
                    for running in [false, true] {
                        let notice = PacemarkImportNotice(running: running, loginChoice: ImportLoginChoice()) { _ in }
                            .background(Color(nsColor: .windowBackgroundColor))
                            .environment(\.colorScheme, dark ? .dark : .light)
                        let url = outDir.appendingPathComponent("import-\(running ? "running" : "alone")-\(style).png")
                        if !(await captureSettings(notice, width: 380, height: running ? 280 : 240, dark: dark, to: url)) { failedPaths.append(url.path) }
                    }
                }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--review-meters") {
                for dark in [false, true] {
                    let style = dark ? "dark" : "light"
                    for pose in ["labels", "empty", "legend", "table", "paused"] {
                        let warm = pose == "paused"
                        let url = outDir.appendingPathComponent("\(pose)-\(style).png")
                        if !(await renderSettings(pane: warm ? .warmUp : .menuBar, percentageMode: .remaining,
                                                  dark: dark, height: warm || pose == "table" ? 1100 : 700,
                                                  warmUpSample: warm, pose: pose, to: url)) { failedPaths.append(url.path) }
                    }
                    let store = MenuBarRenderHarness.fixtureStore(preferences: renderPreferences(mode: .remaining), review: true)
                    await store.refreshAll()
                    let url = outDir.appendingPathComponent("banked-99-plus-\(style).png")
                    if !(await snapshotPopover(store: store, dark: dark, to: url)) { failedPaths.append(url.path) }
                }
                for path in failedPaths { print("Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--settings-layouts") {
                for dark in [false, true] {
                    for compact in [false, true] {
                        for pane in [SettingsPane.general, .appearance, .menuBar, .accounts, .notifications, .apiSpend, .about] {
                            let poses = pane == .menuBar ? ["labels", "empty", "legend"] : pane == .appearance ? ["bottom"] : ["top"]
                            for pose in poses {
                                let style = dark ? "dark" : "light"
                                let name = "settings-\(pane.rawValue)-\(pose)-\(compact ? "minimum" : "default")-\(style).png"
                                let url = outDir.appendingPathComponent(name)
                                if !(await renderSettings(pane: pane, percentageMode: .remaining, dark: dark,
                                                          height: compact ? SettingsView.minimumWindowHeight : nil,
                                                          width: compact ? SettingsView.minimumWindowWidth : nil,
                                                          pose: pose, to: url)) { failedPaths.append(name) }
                            }
                        }
                    }
                }
                for path in failedPaths { print("Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--warm-up-only") {
                for dark in [false, true] {
                    let style = dark ? "dark" : "light"
                    let url = outDir.appendingPathComponent("settings-warm-up-\(style).png")
                    if await renderSettings(pane: .warmUp, percentageMode: .remaining, dark: dark,
                                            height: 700, warmUpSample: true, to: url) {
                        print("✓ \(url.path)")
                    } else { failedPaths.append(url.path) }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--settings-only") {
                for dark in [false, true] {
                    let style = dark ? "dark" : "light"
                    for pane in SettingsPane.allCases {
                        let name = pane == .appearance ? "popover" : pane.rawValue
                        let height: CGFloat? = switch pane {
                        case .appearance, .menuBar: 1000
                        case .accounts: 900
                        default: nil
                        }
                        let url = outDir.appendingPathComponent("settings-\(name)-\(style).png")
                        if await renderSettings(
                            pane: pane, percentageMode: .remaining, dark: dark, height: height,
                            notifications: pane == .notifications ? .custom : .firstOpen, to: url
                        ) {
                            print("✓ \(url.path)")
                        } else { failedPaths.append(url.path) }
                    }
                    let source = outDir.appendingPathComponent("settings-add-source-\(style).png")
                    if await renderAddSource(dark: dark, to: source) { print("✓ \(source.path)") }
                    else { failedPaths.append(source.path) }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--general-only") {
                for dark in [false, true] {
                    for availability in SoftwareUpdatePresentation.Availability.allCases {
                        for compact in [false, true] {
                            let name = "settings-general-\(availability.rawValue)-\(compact ? "compact" : "regular")-\(dark ? "dark" : "light").png"
                            let url = outDir.appendingPathComponent(name)
                            if await renderSettings(
                                pane: .general, percentageMode: .remaining, dark: dark,
                                height: compact ? SettingsView.minimumWindowHeight : nil,
                                width: compact ? SettingsView.minimumWindowWidth : nil,
                                softwareUpdates: RenderSoftwareUpdateController(availability: availability),
                                to: url
                            ) {
                                print("✓ \(url.path)")
                            } else { failedPaths.append(url.path) }
                        }
                    }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--loading-only") {
                do {
                    try await PopoverLoadingRenderHarness.run(to: outDir)
                    exit(0)
                } catch {
                    print("✗ Loading capture checkpoint failed: \(error)")
                    exit(1)
                }
            }
            // Show the full Appearance pane so its lower account-layout choices can be
            // inspected without driving the user's Settings window or scrolling it.
            if CommandLine.arguments.contains("--appearance-only") {
                for dark in [false, true] {
                    for width in [SettingsView.minimumWindowWidth, SettingsView.windowWidth] {
                        let url = outDir.appendingPathComponent("settings-popover-\(Int(width))-\(dark ? "dark" : "light").png")
                        if await renderSettings(
                            pane: .appearance, percentageMode: .remaining, dark: dark,
                            height: 1800, width: width, to: url
                        ) {
                            print("✓ \(url.path)")
                        } else { failedPaths.append(url.path) }
                    }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if CommandLine.arguments.contains("--menu-bar-only") {
                for dark in [false, true] {
                    for (suffix, width, height) in [
                        ("", SettingsView.windowWidth, SettingsView.windowHeight),
                        ("-compact", SettingsView.minimumWindowWidth, SettingsView.minimumWindowHeight),
                        ("-full", SettingsView.windowWidth, 960)
                    ] {
                        let url = outDir.appendingPathComponent("settings-menuBar\(suffix)-\(dark ? "dark" : "light").png")
                        if await renderSettings(pane: .menuBar, percentageMode: .remaining, dark: dark,
                                                height: height, width: width, to: url) {
                            print("✓ \(url.path)")
                        } else { failedPaths.append(url.path) }
                    }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            if let name = renderScenarioArgument() {
                let scenario = MultiAccountScenario(rawValue: name)
                let state = State(rawValue: name)
                if scenario == nil, state == nil {
                    let valid = State.allCases.map(\.rawValue) + MultiAccountScenario.allCases.map(\.rawValue)
                    FileHandle.standardError.write(Data("✗ Unknown --render-scenario '\(name)'. Valid: \(valid.joined(separator: ", "))\n".utf8))
                    exit(2)
                }
                for dark in [false, true] {
                    let url = outDir.appendingPathComponent("popover-\(name)-\(dark ? "dark" : "light").png")
                    let ok = if let scenario {
                        await renderMulti(scenario: scenario, dark: dark, to: url)
                    } else {
                        await render(state: state ?? .connected, percentageMode: .remaining, dark: dark, to: url)
                    }
                    if ok { print("✓ \(url.path)") } else { failedPaths.append(url.path) }
                }
                for path in failedPaths { print("✗ Failed to render \(path)") }
                exit(failedPaths.isEmpty ? 0 : 1)
            }
            for state in State.allCases {
                let modes: [UsagePercentageMode] = state == .connected ? UsagePercentageMode.allCases : [.remaining]
                for mode in modes {
                    for dark in [false, true] {
                        let modeSuffix = mode == .used ? "-used" : ""
                        let name = "popover-\(state.rawValue)\(modeSuffix)-\(dark ? "dark" : "light").png"
                        let url = outDir.appendingPathComponent(name)
                        if await render(state: state, percentageMode: mode, dark: dark, to: url) {
                            print("✓ \(url.path)")
                        } else {
                            failedPaths.append(url.path)
                        }
                    }
                }
            }
            for scenario in MultiAccountScenario.allCases {
                for dark in [false, true] {
                    let name = "popover-\(scenario.rawValue)-\(dark ? "dark" : "light").png"
                    let url = outDir.appendingPathComponent(name)
                    if await renderMulti(scenario: scenario, dark: dark, to: url) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            // KTD10: one capture per sidebar pane and appearance at the fixed frame. The
            // Used variant only matters where Percentages lives now (Appearance).
            for pane in SettingsPane.allCases {
                let modes: [UsagePercentageMode] = pane == .appearance ? UsagePercentageMode.allCases : [.remaining]
                for mode in modes {
                    for dark in [false, true] {
                        let modeSuffix = mode == .used ? "-used" : ""
                        let name = "settings-\(pane == .appearance ? "popover" : pane.rawValue)\(modeSuffix)-\(dark ? "dark" : "light").png"
                        let url = outDir.appendingPathComponent(name)
                        if await renderSettings(pane: pane, percentageMode: mode, dark: dark, to: url) {
                            print("✓ \(url.path)")
                        } else {
                            failedPaths.append(url.path)
                        }
                    }
                }
            }
            // U6: the Notifications pane's other states beside the default capture above —
            // permission denied (R18), and switched on with custom rules (R4–R9), also at
            // the 720pt minimum width so a wrapping rule row shows up.
            let notificationStates: [(suffix: String, state: NotificationsRenderState, width: CGFloat?)] = [
                ("denied", .denied, nil),
                ("custom", .custom, nil),
                ("custom-compact", .custom, SettingsView.minimumWindowWidth),
            ]
            for (suffix, state, width) in notificationStates {
                for dark in [false, true] {
                    let url = outDir.appendingPathComponent("settings-notifications-\(suffix)-\(dark ? "dark" : "light").png")
                    if await renderSettings(
                        pane: .notifications, percentageMode: .remaining, dark: dark,
                        width: width, notifications: state, to: url
                    ) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            for dark in [false, true] {
                let name = "settings-accounts-multi-\(dark ? "dark" : "light").png"
                let url = outDir.appendingPathComponent(name)
                if await renderSettings(
                    pane: .accounts,
                    percentageMode: .remaining,
                    dark: dark,
                    multiAccount: true,
                    // Taller than the shipping window so the whole multi-account list lands
                    // in the capture instead of being cropped at `windowHeight`.
                    height: 1500,
                    to: url
                ) {
                    print("✓ \(url.path)")
                } else {
                    failedPaths.append(url.path)
                }
            }
            let heroURL = outDir.appendingPathComponent("hero-popover-dark.png")
            if await renderHero(to: heroURL) {
                print("✓ \(heroURL.path)")
            } else {
                failedPaths.append(heroURL.path)
            }
            for path in failedPaths {
                FileHandle.standardError.write(Data("✗ Failed to render \(path)\n".utf8))
            }
            exit(failedPaths.isEmpty ? 0 : 1)
        }
        app.run()
    }

    /// U6: which Notifications pane state a Settings capture shows. Scripted, never the
    /// real client (KTD9): the default is undecided permission, the first-open state.
    enum NotificationsRenderState {
        case firstOpen
        case denied
        case custom

        var client: ScriptedNotificationClient {
            switch self {
            case .firstOpen: ScriptedNotificationClient(status: .notDetermined)
            case .denied: ScriptedNotificationClient(status: .denied)
            case .custom: ScriptedNotificationClient(status: .authorized)
            }
        }
    }

    /// `--render-scenario <name>`: a `MultiAccountScenario` or onboarding `State` raw value.
    private static func renderScenarioArgument(arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: "--render-scenario"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    enum State: String, CaseIterable {
        case connect, waiting, connected
        case codexConnect, codexReconnect, codexWaiting, codexConnected
        case dualWaiting
    }

    /// Scenario set + fixture builders now live on `DemoFixture` (demo mode, Jul 2026) so the
    /// live `--demo <scenario>` launch mode and this offscreen harness share one source of
    /// truth. These aliases keep the harness call sites (and its byte-identical output) intact.
    typealias MultiAccountScenario = DemoFixture.MultiAccountScenario

    /// U8: waits for the refresh `refreshNow()` started to finish and its "Refreshing…" hold
    /// to clear, bounded so a scenario that never settles still captures.
    private static func awaitSettledRefresh(_ store: UsageStore, timeout: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while store.lastFullRefreshCompletedAt == nil || store.isRefreshing {
            guard clock.now < deadline else {
                FileHandle.standardError.write(Data("! refresh did not settle within \(timeout); capturing anyway\n".utf8))
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func renderMulti(scenario: MultiAccountScenario, dark: Bool, to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let store = multiStore(for: scenario)
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(700))
        await awaitSettledRefresh(store)
        return await snapshotPopover(store: store, dark: dark, to: url,
                                     fixtureDate: scenario == .paceStates ? DemoFixture.paceStatesDate : nil)
    }

    /// The store a multi-account capture draws, set up the way `AppComposition.demoMultiAccountStore`
    /// does: every provider in the scenario gets its subscription surface (Grok and Cursor default
    /// OFF for upgrade safety, so they would otherwise never draw), and the scenario's spend
    /// providers are wired with their API surfaces enabled, so `spend-states`' xAI and Cursor rows
    /// reach the card.
    static func multiStore(for scenario: MultiAccountScenario) -> UsageStore {
        if scenario == .paceStates {
            return AppComposition.demoMultiAccountStore(scenario: .paceStates, defaults: DemoMemoryDefaults())
        }
        let preferences = renderPreferences(mode: .remaining)
        let fixture = DemoFixture.multiFixture(for: scenario, includesLedgerDetails: preferences.accountLayout == .ledger)
        // Use settled readings at multi-20 instead of waiting for its 4s-per-account simulated probes.
        let pairs = scenario == .envelope ? DemoFixture.settledEnvelopePairs() : Array(zip(fixture.accounts, fixture.providers))
        if CommandLine.arguments.contains("--ledger-expanded-demo") {
            let expandedProviders: Set<ProviderID> = switch scenario {
            case .menubar, .sixProviders: [.claude, .antigravity]
            case .bankedResets: [.codex]
            default: []
            }
            preferences.popoverExpandedAccounts = Set(pairs.map(\.account).filter {
                $0.isBuiltIn && expandedProviders.contains($0.providerID)
            }.map(\.key))
        }
        for providerID in Set(pairs.map(\.account.providerID)) {
            if let surface = UsageSurface.subscription(for: providerID) {
                preferences.setSurfaceEnabled(true, for: surface)
            }
        }
        let spendProviders = AppComposition.demoSpendProviders(for: scenario)
        for provider in spendProviders {
            if let surface = UsageSurface.api(for: provider.id) {
                preferences.setSurfaceEnabled(true, for: surface)
            }
        }
        return UsageStore(
            providers: pairs.map(\.provider),
            apiSpendProviders: spendProviders,
            preferences: preferences,
            accounts: pairs.map(\.account),
            // Default-login U11: the fixture's in-memory records (`remembered` poses its
            // remembered rows from them); never the user's `defaultLoginRecords.v1`.
            defaultLoginRecords: fixture.makeDefaultLoginRecordStore(),
            previewAccountLayout: preferences.accountLayout
        )
    }

    private static func render(state: State, percentageMode: UsagePercentageMode, dark: Bool, to url: URL) async -> Bool {
        // App-wide appearance, not just window-level: SwiftUI's semantic styles
        // (.primary/.secondary/.quaternary) resolve against the app's effective
        // appearance in this offscreen path, so a window-only override leaves
        // light-mode ink in dark renders.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Provider-scoped flags drive each Connect → Waiting → Connected flow.
        ClaudeSetupSession.openedSetupAt = switch state {
        case .waiting, .connected, .dualWaiting: Date()
        default: nil
        }
        CodexSetupSession.openedSetupAt = switch state {
        case .codexWaiting, .codexConnected, .dualWaiting: Date()
        default: nil
        }

        let preferences = renderPreferences(mode: percentageMode)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: claudeSnapshot(for: state)),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: codexSnapshot(for: state)),
            ],
            apiSpendProviders: spendProviders(for: state),
            preferences: preferences,
            previewAccountLayout: preferences.accountLayout
        )
        store.refreshNow()
        // Demo providers resolve instantly; give the cycle + entrance animation a beat.
        try? await Task.sleep(for: .milliseconds(700))
        return await snapshotPopover(store: store, dark: dark, to: url)
    }

    /// Shared popover capture: hosts the real `PopoverView` over the desk backdrop,
    /// sizes to fit, and snapshots the compositor output.
    ///
    /// U8 (popover account layout plan): the canvas is the popover's own width plus the 24pt
    /// desk margin — 432 for one column, 798 for two — not a fixed 432. The column plan is
    /// made from measured heights and lands a main-queue turn after the first layout, so the
    /// window is refitted once it has.
    private static func snapshotPopover(store: UsageStore, dark: Bool, to url: URL, fixtureDate: Date? = nil) async -> Bool {
        let root = PopoverView(
            store: store, onOpenSettings: {},
            forceSolidSurface: CommandLine.arguments.contains("--solid-popover")
        )
            .padding(24)
            .background {
                // Desk backdrop so the system surface has something to sample (mirrors the mockup).
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.137, green: 0.137, blue: 0.169), Color(red: 0.078, green: 0.078, blue: 0.102)]
                        : [Color(red: 0.843, green: 0.827, blue: 0.800), Color(red: 0.725, green: 0.702, blue: 0.663)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Direct environment override (not the scene-level `preferredColorScheme`
            // preference) so semantic styles resolve for the right scheme in this
            // offscreen hosting context.
            .environment(\.loadingDate, fixtureDate)
            .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: 10)
        hosting.frame = NSRect(origin: .zero, size: canvasSize(hosting.fittingSize))

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.isOpaque = true
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        keepOnOneDisplay(window)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        await settle(hosting, in: window)
        if refit(hosting, in: window) { await settle(hosting, in: window) }
        // Let the staged meter arrival (M9A beat, then `arrivalSpring`) land before
        // snapshotting, or numerals are caught mid-roll. AR1 lengthened both; 650ms covers the
        // critically damped spring's visible settle.
        try? await Task.sleep(for: PacemarkMotion.arrivalDelay + .milliseconds(650))
        if refit(hosting, in: window) { await settle(hosting, in: window) }

        // Capture the compositor's actual output (correct dynamic-color resolution and
        // the real OS-selected surface) via `screencapture -l`. The offscreen `cacheDisplay` path
        // resolves semantic text colors against the wrong appearance, so it's only the
        // fallback when screen capture is unavailable (no Screen Recording permission).
        // A window grows from its top-left corner, so one opened at the screen's bottom edge
        // grows off it, and `screencapture -l` returns nothing for the part below the display:
        // every capture taller than the first 200pt canvas came out blank past it.
        if let screen = window.screen ?? NSScreen.main, window.frame.minY < screen.frame.minY {
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: screen.frame.minY))
            await settle(hosting, in: window)
        }
        let captured = capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    /// The capture canvas for a fitted popover: its own width, and at least 200pt tall as before.
    private static func canvasSize(_ fitting: NSSize) -> NSSize {
        NSSize(width: max(fitting.width, 1), height: max(fitting.height, 200))
    }

    /// A few main-queue turns, laid out and drawn each time, so height reports and the column
    /// replan they complete (`PopoverPlanModel`, next main turn) can land.
    private static func settle(_ hosting: NSView, in window: NSWindow, turns: Int = 12) async {
        for _ in 0..<turns {
            try? await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }

    /// Resizes window and hosting view to the popover's current fitting size, as
    /// `MenuBarExtra` grows its window when the shell widens to two columns. False when the
    /// size already matched.
    private static func refit(_ hosting: NSView, in window: NSWindow) -> Bool {
        let size = canvasSize(hosting.fittingSize)
        guard size != hosting.frame.size else { return false }
        window.setContentSize(size)
        keepOnOneDisplay(window)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return true
    }

    /// `screencapture -l` leaves blank whatever part of a window lies outside every display.
    /// The global origin is not inside a display on every arrangement (a second display set
    /// higher than the main one put only the window's top 200pt on screen), so the window
    /// is pinned to the top-left of the tallest display.
    private static func keepOnOneDisplay(_ window: NSWindow) {
        guard let screen = NSScreen.screens.max(by: { $0.frame.height < $1.frame.height }) else { return }
        window.setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.maxY - window.frame.height))
    }

    /// Marketing hero for the project website (U4): the connected, dark popover with the
    /// API Spend section, rendered via `ImageRenderer` at 3× with a transparent
    /// background (rounded corners live in the PNG alpha) — no Screen Recording
    /// permission needed, unlike the compositor `screencapture` path above. Forces the
    /// solid surface branch (reduce-transparency), because `ImageRenderer` can't
    /// rasterize the live Liquid Glass material; the resulting flat shell + tiles match
    /// the design artboard (OQ1 resolved to the solid shell — see the plan).
    @MainActor
    private static func renderHero(to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Steady connected state: clear any setup-session flags the diagnostic render loop
        // left set, so the transient "✓ Connected" payoff chip doesn't appear (the design
        // artboard shows plain provider headers).
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let preferences = renderPreferences(mode: .remaining)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: preferences
        )
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(400))

        let root = PopoverView(
            store: store,
            onOpenSettings: {},
            forceSolidSurface: true,
            // Must fit the whole locked scenario: Claude (3 windows) + Codex (2 windows)
            // + both API Spend rows. At 410 the second spend row clipped under the footer
            // once Codex's restored 5-hour window pushed the stack down.
            // Sized to the locked scenario: Claude (3 windows) + Codex (2 windows) + both
            // API Spend rows. 410 clipped the second spend row once Codex's 5-hour window
            // was restored, and 444 left it fading under the scroll mask. 482 reproduces
            // the approved v3 geometry exactly (384x609pt). Retune if the scenario changes.
            forcedCardsHeight: 482
        )
            .environment(\.colorScheme, .dark)
            .focusEffectDisabled()
            // The popover's `WindowAccessor` background NSView renders as the system accent
            // under ImageRenderer, filling the rounded-corner cutouts with an opaque fringe.
            // Clip the whole export to the surface shape so those cutouts stay transparent.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        // Host the view for one layout cycle. `ImageRenderer` does not mount ScrollView
        // content, so even a fixed height can produce a shell with no cards. A transparent
        // hosting view exercises the same mounted layout path as the 32 review captures
        // while retaining a permission-free bitmap export.
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 384, height: 760)
        let fitting = hosting.fittingSize
        hosting.frame.size.height = max(fitting.height, 200)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = hosting.appearance
        window.contentView = hosting
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let pngData = representation.representation(using: .png, properties: [:])
        window.orderOut(nil)
        guard let data = pngData, data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func captureWindow(number: Int, to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-o", "-x", "-l", String(number), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > 10_000 else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// One capture per sidebar pane, demo store, at the shipping
    /// `SettingsView.windowWidth` × `SettingsView.windowHeight` — verifies the
    /// shared type hierarchy (15pt tile heads / 13pt controls / 11pt fine print) and the
    /// all-tiles material system across both windows. `height` overrides the frame for the
    /// multi-account capture, which needs a taller canvas so the full account list is
    /// visible instead of cropped at the pane height.
    private static func renderSettings(
        pane: SettingsPane,
        percentageMode: UsagePercentageMode,
        dark: Bool,
        multiAccount: Bool = false,
        height heightOverride: CGFloat? = nil,
        width widthOverride: CGFloat? = nil,
        notifications: NotificationsRenderState = .firstOpen,
        softwareUpdates: SoftwareUpdateControlling = DisabledSoftwareUpdateController(),
        warmUpSample: Bool = false,
        pose: String? = nil,
        to url: URL
    ) async -> Bool {
        // L9A retired the per-pane window heights; the harness captures every pane at
        // the shipping default frame unless a caller asks for a taller canvas.
        let height = heightOverride ?? SettingsView.windowHeight
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let preferences = renderPreferences(mode: percentageMode)
        // The window opens on the persisted pane (R4), so selecting it here is how the
        // harness chooses which detail column to capture without a view-side hook.
        preferences.settingsPane = pane
        if notifications == .custom {
            // The mockup's "Customised" state: both switches on, three rules, 5-hour ticked.
            preferences.useItUpRemindersEnabled = true
            preferences.bankedResetNotificationsEnabled = true
            preferences.reminderRules = [
                ReminderRule(amount: 2, unit: .days, threshold: 70),
                ReminderRule(amount: 1, unit: .days, threshold: 50),
                // 100, not the mockup's 15, so the widest threshold proves the field fits it.
                ReminderRule(amount: 3, unit: .hours, threshold: 100),
            ]
            preferences.reminderScope = [.weekly, .billingPeriod, .fiveHour]
        }
        let store: UsageStore
        if multiAccount {
            let fixture = DemoFixture.multiFixture(for: .multiMixed)
            // Demo account changes live only for the duration of this fixture.
            let registry = AccountRegistry(defaults: DemoMemoryDefaults())
            registry.seed(fixture.accounts)
            let factory: @MainActor (ProviderAccount) -> any UsageProvider = { account in
                DemoUsageProvider(
                    id: account.providerID,
                    displayName: account.providerID.displayName,
                    snapshot: .pending(for: account.providerID),
                    accountID: account.id
                )
            }
            store = UsageStore(
                providers: fixture.providers,
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                ],
                preferences: preferences,
                accounts: fixture.accounts,
                accountRegistry: registry,
                providerFactory: factory
            )
            store.refreshNow()
            try? await Task.sleep(for: .milliseconds(300))
        } else if pane == .menuBar || pane == .accounts || pane == .warmUp {
            store = MenuBarRenderHarness.fixtureStore(preferences: preferences, warmUpSample: warmUpSample, review: CommandLine.arguments.contains("--review-meters"))
        } else {
            store = UsageStore(
                providers: [
                    DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                    DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
                ],
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                    DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: .pending(
                        providerID: .grok, displayName: "xAI API", periodLabel: preferences.apiSpendPeriod.label
                    )),
                ],
                preferences: preferences
            )
        }
        if [.menuBar, .accounts, .apiSpend, .notifications, .appearance, .warmUp].contains(pane) { await store.refreshAll() }
        let width = widthOverride ?? SettingsView.windowWidth
        let controls = DemoMemoryDefaults()
        MenuBarMeterControls.seedMenuBarDemo(defaults: controls)
        if pose != nil, pane == .menuBar {
            controls.set(MenuBarMeterTuning.IconSize.base.rawValue, forKey: "t3.menuBar.iconSize")
            controls.set(true, forKey: "t3.menuBar.showNumber")
            if pose == "empty" {
                for row in store.menuBarMeterRows { store.setMeterLabel("", for: row) }
            }
        }
        let root = SettingsView(
            store: store,
            softwareUpdates: softwareUpdates,
            preferences: preferences,
            // The unsigned debug binary's Keychain reads raise a SecurityAgent prompt that
            // blocks the whole run; the diagnostic never needs real keys.
            credentialStore: CredentialStore(codexReader: DemoCodexAuthReader(),
                                             apiKeyStore: SettingsRenderKeyStore(hasSavedKey: pane == .apiSpend)),
            launchControl: DemoLaunchAtLogin(),
            duplicateDetector: AppComposition.makeSettingsDuplicateDetector(isDemo: true),
            notificationClient: notifications.client,
            frameHeightOverride: height
        )
            .defaultAppStorage(controls)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.loadingDate, pane == .menuBar ? Date() : nil)

        return await captureSettings(root, width: width, height: height, dark: dark, scrollToBottom: pose == "bottom" || pose == "legend", to: url)
    }

    private static func renderAddSource(dark: Bool, to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = MenuBarRenderHarness.fixtureStore(preferences: renderPreferences(mode: .remaining))
        let source = AddAccountSourceSheet(providerID: .codex, displayName: "Codex", store: store,
                                           t3Sources: .constant(SharedT3AccountSources()),
                                           enableProvider: {}, addSeparateLogin: { false })
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        return await captureSettings(source, width: 440, height: 330, dark: dark, to: url)
    }

    private struct SettingsRenderKeyStore: APIKeyStoring {
        let hasSavedKey: Bool
        func readAPIKey(for provider: APIKeyProvider) throws -> String {
            guard hasSavedKey, provider == .anthropic else { throw CredentialError.notLoggedIn }
            return "fixture-only"
        }
        func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
        func deleteAPIKey(for provider: APIKeyProvider) throws { throw CredentialError.notLoggedIn }
    }

    private static func captureSettings<Content: View>(
        _ root: Content, width: CGFloat, height: CGFloat, dark: Bool, scrollToBottom: Bool = false, to url: URL
    ) async -> Bool {
        // A window-only capture excludes the desktop behind translucent material.
        let plate = root.frame(width: width, height: height)
            .background(dark ? Color(white: 0.16) : Color(white: 0.94))
        let hosting = NSHostingView(rootView: plate)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        // Kyle (2026-09-10): the harness must never show on screen. A borderless window at
        // the origin flashed in the bottom-left corner of the desktop on every render.
        // Parking it off-screen is not an option — `screencapture -l` returns a fully
        // transparent image for a window outside every display — so it stays on screen but
        // *below the wallpaper*: the window server composites and captures it, nobody sees
        // it, and Mission Control / Spaces leave it alone.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        if scrollToBottom {
            func scrollDetail(_ view: NSView) {
                if let scroll = view as? NSScrollView, let doc = scroll.documentView, scroll.bounds.width > width / 2 {
                    let bottom = doc.isFlipped ? max(0, doc.bounds.height - scroll.contentView.bounds.height) : 0
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                view.subviews.forEach(scrollDetail)
            }
            scrollDetail(hosting)
            try? await Task.sleep(for: .milliseconds(200))
        }
        // The focused acceptance run must fail if WindowServer capture is unavailable;
        // cacheDisplay can save a nonempty but cropped/incorrect Settings bitmap.
        let isFocusedAcceptance = CommandLine.arguments.contains("--menu-bar-only")
        let captured = isFocusedAcceptance
            ? captureWindow(number: window.windowNumber, to: url)
            : capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    static func capture(window: NSWindow, to url: URL) -> Bool {
        if captureWindow(number: window.windowNumber, to: url) { return true }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        (window.appearance ?? NSAppearance(named: .aqua))?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]), data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func renderPreferences(mode: UsagePercentageMode) -> Preferences {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.usagePercentageMode = mode
        // The compatibility layouts can still be posed explicitly by the popover renderer.
        preferences.meterStyle = AppComposition.demoMeterStyle()
        // And for `--account-layout <standard|compact|ledger>` (popover account layout plan, U8).
        preferences.accountLayout = AppComposition.demoAccountLayout()
        if CommandLine.arguments.contains("--ledger-claude-5h-demo") {
            preferences.setMenuBarWindowChoice(.fiveHour, for: .claude)
        }
        if CommandLine.arguments.contains("--ledger-summary-demo") {
            preferences.popoverSummarySlot1 = .tightest
            preferences.popoverSummarySlot2 = .nextReset
        }
        preferences.useEmailAsAccountName = ProcessInfo.processInfo.arguments.contains("--email-account-names")
        preferences.expandAccountsHorizontally = !ProcessInfo.processInfo.arguments.contains("--vertical-accounts")
        // API spend surfaces are off by default (`isSurfaceEnabled` → `isSubscription`),
        // so the store's `apiSpendProviderOrder` is empty and the section renders nothing.
        // Enable both so the connected hero shows the API Spend section — wiring the
        // providers alone is not sufficient (mirrors AppComposition.demoStore()).
        preferences.setSurfaceEnabled(true, for: .anthropicAPI)
        preferences.setSurfaceEnabled(true, for: .openAIAPI)
        return preferences
    }

    /// Demo API-spend providers for a popover render. Only the connected hero carries
    /// spend — the setup/waiting states have no configured keys, so showing dollar
    /// totals there would be misleading. The surfaces themselves are enabled in
    /// `renderPreferences`.
    private static func spendProviders(for state: State) -> [any APISpendProvider] {
        guard state == .connected else { return [] }
        return [
            DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
            DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
        ]
    }

    private static func claudeSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .connect, .waiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .claude,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.providerSetup(.claudeTrustRequired))
            )
        case .connected, .codexConnect, .codexReconnect, .codexWaiting, .codexConnected:
            return DemoFixture.claudeSnapshot
        }
    }

    private static func codexSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .codexConnect:
            return .stale(
                for: .codex,
                reason: .providerSetup(.codexAuthAbsent)
            )
        case .codexReconnect, .codexWaiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .codex,
                windows: DemoFixture.codexSnapshot.windows,
                planLabel: DemoFixture.codexSnapshot.planLabel,
                accountEmail: DemoFixture.codexSnapshot.accountEmail,
                bankedResets: DemoFixture.codexSnapshot.bankedResets,
                capturedAt: DemoFixture.codexSnapshot.capturedAt,
                freshness: .stale(.providerSetup(.codexRejectedAuth))
            )
        case .codexConnected, .connect, .waiting, .connected:
            return DemoFixture.codexSnapshot
        }
    }
}

/// Inert update fixtures for offscreen Settings captures; never starts Sparkle.
@MainActor
private final class RenderSoftwareUpdateController: SoftwareUpdateControlling {
    let canCheckForUpdates = true
    let allowsAutomaticUpdates = true
    let presentation = SoftwareUpdatePresentation()
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    let lastUpdateCheckDate: Date? = Date(timeIntervalSince1970: 1_791_478_920)

    init(availability: SoftwareUpdatePresentation.Availability) {
        presentation.availability = availability
        presentation.canCheckForUpdates = true
    }

    func checkForUpdates() {}
}

/// Fixture sheet for comparing both appearances without any account data.
struct PDSGallery: View {
  private let typeRamp = [
    ("Pane title", PDS.Typography.paneTitle), ("Pane subtitle", PDS.Typography.paneSubtitle),
    ("Caps", PDS.Typography.caps), ("Row title", PDS.Typography.rowTitle),
    ("Body", PDS.Typography.body), ("Secondary", PDS.Typography.secondary),
    ("Number", PDS.Typography.number), ("Large number", PDS.Typography.numberLarge),
    ("Small number", PDS.Typography.numberSmall),
  ]
  init() {}
  var body: some View {
    VStack(alignment: .leading, spacing: PDS.Space.m) {
      Text("Pacemark Design System").font(PDS.Typography.paneTitle)
      Grid(alignment: .leading) {
        ForEach(typeRamp, id: \.0) { label, font in
          GridRow {
            Text(label).font(PDS.Typography.secondary)
            Text(label.lowercased().contains("number") ? "62%" : "Pacemark").font(font)
          }
        }
      }
      HStack(alignment: .bottom) {
        ForEach([PDS.Space.xs, PDS.Space.s, PDS.Space.m, PDS.Space.l, PDS.Space.xl], id: \.self) {
          size in
          VStack {
            Rectangle().frame(width: size, height: size)
            Text(size.formatted())
          }
        }
        Spacer()
      }.frame(height: 48)
      let colours = [
        ("Ink", PDS.Ink.ink), ("Secondary", PDS.Ink.inkSecondary),
        ("Tertiary", PDS.Ink.inkTertiary),
        ("Separator", PDS.Ink.separator), ("Card fill", PDS.Ink.cardFill),
        ("Stroke", PDS.Ink.cardStroke),
        ("Accent", PDS.Ink.accent),
      ]
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
        ForEach(colours, id: \.0) { name, colour in
          HStack {
            Circle().fill(colour).overlay { Circle().strokeBorder(PDS.Ink.cardStroke) }.frame(width: 12, height: 12)
            Text(name)
          }
          .font(PDS.Typography.secondary)
        }
      }
      PDSCard("Accounts", count: 2, mark: { Image(systemName: "person.2") }, accessory: { Text("Week").font(PDS.Typography.secondary) }) {
        HStack {
          PDSColumns.text.cell(PDSCapsHeader("Account"))
          PDSColumns.number.cell(PDSCapsHeader("Left"))
          PDSColumns.menu(width: 110).cell(PDSCapsHeader("Window"))
        }
        PDSRow {
          PDSColumns.text.cell(Text("Personal").font(PDS.Typography.rowTitle))
        } trailing: {
          PDSColumns.number.cell(Text("62%").font(PDS.Typography.numberLarge))
          PDSMenuValue(width: 110) { Text("Runs out first · Gemini weekly") }
        }
        HStack {
          PDSChip(text: "Pro")
          PDSChip(text: "Weekly limit", icon: "checkmark")
          PDSChip(text: "Hidden when narrow").frame(width: 16)
        }
        PDSPickerRow("Window") { Picker("Window", selection: .constant(0)) { Text("Week").tag(0) }.labelsHidden() }
        PDSToggleRow(title: "Show percentage", isOn: .constant(true))
        PDSPickerRow("Count") {
          Picker("Count", selection: .constant(0)) {
            Text("What’s left").tag(0)
            Text("What’s used").tag(1)
          }.labelsHidden().pdsSegmented()
        }
      }
      PDSCard("Hover tip", accessory: { EmptyView() }) {
        PDSTipLabel("4 banked resets\nExpiry not available yet.")
      }
      PDSSidebarRow("General", symbol: "slider.horizontal.3").padding(PDS.Space.xs)
        .foregroundStyle(.white).background(PDS.Ink.accent, in: RoundedRectangle(cornerRadius: PDS.Radius.control))
      PDSSidebarRow("Accounts", symbol: "person.2")
    }.padding(PDS.Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
