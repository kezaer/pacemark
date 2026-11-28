#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct MenuBarPreviewStrip: View {
    let meters: [MenuBarMeter]
    let tuning: MenuBarMeterTuning
    let highlightedAccount: AccountKey?
    var previewAppearance: ColorScheme? = nil
    @State private var darkBarOverride: Bool?

    var body: some View {
        let isDark = darkBarOverride ?? previewAppearance.map { $0 == .dark } ?? MenuBarAppearanceMonitor.shared.isDarkMenuBar
        let palette = MenuBarPalette(isDarkMenuBar: isDark, increasedContrast: contrast == .increased)
        let renderer = MenuBarGaugeRenderer(palette: palette, tuning: tuning)
        let strip = renderer.image(meters: meters, highlighting: highlightedAccount)
        let mayHide = strip.size.width > 180
        SettingsLedgerTile(title: "Preview") {
            Text("\(meters.count) \(meters.count == 1 ? "meter" : "meters") · \(Double(strip.size.width).formatted(.number.grouping(.never).precision(.fractionLength(0)))) pt\(mayHide ? " · May hide behind the notch" : "")")
            .font(PopoverLedgerType.sentence.monospacedDigit())
            .foregroundStyle(mayHide ? PDS.Ink.paceWarning(previewAppearance ?? scheme) : .secondary)
            .lineLimit(1)
        } content: {
            ViewThatFits(in: .horizontal) {
                bar(strip, apple: true, menus: true)
                bar(strip, apple: true, menus: false)
                bar(strip, apple: false, menus: false)
                GeometryReader { proxy in
                    let prefix = fittingPrefix(renderer: renderer, width: proxy.size.width)
                    HStack(spacing: PDS.Space.s) {
                        Spacer(minLength: 0)
                        if prefix.count > 0 { Image(nsImage: prefix.image).fixedSize() }
                        Text("+\(meters.count - prefix.count)").font(PDS.Typography.caps)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, PDS.Space.xs).background(.quaternary, in: Capsule())
                        if proxy.size.width >= Self.statusReserve {
                            Image(systemName: "wifi")
                            Image(systemName: "battery.75percent")
                            Text("Wed 9:41").fixedSize()
                        }
                    }.frame(height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .font(PDS.Typography.rowTitle)
            .foregroundStyle(Color(nsColor: palette.ink.menuBarColor))
            .padding(.horizontal, LedgerMetrics.margin)
            // The preview well allows the tallest supported status item plus the plate inset.
            .frame(height: 44)
            .background(isDark ? Color.black.opacity(0.85) : Color.white.opacity(0.92), in: .rect(cornerRadius: PDS.Radius.chip))
            .accessibilityHidden(true)
            .padding(.bottom, PDS.Space.xs)
            PDSPickerRow("Preview appearance") {
                Picker("Preview appearance", selection: Binding(get: { isDark }, set: { darkBarOverride = $0 })) {
                    Text("Dark bar").tag(true)
                    Text("Light bar").tag(false)
                }
                .pdsSegmented()
                .fixedSize()
            }
        }
    }

    private static let statusReserve: CGFloat = 172

    private func fittingPrefix(renderer: MenuBarGaugeRenderer, width: CGFloat) -> (count: Int, image: NSImage) {
        // Reserve space for the overflow count and the status icons at the trailing edge.
        var low = 0, high = max(0, meters.count - 1)
        func image(_ count: Int) -> NSImage {
            renderer.image(meters: Array(meters.prefix(count)), highlighting: highlightedAccount)
        }
        while low < high {
            let mid = (low + high + 1) / 2
            if image(mid).size.width + Self.statusReserve <= width { low = mid } else { high = mid - 1 }
        }
        return (low, image(low))
    }

    private func bar(_ strip: NSImage, apple: Bool, menus: Bool) -> some View {
        HStack(spacing: PDS.Space.s) {
            if apple { Image(systemName: "apple.logo").opacity(0.55) }
            if menus { Text("File     Edit     View").fixedSize() }
            Spacer(minLength: 0)
            Image(nsImage: strip)
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Wed 9:41")
        }
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
}
