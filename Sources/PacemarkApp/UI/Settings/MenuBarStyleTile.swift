#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct MenuBarStyleTile: View {
    let controls: MenuBarMeterControls
    @Binding var showLabels: Bool
    @State private var heightLimit = MenuBarGaugeRenderer.statusItemHeight
    @State private var showAdvanced = false

    var body: some View {
        SettingsLedgerTile("Style") {
            let renderer = MenuBarGaugeRenderer(palette: MenuBarPalette(isDarkMenuBar: true), tuning: controls.tuning, heightLimit: heightLimit)
            segmented("Icon size", selection: Binding(get: { renderer.effectiveIconSize }, set: { controls.iconSize = $0 }),
                      options: MenuBarMeterTuning.IconSize.allCases.filter(renderer.supports), title: \.title)
                .help("Available sizes depend on the menu bar’s height.")
            toggle("Show percentage next to each icon", selection: controls.$showNumber)
            PDSToggleRow(title: "Show labels", help: "Shows the text you typed under each meter.", isOn: $showLabels)
            if showLabels {
                segmented("Label size", selection: controls.$textSize, options: MenuBarMeterTuning.TextSize.allCases, title: \.title)
            }
            toggle("Pace tick", selection: controls.$showPaceTick)
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                segmented("Stroke", selection: controls.$ringLineWidth, options: MenuBarMeterTuning.ringWidths,
                          title: { $0.formatted(.number.precision(.fractionLength(0...2))) })
                if showLabels {
                    segmented("Label weight", selection: controls.$labelWeight, options: MenuBarMeterTuning.LabelWeight.allCases,
                          title: { $0.rawValue.capitalized })
                }
                segmented("Logo scale", selection: controls.$markScale, options: MenuBarMeterTuning.markScales,
                          title: { $0.formatted(.percent) })
            }
            .font(PDS.Typography.body)
            .padding(.vertical, PDS.Space.xs)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            heightLimit = MenuBarGaugeRenderer.statusItemHeight
        }
    }

    private func toggle(_ label: String, selection: Binding<Bool>) -> some View {
        PDSToggleRow(title: label, isOn: selection)
    }

    private func segmented<Value: Hashable>(
        _ label: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String
    ) -> some View {
        PDSPickerRow(label) {
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { value in Text(title(value)).tag(value) }
            }
            .pdsSegmented()
            .fixedSize()
        }
    }
}

struct MenuBarMeterGlyph: View {
    let meter: MenuBarMeter
    let tuning: MenuBarMeterTuning
    static let defaultSize: CGFloat = 21
    var size: CGFloat = Self.defaultSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let renderer = MenuBarGaugeRenderer(palette: MenuBarPalette(isDarkMenuBar: scheme == .dark, increasedContrast: contrast == .increased), tuning: glyphTuning,
                                           heightLimit: 26)
        let ring = MenuBarRingLayout(requestedDiameter: size - PDS.Space.xs, heightLimit: size,
                                     ringWidth: tuning.ringLineWidth, showsTick: tuning.showPaceTick,
                                     labelWidth: 0, labelHeight: 0, logoScale: tuning.markScale, hasVisibleLabels: false)
        Canvas { canvas, _ in
            canvas.withCGContext { context in
                context.translateBy(x: (size - ring.artworkWidth) / 2, y: (size + ring.height) / 2)
                context.scaleBy(x: 1, y: -1)
                renderer.drawExample(meter: meter, geometry: ring, context: context)
            }
        }
        .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var glyphTuning: MenuBarMeterTuning {
        var result = tuning
        result.showNumber = false
        result.iconSize = .base
        return result
    }
}

/// Drawing and annotation coordinates are points in the same top-leading diagram.
@MainActor
struct MeterLegendLayout {
    let numberFont: NSFont
    let ring: MenuBarRingLayout
    let gauge: CGRect
    let number: CGRect
    let fill: Double
    let expected: Double
    let badgeSize = PDS.Space.l

