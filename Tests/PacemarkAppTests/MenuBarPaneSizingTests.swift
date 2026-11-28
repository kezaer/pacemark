import AppKit
import SwiftUI
import Testing
import PacemarkCore
@testable import Pacemark

/// AppKit pins the Settings detail column's minimum height to the pane's size at a
/// zero-width proposal. The Menu Bar pane's pinned preview tile sits outside a scroll view,
/// so its text wrapped a word per line there and demanded ~1,000pt: the split view outgrew
/// the window, which centred it and clipped both columns' tops under the title bar.
@MainActor
@Suite(.sharedAppState)
struct MenuBarPaneSizingTests {
    @Test func preferredIconSizeReturnsWhenTheMenuBarGrows() {
        var tuning = MenuBarMeterTuning.defaults
        tuning.iconSize = .plus30
        var renderer = MenuBarGaugeRenderer(palette: .init(isDarkMenuBar: true), tuning: tuning, heightLimit: 22)
        let fitting = MenuBarMeterTuning.IconSize.allCases.filter(renderer.supports)
        #expect(renderer.effectiveIconSize == fitting.last)
        #expect(!fitting.contains(.plus30))
        renderer.heightLimit = 39
        #expect(renderer.effectiveIconSize == .plus30)
    }

    @Test func captionWidthIncludesHalfAMeterGapAtEachEnd() {
        let meter = MenuBarMeter(summary: .init(text: "75%", providerID: .claude, detail: nil, isNeutral: false), fill: 0.75)
        let renderer = MenuBarGaugeRenderer(palette: .init(isDarkMenuBar: false), tuning: .defaults, heightLimit: 39)
        for count in 1...3 {
            let meters = Array(repeating: meter, count: count)
            let gauge = renderer.uniformRingLayout(meters: meters).geometry.artworkWidth
            let expectedWidth = ceil(CGFloat(count) * (gauge + MenuBarGaugeRenderer.meterGap))
            let width = renderer.image(meters: meters).size.width
            #expect(abs(width - expectedWidth) < 0.001)
        }
    }

    @Test func cardHeaderCentresTallControls() throws {
        var controlFrame: CGRect?
        var bodyTop: CGFloat?
        let card = PDSCard("Provider", accessory: {
            Toggle("Track", isOn: .constant(true)).toggleStyle(.switch)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("card")) } action: { controlFrame = $0 }
        }) {
            Text("Account")
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("card")).minY } action: { bodyTop = $0 }
        }
        .coordinateSpace(name: "card")
        .frame(width: 300)
        let host = NSHostingView(rootView: card)
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let frame = try #require(controlFrame)
        #expect(frame.height > 0)
        let headerBottom = try #require(bodyTop) - PDS.Space.s
        #expect(frame.minY >= PDS.Space.s)
        #expect(abs(frame.minY - (headerBottom - frame.maxY)) <= 0.5)
    }

    @Test func emptyLabelPromptsForExplicitText() {
        #expect(MenuBarMeterLabelField.placeholder == "Add label")
    }

    @Test(arguments: MenuBarMeterTuning.TextSize.allCases, MenuBarMeterTuning.IconSize.allCases)
    func legendBadgesClearTheArtworkAndEachOther(textSize: MenuBarMeterTuning.TextSize, iconSize: MenuBarMeterTuning.IconSize) {
        var tuning = MenuBarMeterTuning.defaults
        tuning.textSize = textSize
        tuning.iconSize = iconSize
        let renderer = MenuBarGaugeRenderer(palette: MenuBarPalette(isDarkMenuBar: true), tuning: tuning)
        let date = Date()
        let pace = MenuBarPace(usedFraction: 0.45, duration: 100, reset: date.addingTimeInterval(55), now: date)
        let meter = MenuBarMeter(summary: .init(text: "55%", providerID: .claude, detail: nil, isNeutral: false),
                                 fill: 0.55, isLiveReading: true, pace: pace)
        let layout = MeterLegendLayout(renderer: renderer, meter: meter)
        #expect(abs(layout.numberFont.pointSize / layout.ring.diameter - 0.50) < 0.0001)
        for (index, rect) in layout.badges.enumerated() {
            #expect(!rect.intersects(layout.gauge))
            #expect(!rect.intersects(layout.number))
            #expect(layout.badges.dropFirst(index + 1).allSatisfy { !rect.intersects($0) })
        }
    }

    @Test func fivePaceSamplesAndTwoReadingStatesFitTheLegendCard() {
        let legend = MenuBarMeterLegend(tuning: .defaults, date: Date()).frame(width: 488)
        let host = NSHostingController(rootView: legend)
        let size = host.sizeThatFits(in: CGSize(width: 488, height: 700))
        #expect(size.width == 488)
        #expect(size.height > 2 * PDS.Metrics.row)
        #expect(size.height < SettingsView.minimumWindowHeight - 2 * PDS.Space.xl)
    }

    @Test func numberAndLabelBandUseTheRenderedMeters() {
        var tuning = MenuBarMeterTuning.defaults
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let meter = MenuBarMeter(summary: .init(text: "75%", providerID: .claude, detail: nil, isNeutral: false), fill: 0.75)
        let labeled = MenuBarMeter(summary: meter.summary, fill: meter.fill, badge: "Work")
        let plain = MenuBarGaugeRenderer(palette: palette, tuning: tuning)
        let geometry = plain.uniformRingLayout(meters: [meter]).geometry
        #expect(!geometry.showsLabelBand)
        #expect(geometry.center < geometry.height / 2)
        #expect(plain.uniformRingLayout(meters: [meter, labeled]).geometry.showsLabelBand)
        tuning.showNumber = true
        let numbered = MenuBarGaugeRenderer(palette: palette, tuning: tuning)
        #expect(numbered.image(meters: [meter]).size.width > plain.image(meters: [meter]).size.width)
    }

    @Test(arguments: [22.0, 39.0])
    func longLabelOnlyWidensItsOwnMeterWithBeside(limit: Double) {
        var tuning = MenuBarMeterTuning.defaults
        tuning.iconSize = .base
        tuning.showNumber = true
        let renderer = MenuBarGaugeRenderer(palette: .init(isDarkMenuBar: true), tuning: tuning, heightLimit: limit)
        let plain = MenuBarMeter(summary: .init(text: "75%", providerID: .claude, detail: nil, isNeutral: false), fill: 0.75)
        let labeled = MenuBarMeter(summary: plain.summary, fill: plain.fill, badge: "WWWWWWWW")
        let mixed = renderer.uniformRingLayout(meters: [plain, labeled]).geometry
        #expect(mixed.diameter <= renderer.uniformRingLayout(meters: [plain]).geometry.diameter)
        let pair = renderer.image(meters: [labeled, plain]).size.width
        let triple = renderer.image(meters: [labeled, plain, plain]).size.width
        let shortLabel = MenuBarMeter(summary: plain.summary, fill: plain.fill, badge: "W")
        let shortPair = renderer.image(meters: [shortLabel, plain]).size.width
        #expect(abs((triple - pair) - (shortPair - renderer.image(meters: [shortLabel]).size.width)) <= 1)
    }

    @Test func theMenuBarPaneDemandsNoMinimumHeight() {
        let defaults = DemoMemoryDefaults()

        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: defaults)
        )
        let controller = NSHostingController(rootView: MenuBarSettingsPane(store: store).defaultAppStorage(defaults))
        let minimum = controller.sizeThatFits(in: .zero)
        // The scaffold panes report 0 here; the regression reported ~1,000.
        #expect(minimum.height < SettingsView.minimumWindowHeight / 2)
    }
}
