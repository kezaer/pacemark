import SwiftUI
#if SWIFT_PACKAGE
import PacemarkCore
#elseif canImport(PacemarkCore)
import PacemarkCore
#endif

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
public enum ProviderStyle {
    /// Claude keeps its brand colour. Ink marks follow the surface appearance.
    public static func svgResourceName(for id: ProviderID, scheme: ColorScheme) -> String? {
        switch id {
        case .claude: return "claude-color"
        case .codex: return scheme == .dark ? "codex-dark" : "codex-light"
        case .grok: return scheme == .dark ? "grok-dark" : "grok-light"
        case .cursor: return scheme == .dark ? "cursor-dark" : "cursor-light"
        case .copilot: return scheme == .dark ? "copilot-dark" : "copilot-light"
        case .opencode: return scheme == .dark ? "opencode-dark" : "opencode-light"
        case .antigravity: return scheme == .dark ? "antigravity-dark" : "antigravity-light"
        default: return nil
        }
    }

    public static func accent(for id: ProviderID) -> Color {
        switch id {
        case .claude: return Color(PacemarkBrandColorValues.claude)
        case .codex: return .primary
        case .grok: return Color(PacemarkBrandColorValues.grok)
        case .cursor: return Color(PacemarkBrandColorValues.cursor)
        case .copilot: return Color(PacemarkBrandColorValues.copilot)
        case .opencode: return Color(PacemarkBrandColorValues.opencode)
        case .antigravity: return Color(PacemarkBrandColorValues.antigravity)
        default: return .secondary
        }
    }

    public static func textAccent(for id: ProviderID, scheme: ColorScheme) -> Color {
        guard let rgb = PacemarkColorValues.textAccent(for: id.raw, dark: scheme == .dark) else {
            return .primary
        }
        return Color(rgb)
    }

    public static func secondaryText(scheme: ColorScheme) -> Color {
        let tint = PacemarkColorValues.secondaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    public static func tertiaryText(scheme: ColorScheme) -> Color {
        let tint = PacemarkColorValues.tertiaryText(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    public static func accountTitleInk(for id: ProviderID, ink: AccountTitleInk, scheme: ColorScheme) -> Color {
        switch ink {
        case .neutral: return accountTitleInk(scheme: scheme)
        case .brand: return textAccent(for: id, scheme: scheme)
        }
    }

    /// T1A: the neutral grey on its own. Kept for surfaces that are not account titles and
    /// for the `.neutral` branch above.
    public static func accountTitleInk(scheme: ColorScheme) -> Color {
        let tint = PacemarkColorValues.accountTitle(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// PA13: the plan pill's ink. It used to be the system `.tertiary`, which measured
    /// |Lc| ≈ 20 on the dark card against ≈ 40 in light — the plan name is the only thing
    /// saying which subscription a meter measures, so it now has a token that reads the same
    /// in both appearances. See `PacemarkColorValues.planLabel`.
    public static func planLabelInk(scheme: ColorScheme) -> Color {
        color(PacemarkColorValues.planLabel(dark: scheme == .dark))
    }

    public static func barTrack(scheme: ColorScheme) -> Color {
        let tint = PacemarkColorValues.barTrack(dark: scheme == .dark)
        return Color(tint.color).opacity(tint.opacity)
    }

    /// R2C15: the track carries the critical hue the shrinking fill no longer can. Every
    /// other severity keeps the neutral track. See `PacemarkMeterColorValues.criticalBarTrack`.
    public static func barTrack(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        guard severity == .critical else { return barTrack(scheme: scheme) }
        return Color(PacemarkMeterColorValues.criticalBarTrack(dark: scheme == .dark))
    }

    public static func meterLabelInk(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.labelInk(dark: scheme == .dark))
    }

    public static func meterCountdownInk(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.countdownInk(dark: scheme == .dark))
    }

    public static func meterGlassA(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.glassA(dark: scheme == .dark))
    }

    public static func meterGlassB(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.glassB(dark: scheme == .dark))
    }

    public static func meterGlassRim(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.glassRim(dark: scheme == .dark))
    }