    init(renderer: MenuBarGaugeRenderer, meter: MenuBarMeter) {
        let tuning = renderer.tuning
        fill = meter.fill ?? 0
        expected = meter.expectedFill ?? 0
        ring = MenuBarRingLayout(requestedDiameter: 2 * PDS.Metrics.row, heightLimit: 4 * PDS.Space.xl,
                                 ringWidth: tuning.ringLineWidth, showsTick: true, labelWidth: 0,
                                 labelHeight: 0, logoScale: tuning.markScale, hasVisibleLabels: false)
        gauge = CGRect(x: PDS.Space.s, y: 2 * badgeSize, width: ring.artworkWidth, height: ring.height)
        numberFont = renderer.badgeFont(size: ring.besideFontSize, weight: .semibold)
        let numberSize = (meter.summary.text as NSString).size(withAttributes: [.font: numberFont])
        number = CGRect(x: gauge.maxX + PDS.Space.s, y: gauge.maxY - ring.center - numberSize.height / 2,
                        width: numberSize.width, height: numberSize.height)
    }

    private func outerPoint(_ fraction: Double, overhang: Double = 0) -> CGPoint {
        let angle = ring.angle(at: fraction)
        let radius = ring.diameter / 2 + overhang
        return CGPoint(x: gauge.midX + radius * sin(angle), y: gauge.maxY - ring.center - radius * cos(angle))
    }

    var anchors: [CGPoint] {
        [outerPoint(fill / 2), outerPoint(expected, overhang: ring.tickOverhang),
         CGPoint(x: number.midX, y: number.maxY)]
    }

    var badges: [CGRect] {
        let centers = [CGPoint(x: gauge.minX, y: gauge.minY - badgeSize),
                       CGPoint(x: anchors[1].x, y: gauge.minY - badgeSize),
                       CGPoint(x: number.midX, y: number.maxY + badgeSize)]
        return centers.map { CGRect(x: $0.x - badgeSize / 2, y: $0.y - badgeSize / 2,
                                    width: badgeSize, height: badgeSize) }
    }
}

struct MenuBarMeterLegend: View {
    let tuning: MenuBarMeterTuning
    let date: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let legend = [
        "Arc: how much quota is left, colored by your pace.",
        "Tick: where you’d be if you used it evenly until the reset.",
        "Number: the same amount as a percentage (optional)."
    ]

    private func badge(_ number: Int) -> some View {
        Text(String(number)).font(PDS.Typography.caps)
            .frame(width: PDS.Space.l, height: PDS.Space.l)
            .background(.regularMaterial, in: Circle())
    }

