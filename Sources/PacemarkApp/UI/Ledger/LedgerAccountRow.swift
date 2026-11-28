#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct LedgerAccountRow: View {
    let entry: ProviderAccountEntry
    let identity: DesktopAccountIdentity
    let recipe: LedgerRowRecipe
    var showsPlan = true
    let showsPrimaryLabel: Bool
    let percentageMode: UsagePercentageMode
    let now: Date
    let actions: LedgerAccountActions?
    var capabilityMessage: String?
    var isExpanded = false
    var toggleExpansion: ((AccountKey) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accountTitleInk) private var titleInk
    @Environment(\.loadingDate) private var pinnedDate
    @State private var hovering = false
    @State private var connected = false

    private var account: ProviderAccount { entry.account }
    private var snapshot: UsageSnapshot { entry.snapshot }

    private var pinsCreditTip: Bool {
        account.isBuiltIn && account.providerID == .codex && ProcessInfo.processInfo.arguments.contains("--qa-bank-tip")
    }

    var body: some View {
        let _ = BenchCounters.hit("LedgerAccountRow")
        let recovery = recovery
        let message = recovery.message ?? recipe.message
        let showsDetails = isExpanded && recipe.canExpand
        VStack(spacing: .zero) {
            HStack(spacing: LedgerMetrics.rowGap) {
                accountName(dimmed: recipe.isDimmed && recovery.message == nil,
                            showsStale: recipe.isDimmed && message == nil)
                    .frame(maxWidth: message == nil ? .infinity : 86, alignment: .leading)
                if let message {
                    HStack(spacing: PDS.Space.xs) {
                        status(message, waitingStart: recovery.waitingStart)
                        recoveryActions(recovery)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    readingColumn {
                        if !showsDetails, let window = recipe.primary {
                            reading(window, showsLabel: showsPrimaryLabel, showsInlineReset: false)
                        } else {
                            Color.clear.frame(height: 0).accessibilityHidden(true)
                        }
                    }
                    .layoutPriority(1)
                }
            }
            .frame(height: LedgerMetrics.accountContentHeight)
            if showsDetails {
                VStack(spacing: .zero) {
                    ForEach(recipe.windows, id: \.value.window.kind) { window in
                        detailRow(window)
                    }
                }
                .transition(PacemarkMotion.fade(PacemarkMotion.settle, reduceMotion: reduceMotion))
            }
        }
        .contentShape(Rectangle())
        .background(.primary.opacity(hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 5))
        .onHover { entered in
            withAnimation(PacemarkMotion.resolved(
                entered ? PacemarkMotion.rowHoverIn : PacemarkMotion.rowHoverOut, .crossfade,
                reduceMotion: reduceMotion
            )) { hovering = entered }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(identity.title) account")
        .accessibilityHint(recipe.accessibilityHint ?? "")
        .contextMenu {
            if entry.kind.offersRetry, let actions {
                if actions.canMakeMain(account.key) {
                    Button("Make Main") { actions.makeMain(account.key) }
                }
                Button("Refresh This Account") { actions.retry(account.key) }
            }
            if let actions { Button("Settings…", action: actions.settings) }
        }
        .onChange(of: SetupSessions.state(for: account), initial: true) {
            guard actions != nil, !entry.isRemembered else { return }
            SetupSessions.announceFailureIfNeeded(for: account)
            guard let claim = SetupSessions.claimConnectedPayoff(for: account) else { return }
            connected = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                withAnimation(PacemarkMotion.resolved(PacemarkMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                    connected = false
                }
                SetupSessions.settle(for: account, connectedPayoffClaim: claim)
            }
        }
        .overlay(alignment: .topTrailing) {
            if message == nil, !showsDetails, let window = recipe.primary {
                resetCell(window)
                    .frame(height: LedgerMetrics.accountContentHeight)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func accountName(dimmed: Bool, showsStale: Bool) -> some View {
        if recipe.canExpand, let toggleExpansion {
            Button {
                withAnimation(PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion)) {
                    toggleExpansion(account.key)
                }
            } label: {
                accountNameLabel(hasDisclosure: true, dimmed: dimmed, showsStale: showsStale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows all quota windows")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        } else {
            accountNameLabel(hasDisclosure: false, dimmed: dimmed, showsStale: showsStale)
        }
    }

    private func accountNameLabel(hasDisclosure: Bool, dimmed: Bool, showsStale: Bool) -> some View {
        HStack(spacing: LedgerMetrics.nameGap) {
            Group {
                if hasDisclosure {
                    Image(systemName: "chevron.right")
                        .font(PDS.Typography.caps)
                        .foregroundStyle(PDS.Ink.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .frame(width: LedgerMetrics.disclosureWidth)
            .accessibilityHidden(true)
            nameLine(dimmed: dimmed, showsStale: showsStale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func nameLine(dimmed: Bool, showsStale: Bool) -> some View {
        HStack(spacing: LedgerMetrics.nameGap) {
            Text(identity.title)
                .font(PopoverLedgerType.name).kerning(-0.1)
                .foregroundStyle(nameInk(dimmed: dimmed))
                .truncationMode(identity.isEmailTitle ? .middle : .tail)
                .lineLimit(1)
                .layoutPriority(identity.isEmailTitle ? 0 : 1)
            if connected { LedgerChip(text: "Connected", icon: "checkmark", outlined: true) }
            if showsStale { LedgerChip(text: "Stale").fixedSize() }
            if showsPlan, let plan = PlanLabelPresentation.displayName(snapshot.planLabel, provider: account.providerID) {
                LedgerChip(text: plan).fixedSize().layoutPriority(2)
            }
            if !isExpanded, let window = recipe.primary, let count = window.bankedResets {
                bankedChip(count).padding(.leading, PDS.Space.s - LedgerMetrics.nameGap)
                    .pdsHoverTip(BankedCreditDetails.tip(count: count, details: snapshot.bankedCreditDetails, now: now),
                                 pinned: pinsCreditTip)
            }
        }
    }

    private func nameInk(dimmed: Bool) -> Color {
        if dimmed { return PDS.Ink.inkTertiary }
        if titleInk == .brand {
            return ProviderStyle.accountTitleInk(for: account.providerID, ink: titleInk, scheme: scheme)
        }
        return .primary
    }

    @ViewBuilder private func status(_ message: String, waitingStart: Date?) -> some View {
        if let start = waitingStart {
            TimelineView(.periodic(from: start, by: 1)) { tick in
                let elapsed = max(0, (pinnedDate ?? tick.date).timeIntervalSince(start))
                statusText("\(message) · \(LedgerStatusClock.text(elapsed))")
            }
        } else {
            statusText(message)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(PopoverLedgerType.sentence)
            .foregroundStyle(PDS.Ink.inkTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recoveryActions(_ recovery: Recovery) -> some View {
        HStack(spacing: PDS.Space.xs) {
            if let first = recovery.chips.first {
                Button(actionLabel(first)) { perform(first) }
                    .buttonStyle(SetupChipButtonStyle(size: .small))
                    .accessibilityLabel(first.label)
                    .pdsHoverTip(first.label)
            }
            if recovery.canContinue {
                Button("Continue Setup") { SetupSessions.continueSetup(for: account) }
                    .buttonStyle(SetupChipButtonStyle(size: .small))
            }
            if recovery.canOpenTerminal {
                Button("Open Terminal") { _ = SetupSessions.showTerminal(for: account) }
                    .buttonStyle(SetupChipButtonStyle(size: .small))
            }
            if recovery.chips.count > 1 {
                Menu {
                    ForEach(recovery.chips.dropFirst()) { chip in
                        Button(chip.label) { perform(chip) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 18, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(identity.title)")
            }
            if recovery.canStop { StopWaitingButton(account: account, style: .glyph) }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actionLabel(_ chip: SetupRowChip) -> String {
        switch chip {
        case .recovery(.openClaudeWorkspace, _), .recovery(.openCursorWorkspace, _): "Open Workspace"
        case .recovery(.showPrivacyGuidance, _): "Privacy Help"
        default: chip.label
        }
    }

    private func detailRow(_ window: LedgerRowRecipe.Window) -> some View {
        HStack(spacing: LedgerMetrics.rowGap) {
            Text(window.detailLabel.uppercased())
                .font(PopoverLedgerType.column).tracking(0.35)
                .foregroundStyle(PDS.Ink.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count = window.bankedResets { bankedChip(count) }
            if let passedReset = window.passedReset {
                readingColumn {
                    Text(passedReset)
                        .font(PopoverLedgerType.sentence)
                        .foregroundStyle(PDS.Ink.inkSecondary)
                        .lineLimit(1)
                }
            } else {
                reading(window, showsLabel: false)
            }
        }
        .padding(.leading, PDS.Space.l)
        .frame(height: LedgerMetrics.detailRowHeight)
    }

    private func bankedChip(_ count: Int) -> some View {
        LedgerChip(text: count < 100 ? count.formatted() : "99+", icon: "arrow.counterclockwise",
                   outlined: true, compact: true)
            .monospacedDigit().fixedSize()
    }

    private func readingColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: LedgerMetrics.rowGap) {
            Color.clear.frame(width: LedgerMetrics.readingWidth, height: 1)
        }
        .frame(height: LedgerMetrics.accountContentHeight)
        .overlay(alignment: .trailing, content: content)
    }

    private func reading(_ window: LedgerRowRecipe.Window, showsLabel: Bool, showsInlineReset: Bool = true) -> some View {
        let muted = recipe.isDimmed || !window.value.window.freshness.isLive
        let percentage = window.value.displayedPercentage
        let tier = window.pace?.tier
        let amount = percentage.map { "\($0) percent \(percentageMode == .used ? "used" : "left")" } ?? "no reading"
        let spokenReading = [
            window.detailLabel, amount, tier?.label.lowercased(), window.countdown.map(Countdown.spokenReset),
            window.bankedResets.map { BankedCreditDetails.tip(count: $0, details: snapshot.bankedCreditDetails, now: now) }
        ].compactMap { $0 }.joined(separator: ", ")
        return HStack(spacing: LedgerMetrics.rowGap) {
            if showsLabel {
                VStack(spacing: PDS.Space.xs) {
                    Text(window.column.uppercased()).font(PopoverLedgerType.column)
                        .foregroundStyle(PDS.Ink.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.66)
                        .frame(width: LedgerMetrics.paceWidth, alignment: .leading)
                    paceBar(window, dimmed: muted)
                }
            } else {
                paceBar(window, dimmed: muted)
            }
            Text(percentage.map { "\($0)%" } ?? "—")
                .font(PopoverLedgerType.value)
                .foregroundStyle(muted ? PDS.Ink.inkTertiary :
                    LedgerInk.usage(tier, fallback: UsageMeterReading(window: window.value.window).severity, scheme: scheme))
                .contentTransition(PacemarkMotion.numericText(value: Double(percentage ?? 0), reduceMotion: reduceMotion))
                .animation(PacemarkMotion.resolved(PacemarkMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                           value: percentage)
                .frame(width: LedgerMetrics.percentageWidth, alignment: .trailing)
            if showsInlineReset {
                resetCell(window)
            } else {
                Color.clear.frame(width: LedgerMetrics.resetWidth, height: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReading)
    }

    private func resetCell(_ window: LedgerRowRecipe.Window) -> some View {
        HStack(spacing: PDS.Space.xs) {
            Text(window.countdown == "resets now" ? "now" : window.countdown ?? "—")
                .font(PopoverLedgerType.countdown).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(PDS.Ink.inkTertiary)
                .ledgerResetHelp(deadline: window.resetDeadline, window: window.value.window, now: now)
        }
        .frame(width: LedgerMetrics.resetWidth, alignment: .trailing)
    }

    private func paceBar(_ window: LedgerRowRecipe.Window, dimmed: Bool) -> some View {
        let remaining = window.value.displayedPercentage == nil ? 0 : window.value.window.percentRemaining / 100
        let severity = UsageMeterReading(window: window.value.window).severity ?? .healthy
        return LedgerPaceBar(remaining: remaining, pace: window.pace, severity: severity,
                             dimmed: dimmed, mode: window.value.displayedPercentage == nil ? .remaining : percentageMode)
    }

    private struct Recovery {
        var message: String? = nil
        var chips: [SetupRowChip] = []
        var waitingStart: Date? = nil
        var canContinue = false
        var canOpenTerminal = false
        var canStop = false
    }

    private var recovery: Recovery {
        guard actions != nil, !entry.isRemembered else { return Recovery() }
        let state = SetupSessions.state(for: account)
        if let refusal = setupHandoffRefusalMessage(for: state) {
            return Recovery(message: refusal, canStop: setupSessionOffersStopWaiting(for: account))
        }
        if case .blockedByProviderLogin = state {
            return Recovery(message: "Another \(account.providerID.displayName) sign-in is open",
                            canContinue: true)
        }
        if let phase = SetupSessions.waitingPhase(for: account) {
            let isOpen = SetupSessions.hasActiveHandoff(for: account)
            return Recovery(
                message: isOpen ? "Waiting in Terminal" : phase.copy.title,
                waitingStart: isOpen ? SetupSessions.waitingStart(for: account) : nil,
                canOpenTerminal: isOpen, canStop: setupSessionOffersStopWaiting(for: account)
            )
        }
        let failure = SetupSessions.failureMessage(for: account)
        if failure == nil, snapshot.freshness == .pending, let capabilityMessage {
            return Recovery(message: capabilityMessage)
        }
        let plan = snapshot.planStatusRecovery
        let reason: FailureReason? = if case .stale(let reason) = snapshot.freshness,
            reason.isPermanent || reason.providerSetupOutcome == .opencodeFormatChanged
                || (reason.providerSetupOutcome != nil && snapshot.windows.isEmpty) { reason } else { nil }
        let outcome = reason.flatMap { presentedSetupOutcome(for: $0, providerID: account.providerID) }
        guard let fullMessage = failure ?? plan?.status ?? outcome?.message ?? reason?.message else { return Recovery() }
        let message: String = if failure == nil, plan?.primaryAction == .seeOpenCodeGoPlans {
            "No Go plan"
        } else if failure == nil, let outcome {
            switch outcome {
            case .claudeTrustRequired, .cursorTrustRequired: "Approve workspace"
            case .opencodeUpdateRequired: "Requires OpenCode 2.2+"
            default: fullMessage
            }
        } else {
            fullMessage
        }
        let chips = capabilityMessage != nil && failure == nil && plan == nil ? [] : setupRowChips(
            state: state, presentation: plan ?? outcome?.recoveryPresentation, hasFailureMessage: failure != nil
        )
        return Recovery(message: message, chips: chips, canStop: setupSessionOffersStopWaiting(for: account))
    }

    private func perform(_ chip: SetupRowChip) {
        performSetupRowChip(chip, for: account) { actions?.retry(account.key) }
    }
}

extension View {
    @ViewBuilder
    func ledgerResetHelp(deadline: Date?, window: UsageWindow, now: Date) -> some View {
        if let deadline, let text = Countdown.resetClockText(deadline: deadline, windowName: window.displayLabel ?? window.kind.spokenName, now: now) {
            self.pdsHoverTip(text)
        } else {
            self
        }
    }
}

struct LedgerAccountActions {
    let retry: (AccountKey) -> Void
    let canMakeMain: (AccountKey) -> Bool
    let makeMain: (AccountKey) -> Void
    let settings: () -> Void
}

enum LedgerStatusClock {
    static func text(_ elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

enum LedgerInk {
    static func usage(_ tier: MenuBarPace.Tier?, fallback: UsageSeverity?, scheme: ColorScheme) -> Color {
        let severity = if let tier { tier.isOffPace ? tier.severity : .healthy } else { fallback }
        return switch severity {
        case .low: PDS.Ink.paceWarning(scheme)
        case .critical: PDS.Ink.paceCritical(scheme)
        case .healthy: .primary
        case nil: PDS.Ink.inkTertiary
        }
    }
}
