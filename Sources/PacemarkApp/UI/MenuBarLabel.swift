import AppKit
import PacemarkCore
import SwiftUI

struct MenuBarStatusLabel: View {
    let store: UsageStore
    var appearanceOverride: Bool?
    private var controls = MenuBarMeterControls()
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let _ = BenchCounters.hit("MenuBarStatusLabel")
        let tuning = controls.tuning
        let meters = store.menuBarMeters
        let renderer = MenuBarGaugeRenderer(
            palette: MenuBarPalette(
                isDarkMenuBar: appearanceOverride ?? MenuBarAppearanceMonitor.shared.isDarkMenuBar,
                increasedContrast: contrast == .increased
            ),
            tuning: tuning)
        let description = meters.compactMap(\.accessibilityReading).joined(separator: ". ")
        Image(nsImage: renderer.image(meters: meters))
            .accessibilityLabel(description.isEmpty ? "Pacemark" : description)
    }
}

struct MenuBarSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Menu Bar Settings")
        .help("Open Menu Bar settings")
    }
}

/// The live appearance of the menu bar itself (L1A).
///
/// `MenuBarExtra` hands out no `NSStatusItem`, so there is no supported handle on the status
/// item's button. The status item does live in an `NSStatusBarWindow` inside this process,
/// though, and that window's appearance is the very thing the old dark pin was working
/// around: the system sets it from the menu bar's backplate, so it reports dark over a dark
/// wallpaper even when the system appearance is light. We find that window by class name and
/// KVO its `effectiveAppearance`.
///
/// `NSApp.effectiveAppearance` is deliberately **not** the source: it is the process
/// appearance (which Pacemark's own theme switch pins), and it would answer "light" for the
/// light-system / dark-menu-bar case that this decision exists to fix. It is used only as a
/// first-paint fallback before the status window exists.
@MainActor
@Observable
final class MenuBarAppearanceMonitor {
    static let shared = MenuBarAppearanceMonitor()

    /// Defaults to dark: that is what the menu bar is in most of the day, and it is the
    /// palette that shipped, so the pre-attach frame is never a regression.
    private(set) var isDarkMenuBar = true

    @ObservationIgnored private weak var observedWindow: NSWindow?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var attachTask: Task<Void, Never>?

    private init() {}

    /// Begin (or re-begin) tracking. Safe to call repeatedly — the status item's window is
    /// created after the scene's first paint, and can be torn down and rebuilt, so a lost
    /// window simply restarts the search.
    func start() {
        guard observedWindow == nil else { return }
        attachTask?.cancel()
        attachTask = Task { [weak self] in
            // The status window shows up a runloop turn or two after the scene appears.
            // Poll briefly, then back off; give up rather than spin forever, leaving the
            // process-appearance fallback in place.
            for attempt in 0..<40 {
                guard let self, !Task.isCancelled else { return }
                if self.bind() { return }
                try? await Task.sleep(for: .milliseconds(attempt < 10 ? 100 : 500))
            }
        }
    }

    /// Re-read the current appearance, re-attaching if the status window was replaced.
    /// Called on OS theme flips, which can swap the menu bar backplate without the KVO
    /// having a window to fire from yet.
    func refresh() {
        if observedWindow == nil {
            start()
        } else {
            readCurrentAppearance()
        }
    }

    private func bind() -> Bool {
        guard let window = Self.statusBarWindow() else {
            readCurrentAppearance()
            return false
        }
        observedWindow = window
        // `.initial` gives us the first value synchronously; later fires cover wallpaper
        // changes, display moves, and OS theme flips.
        observation = window.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.readCurrentAppearance() }
        }
        return true
    }

    private func readCurrentAppearance() {
        guard let window = observedWindow else {
            isDarkMenuBar = Self.isDark(NSApplication.shared.effectiveAppearance)
            return
        }
        // Measured on macOS 26 (2026-09-04): the status window carries no explicit
        // `appearance`, and its `effectiveAppearance` is NOT the inherited process one — it
        // reported `NSAppearanceNameVibrantLight` and then `VibrantDark` while
        // `NSApp.appearance` sat pinned at `NSAppearanceNameDarkAqua` throughout. So this is
        // genuinely the menu bar's backplate and Pacemark's own theme pin does not taint it.
        // `window.appearance` is still preferred if the system ever starts setting one.
        // The light→dark settle took ~45ms at launch, before the item is drawn.
        isDarkMenuBar = Self.isDark(window.appearance ?? window.effectiveAppearance)
    }

    private static func statusBarWindow() -> NSWindow? {
        NSApplication.shared.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
