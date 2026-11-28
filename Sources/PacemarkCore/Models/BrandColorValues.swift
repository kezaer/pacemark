import Foundation

public struct PacemarkRGBColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = PacemarkRGBColor(red: 1, green: 1, blue: 1)
    public static let black = PacemarkRGBColor(red: 0, green: 0, blue: 0)
}

public struct PacemarkTint: Sendable, Equatable {
    public let color: PacemarkRGBColor
    public let opacity: Double

    public init(color: PacemarkRGBColor, opacity: Double) {
        self.color = color
        self.opacity = opacity
    }
}

/// R2C18 / R2C12 / R2C16: perceptual (OKLCH) coordinates for an sRGB color.
///
/// Three round-2 decisions all need the *same* operation — move a color's lightness or
/// chroma while its hue stays put — and sRGB arithmetic cannot do it: mixing a fill toward
/// white in sRGB swings the amber ramp ~8.5° warmer at its start, and hand-authored "same
/// family" literals had drifted the Claude token 9° off its own artwork. Keeping one
/// conversion here means the brand ramps (R2C18), the meter ramp (R2C12), and the stale
/// desaturation (R2C16) all traverse the same space rather than three approximations of it.
///
/// Out-of-gamut results are clamped per channel at the `rgb` boundary; every shipped token
/// is asserted to survive that clamp with < 2° of hue error.
public struct PacemarkOKLCH: Sendable, Equatable {
    public let lightness: Double
    public let chroma: Double
    /// Degrees, 0..<360.
    public let hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = max(0, chroma)
        self.hue = hue
    }

    public init(_ rgb: PacemarkRGBColor) {
        let (l, a, b) = Self.oklab(from: rgb)
        self.lightness = l
        self.chroma = (a * a + b * b).squareRoot()
        let degrees = atan2(b, a) * 180 / .pi
        self.hue = degrees < 0 ? degrees + 360 : degrees
    }

    /// The color with a new lightness, keeping hue and chroma.
    public func withLightness(_ lightness: Double) -> PacemarkOKLCH {
        PacemarkOKLCH(lightness: lightness, chroma: chroma, hue: hue)
    }

    /// The color with its chroma scaled, keeping lightness and hue (R2C16's stale hedge).
    public func scalingChroma(by factor: Double) -> PacemarkOKLCH {
        PacemarkOKLCH(lightness: lightness, chroma: chroma * factor, hue: hue)
    }

    /// Interpolates lightness and chroma toward `other` while holding *this* color's hue.
    /// Both call sites (the meter ramp, the brand ramps) are constant-hue by construction, so
    /// carrying `self.hue` through is what keeps a mix toward white or black from bending the
    /// family sideways — and it is why the ramp's hue-drift assertion can hold at 0°.
    public func interpolated(to other: PacemarkOKLCH, progress: Double) -> PacemarkOKLCH {
        let t = min(1, max(0, progress))
        return PacemarkOKLCH(
            lightness: lightness + (other.lightness - lightness) * t,
            chroma: chroma + (other.chroma - chroma) * t,
            hue: hue
        )
    }

    public var rgb: PacemarkRGBColor {
        let a = chroma * cos(hue * .pi / 180)
        let b = chroma * sin(hue * .pi / 180)
        return Self.srgb(fromOklabL: lightness, a: a, b: b)
    }

    // MARK: - Conversion (Björn Ottosson's Oklab, sRGB transfer function)

    private static func oklab(from rgb: PacemarkRGBColor) -> (Double, Double, Double) {
        let r = linearized(rgb.red), g = linearized(rgb.green), b = linearized(rgb.blue)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return (
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    private static func srgb(fromOklabL lightness: Double, a: Double, b: Double) -> PacemarkRGBColor {
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return PacemarkRGBColor(
            red: encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ component: Double) -> Double {
        let value = component <= 0.0031308
            ? component * 12.92
            : 1.055 * pow(max(component, 0), 1 / 2.4) - 0.055
        return min(1, max(0, value))
    }
}

public enum PacemarkBrandColorValues {
    /// R2C18: the artwork's own hues. `claude-color.svg` fills `#D97757` = `oklch(0.672
    /// 0.131 38.8)`; the token used to be a hand-authored `#D97842` at H 47.8°, so the mark
    /// and its accent were 9° apart in the same card. Every Claude/Codex brand value below
    /// and in `PacemarkBrandRamp` is now one constant-hue ramp off these two numbers.
    public static let claudeHue: Double = 38.8
    public static let codexHue: Double = 271.5

    public static let claude = PacemarkOKLCH(lightness: 0.672, chroma: 0.131, hue: claudeHue).rgb
    public static let codex = PacemarkOKLCH(lightness: 0.555, chroma: 0.246, hue: codexHue).rgb
    // Grok and Cursor are monochrome brands (their marks ship as light/dark pairs); these
    // mid-tone accents exist for the SF Symbol fallback + single-color tints and read on
    // both schemes. First-pass identity values — Phase 2 owns visual density.
    public static let grok = PacemarkRGBColor(red: 0.36, green: 0.40, blue: 0.46)
    public static let cursor = PacemarkRGBColor(red: 0.33, green: 0.34, blue: 0.38)
    /// GitHub draws the Copilot mark in black or white only, so it is a monochrome brand
    /// too, given a cooler neutral than Cursor's so the two read apart (U6, Copilot plan).
    public static let copilot = PacemarkRGBColor(red: 0.34, green: 0.37, blue: 0.43)
    /// OpenCode publishes its mark in black or white only, so it is monochrome too. Its own
    /// palette is a warm neutral (the mark's inner block is `#5A5858`), which keeps it apart
    /// from Cursor's and Copilot's cooler neutrals (U6, OpenCode plan).
    public static let opencode = PacemarkRGBColor(red: 0.35, green: 0.34, blue: 0.34)
    /// Antigravity ships its monochrome mark (the color mark's blurred gradient does not
    /// survive AppKit's SVG renderer), so it takes a neutral like the other monochrome marks.
    /// The mark, not this accent, tells them apart.
    public static let antigravity = PacemarkRGBColor(red: 0.36, green: 0.36, blue: 0.38)

    public static func monochromeMarkInk(dark: Bool) -> PacemarkRGBColor {
        dark
            ? PacemarkRGBColor(red: 0xC9 / 255, green: 0xCD / 255, blue: 0xD4 / 255)
            : PacemarkRGBColor(red: 0x3A / 255, green: 0x3D / 255, blue: 0x42 / 255)
    }

    public static func monochromeMarkInkHex(dark: Bool) -> String {
        dark ? "#C9CDD4" : "#3A3D42"
    }
}

/// R2C18: the two brand families as constant-hue OKLCH ramps.
///
/// Before this, `textAccent` lived here while both CTA gradients, the "Connected" ink and a
/// byte-copy of the shared light neutral lived as raw `Color(red:green:blue:)` literals
/// inside the two setup views — eight Claude oranges and four Codex blues, no two of which
/// agreed on a hue. Each stop below is `(lightness, chroma)` at its family's hue, so a tweak
/// moves along the ramp instead of off it. The setup views keep their own `…SetupStyle`
/// enums as the *call* surface (the two provider flows stay decoupled); only the numbers
/// moved here.
///
/// White-on-CTA-top clears WCAG AA (≥4.5:1) in both schemes — the dark tops dropped
/// (Claude L 0.605 → 0.560, Codex 0.611 → 0.565) because they measured 4.05 / 3.97:1 while
/// the old comment claimed the ramp "averages ≈4.5:1". `BrandColorValuesTests` asserts it.
public enum PacemarkBrandRamp {
    private static func claude(_ lightness: Double, _ chroma: Double) -> PacemarkRGBColor {
        PacemarkOKLCH(lightness: lightness, chroma: chroma, hue: PacemarkBrandColorValues.claudeHue).rgb
    }

    private static func codex(_ lightness: Double, _ chroma: Double) -> PacemarkRGBColor {
        PacemarkOKLCH(lightness: lightness, chroma: chroma, hue: PacemarkBrandColorValues.codexHue).rgb
    }

    public static func claudeTextAccent(dark: Bool) -> PacemarkRGBColor {
        dark ? claude(0.734, 0.121) : claude(0.556, 0.139)
    }

    public static func codexTextAccent(dark: Bool) -> PacemarkRGBColor {
        dark ? .white : .black
    }

    public static func claudeCTATop(dark: Bool) -> PacemarkRGBColor {
        dark ? claude(0.560, 0.129) : claude(0.575, 0.143)
    }

    public static func claudeCTABottom(dark: Bool) -> PacemarkRGBColor {
        dark ? claude(0.515, 0.130) : claude(0.530, 0.135)
    }

    public static func codexCTATop(dark: Bool) -> PacemarkRGBColor {
        dark ? codex(0.565, 0.189) : codex(0.540, 0.210)
    }

    public static func codexCTABottom(dark: Bool) -> PacemarkRGBColor {
        dark ? codex(0.472, 0.187) : codex(0.447, 0.203)
    }

    /// R2C18: the "Connected" chip's ink, now a documented lightness offset from the healthy
    /// severity token rather than a hand-written green beside a chip fill *derived* from that
    /// token — one chip, two greens. The offset is what the hand-written pair already
    /// measured (dark +0.058 Lc, light −0.054), i.e. "step away from the surface so the label
    /// passes AA on its own tint"; hue and chroma come from `healthy` so the family cannot
    /// drift again.
    public static func connectedInkLightnessOffset(dark: Bool) -> Double {
        dark ? 0.058 : -0.054
    }

    public static func connectedInk(dark: Bool) -> PacemarkRGBColor {
        let green = PacemarkOKLCH(PacemarkSeverityColorValues.healthy(dark: dark))
        return green.withLightness(green.lightness + connectedInkLightnessOffset(dark: dark)).rgb
    }
}

public enum PacemarkColorValues {
    /// Provider display-name accent, tuned warmer/cooler than the raw brand fill per scheme.
    /// Returns `nil` for unknown providers so the caller can fall back to `.secondary`.
    public static func textAccent(for providerID: String, dark: Bool) -> PacemarkRGBColor? {
        switch (providerID, dark) {
        // R2C18: Claude's and Codex's steps are now stops on their family's constant-hue
        // OKLCH ramp (`PacemarkBrandRamp`) rather than free literals — same lightnesses the
        // WCAG tuning landed on, re-authored at the artwork's real hue.
        case (ProviderID.claude.raw, _): PacemarkBrandRamp.claudeTextAccent(dark: dark)
        case (ProviderID.codex.raw, _): PacemarkBrandRamp.codexTextAccent(dark: dark)
        // Grok/Cursor are monochrome brands: their title accent is a legible near-primary
        // neutral (grok cooler, cursor pure) that clears WCAG AA small-text on the light
        // container (dark step) and the dark tile (light step).
        case (ProviderID.grok.raw, false): PacemarkRGBColor(red: 0.20, green: 0.22, blue: 0.25)
        case (ProviderID.grok.raw, true): PacemarkRGBColor(red: 0.78, green: 0.80, blue: 0.84)
        case (ProviderID.cursor.raw, false): PacemarkRGBColor(red: 0.17, green: 0.17, blue: 0.18)
        case (ProviderID.cursor.raw, true): PacemarkRGBColor(red: 0.81, green: 0.81, blue: 0.83)
        case (ProviderID.copilot.raw, false): PacemarkRGBColor(red: 0.18, green: 0.20, blue: 0.24)
        case (ProviderID.copilot.raw, true): PacemarkRGBColor(red: 0.79, green: 0.81, blue: 0.86)
        // OpenCode: the warm neutral of its own palette, at Cursor's legible lightnesses.
        case (ProviderID.opencode.raw, false): PacemarkRGBColor(red: 0.18, green: 0.17, blue: 0.17)
        case (ProviderID.opencode.raw, true): PacemarkRGBColor(red: 0.82, green: 0.81, blue: 0.81)
        // Antigravity: a plain neutral at Cursor's legible lightnesses.
        case (ProviderID.antigravity.raw, false): PacemarkRGBColor(red: 0.18, green: 0.18, blue: 0.20)
        case (ProviderID.antigravity.raw, true): PacemarkRGBColor(red: 0.81, green: 0.82, blue: 0.84)
        default: nil
        }
    }

    private static let darkNeutral = PacemarkRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightNeutral = PacemarkRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    public static func secondaryText(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: darkNeutral, opacity: 0.76) : PacemarkTint(color: lightNeutral, opacity: 0.84)
    }

    public static func tertiaryText(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: darkNeutral, opacity: 0.68) : PacemarkTint(color: lightNeutral, opacity: 0.74)
    }

    /// R2C18: the setup flow's quiet-chip label ink. Its light step was a byte-for-byte copy
    /// of `lightNeutral` written out again in `ClaudeSetupViews`, and its dark step was a
    /// bare `Color(white: 0.85)` with no relationship to anything. Both now read the shared
    /// neutral bases; dark's slightly recessed step survives as an opacity on `darkNeutral`
    /// (which composites to ≈0.86 white on the setup card) rather than as a second grey.
    /// CMM3 (Kyle, 2026-09-09): the dark label sits just under full neutral so the chip stays
    /// quieter than the numerals beside it (CMM1 briefly took it to 1.0 and it shouted).
    public static func setupChipInk(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: darkNeutral, opacity: 0.94) : PacemarkTint(color: lightNeutral, opacity: 1)
    }

    /// PA13: the plan pill's own ink. It used to take the system `.tertiary`, which measured
    /// |Lc| ≈ 20 on the dark card — below APCA's placeholder floor — against ≈ 40 in light, and
    /// the plan name is the only thing that says which subscription a meter is measuring. This
    /// token lands both schemes at |Lc| ≈ 46–50 *on the identity capsule* (which is itself only
    /// white @ 0.06 / black @ 0.045 over the card), so the pill reads the same in either
    /// appearance instead of dissolving in one of them.
    public static func planLabel(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: darkNeutral, opacity: 0.60) : PacemarkTint(color: lightNeutral, opacity: 0.52)
    }

    // G1A (Sep 2026): the account title's ink — a cool grey that sits *below* the countdown
    // in the hierarchy on purpose (the numeral carries the value, the title only names the
    // account). Light #5F6771 measures |Lc| ≈ 78 on the card.
    //
    // PA13: the dark step was #7B838D, derived by mirroring the light step across the card on
    // WCAG ratio. Ratio is polarity-blind, and that mirror actually measured |Lc| ≈ 33 — less
    // than half of light's separation, on the one label that names the account a meter belongs
    // to. Re-derived on APCA against the same card fills, #9AA2AC measures |Lc| ≈ 48–50: still
    // deliberately under the 15pt title's full-primary ink, but no longer recessive in dark
    // only.
    public static func accountTitle(dark: Bool) -> PacemarkTint {
        dark
            ? PacemarkTint(color: PacemarkRGBColor(red: 154 / 255, green: 162 / 255, blue: 172 / 255), opacity: 1)
            : PacemarkTint(color: PacemarkRGBColor(red: 95 / 255, green: 103 / 255, blue: 113 / 255), opacity: 1)
    }

    public static func barTrack(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: .white, opacity: 0.14) : PacemarkTint(color: .black, opacity: 0.12)
    }

    public static func hairline(dark: Bool) -> PacemarkTint {
        dark ? PacemarkTint(color: .white, opacity: 0.10) : PacemarkTint(color: .black, opacity: 0.07)
    }

    /// A stale neutral bar has no chroma to reduce, so it recedes in lightness.
    public static func staleNeutralFill(dark: Bool) -> PacemarkRGBColor {
        // The dark stop sits between the track and the live fill so the stale bar recedes.
        dark
            ? PacemarkRGBColor(red: 85 / 255, green: 87 / 255, blue: 92 / 255)
            : PacemarkRGBColor(red: 141 / 255, green: 146 / 255, blue: 153 / 255)
    }

    /// R2C18: the recessed well every "content sits in here" surface uses — the setup flow's
    /// command wells and the Settings preview wells. Both already drew the same two numbers;
    /// the Settings panes just reached them through `ClaudeSetupStyle.wellBackground`, which
    /// made a Claude-branded token the source of truth for a pane with no Claude in it. The
    /// value is unchanged, so nothing moves visually — only where it is read from.
    public static func recessedWell(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .black, opacity: dark ? 0.32 : 0.05)
    }

    public static func containerBackgroundTop(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.082, green: 0.090, blue: 0.114) : PacemarkRGBColor(red: 0.965, green: 0.969, blue: 0.976)
    }

    public static func containerBackgroundMiddle(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.061, green: 0.070, blue: 0.091) : PacemarkRGBColor(red: 0.945, green: 0.951, blue: 0.963)
    }

    public static func containerBackgroundBottom(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.043, green: 0.051, blue: 0.067) : PacemarkRGBColor(red: 0.925, green: 0.933, blue: 0.949)
    }

    public static func containerBackgroundGlow(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: PacemarkRGBColor(red: 0.431, green: 0.475, blue: 1.0), opacity: dark ? 0.10 : 0.08)
    }

    public static func tileFillTop(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.145, green: 0.152, blue: 0.176) : .white
    }

    public static func tileFillBottom(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.098, green: 0.106, blue: 0.129) : PacemarkRGBColor(red: 0.984, green: 0.984, blue: 0.988)
    }
}