    public static func meterWellBackground(scheme: ColorScheme) -> Color {
        Color(PacemarkMeterColorValues.wellBackground(dark: scheme == .dark))
    }

    public static func meterWellShadow(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.wellShadow(dark: scheme == .dark))
    }

    public static func meterWellTopShade(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.wellTopShade(dark: scheme == .dark))
    }

    public static func meterWellBottomLip(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.wellBottomLip(dark: scheme == .dark))
    }

    public static func meterWellHairline(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.wellHairline(dark: scheme == .dark))
    }

    public static func meterTickOff(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.tickOff(dark: scheme == .dark))
    }

    public static func meterTickGlass(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.tickGlass(dark: scheme == .dark))
    }

    public static func meterTickGlassCap(scheme: ColorScheme) -> Color {
        color(PacemarkMeterColorValues.tickGlassCap(dark: scheme == .dark))
    }

    /// R2C16: the `.stale` fill keeps its severity's lightness and hue at reduced chroma
    /// instead of collapsing to the system secondary grey — a stale critical is still a
    /// critical. See `PacemarkMeterColorValues.staleFill`.
    public static func meterStaleFill(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(PacemarkMeterColorValues.staleFill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    /// R2C18: the recessed well shared by the setup flow's command wells and the Settings
    /// preview wells. The Settings panes reached this through `ClaudeSetupStyle.wellBackground`
    /// — a Claude-branded token owning a pane with no Claude in it. Same value, one home.
    public static func recessedWell(dark: Bool) -> Color {
        color(PacemarkColorValues.recessedWell(dark: dark))
    }

    /// R2C18: the setup flow's quiet-chip label ink, shared with the neutral text bases.
    public static func setupChipInk(dark: Bool) -> Color {
        color(PacemarkColorValues.setupChipInk(dark: dark))
    }

    // MARK: - R2C18: brand-ramp bridges for the two setup flows
    //
    // `ClaudeSetupStyle` / `CodexSetupStyle` stay the setup views' call surface (the two
    // provider flows are deliberately decoupled), but every number they draw now comes from
    // the one constant-hue ramp in `PacemarkBrandRamp`. These take `dark:` rather than a
    // `ColorScheme` because that is what the setup styles already resolve.

    public static func claudeCTATop(dark: Bool) -> Color {
        Color(PacemarkBrandRamp.claudeCTATop(dark: dark))
    }

    public static func claudeCTABottom(dark: Bool) -> Color {
        Color(PacemarkBrandRamp.claudeCTABottom(dark: dark))
    }

    public static func codexCTATop(dark: Bool) -> Color {
        Color(PacemarkBrandRamp.codexCTATop(dark: dark))
    }

    public static func codexCTABottom(dark: Bool) -> Color {
        Color(PacemarkBrandRamp.codexCTABottom(dark: dark))
    }

    public static func connectedInk(dark: Bool) -> Color {
        Color(PacemarkBrandRamp.connectedInk(dark: dark))
    }

    /// The "Connected" chip's fill: the healthy severity token at 0.12, the tint its ink is
    /// offset from (R2C18). Shared so the identity row's chip needs no setup-view import.
    public static func connectedBackground(dark: Bool) -> Color {
        Color(PacemarkSeverityColorValues.healthy(dark: dark)).opacity(0.12)
    }

    /// PB13: the quarter-mark hairline, same split as `meterStaleFill`.
    public static func meterQuarterMark(scheme: ColorScheme) -> Color {
        Color.primary.opacity(PacemarkMeterColorValues.quarterMarkOpacity(dark: scheme == .dark))
    }

    /// R2C12: the ramp's gradient stops. Three, not two — SwiftUI interpolates a two-colour
    /// gradient in its own space, so the explicit middle stop is what holds the drawn bar on
    /// the OKLCH path the recipe computed. See `MeterRampStops.color(at:)`.
    ///
    /// MX2: Full draws its softer, eased ramp, which needs more than one middle stop to hold
    /// its curve — `gradientSamples` supplies them. Micro's linear ramp is unchanged.
    public static func meterRampColors(
        for severity: UsageSeverity,
        format: GaugeFormat,
        surface: MeterRampSurface,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> [Color] {
        MeterRecipe.rampStops(
            format: format,
            severity: severity,
            scheme: scheme == .dark ? .dark : .light,
            surface: surface,
            increasedContrast: increasedContrast
        ).gradientSamples.map { Color($0) }
    }

    public static func meterGhostBody(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        severityFill(for: severity, scheme: scheme, increasedContrast: increasedContrast)
            .opacity(
                PacemarkMeterColorValues.ghostBodyOpacity(
                    for: severity,
                    dark: scheme == .dark
                )
            )
    }

    /// Semantic fill for a usage bar by health band (UI-01). A static three-stop ramp —
    /// green → amber → red — chosen over the brand accent because Claude's warm clay is
    /// too close to amber to read as "warning". Brand identity stays in the logo + plan
    /// pill; the bar's job is to signal how much is left. No animation: a threshold, not
    /// a pulse, so it honors the standing no-pulsing rule.
    public static func severityColor(for severity: UsageSeverity, scheme: ColorScheme) -> Color {
        Color(PacemarkSeverityColorValues.color(for: severity, dark: scheme == .dark))
    }

    /// Meter fills for the current appearance. SwiftUI callers provide the
    /// `colorSchemeContrast` preference so the token remains testable in Core.
    public static func severityFill(
        for severity: UsageSeverity,
        scheme: ColorScheme,
        increasedContrast: Bool
    ) -> Color {
        Color(PacemarkSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        ))
    }

    public static func statusCriticalText(scheme: ColorScheme) -> Color {
        Color(PacemarkSeverityColorValues.statusCriticalText(dark: scheme == .dark))
    }

    public static func symbol(for id: ProviderID) -> String {
        switch id {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .grok: return "atom"
        case .cursor: return "cursorarrow"
        case .copilot: return "person.2"
        case .opencode: return "rectangle.portrait"
        case .antigravity: return "chevron.up"
        default: return "circle.dashed"
        }
    }

    private static func color(_ tint: PacemarkTint) -> Color {
        Color(tint.color).opacity(tint.opacity)
    }
}

private extension Color {
    init(_ rgb: PacemarkRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Account-title ink propagation (G1A)

/// The popover's account-title ink travels through the environment rather than through
/// every card/section initializer: `IdentityRow` is reached at three nesting depths (single
/// account, account section, spend row) and none of them already carry a display
/// preference, so threading one would add a parameter to four types to deliver a value that
/// only ever changes in Settings. The popover root and the Settings specimen are the only
/// two places that set it; everything below just reads it.
private struct AccountTitleInkKey: EnvironmentKey {
    static let defaultValue: AccountTitleInk = .neutral
}

public extension EnvironmentValues {
    var accountTitleInk: AccountTitleInk {
        get { self[AccountTitleInkKey.self] }
        set { self[AccountTitleInkKey.self] = newValue }
    }
}

/// Applies the resolved title ink for `providerID`, reading both the scheme and the user's
/// choice itself so a call site is a single modifier.
private struct AccountTitleInkStyle: ViewModifier {
    let providerID: ProviderID

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accountTitleInk) private var ink

    func body(content: Content) -> some View {
        content.foregroundStyle(ProviderStyle.accountTitleInk(for: providerID, ink: ink, scheme: scheme))
    }
}

public extension View {
    func accountTitleInk(for providerID: ProviderID) -> some View {
        modifier(AccountTitleInkStyle(providerID: providerID))
    }
}
