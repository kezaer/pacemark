import Foundation
import Testing
@testable import PacemarkCore

struct BrandColorValuesTests {
    @Test func criticalUsageInkClearsSmallTextOnLedgerCardsAndMenuPlates() {
        // Samples beside the Lab reading and beside the status artwork in the pace-states fixture.
        let references: [(Bool, PacemarkRGBColor, PacemarkRGBColor)] = [
            (false, rgb(234, 234, 234), rgb(232, 232, 232)),
            (true, rgb(53, 53, 53), rgb(33, 33, 33))
        ]
        for (dark, card, plate) in references {
            let ink = PacemarkSeverityColorValues.criticalText(dark: dark)
            #expect(contrastRatio(ink, card) >= 4.5)
            #expect(contrastRatio(ink, plate) >= 4.5)
            for increasedContrast in [false, true] {
                let fill = PacemarkSeverityColorValues.criticalFill(dark: dark, increasedContrast: increasedContrast)
                #expect(contrastRatio(fill, plate) >= 3)
                if !dark { #expect(contrastRatio(fill, card) >= 3) }
            }
        }
        // The brighter default Ledger card used when approving the revised ink.
        #expect(contrastRatio(PacemarkSeverityColorValues.criticalText(dark: true), rgb(55, 56, 59)) >= 4.5)
        let lightFill = PacemarkSeverityColorValues.criticalFill(dark: false, increasedContrast: false)
        #expect(contrastRatio(lightFill, rgb(203, 203, 203)) >= 3)
    }

    @Test func standardDarkCriticalFillHasAnAcceptedLedgerTrackAndCardException() {
        let fill = PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: false)
        // Samples beside the Lab reading on the pinned dark fixture.
        #expect(abs(contrastRatio(fill, rgb(85, 85, 85)) - 1.6001) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(53, 53, 53)) - 2.6326) < 0.0001)
        // The original single-account fixture has a slightly brighter substrate.
        #expect(abs(contrastRatio(fill, rgb(87, 88, 91)) - 1.5267) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(55, 56, 59)) - 2.5162) < 0.0001)
    }

