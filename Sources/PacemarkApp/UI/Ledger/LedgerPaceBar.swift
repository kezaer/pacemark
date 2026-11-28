#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

/// The tick marks expected remaining quota at this point in the window.
struct LedgerPaceBar: View {
    let remaining: Double
    let pace: MenuBarPace?
    let severity: UsageSeverity
    var width = LedgerMetrics.paceWidth
    var height: CGFloat = 4
    var dimmed = false
    var mode: UsagePercentageMode = .remaining

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = MenuBarPalette(isDarkMenuBar: scheme == .dark, increasedContrast: contrast == .increased)
        let band = pace?.tier?.severity ?? severity
        let fill = dimmed ? Color.primary.opacity(0.30) : Color(nsColor: palette.liquid(for: band).menuBarColor)
        let track = Color(nsColor: palette.ink.menuBarColor).opacity(0.16)
        ZStack(alignment: .leading) {
            Capsule().fill(track)
                .frame(width: width, height: height)
            let fraction = mode == .remaining ? remaining : 1 - remaining
            if fraction > 0 {
                Capsule().fill(fill).frame(width: width * fraction, height: height)
            }
            if let expected = pace?.expectedRemaining, !dimmed {
                Capsule()
                    .fill(Color(nsColor: palette.ink.menuBarColor))
                    .frame(width: 1.5, height: height + (height < 4 ? 3 : 5))
                    .offset(x: min(width - 1.5, max(0, width * (mode == .remaining ? expected : 1 - expected) - 0.75)))
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .animation(PacemarkMotion.resolved(PacemarkMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                   value: pace)
        .accessibilityHidden(true)
    }
}