/// The ramp's dark-scheme start is mixed against different meter surfaces. Light mode
/// uses the same white mix on both because both reference surfaces are light neutrals.
public enum MeterRampSurface: Sendable {
    case flat
    case well
}

public enum PacemarkMeterColorValues {
    private static let darkText = PacemarkRGBColor(red: 0.92, green: 0.92, blue: 0.96)
    private static let lightLabel = PacemarkRGBColor(
        red: 29.0 / 255.0,
        green: 31.0 / 255.0,
        blue: 36.0 / 255.0
    )
    private static let lightMetadata = PacemarkRGBColor(red: 0.24, green: 0.24, blue: 0.26)

    public static func labelInk(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: dark ? darkText : lightLabel, opacity: 0.90)
    }

    public static func countdownInk(dark: Bool) -> PacemarkTint {
        // The round-4 D2 values clear 4.5:1 against both RaisedTile fill endpoints.
        //
        // PA13: dark stepped 0.53 → 0.66. The pair was matched on WCAG ratio, which is
        // polarity-blind — at 0.53 the dark countdown measured |Lc| ≈ 39 against light's ≈ 71,
        // so the reset time was noticeably fainter in one appearance than the other. 0.66
        // lands at |Lc| ≈ 52 and still clears 4.5:1 (6.33–6.95) on both card fills.
        PacemarkTint(color: dark ? darkText : lightMetadata, opacity: dark ? 0.66 : 0.72)
    }

    // PA1: the neutral (no-event) meter greys.
    //
    // Light used to be *opaque* mid-greys (#757C86 / #666C75, #6B727B / #474E57) while dark was
    // white-alpha over the card. Alpha over an opaque literal is not a cosmetic difference: on
    // the shipping default (micro · chip · color-as-event) the light neutral body measured APCA
    // |Lc| ≈ 72 on the card while the amber "running low" fill measured ≈ 52, so a healthy 72%
    // bar visibly outweighed the low 38% bar above it and "color as event" inverted its own
    // meaning. Light now mirrors dark's construction — black-alpha over the card — which puts
    // the neutral body below every severity fill in both schemes.
    //
    // Body ≈ black @ 0.24, end stop ≈ black @ 0.36; the amber is untouched. These are the
    // starting values from the decision, tuned from live `--demo multi-4` captures.
    // `BrandColorValuesTests` pins the ordering, not the literals.
    public static func glassA(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: dark ? .white : .black, opacity: dark ? 0.22 : 0.24)
    }

    public static func glassB(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: dark ? .white : .black, opacity: dark ? 0.11 : 0.36)
    }

    public static func glassRim(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .white, opacity: dark ? 0.25 : 0.30)
    }

    public static func wellBackground(dark: Bool) -> PacemarkRGBColor {
        dark
            ? PacemarkRGBColor(
                red: 15.0 / 255.0,
                green: 17.0 / 255.0,
                blue: 20.0 / 255.0
            )
            : PacemarkRGBColor(
                red: 223.0 / 255.0,
                green: 226.0 / 255.0,
                blue: 231.0 / 255.0
            )
    }

    public static func wellShadow(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .black, opacity: dark ? 0.65 : 0.20)
    }

    public static func tickOff(dark: Bool) -> PacemarkTint {
        dark
            ? PacemarkTint(color: .white, opacity: 0.09)
            : PacemarkTint(color: .black, opacity: 0.08)
    }

    /// Dark neutral segments stay quieter than the deep critical fill.
    public static func tickGlass(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: dark ? .white : .black, opacity: dark ? 0.16 : 0.24)
    }

    /// The end segment retains a distinct lightness step over the body.
    public static func tickGlassCap(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: dark ? .white : .black, opacity: dark ? 0.265 : 0.36)
    }

    /// The compatibility meter's tinted track stays close to the neutral track in lightness
    /// and shares the standard critical fill's hue.
    public static func criticalBarTrack(dark: Bool) -> PacemarkRGBColor {
        let fill = PacemarkSeverityColorValues.criticalFill(dark: dark, increasedContrast: false)
        return PacemarkOKLCH(
            lightness: dark ? 0.391 : 0.905,
            chroma: dark ? 0.055 : 0.045,
            hue: PacemarkOKLCH(fill).hue
        ).rgb
    }

    /// How much of the severity *fill* survives in the Hue ramp's start stop (the rest is
    /// mixed toward white in light, black in dark).
    ///
    /// Light retuned 0.55 → 0.75 alongside the vivid fill tier: the default light fills are
    /// lighter than the text-tier values the 0.55 mix was set against, so a 45% white mix
    /// washed the start into the track (amber 1.27:1, was 1.55:1). At 0.75 every light start
    /// matches or beats its previous separation. Increase Contrast uses more white in the
    /// light start stop so the deeper fills still fade across the track.
    public static func rampStartSeverityMix(
        dark: Bool,
        surface: MeterRampSurface,
        increasedContrast: Bool = false
    ) -> Double {
        guard dark else { return increasedContrast ? 0.55 : 0.75 }
        return surface == .flat ? 0.58 : 0.42
    }

    /// R2C16: how much chroma a `.stale` fill keeps.
    ///
    /// Stale used to replace the whole fill with the system secondary label at 0.55, so a
    /// stale **21%** row rendered flat grey directly beneath a live **38%** amber bar and the
    /// eye ranked the healthier number as the more urgent one. A stale critical is still a
    /// critical: desaturate to de-emphasise, don't neutralise to erase. The fill keeps its
    /// severity lightness and hue and drops to 35% of its chroma — the dim the numeral takes
    /// is unchanged, and `.unavailable` (which paints no fill at all) is untouched.
    public static let staleFillChromaScale: Double = 0.35

    /// The fill a `.stale` meter paints for `severity`. See `staleFillChromaScale`.
    public static func staleFill(
        for severity: UsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> PacemarkRGBColor {
        let live = PacemarkSeverityColorValues.fill(
            for: severity,
            dark: dark,
            increasedContrast: increasedContrast
        )
        return PacemarkOKLCH(live).scalingChroma(by: staleFillChromaScale).rgb
    }


    /// FS1 (Kyle, Sep 2026): how strongly a segmented *body* cell paints its fill colour.
    /// Every lit cell used to sit at full strength, so the tip — the cell that carries the
    /// reading — had nothing to stand out against. Body cells drop to this fraction of their
    /// own colour so the tip reads as the value and the trail reads as context. `.staleGrey`
    /// is exempt (it is already a dim), and `.off` cells never see it.
    ///
    /// FS2 (Kyle, Sep 2026): retuned 0.72 → 0.70 alongside the larger Full cell. Deliberately
    /// one number shared by both formats — Full is the Micro cell scaled up, so the trail
    /// should sit the same distance behind its tip at either size rather than reading as two
    /// different meters.
    public static let segmentBodyAttenuation: Double = 0.70

    /// MX3 (Kyle, Oct 2026): how much of `tickOff` a Full *unlit* cell keeps. Fourteen unlit
    /// tiles at full `tickOff` were as loud as the dimmed trail, so the row read as a grid; at
    /// 0.70 the lit run reads as the meter and the empties as its scale. Micro's five cells keep
    /// `tickOff` as is.
    public static let fullUnlitCellScale: Double = 0.70

    /// MX2 (Kyle, Oct 2026): Full Fade's start — the fill's own hue, `fullRampChromaScale` of
    /// its chroma, `fullRampLightnessShift` toward the card — eased out by `fullRampEasing`.
    /// Tuned side by side against the old surface-weighted ramp in the options doc.
    public static let fullRampLightnessShift: Double = 0.14
    public static let fullRampChromaScale: Double = 0.65
    public static let fullRampEasing: Double = 1.3

    /// MX4 (Kyle, Oct 2026): Full Machined's well is lit from above instead of outlined — a
    /// shade under the top edge, a faint lip along the bottom, and a hairline that only holds
    /// the edge. Micro Machined keeps `wellShadow`'s outline; at 6pt the shading is invisible.
    public static func wellTopShade(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .black, opacity: dark ? 0.55 : 0.16)
    }

    public static func wellBottomLip(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .white, opacity: dark ? 0.06 : 0.55)
    }

    public static func wellHairline(dark: Bool) -> PacemarkTint {
        PacemarkTint(color: .black, opacity: dark ? 0.35 : 0.06)
    }

    /// R2C18: the dim a *flat* (non-tip) severity fill takes in dark — the continuous Solid
    /// bar and the segmented body's severity cell. These two numbers were untokenised inline
    /// literals in `MeterGauge.flatSeverityColor`; they belong beside
    /// `segmentBodyAttenuation`, which is the same idea one layer up. Critical keeps more of
    /// itself (0.95) than the other bands (0.85) because it is the one fill the card is
    /// trying to draw attention to. Light takes no dim.
    public static func flatFillAttenuation(for severity: UsageSeverity, dark: Bool) -> Double {
        guard dark else { return 1 }
        return severity == .critical ? 0.95 : 0.85
    }

    /// PB13: the quarter-mark hairline. The base is the system primary label at the SwiftUI
    /// edge, the per-scheme number lives here.
    public static func quarterMarkOpacity(dark: Bool) -> Double {
        dark ? 0.11 : 0.14
    }

    /// Ghost uses the current severity fill at deliberately low contrast.
    public static func ghostBodyOpacity(for severity: UsageSeverity, dark: Bool) -> Double {
        switch (dark, severity) {
        case (true, .critical): 0.22
        case (true, _): 0.18
        case (false, .critical): 0.34
        case (false, _): 0.30
        }
    }
}

