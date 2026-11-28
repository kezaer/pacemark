import Testing
@testable import PacemarkCore

/// L1A: the menu bar label follows the menu bar's own appearance. Both branches are pinned
/// here because the light one cannot be seen in a unit test *or* in a screenshot taken on a
/// dark-wallpaper machine — it is only ever exercised by a light menu bar.
struct MenuBarPaletteTests {
    @Test func darkMenuBarInkIsOpaqueWhite() {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        #expect(palette.ink.color == .white)
        #expect(palette.ink.opacity == 1.0)
    }

    @Test func lightMenuBarInkIsBlackAt85Percent() {
        let palette = MenuBarPalette(isDarkMenuBar: false)
        #expect(palette.ink.color == .black)
        #expect(palette.ink.opacity == 0.85)
    }

    /// Neutral liquid is defined as the ink at 0.62 — not an independent constant — so the
    /// two can never drift apart.
    @Test func neutralLiquidIsInkAt62Percent() {
        for isDark in [true, false] {
            let palette = MenuBarPalette(isDarkMenuBar: isDark)
            #expect(palette.neutralLiquid.color == palette.ink.color)
            #expect(abs(palette.neutralLiquid.opacity - palette.ink.opacity * 0.62) < 0.0001)
        }
        // The values the design doc's strips use: white @ .62 on dark, black @ .53 on light.
        #expect(abs(MenuBarPalette(isDarkMenuBar: true).neutralLiquid.opacity - 0.62) < 0.0001)
        #expect(abs(MenuBarPalette(isDarkMenuBar: false).neutralLiquid.opacity - 0.53) < 0.005)
    }

    @Test func liquidUsesTheSeverityFillTierForEachAppearance() {
        for isDark in [true, false] {
            let palette = MenuBarPalette(isDarkMenuBar: isDark)
            for severity in [UsageSeverity.healthy, .low, .critical] {
                #expect(
                    palette.liquid(for: severity)
                        == PacemarkSeverityColorValues.fill(for: severity, dark: isDark, increasedContrast: false)
                )
            }
        }
    }

    @Test func lightIncreaseContrastDarkensHealthyAndLowFills() {
        let standard = MenuBarPalette(isDarkMenuBar: false)
        let increased = MenuBarPalette(isDarkMenuBar: false, increasedContrast: true)
        for severity in [UsageSeverity.healthy, .low] {
            #expect(increased.liquid(for: severity)
                == PacemarkSeverityColorValues.fill(for: severity, dark: false, increasedContrast: true))
            #expect(standard.liquid(for: severity) != increased.liquid(for: severity))
        }
        #expect(standard.liquid(for: .critical) == increased.liquid(for: .critical))
    }

    @Test func darkLiquidAppliesIncreaseContrastToCriticalOnly() {
        let standard = MenuBarPalette(isDarkMenuBar: true)
        let increased = MenuBarPalette(isDarkMenuBar: true, increasedContrast: true)
        for severity in [UsageSeverity.healthy, .low] {
            #expect(standard.liquid(for: severity) == increased.liquid(for: severity))
        }
        #expect(standard.liquid(for: .critical) == PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: false))
        #expect(increased.liquid(for: .critical) == PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: true))
        #expect(standard.severityInk(for: .critical) == increased.severityInk(for: .critical))
    }

    /// Severity *ink* is the text tier. On a dark menu bar it parts from the fill tier only at
    /// critical (the fill red fails at numeral size); on a light menu bar every fill is the
    /// vivid tier while ink keeps the darker text-safe values, so they part everywhere.
    @Test func severityInkUsesTheTextTierAndPartsFromTheFill() {
        for isDark in [true, false] {
            let palette = MenuBarPalette(isDarkMenuBar: isDark)
            #expect(palette.severityInk(for: .critical) == PacemarkSeverityColorValues.criticalText(dark: isDark))
            #expect(palette.severityInk(for: .critical) != palette.liquid(for: .critical))
            #expect(palette.severityInk(for: .low) == PacemarkSeverityColorValues.color(for: UsageSeverity.low, dark: isDark))
            #expect(palette.severityInk(for: .healthy) == PacemarkSeverityColorValues.color(for: UsageSeverity.healthy, dark: isDark))
        }
        let dark = MenuBarPalette(isDarkMenuBar: true)
        #expect(dark.severityInk(for: .low) == dark.liquid(for: .low))
        let light = MenuBarPalette(isDarkMenuBar: false)
        #expect(light.severityInk(for: .low) != light.liquid(for: .low))
    }

    /// Nothing in the light branch may equal the dark branch, or the light menu bar would
    /// still be painting white-on-white.
    @Test func lightAndDarkNeverResolveToTheSameInk() {
        let dark = MenuBarPalette(isDarkMenuBar: true)
        let light = MenuBarPalette(isDarkMenuBar: false)
        #expect(dark.ink != light.ink)
        for severity in [UsageSeverity.healthy, .low, .critical] {
            #expect(dark.liquid(for: severity) != light.liquid(for: severity))
            #expect(dark.severityInk(for: severity) != light.severityInk(for: severity))
        }
    }
}