    private var example: some View {
        var style = tuning
        style.showNumber = false
        style.showPaceTick = true
        let renderer = MenuBarGaugeRenderer(palette: .init(isDarkMenuBar: scheme == .dark, increasedContrast: contrast == .increased), tuning: style)
        let pace = MenuBarPace(usedFraction: 0.45, duration: 100, reset: date.addingTimeInterval(55), now: date)
        let meter = MenuBarMeter(summary: .init(text: "55%", providerID: .claude, detail: nil, isNeutral: false),
                                 fill: pace?.remaining, isLiveReading: true, pace: pace)
        let layout = MeterLegendLayout(renderer: renderer, meter: meter)
        return ZStack(alignment: .topLeading) {
            Canvas { canvas, _ in
                canvas.withCGContext { context in
                    context.saveGState()
                    context.translateBy(x: layout.gauge.minX, y: layout.gauge.maxY)
                    context.scaleBy(x: 1, y: -1)
                    renderer.drawExample(meter: meter, geometry: layout.ring, context: context)
                    context.restoreGState()
                }
                for (rect, anchor) in zip(layout.badges, layout.anchors) {
                    let dx = anchor.x - rect.midX, dy = anchor.y - rect.midY
                    let ratio = rect.width / (2 * hypot(dx, dy))
                    var leader = Path()
                    leader.move(to: CGPoint(x: rect.midX + dx * ratio, y: rect.midY + dy * ratio))
                    leader.addLine(to: anchor)
                    canvas.stroke(leader, with: .color(PDS.Ink.inkTertiary), lineWidth: 1)
                }
            }
            Text(meter.summary.text).font(Font(layout.numberFont))
                .frame(width: layout.number.width, alignment: .trailing)
                .position(x: layout.number.midX, y: layout.number.midY)
            ForEach(Array(layout.badges.enumerated()), id: \.offset) { index, rect in
                badge(index + 1).position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: layout.number.maxX, height: max(layout.gauge.maxY, layout.badges[2].maxY))
        .accessibilityHidden(true)
    }

    var body: some View {
        SettingsLedgerTile("Reading a meter") {
            HStack(spacing: PDS.Space.l) {
                example
                VStack(alignment: .leading, spacing: PDS.Space.s) {
                    ForEach(legend.indices, id: \.self) { index in
                        HStack(alignment: .center, spacing: PDS.Space.s) {
                            badge(index + 1)
                            PDSHelpText(legend[index])
                        }
                    }
                }
            }
            VStack(spacing: PDS.Space.s) {
                paceStates
                HStack(alignment: .top, spacing: LedgerMetrics.rowGap) {
                    sample("Last reading", "Prior reading.", used: 0.35, live: false)
                    sample("Waiting", "No reading yet.", used: nil, live: false)
                }
            }
            .padding(.bottom, PDS.Space.xs)
        }
    }

    private var paceStates: some View {
        let samples: [(tier: MenuBarPace.Tier, meaning: String, used: Double)] = [
            (.onPace, "Within 5 points of even use.", 0.50),
            (.offPace(.fast), "5–15 points faster than even use.", 0.60),
            (.offPace(.slow), "5–15 points slower than even use.", 0.40),
            (.farOffPace(.fast), "Over 15 points faster than even use.", 0.75),
            (.farOffPace(.slow), "Over 15 points slower than even use.", 0.25),
        ]
        return Grid(horizontalSpacing: LedgerMetrics.rowGap, verticalSpacing: PDS.Space.xs) {
            GridRow {
                ForEach(samples.indices, id: \.self) { index in
                    glyph(used: samples[index].used, live: true, size: 36)
                        .padding(.vertical, PDS.Space.xs)
                }
            }
            GridRow(alignment: .firstTextBaseline) {
                ForEach(samples.indices, id: \.self) { index in
                    Text(samples[index].tier.label)
                        .font(SettingsType.help.bold())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            GridRow(alignment: .firstTextBaseline) {
                ForEach(samples.indices, id: \.self) { index in
                    PDSHelpText(samples[index].meaning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    private func sample(_ label: String, _ meaning: String, used: Double?, live: Bool = true) -> some View {
        VStack(spacing: PDS.Space.xs) {
            glyph(used: used, live: live, size: 36)
                .padding(.vertical, PDS.Space.xs)
            Text(label).font(SettingsType.help.bold()).fixedSize(horizontal: false, vertical: true)
            PDSHelpText(meaning).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func glyph(used: Double?, live: Bool, size: CGFloat) -> some View {
        let pace = used.flatMap { MenuBarPace(usedFraction: $0, duration: 3600, reset: date.addingTimeInterval(1800), now: date) }
        let summary = MenuBarSummary(text: "", providerID: .claude, detail: nil, isNeutral: used == nil)
        let meter = MenuBarMeter(summary: summary, fill: pace?.remaining, awaitingFirstReading: used == nil,
                                 isLiveReading: live, pace: live ? pace : nil)
        var sampleTuning = tuning
        sampleTuning.showPaceTick = true
        return MenuBarMeterGlyph(meter: meter, tuning: sampleTuning, size: size)
    }
}