/// The rendered size of one brand mark's *ink*, in points.
public struct PacemarkBrandMarkSize: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum PacemarkBrandMark {
    /// The ink's larger dimension as a fraction of the slot *before* mass correction: 13pt of
    /// ink in the card's 15pt mark slot. That is what the accepted Claude/Codex rendering
    /// already measured at, so it is the rule the other two marks are brought onto rather
    /// than a new look.
    public static let inkFraction: Double = 13.0 / 15.0

    /// Per-provider shape-mass tuning, applied on top of `inkFraction`.
    ///
    /// This is the dial the rule's own comment predicted: equal ink *boxes* are not equal ink
    /// *mass*. The OpenAI Blossom covers about 37% of its square, close to Claude's 42%.
    /// Cursor's cube covers 56%, and Grok's hairline slash covers 25%.
    ///
    /// PA9 (Sep 2026): first correction pass, weighting each mark against its coverage —
    /// the sparse marks grow, the dense ones shrink. These are starting values; live
    /// `--demo multi-4` captures in both appearances are what settles them.
    ///
    /// Grok 1.10 → 1.20 (Sep 2026): its slash tails take 24% of the ink width, so at 1.10
    /// the ring — what the eye reads as the mark — measured ~10.8pt and
    /// read a size smaller. At 1.20 the ring lands at ~11.8pt and the hairline tails
    /// overhang the 15pt slot by ~0.3pt a side.
    ///
    /// Claude 1.05 → 1.00, Cursor 0.94 → 1.03 (Sep 2026): scored in the centred 15pt slot as
    /// the geometric mean of √(ink box) and √(ink area) — box alone overrates sparse marks,
    /// area alone overrates dense ones — the four read Claude 11.6, Codex 11.1, Grok 11.2,
    /// Cursor 10.2. Coverage alone had pushed Cursor down, but its cube is also the narrowest
    /// box (0.88 aspect), so it read a size small.
    public static func massCorrection(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 1.00
        case ProviderID.codex.raw: 1.08
        case ProviderID.grok.raw: 1.20
        case ProviderID.cursor.raw: 1.03
        // Copilot 1.14 → 1.00 (Nov 2026): its box is 1.20 wide, so at 1.14 the ink spanned
        // 14.8pt of the 15pt slot and sat ~2pt nearer its title than the other marks, which
        // read as a cramped gap in the live five-provider popover. At 1.00 it is 13pt wide,
        // Claude's width, and the gap matches theirs.
        case ProviderID.copilot.raw: 1.00
        // OpenCode 1.00 (Nov 2026): a solid 4:5 block, ~0.74 alpha-weighted coverage (the
        // frame plus its translucent inner block) in a box only 0.8 as wide.
        // Scored like Claude and Cursor above, it reads level with Codex and
        // Cursor at 1.00, and its 10.4pt width leaves a wider title gap than Claude's, never
        // the cramped one Copilot had.
        case ProviderID.opencode.raw: 1.00
        // Antigravity 1.00: an arch wider than it is tall, ~0.37 coverage, so
        // like Copilot it scores a little under Claude by optical size. At 1.00 it is 13pt
        // wide, Claude's width, which keeps the title gap level with the other marks.
        case ProviderID.antigravity.raw: 1.00
        default: 1.0
        }
    }

    /// The fraction of the slot the mark's ink should occupy along its larger dimension.
    public static func inkScale(for providerID: String) -> Double {
        inkFraction * massCorrection(for: providerID)
    }

    public static func inkAspect(for providerID: String) -> Double {
        switch providerID {
        case ProviderID.claude.raw: 1.0
        case ProviderID.codex.raw: 1.0
        // Grok's slash is wider than it is tall; Cursor's cube is taller than it is wide.
        // Neither is padded back to square — the slot's leftover splits either side.
        case ProviderID.grok.raw: 24.0 / 23.0332
        case ProviderID.cursor.raw: 21.0586 / 24.0
        // Copilot's head is wider than it is tall.
        case ProviderID.copilot.raw: 24.0 / 20.03
        // OpenCode's block is a 4:5 portrait (its official 240 × 300 artboard is all ink).
        case ProviderID.opencode.raw: 240.0 / 300.0
        case ProviderID.antigravity.raw: 24.0 / 22.1087
        default: 1.0
        }
    }

    /// The mark's rendered ink size inside a square `slot`: the larger dimension is
    /// `inkScale × slot`, the other follows from `inkAspect`, and the aspect is preserved.
    public static func markSize(for providerID: String, slot: Double) -> PacemarkBrandMarkSize {
        let ink = slot * inkScale(for: providerID)
        let aspect = inkAspect(for: providerID)
        guard aspect.isFinite, aspect > 0 else {
            return PacemarkBrandMarkSize(width: ink, height: ink)
        }
        return aspect >= 1
            ? PacemarkBrandMarkSize(width: ink, height: ink / aspect)
            : PacemarkBrandMarkSize(width: ink * aspect, height: ink)
    }
}

