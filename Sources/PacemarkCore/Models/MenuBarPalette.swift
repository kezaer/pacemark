import Foundation

/// Every color the menu bar label paints, resolved for one *menu bar* appearance (L1A).
///
/// Until Sep 2026 the label pinned all of these to their dark-scheme values, on the belief
/// that Tahoe always draws status items on a dark translucent backplate. It doesn't: over a
/// light wallpaper the menu bar itself goes light, and the pinned white vessel and white
/// numerals disappeared into it.
///
/// The pin was really a workaround for a *rendering* bug, not an appearance decision: SwiftUI
/// rasterizes `Image(nsImage:)` against the **system** appearance, so a dynamic severity
/// `NSColor` baked to its light value while a sibling `.labelColor` stayed dynamic and
/// resolved white against the dark menu bar — one label, two palettes. This type removes the
/// ambiguity instead of pinning around it: every value is an explicit constant selected by a
/// single flag, so the render never depends on whichever appearance the rasterizer happens to
/// be in.
///
/// The flag is the **menu bar's** appearance, not the system's. Those differ in a case that a
/// system-appearance check gets wrong: a light system appearance over a dark wallpaper still
/// gets a dark menu bar. `MenuBarAppearanceMonitor` (app target) supplies it from the status
/// item's own window.
public struct MenuBarPalette: Sendable, Equatable {
    public let isDarkMenuBar: Bool

    public let increasedContrast: Bool

    public init(isDarkMenuBar: Bool, increasedContrast: Bool = false) {
        self.isDarkMenuBar = isDarkMenuBar
        self.increasedContrast = increasedContrast
    }

    /// The menu bar's label color — what every other status item's ink matches. White on a
    /// dark bar, black at 0.85 on a light one (AppKit's own `labelColor` pair), resolved to
    /// explicit values rather than left dynamic.
    public var ink: PacemarkTint {
        isDarkMenuBar
            ? PacemarkTint(color: .white, opacity: 1.0)
            : PacemarkTint(color: .black, opacity: 0.85)
    }

    /// Liquid for a vessel with no severity to report (automatic fill, or no data yet): the
    /// ink knocked back to 0.62 so the level reads as decoration rather than as status.
    public var neutralLiquid: PacemarkTint {
        PacemarkTint(color: ink.color, opacity: ink.opacity * 0.62)
    }

    /// The gauge fill follows the menu bar appearance and Increase Contrast.
    public func liquid(for severity: UsageSeverity) -> PacemarkRGBColor {
        PacemarkSeverityColorValues.fill(
            for: severity, dark: isDarkMenuBar, increasedContrast: increasedContrast
        )
    }

    public func severityInk(for severity: UsageSeverity) -> PacemarkRGBColor {
        PacemarkSeverityColorValues.color(for: severity, dark: isDarkMenuBar)
    }
}