    @Test func increasedContrastDarkCriticalFillHasAnAcceptedLedgerTrackAndCardException() {
        let fill = PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: true)
        // Live Increase Contrast capture of the neutral Ledger track and card.
        #expect(abs(contrastRatio(fill, rgb(74, 74, 74)) - 2.2897) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(40, 40, 40)) - 3.8090) < 0.0001)
        // Use the same neutral track and card samples as the standard dark fill.
        #expect(abs(contrastRatio(fill, rgb(85, 85, 85)) - 1.9261) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(53, 53, 53)) - 3.1690) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(87, 88, 91)) - 1.8378) < 0.0001)
        #expect(abs(contrastRatio(fill, rgb(55, 56, 59)) - 3.0289) < 0.0001)
    }

    @Test func statusCriticalInkRetainsItsIndependentPalette() {
        for dark in [false, true] {
            let status = PacemarkSeverityColorValues.statusCriticalText(dark: dark)
            #expect(hex(status) == (dark ? "#FF6659" : "#D1241C"))
            #expect(status != PacemarkSeverityColorValues.criticalText(dark: dark))
        }
    }

    /// R2C18: the Claude accent *is* the mark's own fill. It used to be a hand-authored
    /// `#D97842` at H 47.8° beside a `#D97757` SVG at H 38.8° — the same card carrying two
    /// oranges nine degrees apart. Codex is unchanged in appearance; it is simply re-authored
    /// on its own measured hue so the whole family has one construction.
    @Test func providerAccentsMatchCanonicalSpec() {
        let claude = PacemarkOKLCH(PacemarkBrandColorValues.claude)
        #expect(abs(claude.lightness - 0.672) < 0.002)
        #expect(abs(claude.chroma - 0.131) < 0.002)
        #expect(abs(claude.hue - PacemarkBrandColorValues.claudeHue) < 0.5)
        // The SVG's fill, to the byte.
        #expect(hex(PacemarkBrandColorValues.claude) == "#D97757")

        let codex = PacemarkOKLCH(PacemarkBrandColorValues.codex)
        #expect(abs(codex.lightness - 0.555) < 0.002)
        #expect(abs(codex.hue - PacemarkBrandColorValues.codexHue) < 0.5)
        #expect(distance(PacemarkBrandColorValues.codex, PacemarkRGBColor(red: 0.28, green: 0.34, blue: 1.00)) < 0.01)

        #expect(PacemarkBrandColorValues.grok == PacemarkRGBColor(red: 0.36, green: 0.40, blue: 0.46))
        #expect(PacemarkBrandColorValues.cursor == PacemarkRGBColor(red: 0.33, green: 0.34, blue: 0.38))
        #expect(PacemarkBrandColorValues.copilot == PacemarkRGBColor(red: 0.34, green: 0.37, blue: 0.43))
        #expect(PacemarkBrandColorValues.opencode == PacemarkRGBColor(red: 0.35, green: 0.34, blue: 0.34))
        #expect(PacemarkBrandColorValues.antigravity == PacemarkRGBColor(red: 0.36, green: 0.36, blue: 0.38))
    }

    /// R2C18: every Claude/Codex brand value is a stop on one constant-hue ramp — accent,
    /// title accent, and both CTA gradient ends. A new literal at a different hue fails here.
    @Test func everyBrandRampStopHoldsItsFamilyHue() {
        var claudeStops: [(String, PacemarkRGBColor)] = [("accent", PacemarkBrandColorValues.claude)]
        var codexStops: [(String, PacemarkRGBColor)] = [("accent", PacemarkBrandColorValues.codex)]
        for dark in [true, false] {
            claudeStops += [
                ("textAccent dark=\(dark)", PacemarkBrandRamp.claudeTextAccent(dark: dark)),
                ("ctaTop dark=\(dark)", PacemarkBrandRamp.claudeCTATop(dark: dark)),
                ("ctaBottom dark=\(dark)", PacemarkBrandRamp.claudeCTABottom(dark: dark)),
            ]
            codexStops += [
                ("ctaTop dark=\(dark)", PacemarkBrandRamp.codexCTATop(dark: dark)),
                ("ctaBottom dark=\(dark)", PacemarkBrandRamp.codexCTABottom(dark: dark)),
            ]
        }
        for (name, stop) in claudeStops {
            let hue = PacemarkOKLCH(stop).hue
            #expect(abs(hue - PacemarkBrandColorValues.claudeHue) < 2, "claude \(name) at H \(hue)")
        }
        for (name, stop) in codexStops {
            let hue = PacemarkOKLCH(stop).hue
            #expect(abs(hue - PacemarkBrandColorValues.codexHue) < 2, "codex \(name) at H \(hue)")
        }
        for dark in [true, false] {
            #expect(PacemarkColorValues.textAccent(for: ProviderID.claude.raw, dark: dark)
                == PacemarkBrandRamp.claudeTextAccent(dark: dark))
            #expect(PacemarkColorValues.textAccent(for: ProviderID.codex.raw, dark: dark)
                == PacemarkBrandRamp.codexTextAccent(dark: dark))
        }
        // The CTA is a gradient, so its bottom stop is the darker one in both schemes.
        for dark in [true, false] {
            #expect(PacemarkOKLCH(PacemarkBrandRamp.claudeCTABottom(dark: dark)).lightness
                < PacemarkOKLCH(PacemarkBrandRamp.claudeCTATop(dark: dark)).lightness)
            #expect(PacemarkOKLCH(PacemarkBrandRamp.codexCTABottom(dark: dark)).lightness
                < PacemarkOKLCH(PacemarkBrandRamp.codexCTATop(dark: dark)).lightness)
        }
    }

    /// R2C18: the CTA carries a white 13pt label. The dark tops used to measure 4.05:1
    /// (Claude) and 3.97:1 (Codex) against it while the comment beside them claimed the ramp
    /// "averages ≈4.5:1" — so the *top* stop, the lightest thing under the label, is what has
    /// to clear AA, not an average of the button face.
    @Test func whiteOnEveryCTATopClearsSmallTextContrast() {
        for dark in [true, false] {
            for (name, top) in [
                ("claude", PacemarkBrandRamp.claudeCTATop(dark: dark)),
                ("codex", PacemarkBrandRamp.codexCTATop(dark: dark)),
            ] {
                let measured = contrastRatio(.white, top)
                #expect(measured >= 4.5, "\(name) CTA top, dark=\(dark): \(measured):1")
                // The bottom stop is darker, so the whole face clears it too.
                let bottom = name == "claude"
                    ? PacemarkBrandRamp.claudeCTABottom(dark: dark)
                    : PacemarkBrandRamp.codexCTABottom(dark: dark)
                #expect(contrastRatio(.white, bottom) >= 4.5, "\(name) CTA bottom, dark=\(dark)")
            }
        }
    }

    /// R2C18: "Connected" used to be a hand-written green sitting beside a chip fill derived
    /// from `healthy` — one chip, two greens. The ink is now the same token stepped in
    /// lightness only, and it still has to pass AA as text on that chip.
    @Test func connectedInkIsALightnessOffsetFromHealthyAndStillPassesOnItsChip() {
        for dark in [true, false] {
            let green = PacemarkOKLCH(PacemarkSeverityColorValues.healthy(dark: dark))
            let ink = PacemarkOKLCH(PacemarkBrandRamp.connectedInk(dark: dark))
            #expect(abs(ink.hue - green.hue) < 2, "dark=\(dark) hue")
            #expect(abs(ink.chroma - green.chroma) < 0.02, "dark=\(dark) chroma")
            #expect(
                abs(ink.lightness - green.lightness
                    - PacemarkBrandRamp.connectedInkLightnessOffset(dark: dark)) < 0.01,
                "dark=\(dark) lightness offset"
            )
            // Dark steps away from its dark surface by getting brighter, light by getting darker.
            #expect((ink.lightness > green.lightness) == dark, "dark=\(dark) offset direction")

            let chip = composite(
                PacemarkTint(color: PacemarkSeverityColorValues.healthy(dark: dark), opacity: 0.12),
                over: raisedTileFillColors(dark: dark)[0]
            )
            let measured = contrastRatio(PacemarkBrandRamp.connectedInk(dark: dark), chip)
            #expect(measured >= 4.5, "connected ink on its chip, dark=\(dark): \(measured):1")
        }
    }

    @Test func monochromeBrandMarksShipAtTheCappedInkValue() throws {
        #expect(hex(PacemarkBrandColorValues.monochromeMarkInk(dark: true)) == "#C9CDD4")
        #expect(hex(PacemarkBrandColorValues.monochromeMarkInk(dark: false)) == "#3A3D42")
        #expect(PacemarkBrandColorValues.monochromeMarkInkHex(dark: true)
            == hex(PacemarkBrandColorValues.monochromeMarkInk(dark: true)))
        #expect(PacemarkBrandColorValues.monochromeMarkInkHex(dark: false)
            == hex(PacemarkBrandColorValues.monochromeMarkInk(dark: false)))

        // The dark mark is dimmer than the numeral it used to match; the light mark is
        // lighter than the near-black it used to be. Both move *toward* their surface.
        #expect(PacemarkOKLCH(PacemarkBrandColorValues.monochromeMarkInk(dark: true)).lightness
            < PacemarkOKLCH(PacemarkRGBColor(red: 0.92, green: 0.92, blue: 0.96)).lightness)
        #expect(PacemarkOKLCH(PacemarkBrandColorValues.monochromeMarkInk(dark: false)).lightness
            > PacemarkOKLCH(PacemarkRGBColor(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0F / 255)).lightness)

        for (path, dark) in monochromeMarkFiles {
            let svg = try String(contentsOf: path, encoding: .utf8)
            let expected = "fill=\"\(PacemarkBrandColorValues.monochromeMarkInkHex(dark: dark))\""
            #expect(svg.contains(expected), "\(path.lastPathComponent) does not carry \(expected)")
        }
    }

    @Test func theCriticalTrackKeepsItsHueAndItsSeparationFromTheFill() {
        for dark in [true, false] {
            let track = PacemarkMeterColorValues.criticalBarTrack(dark: dark)
            for increasedContrast in [false, true] {
                let fill = PacemarkSeverityColorValues.criticalFill(dark: dark, increasedContrast: increasedContrast)
                #expect(abs(PacemarkOKLCH(track).hue - PacemarkOKLCH(fill).hue) < 2)
                let ratio = contrastRatio(fill, track)
                #expect(ratio >= (dark ? 2 : 3), "Critical fill vs tinted track: \(ratio)")
            }
            for card in raisedTileFillColors(dark: dark) {
                let neutral = composite(PacemarkColorValues.barTrack(dark: dark), over: card)
                let shift = abs(abs(apcaLc(text: track, background: card))
                    - abs(apcaLc(text: neutral, background: card)))
                #expect(shift < 12, "dark=\(dark) tinted track shifts |Lc| by \(shift)")
            }
        }
    }

    /// R2C16: a stale critical is still a critical. The fill keeps its severity's lightness
    /// and hue and drops to 35% chroma instead of collapsing to one flat grey, so a stale 21%
    /// row can no longer read as calmer than the live 38% row above it.
    @Test func staleFillsKeepTheirSeverityHueAtReducedChroma() {
        for dark in [true, false] {
            for increasedContrast in [true, false] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let live = PacemarkOKLCH(PacemarkSeverityColorValues.fill(
                        for: severity, dark: dark, increasedContrast: increasedContrast
                    ))
                    let stale = PacemarkOKLCH(PacemarkMeterColorValues.staleFill(
                        for: severity, dark: dark, increasedContrast: increasedContrast
                    ))
                    let label = "\(severity) dark=\(dark) ic=\(increasedContrast)"
                    #expect(abs(stale.hue - live.hue) < 2, "\(label) hue")
                    #expect(abs(stale.lightness - live.lightness) < 0.01, "\(label) lightness")
                    #expect(
                        abs(stale.chroma - live.chroma * PacemarkMeterColorValues.staleFillChromaScale) < 0.005,
                        "\(label) chroma"
                    )
                    // Hedged, not erased, and not still shouting.
                    #expect(stale.chroma > 0.02, "\(label) still carries hue")
                    #expect(stale.chroma < live.chroma, "\(label) is quieter than live")
                }
                // The severity order survives the hedge, which is the whole point.
                let chromas = [UsageSeverity.healthy, .low, .critical].map {
                    PacemarkOKLCH(PacemarkMeterColorValues.staleFill(
                        for: $0, dark: dark, increasedContrast: increasedContrast
                    )).chroma
                }
                #expect(chromas.allSatisfy { $0 > 0 })
            }
        }
    }

    @Test func newProviderTextAccentsMatchCanonicalSpec() {
        #expect(PacemarkColorValues.textAccent(for: ProviderID.grok.raw, dark: false) == PacemarkRGBColor(red: 0.20, green: 0.22, blue: 0.25))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.grok.raw, dark: true) == PacemarkRGBColor(red: 0.78, green: 0.80, blue: 0.84))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.cursor.raw, dark: false) == PacemarkRGBColor(red: 0.17, green: 0.17, blue: 0.18))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.cursor.raw, dark: true) == PacemarkRGBColor(red: 0.81, green: 0.81, blue: 0.83))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.copilot.raw, dark: false) == PacemarkRGBColor(red: 0.18, green: 0.20, blue: 0.24))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.copilot.raw, dark: true) == PacemarkRGBColor(red: 0.79, green: 0.81, blue: 0.86))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.opencode.raw, dark: false) == PacemarkRGBColor(red: 0.18, green: 0.17, blue: 0.17))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.opencode.raw, dark: true) == PacemarkRGBColor(red: 0.82, green: 0.81, blue: 0.81))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.antigravity.raw, dark: false) == PacemarkRGBColor(red: 0.18, green: 0.18, blue: 0.20))
        #expect(PacemarkColorValues.textAccent(for: ProviderID.antigravity.raw, dark: true) == PacemarkRGBColor(red: 0.81, green: 0.82, blue: 0.84))
    }

    @Test func antigravityTextAccentClearsSmallTextContrastOnEverySurface() throws {
        for dark in [true, false] {
            let accent = try #require(PacemarkColorValues.textAccent(for: ProviderID.antigravity.raw, dark: dark))
            for surface in raisedTileFillColors(dark: dark) + containerBackgroundColors(dark: dark) {
                let measured = contrastRatio(accent, surface)
                #expect(measured >= 4.5, "antigravity accent dark=\(dark): \(measured):1")
            }
        }
    }

    @Test func opencodeTextAccentClearsSmallTextContrastOnEverySurface() throws {
        for dark in [true, false] {
            let accent = try #require(PacemarkColorValues.textAccent(for: ProviderID.opencode.raw, dark: dark))
            for surface in raisedTileFillColors(dark: dark) + containerBackgroundColors(dark: dark) {
                let measured = contrastRatio(accent, surface)
                #expect(measured >= 4.5, "opencode accent dark=\(dark): \(measured):1")
            }
        }
    }

    /// U6 (OpenCode plan): OpenCode's own palette is a warm neutral (its mark's inner block is
    /// `#5A5858`), so its accent stays warm of Cursor's cool neutral and the two read apart.
    @Test func opencodeAccentIsAWarmNeutralDistinctFromCursor() {
        let opencode = PacemarkBrandColorValues.opencode
        #expect(opencode.red >= opencode.blue)
        #expect(opencode != PacemarkBrandColorValues.cursor)
        #expect(PacemarkOKLCH(opencode).chroma < 0.02)
    }

    @Test func copilotTextAccentClearsSmallTextContrastOnEverySurface() throws {
        for dark in [true, false] {
            let accent = try #require(PacemarkColorValues.textAccent(for: ProviderID.copilot.raw, dark: dark))
            for surface in raisedTileFillColors(dark: dark) + containerBackgroundColors(dark: dark) {
                let measured = contrastRatio(accent, surface)
                #expect(measured >= 4.5, "copilot accent dark=\(dark): \(measured):1")
            }
        }
    }

    /// Guards the P1 "grey-identity default arm" class of bug: every registered provider
    /// must resolve a real title accent (both schemes), not fall through to `.secondary`.
    @Test func everyRegisteredProviderHasABrandTextAccent() {
        for id in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode, .antigravity] {
            #expect(PacemarkColorValues.textAccent(for: id.raw, dark: false) != nil, "\(id.raw) light")
            #expect(PacemarkColorValues.textAccent(for: id.raw, dark: true) != nil, "\(id.raw) dark")
        }
    }

    // MARK: - OA2 brand-mark sizing rule

    /// The shared rule is still one number for everyone — the ink's larger dimension is 13/15
    /// of the slot — and `massCorrection` is the only per-provider dial on top of it, so any
    /// provider drifting off `13/15 × its correction` is a deliberate edit that has to land
    /// here first.
    ///
    /// The OpenAI Blossom and Grok’s slash both use a modest size increase to compensate
    /// for their low ink coverage. Cursor’s narrower box also needs a small increase.
    @Test func everyProviderRendersItsInkAtThirteenFifteenthsOfTheSlotTimesItsMassCorrection() {
        #expect(PacemarkBrandMark.inkFraction == 13.0 / 15.0)
        let corrections: [(ProviderID, Double)] = [
            (.claude, 1.00), (.codex, 1.08), (.grok, 1.20), (.cursor, 1.03), (.copilot, 1.00),
            (.opencode, 1.00), (.antigravity, 1.00),
        ]
        for (id, correction) in corrections {
            #expect(PacemarkBrandMark.massCorrection(for: id.raw) == correction, "\(id.raw) mass")
            #expect(
                abs(PacemarkBrandMark.inkScale(for: id.raw) - 13.0 / 15.0 * correction) < 1e-12,
                "\(id.raw) scale"
            )
        }
        #expect(PacemarkBrandMark.massCorrection(for: ProviderID.codex.raw) > 1)
        for id in [ProviderID.claude, .codex, .cursor, .copilot, .opencode, .antigravity] {
            #expect(PacemarkBrandMark.massCorrection(for: ProviderID.grok.raw)
                >= PacemarkBrandMark.massCorrection(for: id.raw))
        }
        // An unregistered provider gets the uncorrected shared rule.
        #expect(PacemarkBrandMark.massCorrection(for: "unknown-provider") == 1.0)
        #expect(PacemarkBrandMark.inkScale(for: "unknown-provider") == 13.0 / 15.0)
    }

    /// The larger dimension lands on the provider's mass-corrected share of 13pt in the card's
    /// 15pt slot, the aspect is preserved rather than padded back to square, and the shorter
    /// dimension is what shrinks (Grok's slash vertically, Cursor's cube horizontally).
    @Test func markSizeFitsTheLargerInkDimensionAndKeepsAspect() {
        for id in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode, .antigravity] {
            let mark = PacemarkBrandMark.markSize(for: id.raw, slot: 15)
            let box = 13 * PacemarkBrandMark.massCorrection(for: id.raw)
            #expect(abs(max(mark.width, mark.height) - box) < 0.0001, "\(id.raw) larger dimension")
            #expect(min(mark.width, mark.height) <= box + 0.0001, "\(id.raw) shorter dimension")
            let aspect = PacemarkBrandMark.inkAspect(for: id.raw)
            #expect(abs(mark.width / mark.height - aspect) < 0.0001, "\(id.raw) aspect")
        }
        // Square marks fill their corrected box in both axes; the two non-square marks do not.
        for id in [ProviderID.claude, .codex] {
            let mark = PacemarkBrandMark.markSize(for: id.raw, slot: 15)
            #expect(abs(mark.height - 13 * PacemarkBrandMark.massCorrection(for: id.raw)) < 0.0001)
            #expect(abs(mark.width - mark.height) < 0.0001)
        }
        #expect(PacemarkBrandMark.markSize(for: ProviderID.grok.raw, slot: 15).height
            < 13 * PacemarkBrandMark.massCorrection(for: ProviderID.grok.raw))
        #expect(PacemarkBrandMark.markSize(for: ProviderID.cursor.raw, slot: 15).width
            < 13 * PacemarkBrandMark.massCorrection(for: ProviderID.cursor.raw))
        // OpenCode's block is a 4:5 portrait: full height, 0.8 of it wide.
        let opencode = PacemarkBrandMark.markSize(for: ProviderID.opencode.raw, slot: 15)
        #expect(abs(opencode.height - 13) < 0.0001)
        #expect(abs(opencode.width - 10.4) < 0.0001)
        let antigravity = PacemarkBrandMark.markSize(for: ProviderID.antigravity.raw, slot: 15)
        #expect(abs(antigravity.width - 13) < 0.0001)
        #expect(abs(antigravity.height - 13 * 22.1087 / 24) < 0.0001)
    }

    @Test func markSizeScalesLinearlyWithTheSlot() {
        let small = PacemarkBrandMark.markSize(for: ProviderID.cursor.raw, slot: 15)
        let large = PacemarkBrandMark.markSize(for: ProviderID.cursor.raw, slot: 30)
        #expect(abs(large.width - small.width * 2) < 0.0001)
        #expect(abs(large.height - small.height * 2) < 0.0001)
    }

    @Test func usageSeverityColorsMatchCanonicalSpec() {
        #expect(PacemarkSeverityColorValues.healthy(dark: true) == PacemarkRGBColor(red: 0.20, green: 0.78, blue: 0.35))
        #expect(PacemarkSeverityColorValues.low(dark: true) == PacemarkRGBColor(red: 1.00, green: 0.62, blue: 0.04))
        #expect(PacemarkSeverityColorValues.healthy(dark: false) == PacemarkRGBColor(red: 0.09, green: 0.52, blue: 0.22))
        #expect(PacemarkSeverityColorValues.low(dark: false) == PacemarkRGBColor(red: 0.70, green: 0.41, blue: 0.00))
        #expect(hex(PacemarkSeverityColorValues.criticalText(dark: true)) == "#FF7F74")
        #expect(hex(PacemarkSeverityColorValues.criticalText(dark: false)) == "#8A1410")
    }

    @Test func usageSeverityLookupReturnsCanonicalValues() {
        for dark in [true, false] {
            #expect(PacemarkSeverityColorValues.color(for: UsageSeverity.healthy, dark: dark) == PacemarkSeverityColorValues.healthy(dark: dark))
            #expect(PacemarkSeverityColorValues.color(for: UsageSeverity.low, dark: dark) == PacemarkSeverityColorValues.low(dark: dark))
            #expect(PacemarkSeverityColorValues.color(for: UsageSeverity.critical, dark: dark) == PacemarkSeverityColorValues.criticalText(dark: dark))
            #expect(PacemarkSeverityColorValues.color(for: UsageSeverity.healthy, dark: dark) == PacemarkSeverityColorValues.healthy(dark: dark))
        }
    }

    @Test func meterTokensMatchTheApprovedSchemeSpecificValues() {
        #expect(PacemarkMeterColorValues.labelInk(dark: true) == PacemarkTint(
            color: PacemarkRGBColor(red: 0.92, green: 0.92, blue: 0.96),
            opacity: 0.90
        ))
        #expect(PacemarkMeterColorValues.labelInk(dark: false) == PacemarkTint(
            color: PacemarkRGBColor(red: 29.0 / 255.0, green: 31.0 / 255.0, blue: 36.0 / 255.0),
            opacity: 0.90
        ))
        // PA13: dark stepped 0.53 → 0.66; ratio-matched pairs left it ~half of light's |Lc|.
        #expect(PacemarkMeterColorValues.countdownInk(dark: true).opacity == 0.66)
        #expect(PacemarkMeterColorValues.countdownInk(dark: false).opacity == 0.72)

        // PA1: light is black-alpha over the card, mirroring dark's white-alpha (it used to be
        // opaque mid-greys, which is what let the neutral fill outshout the amber one).
        #expect(PacemarkMeterColorValues.glassA(dark: true) == PacemarkTint(color: .white, opacity: 0.22))
        #expect(PacemarkMeterColorValues.glassB(dark: true) == PacemarkTint(color: .white, opacity: 0.11))
        #expect(PacemarkMeterColorValues.glassA(dark: false) == PacemarkTint(color: .black, opacity: 0.24))
        #expect(PacemarkMeterColorValues.glassB(dark: false) == PacemarkTint(color: .black, opacity: 0.36))
        #expect(PacemarkMeterColorValues.glassRim(dark: true) == PacemarkTint(color: .white, opacity: 0.25))
        #expect(PacemarkMeterColorValues.glassRim(dark: false) == PacemarkTint(color: .white, opacity: 0.30))

        #expect(PacemarkMeterColorValues.wellBackground(dark: true) == PacemarkRGBColor(
            red: 15.0 / 255.0, green: 17.0 / 255.0, blue: 20.0 / 255.0
        ))
        #expect(PacemarkMeterColorValues.wellBackground(dark: false) == PacemarkRGBColor(
            red: 223.0 / 255.0, green: 226.0 / 255.0, blue: 231.0 / 255.0
        ))
        #expect(PacemarkMeterColorValues.wellShadow(dark: true) == PacemarkTint(color: .black, opacity: 0.65))
        #expect(PacemarkMeterColorValues.wellShadow(dark: false) == PacemarkTint(color: .black, opacity: 0.20))
        // MX4: Full Machined's lit-from-above well.
        #expect(PacemarkMeterColorValues.wellTopShade(dark: true) == PacemarkTint(color: .black, opacity: 0.55))
        #expect(PacemarkMeterColorValues.wellTopShade(dark: false) == PacemarkTint(color: .black, opacity: 0.16))
        #expect(PacemarkMeterColorValues.wellBottomLip(dark: true) == PacemarkTint(color: .white, opacity: 0.06))
        #expect(PacemarkMeterColorValues.wellBottomLip(dark: false) == PacemarkTint(color: .white, opacity: 0.55))
        #expect(PacemarkMeterColorValues.wellHairline(dark: true) == PacemarkTint(color: .black, opacity: 0.35))
        #expect(PacemarkMeterColorValues.wellHairline(dark: false) == PacemarkTint(color: .black, opacity: 0.06))
        // MX3: Full's unlit cells step back from `tickOff`.
        #expect(PacemarkMeterColorValues.fullUnlitCellScale == 0.70)

        #expect(PacemarkMeterColorValues.tickOff(dark: true) == PacemarkTint(color: .white, opacity: 0.09))
        #expect(PacemarkMeterColorValues.tickOff(dark: false) == PacemarkTint(color: .black, opacity: 0.08))
        #expect(PacemarkMeterColorValues.tickGlass(dark: true) == PacemarkTint(color: .white, opacity: 0.16))
        #expect(PacemarkMeterColorValues.tickGlass(dark: false) == PacemarkTint(color: .black, opacity: 0.24))
        #expect(PacemarkMeterColorValues.tickGlassCap(dark: true) == PacemarkTint(color: .white, opacity: 0.265))
        #expect(PacemarkMeterColorValues.tickGlassCap(dark: false) == PacemarkTint(color: .black, opacity: 0.36))

        // R2C16: the stale fill is no longer a flat system grey — it keeps its severity's
        // lightness and hue at 35% chroma (see `staleFillsKeepTheirSeverityHue`).
        #expect(PacemarkMeterColorValues.staleFillChromaScale == 0.35)
        #expect(PacemarkMeterColorValues.quarterMarkOpacity(dark: true) == 0.11)
        #expect(PacemarkMeterColorValues.quarterMarkOpacity(dark: false) == 0.14)

        // FS1: the segmented body dim. It must be a genuine step back from the tip — never
        // 1 (no separation at all) and never 0 (the trail would vanish and the meter would
        // read as a single lit cell). FS2 retuned it 0.72 → 0.70 with the larger Full cell,
        // and kept it a single number shared by both formats on purpose.
        #expect(PacemarkMeterColorValues.segmentBodyAttenuation == 0.70)
        #expect(PacemarkMeterColorValues.segmentBodyAttenuation > 0)
        #expect(PacemarkMeterColorValues.segmentBodyAttenuation < 1)

        // R2C18: the flat-fill dims moved out of `MeterGauge` and in beside it. Same shape as
        // `segmentBodyAttenuation`: a genuine step back in dark, no dim in light, and
        // critical keeps more of itself than the quieter bands.
        #expect(PacemarkMeterColorValues.flatFillAttenuation(for: .critical, dark: true) == 0.95)
        #expect(PacemarkMeterColorValues.flatFillAttenuation(for: .low, dark: true) == 0.85)
        #expect(PacemarkMeterColorValues.flatFillAttenuation(for: .healthy, dark: true) == 0.85)
        for severity in [UsageSeverity.healthy, .low, .critical] {
            #expect(PacemarkMeterColorValues.flatFillAttenuation(for: severity, dark: false) == 1)
            #expect(PacemarkMeterColorValues.flatFillAttenuation(for: severity, dark: true) > 0)
            #expect(PacemarkMeterColorValues.flatFillAttenuation(for: severity, dark: true) < 1)
        }
        #expect(PacemarkMeterColorValues.flatFillAttenuation(for: .critical, dark: true)
            > PacemarkMeterColorValues.flatFillAttenuation(for: .healthy, dark: true))

        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: true, surface: .well) == 0.42)
        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: true, surface: .flat) == 0.58)
        // Light retuned 0.55 → 0.75 with the vivid fill tier (the lighter fills washed the
        // ramp start into the track at 0.55). Increase Contrast reverts fills *and* mix.
        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: false, surface: .well) == 0.75)
        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: false, surface: .flat) == 0.75)
        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: false, surface: .well, increasedContrast: true) == 0.55)
        #expect(PacemarkMeterColorValues.rampStartSeverityMix(dark: true, surface: .flat, increasedContrast: true) == 0.58)
        #expect(PacemarkMeterColorValues.ghostBodyOpacity(for: .healthy, dark: true) == 0.18)
        #expect(PacemarkMeterColorValues.ghostBodyOpacity(for: .critical, dark: true) == 0.22)
        #expect(PacemarkMeterColorValues.ghostBodyOpacity(for: .healthy, dark: false) == 0.30)
        #expect(PacemarkMeterColorValues.ghostBodyOpacity(for: .critical, dark: false) == 0.34)
    }

    @Test func meterTextClearsSmallTextContrastOnRaisedTileFills() {
        for dark in [true, false] {
            for background in raisedTileFillColors(dark: dark) {
                let label = composite(PacemarkMeterColorValues.labelInk(dark: dark), over: background)
                let countdown = composite(PacemarkMeterColorValues.countdownInk(dark: dark), over: background)
                #expect(contrastRatio(label, background) >= 4.5, "label, dark=\(dark)")
                #expect(contrastRatio(countdown, background) >= 4.5, "countdown, dark=\(dark)")
            }
        }
    }

    @Test func severityFillTokensMatchCanonicalSpec() {
        #expect(PacemarkSeverityColorValues.healthyFill(dark: false, increasedContrast: false) == PacemarkRGBColor(red: 0.16, green: 0.66, blue: 0.30))
        #expect(PacemarkSeverityColorValues.lowFill(dark: false, increasedContrast: false) == PacemarkRGBColor(red: 0.856, green: 0.450, blue: 0.000))
        #expect(hex(PacemarkSeverityColorValues.criticalFill(dark: false, increasedContrast: false)) == "#A51C17")
        #expect(hex(PacemarkSeverityColorValues.criticalFill(dark: false, increasedContrast: true)) == "#A51C17")
        #expect(hex(PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: false)) == "#D63A30")
        #expect(hex(PacemarkSeverityColorValues.criticalFill(dark: true, increasedContrast: true)) == "#E8483D")

        let amber = PacemarkOKLCH(PacemarkSeverityColorValues.lowFill(dark: false, increasedContrast: false))
        #expect(abs(amber.lightness - 0.660) < 0.005)
        #expect(abs(amber.chroma - 0.166) < 0.006)
        #expect(abs(amber.hue - 58.3) < 2.5)

        for severity in [UsageSeverity.healthy, .low] {
            for dark in [false, true] {
                #expect(PacemarkSeverityColorValues.fill(for: severity, dark: dark, increasedContrast: true)
                    == PacemarkSeverityColorValues.color(for: severity, dark: dark))
            }
        }
    }

    /// Increase Contrast fills meet 3:1 on the neutral track, with the named dark critical
    /// exception covered separately.
    @Test func everySeverityFillClearsNonTextContrastWhereItIsClaimed() {
        for dark in [true, false] {
            for background in raisedTileFillColors(dark: dark) {
                let track = composite(PacemarkColorValues.barTrack(dark: dark), over: background)
                for severity in [UsageSeverity.healthy, .low, .critical] where !dark || severity != .critical {
                    let fill = PacemarkSeverityColorValues.fill(
                        for: severity,
                        dark: dark,
                        increasedContrast: true
                    )
                    #expect(contrastRatio(fill, track) >= 3, "\(severity), dark=\(dark)")
                }
            }
        }
    }

    /// Characterizes the deliberate policy change. In the default light appearance the bar is a
    /// *redundant* visualization — the percent numeral beside it states the value at full text
    /// contrast — so the fills trade 1.4.11's 3:1 for vividness and are held instead to a
    /// legibility floor of ≥2.0:1 against the track and ≥2.5:1 against the card behind it.
    /// Increase Contrast restores the 3:1 fills (asserted above).
    @Test func defaultLightSeverityFillsClearTheRedundantVisualizationFloor() {
        for background in raisedTileFillColors(dark: false) {
            let track = composite(PacemarkColorValues.barTrack(dark: false), over: background)
            for severity in [UsageSeverity.healthy, .low, .critical] {
                let fill = PacemarkSeverityColorValues.fill(
                    for: severity,
                    dark: false,
                    increasedContrast: false
                )
                #expect(contrastRatio(fill, track) >= 2.0, "\(severity) vs track")
                #expect(contrastRatio(fill, background) >= 2.5, "\(severity) vs card")
            }
        }
    }

    /// Why the policy is a two-tier split rather than a palette retune, and why the light track
    /// stays at black @ 0.12 (renamed from `vividDarkSeverityColorsCannotBeReusedOnTheLightTrack`
    /// now that the default light fills sit below 3:1 on purpose). On the light track no
    /// saturated fill can reach 3:1: the track sits at L≈0.745, so a 3:1 fill needs L ≤ 0.215 —
    /// darker than any vivid sRGB amber (the dark token is L≈0.41). And *deepening* the track
    /// lowers the ratio instead of raising it, because these mid-luminance fills are darker than
    /// the track and converge on it as it darkens (amber: 2.06 → 1.46 at 0.18 alpha). Both facts
    /// are asserted so a future "just darken the track" fix fails here first.
    @Test func noVividLightFillCanClearThreeToOneOnTheLightTrack() {
        let card = raisedTileFillColors(dark: false)[1]
        let track = composite(PacemarkColorValues.barTrack(dark: false), over: card)

        for severity in [UsageSeverity.healthy, .low, .critical] {
            let darkToken = PacemarkSeverityColorValues.fill(for: severity, dark: true, increasedContrast: false)
            let lightFill = PacemarkSeverityColorValues.fill(
                for: severity,
                dark: false,
                increasedContrast: false
            )
            if severity != .critical {
                #expect(contrastRatio(darkToken, track) < 3, "dark \(severity) reused on the light track")
            }
            // Critical's light fill happens to clear 3:1 on its own; healthy and low do not,
            // and the policy does not require them to.
            if severity != .critical {
                #expect(contrastRatio(lightFill, track) < 3, "default light \(severity) is intentionally below 3:1")
            }

            let deeperTrack = composite(PacemarkTint(color: .black, opacity: 0.18), over: card)
            #expect(
                contrastRatio(lightFill, deeperTrack) < contrastRatio(lightFill, track),
                "deepening the light track reduces fill separation: \(severity)"
            )
        }
    }

    @Test func rampStartsRemainChromaBearingInBothSchemes() {
        for scheme in MeterColorScheme.allCases {
            for surface in [MeterRampSurface.flat, .well] {
                for increasedContrast in [false, true] {
                    for severity in [UsageSeverity.healthy, .low, .critical] {
                        let start = MeterRecipe.rampStops(
                            severity: severity,
                            scheme: scheme,
                            surface: surface,
                            increasedContrast: increasedContrast
                        ).start
                        #expect(rgbChroma(start) >= 0.04, "\(severity), \(scheme), \(surface), ic=\(increasedContrast)")
                    }
                }
            }
        }
    }

    /// MX2: the harshness Kyle saw was the dark Full Fade starting *below* the track it sits
    /// on — mixed toward black, the start was a hole in the bar. Full's start now stays at or
    /// above the dark track's lightness on both card fills, so the ramp only ever brightens.
    @Test func darkFullRampStartsNeverSinkBelowTheTrack() {
        for background in raisedTileFillColors(dark: true) {
            let track = PacemarkOKLCH(composite(PacemarkColorValues.barTrack(dark: true), over: background))
            for increasedContrast in [false, true] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let start = PacemarkOKLCH(MeterRecipe.fullRampStops(
                        severity: severity,
                        scheme: .dark,
                        increasedContrast: increasedContrast
                    ).start)
                    #expect(start.lightness > track.lightness, "\(severity) ic=\(increasedContrast)")
                    #expect(rgbChroma(start.rgb) >= 0.04, "\(severity) ic=\(increasedContrast) keeps its colour")
                }
            }
        }
    }

    /// The light ramp-start retune (0.55 → 0.75) exists to hold the start's separation from the
    /// track once the fills went vivid; at 0.55 the amber start fell to 1.27:1 (was 1.55:1).
    /// Each default light start now matches or beats what the old text-tier ramp measured.
    @Test func lightRampStartsKeepTheirSeparationFromTheTrack() {
        let previousLightStartRatios: [UsageSeverity: Double] = [
            .healthy: 1.628,
            .low: 1.545,
            .critical: 1.833,
        ]
        for background in raisedTileFillColors(dark: false) {
            let track = composite(PacemarkColorValues.barTrack(dark: false), over: background)
            for (severity, previous) in previousLightStartRatios {
                let start = MeterRecipe.rampStops(
                    severity: severity,
                    scheme: .light,
                    surface: .flat,
                    increasedContrast: false
                ).start
                #expect(contrastRatio(start, track) >= previous, "\(severity) ramp start")
            }
        }
    }

    /// Ghost body contrast is measured on the neutral track. Ghost remains deliberately subtle.
    @Test func ghostBodyContrastOnTrackIsRecorded() throws {
        let bounds: [(Bool, Bool, Double, Double)] = [
            (true, false, 1.1017, 1.3733), (true, true, 1.1600, 1.3733),
            (false, false, 1.2846, 1.7906), (false, true, 1.3815, 1.7906),
        ]
        for (dark, increasedContrast, minimum, maximum) in bounds {
            let ratios = measuredGhostRatios(dark: dark, increasedContrast: increasedContrast)
            #expect(abs(try #require(ratios.min()) - minimum) < 0.0001)
            #expect(abs(try #require(ratios.max()) - maximum) < 0.0001)
        }
    }

    /// Glass is recorded rather than promoted to a blanket pass. Dark is unchanged. The light
    /// band moved 3.0986–4.0254 → 1.7514–2.4396 under PA1: the old light glass was an opaque
    /// mid-grey that measured *higher* against its own track than any severity fill did, which
    /// is precisely the inversion PA1 removes. Glass is decorative chrome — the percent numeral
    /// beside it carries the value at full text contrast — so the drop is the fix, not a
    /// regression.
    @Test func healthyGlassContrastOnTrackIsRecorded() {
        #expect(measuredGlassRatios(dark: true).min().map { abs($0 - 1.3782) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: true).max().map { abs($0 - 1.9544) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).min().map { abs($0 - 1.7514) < 0.0001 } == true)
        #expect(measuredGlassRatios(dark: false).max().map { abs($0 - 2.4396) < 0.0001 } == true)
    }

    // MARK: - PA1: neutral never outshouts an event

    /// "Colour as event" means a neutral meter says *nothing is happening* and a coloured one
    /// says something is. That only reads if the neutral fill is the quietest thing in the
    /// list. In light it was not: the neutral greys were opaque mid-greys measuring APCA
    /// |Lc| ≈ 72 against the card while the amber "running low" fill measured ≈ 52, so on the
    /// shipping default a healthy 72% bar visibly outweighed a low 38% bar above it and the
    /// mode inverted its own meaning.
    ///
    /// Measured the way it renders: the neutral fill is an alpha over the bar track, which is
    /// itself an alpha over the card; the severity fills paint opaque over that same track.
    /// The ordering is what is pinned here — the literals stay tunable from live captures.
    ///
    /// R2C4b retired half of the old exemption here. `glassB` stays exempt — it is the glass
    /// gradient's shaded foot, not the fill's weight. `tickGlassCap` no longer is: see
    /// `theDarkSeverityRampIsMonotonicInLc`.
    @Test func theNeutralMeterBodyNeverOutweighsASeverityFillInEitherScheme() {
        for dark in [true, false] {
            for card in raisedTileFillColors(dark: dark) {
                let track = composite(PacemarkColorValues.barTrack(dark: dark), over: card)
                let quietestEvent = [UsageSeverity.healthy, .low, .critical]
                    .map { severity in
                        abs(apcaLc(
                            text: PacemarkSeverityColorValues.fill(
                                for: severity,
                                dark: dark,
                                increasedContrast: false
                            ),
                            background: card
                        ))
                    }
                    .min() ?? 0
                let bodies = [
                    ("glassA", PacemarkMeterColorValues.glassA(dark: dark)),
                    ("tickGlass", PacemarkMeterColorValues.tickGlass(dark: dark)),
                ]
                for (name, tint) in bodies {
                    let neutral = abs(apcaLc(text: composite(tint, over: track), background: card))
                    #expect(
                        neutral < quietestEvent,
                        "\(name) |Lc| \(neutral) vs quietest severity \(quietestEvent), dark=\(dark)"
                    )
                }
            }
        }
    }

    // MARK: - R2C4: the severity ramp is monotonic in |Lc|

    /// R2C4a. PA1 fixed the neutral-vs-severity ordering; the severity tokens were never
    /// measured against *each other*. In light they ran backwards — `lowFill` |Lc| 53.4/51.0
    /// sat below `healthyFill` 57.2/54.8, so "running low" was quieter than "you're fine" on
    /// the same row. A ramp that is not monotonic does not encode severity.
    @Test func theLightSeverityRampIsMonotonicInLc() {
        for card in raisedTileFillColors(dark: false) {
            let ordered = [UsageSeverity.healthy, .low, .critical].map { severity in
                abs(apcaLc(
                    text: PacemarkSeverityColorValues.fill(
                        for: severity,
                        dark: false,
                        increasedContrast: false
                    ),
                    background: card
                ))
            }
            #expect(ordered[1] > ordered[0], "low \(ordered[1]) must outweigh healthy \(ordered[0])")
            #expect(ordered[2] > ordered[1], "critical \(ordered[2]) must outweigh low \(ordered[1])")
        }
    }

    /// R2C4b, the assertion that replaces PA1's documented exemption ("the two end tokens are
    /// exempt and stay exempt … dark's 0.52 cap has always measured above the dark critical
    /// fill"). It always had — that *was* the bug: a fully healthy grey meter's tip
    /// out-shouted a critical red meter's. The whole dark ramp is pinned in order now.
    ///
    /// The honest limit, recorded rather than chased: |Lc| cannot put red above amber in dark
    /// without desaturating the red. That is fine — AP1 gives critical a second channel (the
    /// red numeral), which is why critical sits below healthy/low here by design.
    @Test func theDarkSeverityRampIsMonotonicInLc() {
        for card in raisedTileFillColors(dark: true) {
            let track = composite(PacemarkColorValues.barTrack(dark: true), over: card)
            func onCard(_ tint: PacemarkTint) -> Double {
                abs(apcaLc(text: composite(tint, over: track), background: card))
            }
            func fill(_ severity: UsageSeverity) -> Double {
                abs(apcaLc(
                    text: PacemarkSeverityColorValues.fill(
                        for: severity,
                        dark: true,
                        increasedContrast: false
                    ),
                    background: card
                ))
            }
            let ladder: [(String, Double)] = [
                ("body", onCard(PacemarkMeterColorValues.tickGlass(dark: true))),
                ("cap", onCard(PacemarkMeterColorValues.tickGlassCap(dark: true))),
                ("critical", fill(.critical)),
                ("healthy", fill(.healthy)),
                ("low", fill(.low)),
            ]
            for (lower, upper) in zip(ladder, ladder.dropFirst()) {
                #expect(
                    lower.1 < upper.1,
                    "\(lower.0) |Lc| \(lower.1) must sit below \(upper.0) |Lc| \(upper.1)"
                )
            }
            // The cap is still a genuine end marker against its own body.
            #expect(ladder[1].1 > ladder[0].1 + 8, "cap barely reads against its body")
        }
    }

    /// The structural half of PA1: light is *authored* the way dark is, an alpha over the card,
    /// so the two branches cannot drift back apart into "opaque grey here, translucent white
    /// there". A future opaque literal fails here even if it happens to measure quietly on the
    /// two card fills this suite samples.
    @Test func lightNeutralMeterTokensMirrorDarksAlphaConstruction() {
        let tokens: [(String, (Bool) -> PacemarkTint)] = [
            ("glassA", PacemarkMeterColorValues.glassA),
            ("glassB", PacemarkMeterColorValues.glassB),
            ("tickGlass", PacemarkMeterColorValues.tickGlass),
            ("tickGlassCap", PacemarkMeterColorValues.tickGlassCap),
        ]
        for (name, token) in tokens {
            #expect(token(true).color == .white, "\(name) dark base")
            #expect(token(false).color == .black, "\(name) light base")
            #expect(token(true).opacity < 1, "\(name) dark is an alpha")
            #expect(token(false).opacity < 1, "\(name) light is an alpha")
        }
        // Each scheme's end stop is heavier than its body, in both branches.
        #expect(PacemarkMeterColorValues.tickGlassCap(dark: true).opacity
            > PacemarkMeterColorValues.tickGlass(dark: true).opacity)
        #expect(PacemarkMeterColorValues.tickGlassCap(dark: false).opacity
            > PacemarkMeterColorValues.tickGlass(dark: false).opacity)
    }

    // MARK: - PA13: dark muted text re-derived by |Lc|

    /// The dark muted-text steps were matched to their light partners on WCAG *ratio*, which is
    /// polarity-blind — the same ratio buys much less separation on a dark surface. Measured on
    /// APCA against the same card fills, the dark account title came out at |Lc| 33 against
    /// light's 79 (41%), and the plan pill, on the system `.tertiary`, at ≈ 20.
    ///
    /// Two relationships are pinned rather than the literals: every muted role clears APCA's
    /// Lc 45 tier in *both* schemes, and no dark role keeps less than 55% of its light partner's
    /// separation. Re-tuning the numbers is fine; letting one scheme recede again is not.
    @Test func everyMutedTextRoleHoldsItsSeparationInBothSchemes() {
        for (name, measured) in mutedTextSeparations() {
            for (dark, values) in measured {
                for value in values {
                    #expect(value >= 45, "\(name) |Lc| \(value), dark=\(dark)")
                }
            }
            for (darkValue, lightValue) in zip(measured[true] ?? [], measured[false] ?? []) {
                #expect(
                    darkValue / lightValue >= 0.55,
                    "\(name) keeps \(darkValue / lightValue) of its light separation"
                )
            }
        }
    }

    /// The two-level grey hierarchy the light branch documents has to hold in dark too — the
    /// tertiary bump would otherwise have pushed tertiary *past* secondary, which is why
    /// secondary moved with it.
    @Test func secondaryTextStaysAboveTertiaryTextInBothSchemes() {
        for dark in [true, false] {
            for card in raisedTileFillColors(dark: dark) {
                let secondary = abs(apcaLc(
                    text: composite(PacemarkColorValues.secondaryText(dark: dark), over: card),
                    background: card
                ))
                let tertiary = abs(apcaLc(
                    text: composite(PacemarkColorValues.tertiaryText(dark: dark), over: card),
                    background: card
                ))
                #expect(secondary > tertiary, "dark=\(dark): secondary \(secondary), tertiary \(tertiary)")
            }
        }
    }

    @Test func theStaleNeutralFillMatchesCanonicalSpec() {
        #expect(hex(PacemarkColorValues.staleNeutralFill(dark: true)) == "#55575C")
        #expect(hex(PacemarkColorValues.staleNeutralFill(dark: false)) == "#8D9299")
    }

}