/// Scheme-paired usage fills and inks. Critical status sentences use their own ink.
public enum PacemarkSeverityColorValues {
    public static func healthy(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 0.20, green: 0.78, blue: 0.35) : PacemarkRGBColor(red: 0.09, green: 0.52, blue: 0.22)
    }

    public static func low(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 1.00, green: 0.62, blue: 0.04) : PacemarkRGBColor(red: 0.70, green: 0.41, blue: 0.00)
    }

    /// Usage numerals need more contrast than the bar fill.
    public static func criticalText(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 1, green: 127.0 / 255, blue: 116.0 / 255)
            : PacemarkRGBColor(red: 138.0 / 255, green: 20.0 / 255, blue: 16.0 / 255)
    }

    /// Provider refusals, limit-reached sentences and spend alerts retain their existing ink.
    public static func statusCriticalText(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 1.00, green: 0.40, blue: 0.35)
            : PacemarkRGBColor(red: 0.82, green: 0.14, blue: 0.11)
    }

    // Light green and amber use their deeper ink values as fills under Increase Contrast.
    public static func healthyFill(dark: Bool, increasedContrast: Bool) -> PacemarkRGBColor {
        guard !dark else { return healthy(dark: true) }
        return increasedContrast
            ? healthy(dark: false)
            : PacemarkRGBColor(red: 0.16, green: 0.66, blue: 0.30)
    }

    /// R2C4a: the light default darkened `oklch(0.700 0.166 58.3)` → `oklch(0.660 0.166
    /// 58.3)`, hue and chroma untouched. A severity ramp that is not monotonic does not
    /// encode severity, and this one ran backwards: light `lowFill` measured |Lc| 53.4/51.0
    /// against the card while `healthyFill` measured 57.2/54.8, so "running low" was quieter
    /// than "you're fine" on the same row. It now reads 59.4/57.0 — above healthy, below
    /// critical — and both pinned floors improve with it (vs track 2.06 → 2.48:1, vs card
    /// 2.71 → 3.27:1).
    public static func lowFill(dark: Bool, increasedContrast: Bool) -> PacemarkRGBColor {
        guard !dark else { return low(dark: true) }
        return increasedContrast
            ? low(dark: false)
            : PacemarkRGBColor(red: 0.856, green: 0.450, blue: 0.000)
    }

    public static func criticalFill(dark: Bool, increasedContrast: Bool) -> PacemarkRGBColor {
        guard dark else {
            return PacemarkRGBColor(red: 165.0 / 255, green: 28.0 / 255, blue: 23.0 / 255)
        }
        return increasedContrast
            ? PacemarkRGBColor(red: 232.0 / 255, green: 72.0 / 255, blue: 61.0 / 255)
            : PacemarkRGBColor(red: 214.0 / 255, green: 58.0 / 255, blue: 48.0 / 255)
    }
}