private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> PacemarkRGBColor {
    PacemarkRGBColor(red: red / 255, green: green / 255, blue: blue / 255)
}

private func hex(_ color: PacemarkRGBColor) -> String {
    func channel(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", channel(color.red), channel(color.green), channel(color.blue))
}

private func distance(_ lhs: PacemarkRGBColor, _ rhs: PacemarkRGBColor) -> Double {
    max(abs(lhs.red - rhs.red), max(abs(lhs.green - rhs.green), abs(lhs.blue - rhs.blue)))
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // PacemarkCoreTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repo root
private let brandBundleDirectory = repositoryRoot.appendingPathComponent("Sources/PacemarkApp/Resources/BrandIcons")
private let monochromeMarkFiles: [(URL, Bool)] = {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PacemarkCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
    let appIcons = root.appendingPathComponent("Sources/PacemarkApp/Resources/BrandIcons")
    return [
        (appIcons.appendingPathComponent("grok-dark.svg"), true),
        (appIcons.appendingPathComponent("grok-light.svg"), false),
        (appIcons.appendingPathComponent("cursor-dark.svg"), true),
        (appIcons.appendingPathComponent("cursor-light.svg"), false),
        (appIcons.appendingPathComponent("copilot-dark.svg"), true),
        (appIcons.appendingPathComponent("copilot-light.svg"), false),
        (appIcons.appendingPathComponent("opencode-dark.svg"), true),
        (appIcons.appendingPathComponent("opencode-light.svg"), false),
        (appIcons.appendingPathComponent("antigravity-dark.svg"), true),
        (appIcons.appendingPathComponent("antigravity-light.svg"), false),
    ]
}()

private func raisedTileFillColors(dark: Bool) -> [PacemarkRGBColor] {
    // Flattened endpoints of RaisedTile's current glass fill in the design reference.
    [
        PacemarkColorValues.tileFillTop(dark: dark),
        PacemarkColorValues.tileFillBottom(dark: dark),
    ]
}

private func containerBackgroundColors(dark: Bool) -> [PacemarkRGBColor] {
    [
        PacemarkColorValues.containerBackgroundTop(dark: dark),
        PacemarkColorValues.containerBackgroundMiddle(dark: dark),
        PacemarkColorValues.containerBackgroundBottom(dark: dark),
    ]
}

private func composite(_ tint: PacemarkTint, over background: PacemarkRGBColor) -> PacemarkRGBColor {
    mix(tint.color, weight: tint.opacity, with: background)
}

private func mix(
    _ foreground: PacemarkRGBColor,
    weight: Double,
    with background: PacemarkRGBColor
) -> PacemarkRGBColor {
    PacemarkRGBColor(
        red: foreground.red * weight + background.red * (1 - weight),
        green: foreground.green * weight + background.green * (1 - weight),
        blue: foreground.blue * weight + background.blue * (1 - weight)
    )
}

private func contrastRatio(_ lhs: PacemarkRGBColor, _ rhs: PacemarkRGBColor) -> Double {
    let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
    let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: PacemarkRGBColor) -> Double {
    0.2126 * linearized(color.red)
        + 0.7152 * linearized(color.green)
        + 0.0722 * linearized(color.blue)
}

private func linearized(_ component: Double) -> Double {
    component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
}

private func rgbChroma(_ color: PacemarkRGBColor) -> Double {
    max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue)
}

private func measuredGhostRatios(dark: Bool, increasedContrast: Bool) -> [Double] {
    raisedTileFillColors(dark: dark).flatMap { background in
        let track = composite(PacemarkColorValues.barTrack(dark: dark), over: background)
        return [UsageSeverity.healthy, .low, .critical].map { severity in
            let body = PacemarkTint(
                color: PacemarkSeverityColorValues.fill(
                    for: severity,
                    dark: dark,
                    increasedContrast: increasedContrast
                ),
                opacity: PacemarkMeterColorValues.ghostBodyOpacity(for: severity, dark: dark)
            )
            return contrastRatio(composite(body, over: track), track)
        }
    }
}

private func measuredGlassRatios(dark: Bool) -> [Double] {
    let glass = [
        PacemarkMeterColorValues.glassA(dark: dark),
        PacemarkMeterColorValues.glassB(dark: dark),
    ]
    return raisedTileFillColors(dark: dark).flatMap { background in
        let track = composite(PacemarkColorValues.barTrack(dark: dark), over: background)
        return glass.map { contrastRatio(composite($0, over: track), track) }
    }
}

/// APCA-W3 (0.0.98 G-4g) lightness contrast, signed: positive for dark-on-light, negative for
/// light-on-dark. WCAG's ratio is polarity-blind, which is exactly what let the dark muted text
/// and the light neutral meter greys drift (PA1, PA13), so those two decisions are measured
/// here instead. Inputs are already-composited opaque sRGB.
private func apcaLc(text: PacemarkRGBColor, background: PacemarkRGBColor) -> Double {
    let textY = apcaScreenLuminance(text)
    let backgroundY = apcaScreenLuminance(background)
    guard abs(backgroundY - textY) >= 0.0005 else { return 0 }
    if backgroundY > textY {
        let sapc = (pow(backgroundY, 0.56) - pow(textY, 0.57)) * 1.14
        return sapc < 0.1 ? 0 : (sapc - 0.027) * 100
    }
    let sapc = (pow(backgroundY, 0.65) - pow(textY, 0.62)) * 1.14
    return sapc > -0.1 ? 0 : (sapc + 0.027) * 100
}

private func apcaScreenLuminance(_ color: PacemarkRGBColor) -> Double {
    let y = 0.2126729 * pow(color.red, 2.4)
        + 0.7151522 * pow(color.green, 2.4)
        + 0.0721750 * pow(color.blue, 2.4)
    // APCA's soft black clamp.
    return y < 0.022 ? y + pow(0.022 - y, 1.414) : y
}

/// Every muted text role's |Lc| on both card fills, per scheme. The plan pill is measured on
/// the identity capsule it actually sits in (white @ 0.06 dark / black @ 0.045 light over the
/// card) rather than on the bare card, because that is the surface it has to read against.
private func mutedTextSeparations() -> [(String, [Bool: [Double]])] {
    func onCard(_ tint: @escaping (Bool) -> PacemarkTint) -> [Bool: [Double]] {
        var result: [Bool: [Double]] = [:]
        for dark in [true, false] {
            result[dark] = raisedTileFillColors(dark: dark).map { card in
                abs(apcaLc(text: composite(tint(dark), over: card), background: card))
            }
        }
        return result
    }

    var planPill: [Bool: [Double]] = [:]
    for dark in [true, false] {
        let capsule = PacemarkTint(color: dark ? .white : .black, opacity: dark ? 0.06 : 0.045)
        planPill[dark] = raisedTileFillColors(dark: dark).map { card in
            let surface = composite(capsule, over: card)
            return abs(apcaLc(
                text: composite(PacemarkColorValues.planLabel(dark: dark), over: surface),
                background: surface
            ))
        }
    }

    return [
        ("accountTitle", onCard(PacemarkColorValues.accountTitle)),
        ("secondaryText", onCard(PacemarkColorValues.secondaryText)),
        ("tertiaryText", onCard(PacemarkColorValues.tertiaryText)),
        ("countdownInk", onCard(PacemarkMeterColorValues.countdownInk)),
        ("planLabel", planPill),
    ]
}
