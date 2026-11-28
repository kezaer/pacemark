#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import AppKit
import PacemarkCore

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--qa-display") {
            MainActor.assumeIsolated { QALaunch.run() }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--dry-run-warm-up") {
            guard let name = CommandLine.arguments.dropFirst(index + 1).first else { exit(EXIT_FAILURE) }
            Task {
                let sender = WarmUpCLISender(claudeLocator: AppComposition.claudeExecutableLocator,
                                             antigravity: AppComposition.antigravityUsageSource as? AntigravityCLIUsageSource)
                guard let lines = await sender.diagnostic(for: ProviderID(name)) else {
                    print("Warm-up executable unavailable")
                    exit(EXIT_FAILURE)
                }
                lines.forEach { print($0) }
                exit(EXIT_SUCCESS)
            }
            RunLoop.main.run()
            return
        }
        if let capture = AppComposition.capturedDemoResult {
            if case .failure(let error) = capture {
                MainActor.assumeIsolated { DevCaptureCommand.showLoadFailure(error) }
                exit(EXIT_FAILURE)
            }
            PacemarkApp.main()
            return
        }
        if CommandLine.arguments.contains(DevCaptureCommand.flag), !DemoFixture.isEnabled {
            DevCaptureCommand.run()
        }
        if CommandLine.arguments.contains("--probe-claude") {
            runClaudeProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-codex") {
            runCodexProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-grok") {
            runGrokProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-cursor") {
            runCursorProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-copilot") {
            runCopilotProbe()
            return
        }
        if CommandLine.arguments.contains(OpenCodeLaunchArguments.probeFlag) {
            runOpenCodeProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-antigravity") {
            runAntigravityProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-spend") {
            runSpendProbe()
            return
        }
        if CommandLine.arguments.contains("--dump-session-reliability") {
            MainActor.assumeIsolated {
                print("bundle id: \(Bundle.main.bundleIdentifier ?? "none — unbundled diagnostics are not the installed app's state")")
                SessionReliabilityRecord(defaults: AppComposition.launchDefaults)
                    .diagnosticLines().forEach { print($0) }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-loading-preview") {
            let outDir = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1] : "loading-preview"
            MainActor.assumeIsolated { MiniPillPreviewHarness.run(outputDirectory: outDir) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(where: {
            $0 == "--render-menubar" || $0 == "--render-menubar-variants"
        }) {
            guard CommandLine.arguments.indices.contains(index + 1) else {
                FileHandle.standardError.write(Data("Expected --render-menubar <dir>\n".utf8))
                exit(EXIT_FAILURE)
            }
            do {
                try MainActor.assumeIsolated {
                    try MenuBarRenderHarness.run(outputDirectory: CommandLine.arguments[index + 1])
                }
            } catch {
                FileHandle.standardError.write(Data("Could not write menu bar previews: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(where: { ["--render-popover", "--render-design-system"].contains($0) }) {
            let outDir = CommandLine.arguments.indices.contains(index + 1)
                ? CommandLine.arguments[index + 1] : "popover-shots"
            MainActor.assumeIsolated { PopoverRenderHarness.run(outputDirectory: outDir) }
            return
        }
        if CommandLine.arguments.contains("--bench-ui") {
            // Offscreen perf bench: timings, frame-by-frame probes, and (with -DPACEMARK_BENCH)
            // view-body counts for the popover and Settings.
            MainActor.assumeIsolated { UIBenchHarness.run() }
            return
        }
        // `--demo <scenario>` (demo mode, Jul 2026): reject an unrecognized scenario before the
        // menu bar launches, mirroring the probe/render diagnostics above — a bare `--demo`
        // (single-account screenshot fixtures) still launches normally.
        if case .invalid(let token) = DemoFixture.scenarioRequest() {
            let valid = DemoFixture.MultiAccountScenario.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data("Unknown --demo scenario '\(token)'. Valid scenarios: captured, captured=<path>, \(valid)\n".utf8))
            exit(1)
        }
        if DemoFixture.isEnabled,
           let index = CommandLine.arguments.firstIndex(of: "--meter-style"),
           (!CommandLine.arguments.indices.contains(index + 1)
               || MeterStyle(launchToken: CommandLine.arguments[index + 1]) == nil) {
            FileHandle.standardError.write(Data(
                "Invalid --meter-style. Expected <format>.<shape>.<fill>, for example micro.chip.event.\n".utf8
            ))
            exit(1)
        }
        // Compatibility flag: --account-title-ink accepts either legacy value. The Ledger always uses neutral ink.
        if DemoFixture.isEnabled,
           let index = CommandLine.arguments.firstIndex(of: "--account-title-ink"),
           (!CommandLine.arguments.indices.contains(index + 1)
               || AccountTitleInk(rawValue: CommandLine.arguments[index + 1]) == nil) {
            let valid = AccountTitleInk.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data(
                "Invalid --account-title-ink. Expected one of: \(valid).\n".utf8
            ))
            exit(1)
        }
        // `--account-layout <standard|compact|ledger>`: seeds the popover account layout for demo
        // captures, validated like `--account-title-ink` above.
        if DemoFixture.isEnabled,
           let index = CommandLine.arguments.firstIndex(of: "--account-layout"),
           (!CommandLine.arguments.indices.contains(index + 1)
               || AccountLayout(rawValue: CommandLine.arguments[index + 1]) == nil) {
            let valid = AccountLayout.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data(
                "Invalid --account-layout. Expected one of: \(valid).\n".utf8
            ))
            exit(1)
        }
        if !DemoFixture.isEnabled, let running = SingleInstance.otherRunningCopy() {
            let path = running.bundleURL?.path ?? "another location"
            FileHandle.standardError.write(Data(
                "Pacemark is already running (pid \(running.processIdentifier), \(path)). Quit it first.\n".utf8
            ))
            exit(0)
        }
        PacemarkApp.main()
    }

    private static func runClaudeProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            // `--claude-config <dir>`: probe an alternate account home (multi-account
            // diagnostic) — exercises the same CLAUDE_CONFIG_DIR override the extra
            // accounts use in production.
            var overrides: [String: String] = [:]
            let accountCategory: ClaudeCapabilityDiagnosticAccount
            if let flagIndex = CommandLine.arguments.firstIndex(of: "--claude-config"),
               CommandLine.arguments.indices.contains(flagIndex + 1) {
                overrides["CLAUDE_CONFIG_DIR"] = CommandLine.arguments[flagIndex + 1]
                accountCategory = .extra
            } else {
                accountCategory = .builtIn
            }
            let location = await AppComposition.claudeExecutableLocator.locate()
            let versionBand = if let path = location.path {
                await ClaudeUsageCLIProbe.versionBand(
                    executablePath: path,
                    environmentOverrides: overrides
                )
            } else {
                ClaudeCLIVersionBand.unknown
            }
            let (result, trace) = await ClaudeUsageCLIProbe(
                locator: AppComposition.claudeExecutableLocator,
                workingDirectory: claudeWorkingDirectory(),
                environmentOverrides: overrides
            ).captureWithTrace()
            let events = await AppComposition.claudeExecutableLocator.recentDiagnosticEvents()
            ClaudeCapabilityDiagnostic.lines(
                account: accountCategory,
                versionBand: versionBand,
                outcome: diagnosticOutcome(for: result),
                events: events,
                trace: trace,
                signOutEvents: AppComposition.signOutRecord.events
            ).forEach { print($0) }

            switch result {
            case .cliNotFound:
                print("RESULT: CLI not found")
            case .cliInconclusive:
                print("RESULT: CLI discovery inconclusive")
            case .transientCapture:
                print("RESULT: capture failed (no panel text)")
            case .loginRequired:
                print("RESULT: login required (first-run screen — no account signed into this config home)")
            case .workspaceTrustRequired:
                print("RESULT: workspace trust required")
            case .startupQuestion:
                print("RESULT: Claude startup question before the prompt (no input sent)")
            case .unknownUI:
                print("RESULT: unrecognized Claude surface (no input sent)")
            case .panel(let text, let planHint):
                let capturedAt = Date()
                let windows = ClaudeUsageParser.parse(text)
                let plan = ClaudeUsageParser.plan(in: text) ?? planHint
                print("RESULT: parsed \(windows.count) window(s) plan=\(plan == nil ? "absent" : "present")")
                for w in windows {
                    let schedule = ClaudeResetNormalizer.schedule(
                        label: w.resetLabel,
                        timeZoneIdentifier: w.resetTimeZoneIdentifier,
                        kind: w.kind,
                        now: capturedAt
                    )
                    print("  • category=\(diagnosticWindowCategory(w.kind))  \(Int(w.percentUsed))% used  \(ResetDiagnostic.line(for: schedule, observedAt: capturedAt, now: capturedAt))")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func diagnosticOutcome(
        for result: ClaudePanelResult
    ) -> ClaudeCapabilityDiagnosticOutcome {
        switch result {
        case .panel: .available
        case .loginRequired: .loginRequired
        case .workspaceTrustRequired: .trustRequired
        case .startupQuestion: .startupQuestion
        case .cliNotFound: .confirmedAbsent
        case .cliInconclusive: .discoveryInconclusive
        case .transientCapture: .captureFailed
        case .unknownUI: .unknownSurface
        }
    }

    private static func diagnosticWindowCategory(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "five-hour"
        case .weekly: "weekly"
        case .billingPeriod: "billing-period"
        case .other: "other"
        }
    }

    fileprivate static func claudeWorkingDirectory() -> String {
        do {
            return try ClaudeUsageWorkspace.ensureDefaultDirectory().path
        } catch {
            return ClaudeUsageWorkspace.defaultDirectoryURL.path
        }
    }

    private static func runCodexProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            let provider: any UsageProvider
            if let index = CommandLine.arguments.firstIndex(of: "--codex-home") {
                guard CommandLine.arguments.indices.contains(index + 1) else {
                    print("RESULT: supply a folder after --codex-home")
                    return
                }
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                switch BorrowedHomeEnvironment.live(t3: T3Installation()).canonicalize(url) {
                case .failure(let reason):
                    print("RESULT: \(reason.message)")
                    return
                case .success(let path):
                    let home = BorrowedHome(path: path, source: .manual)
                    provider = CodexAppServerProvider(accountID: .borrowedHome(path), home: home)
                }
            } else {
                provider = CodexProvider(credentials: CredentialStore())
            }
            let snapshot = await provider.fetchSnapshot()
            switch snapshot.freshness {
            case .pending:
                print("RESULT: pending")
            case .live:
                print("RESULT: live Codex snapshot, parsed \(snapshot.windows.count) window(s):")
                if let plan = snapshot.planLabel {
                    print("  plan: \(plan)")
                }
                print("  \(snapshot.codexBankedResetProbeLine)")
                for window in snapshot.windows {
                    print("  • \(window.kind)  \(Int(window.utilization.rounded()))% used  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: Date()))  (remaining \(Int(window.percentRemaining.rounded()))%)")
                }
            case .stale(let reason):
                print("RESULT: stale Codex snapshot: \(reason.message)")
            }
        }
        semaphore.wait()
    }

    private static func runGrokProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            var overrides: [String: String] = [:]
            var authPath: URL?
            if let index = CommandLine.arguments.firstIndex(of: "--grok-home"),
               CommandLine.arguments.indices.contains(index + 1) {
                let home = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                overrides["GROK_HOME"] = home.path
                authPath = home.appendingPathComponent("auth.json")
                print("account home: isolated")
            } else {
                print("account home: built-in")
            }

            let source = GrokFallbackUsageSource(
                primary: GrokACPUsageSource(environmentOverrides: overrides),
                fallback: GrokHTTPUsageSource(authReader: GrokAuthFileReader(path: authPath))
            )
            let result = await source.fetchUsage()
            switch result {
            case .payload(let data, let transport):
                let snapshot = await GrokProvider(
                    source: CapturedGrokUsageSource(data: data, transport: transport),
                    // Identity from the same isolated auth.json the billing call used —
                    // never the built-in home when --grok-home targets another account.
                    emailSource: GrokCredentialEmailReader(
                        authReader: GrokAuthFileReader(path: authPath)
                    )
                ).fetchSnapshot()
                guard snapshot.freshness == .live else {
                    print("RESULT: Grok payload could not be parsed")
                    semaphore.signal()
                    return
                }
                print("RESULT: live Grok snapshot via \(transport.rawValue), parsed \(snapshot.windows.count) window(s):")
                if let plan = snapshot.planLabel { print("  plan: \(plan)") }
                for window in snapshot.windows {
                    print("  • \(window.kind.shortLabel)  \(Int(window.percentUsed.rounded()))% used  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: Date()))")
                }
            case .methodUnavailable:
                print("RESULT: Grok billing method unavailable and fallback was not attempted")
            case .cliNotFound:
                print("RESULT: Grok Build CLI not found")
            case .authAbsent:
                print("RESULT: login required")
            case .authPermissionDenied, .authUnsafePermissions, .authMalformed, .authIOFailure:
                print("RESULT: Grok sign-in file is unavailable")
            case .rejectedAuth:
                print("RESULT: Grok sign-in expired")
            case .failure(let reason):
                print("RESULT: Grok probe failed: \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// `--probe-opencode [--opencode-home <dir>]`: one usage read through the official client
    /// (KTD1). `<dir>` is an isolated home root holding `data`, `config`, `cache` and `state`;
    /// without it the built-in default home is read. Prints the parsed windows or the outcome
    /// name only: never a workspace ID, name or Console URL, an email, a token, raw output or
    /// anything inside the home. KTD18: a DEBUG build also takes `--opencode-executable
    /// <path>`, and only together with `--opencode-home`.
    private static func runOpenCodeProbe() {
        let arguments = CommandLine.arguments
        guard let target = OpenCodeLaunchArguments.probeTarget(arguments: arguments) else {
            print("Usage: --probe-opencode [--opencode-home <dir>]")
            return
        }
        print("account home: \(target.home == .builtIn ? "built-in" : "isolated")")
        if target.executable != nil {
            print("executable: override")
        } else if arguments.contains(OpenCodeLaunchArguments.executableFlag) {
            print(OpenCodeLaunchArguments.buildAllowsExecutableOverride
                ? "executable: resolved (override ignored: never used for the built-in home)"
                : "executable: resolved (override ignored: release build)")
        } else {
            print("executable: resolved")
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let source = target.executable.map { path in OpenCodeCLIUsageSource(resolveExecutable: { path }) }
                ?? OpenCodeCLIUsageSource()
            let capture = await source.capture(home: target.home)
            switch capture {
            case .goUsage:
                let snapshot = await OpenCodeProvider(
                    source: CapturedOpenCodeUsageSource(capture: capture),
                    home: target.home
                ).fetchSnapshot()
                print("RESULT: live OpenCode snapshot, parsed \(snapshot.windows.count) window(s):")
                for window in snapshot.windows {
                    let limited = window.isLimited ? "  limited" : ""
                    print("  • \(window.kind.shortLabel)  \(Int(window.percentUsed.rounded()))% used\(limited)  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: Date()))")
                }
            case .noGoPlan:
                print("RESULT: noGoPlan (signed in, no Go plan on the active workspace)")
            case .failed(let failure):
                let detail: String
                switch failure {
                case .formatChanged(let stage): detail = " (stage: \(stage.rawValue))"
                case .transient(let cause): detail = " (cause: \(cause.rawValue))"
                default: detail = ""
                }
                print("RESULT: \(failure.outcome)\(detail)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// `--probe-antigravity`: one read through the official `agy` CLI's no-turn `/usage` and
    /// `/credits` answers. Prints the parsed rows, the credits badge, or the outcome name with
    /// its stage or cause only: never raw output, stderr, an email or anything identifying.
    private static func runAntigravityProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let plan = AntigravityLaunchResolver(t3: T3Installation())
                .resolve(preference: Preferences().antigravitySourcePreference)
            let source = plan.map { $0.signInHome == .system ? "System agy CLI" : "T3 Code" }
            print("Antigravity source: \(source ?? "missing")")
            let capture = await AntigravityCLIUsageSource(
                resolveLaunch: { plan }, memory: .preferences(Preferences())
            ).capture()
            switch capture {
            case .usage:
                let snapshot = await AntigravityProvider(source: CapturedAntigravityUsageSource(capture: capture))
                    .fetchSnapshot()
                print("RESULT: live Antigravity snapshot, parsed \(snapshot.windows.count) window(s):")
                let formatter = ISO8601DateFormatter()
                for window in snapshot.windows {
                    let reset: String
                    if case .scheduled(let date) = window.resetSchedule {
                        reset = "resets \(formatter.string(from: date))"
                    } else {
                        reset = "no reset"
                    }
                    let remaining = String(format: "%.2f", 100 - window.utilization)
                    print("  • \(window.kind.shortLabel)  \(remaining)% remaining  \(reset)")
                }
                print("  credits badge: \(snapshot.planLabel ?? "none")")
            case .failed(let failure):
                let detail: String
                switch failure {
                case .formatChanged(let stage): detail = " (stage: \(stage.rawValue))"
                case .transient(let cause): detail = " (cause: \(cause.rawValue))"
                default: detail = ""
                }
                print("RESULT: \(failure.outcome)\(detail)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func runCursorProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        print("cursor-agent CLI: \(CursorUsageCLIProbe.resolveCursorPath() == nil ? "missing" : "available")")
        Task {
            switch await CursorUsageCLIProbe().capturePanel() {
            case .panel(let text):
                guard let parsed = CursorUsageParser.parse(text) else {
                    print("RESULT: Cursor usage panel could not be parsed")
                    semaphore.signal()
                    return
                }
                switch parsed.subscription {
                case .namedPools(let pools):
                    print("RESULT: live Cursor snapshot via official /usage panel")
                    print("  plan: \(parsed.planName)")
                    for pool in pools {
                        print("  • \(pool.label)  \(Int(pool.percentUsed.rounded()))% used  reset-evidence=scheduled")
                    }
                case .includedFallback(let percentUsed):
                    print("RESULT: live Cursor snapshot via official /usage panel")
                    print("  plan: \(parsed.planName)")
                    print("  • Included (compatibility fallback)  \(Int(percentUsed.rounded()))% used  reset-evidence=scheduled")
                case .incomplete:
                    print("RESULT: Cursor subscription table was incomplete")
                }
                print("  on-demand: \(parsed.onDemand.isEnabled ? "enabled" : "disabled")")
            case .loginRequired:
                print("RESULT: login required")
            case .workspaceTrustRequired:
                print("RESULT: Cursor workspace trust required (no input sent)")
            case .mcpApprovalRequired:
                print("RESULT: Cursor MCP server approval required (no input sent)")
            case .cliNotFound:
                print("RESULT: Cursor Agent CLI not found")
            case .unknownUI:
                print("RESULT: unrecognized Cursor Agent surface (no input sent)")
            case .transientCapture:
                print("RESULT: Cursor usage capture failed")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// Parsed values only: never the login, a raw log line or a server reply. The status
    /// source caches its reading, so the provider reuses the one spawn made here.
    private static func runCopilotProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let source = CopilotStatusSource()
            let ledger = CopilotUsageLedger(
                copilotHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot", isDirectory: true)
            )
            let loginMemory = UserDefaultsCopilotLoginMemory()
            switch await source.status() {
            case .cliMissing:
                print("RESULT: GitHub Copilot CLI not found")
            case .signedOut:
                print("RESULT: login required")
            case .failure(let reason):
                print("RESULT: Copilot status failed: \(reason.message)")
            case .signedIn(let status):
                let snapshot = await CopilotProvider(statusSource: source, ledger: ledger, loginMemory: loginMemory)
                    .fetchSnapshot()
                let now = Date()
                let loginChangedAt = loginMemory.loginChangedAt(noting: status.login, at: now)
                func credits(_ value: Double?) -> String {
                    value.map { String(format: "%.1f credits", $0) } ?? "none"
                }
                if case .stale(let reason) = snapshot.freshness {
                    print("RESULT: stale Copilot snapshot: \(reason.message)")
                } else {
                    print("RESULT: live Copilot snapshot, \(snapshot.windows.count) window(s)")
                }
                print("  ledger only (this month's usage records, no snapshot or server count): \(credits(await ledger.recordedCredits()))")
                switch await CopilotProvider.reading(from: ledger, for: status, loginChangedAt: loginChangedAt, now: now) {
                case .unreadable:
                    print("  shown (logs, raised only by the server reading's lower bound): session logs unreadable")
                case .reading(let reading):
                    print("  shown (logs, raised only by the server reading's lower bound): \(credits(reading.usedCredits))")
                    print("  newest evidence age: \(reading.newestEvidenceAt.map { "\(max(0, Int(now.timeIntervalSince($0)))) s" } ?? "none")")
                }
                print("  entitlement: \(status.isUnlimited ? "unlimited" : status.entitlement.map { String(format: "%.0f", $0) } ?? "none")")
                for window in snapshot.windows {
                    let freshness: String
                    switch window.freshness {
                    case .live: freshness = "live"
                    case .stale(let observedAt): freshness = "stale (observed \(Int(now.timeIntervalSince(observedAt))) s ago)"
                    case .unavailable: freshness = "unavailable"
                    }
                    print("  reset: \(window.resetSchedule.deadline.map { ISO8601DateFormatter().string(from: $0) } ?? "unresolved")  \(ResetDiagnostic.line(for: window.resetSchedule, observedAt: window.observedAt ?? snapshot.capturedAt, now: now))")
                    print("  freshness: \(freshness)  \(window.freshness.isUnavailable ? "no percentage" : "\(Int(window.percentUsed.rounded()))% used")")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// `--probe-spend <openai|anthropic|xai>` verifies a real key-based API-spend path (U8
    /// acceptance): the three admin/management-key providers share one shape (key → vendor
    /// billing/cost API → typed spend or balance row), so one probe covers all of them. It
    /// prints only the typed, redacted outcome. The key read is off any leak-prone channel:
    /// pass `--key-file <path>` and the key is read from that file (never an argument or env
    /// var, so it can't surface in `ps`/shell history), never echoed, and never persisted.
    /// With no file flag it reads the app-saved Keychain key instead. The API calls are
    /// read-only status fetches. For xAI, compare the printed balance against console.x.ai to
    /// confirm the documented negative-liability sign convention holds against a real response.
    private static func runSpendProbe() {
        let valid = ["openai", "anthropic", "xai"]
        guard let index = CommandLine.arguments.firstIndex(of: "--probe-spend"),
              CommandLine.arguments.indices.contains(index + 1),
              case let token = CommandLine.arguments[index + 1].lowercased(),
              valid.contains(token) else {
            print("Usage: --probe-spend <\(valid.joined(separator: "|"))> [--key-file <path>]")
            return
        }
        let keyProvider: APIKeyProvider
        let label: String
        switch token {
        case "openai": (keyProvider, label) = (.openAI, "OpenAI")
        case "anthropic": (keyProvider, label) = (.anthropic, "Anthropic")
        default: (keyProvider, label) = (.xAI, "xAI")
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let credentials: CredentialStore
            if let fileIndex = CommandLine.arguments.firstIndex(of: "--key-file"),
               CommandLine.arguments.indices.contains(fileIndex + 1) {
                let path = CommandLine.arguments[fileIndex + 1]
                guard let raw = try? String(contentsOfFile: path, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    print("RESULT: could not read a non-empty key from \(path)")
                    semaphore.signal()
                    return
                }
                print("key source: file (\(raw.count) chars — value not shown)")
                credentials = CredentialStore(apiKeyStore: SingleAPIKeyStore(key: raw, provider: keyProvider))
            } else {
                print("key source: Keychain (app-saved; pass --key-file <path> to test a raw key)")
                credentials = CredentialStore()
            }

            let provider: any APISpendProvider
            switch keyProvider {
            case .openAI: provider = OpenAIAPISpendProvider(credentials: credentials)
            case .anthropic: provider = AnthropicAPISpendProvider(credentials: credentials)
            case .xAI: provider = XAIAPISpendProvider(credentials: credentials)
            }

            let snapshot = await provider.fetchSpend(period: .currentMonth)
            print("provider: \(label)")
            switch snapshot.freshness {
            case .pending:
                print("RESULT: pending")
            case .live:
                let amount = snapshot.amount.map { String(format: "%.2f", $0) } ?? "(none)"
                print("RESULT: live \(label) \(snapshot.kind == .balance ? "balance" : "period spend")")
                print("  label:  \(snapshot.periodLabel)")
                print("  amount: \(amount) \(snapshot.currency ?? "")")
            case .stale(let reason):
                print("RESULT: stale — \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

}

/// Menu bar app (U1). `MenuBarExtra(.window)` gives a custom Liquid Glass popover
/// (KTD9). No Dock icon in the shipped app — `LSUIElement = YES` is stamped into the
/// Xcode app target's Info.plist when finalizing the bundle (U1/KTD8).
struct PacemarkApp: App {
    @State private var store: UsageStore
    // A signed demo or XCTest host must not download/install into its own app bundle.
    @StateObject private var softwareUpdates = SoftwareUpdateController(
        enabled: !DemoFixture.isEnabled && !AppComposition.isTestHost()
    )
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let preferences: Preferences
    private let demoController: LoadingDemoController?

    @MainActor
    init() {
        FirstLaunchImport.run()
        if AppComposition.capturedDemo == nil { PopoverTuningModel.startAgent() }
        let preferences = AppComposition.launchPreferences
        // Hosted tests supply their own setup boundaries. A launch-time demo controller
        // would install inert cleanup over tests that stage real handoff fixture scripts.
        let demoController = DemoFixture.isEnabled && !AppComposition.isTestHost()
            ? LoadingDemoController(loading: DemoFixture.scenarioRequest() == .multiAccount(.loading)) : nil
        let store = AppComposition.store(preferences: preferences, demoController: demoController)
        demoController?.configure(store: store)
        if !DemoFixture.isEnabled {
            SetupSessions.configure(
                store: store,
                claudeExecutableLocator: AppComposition.claudeExecutableLocator
            )
        }
        self.preferences = preferences
        self.demoController = demoController
        _store = State(initialValue: store)
        AppDelegate.startUsageStore = {
            if demoController?.loading == true { demoController?.start() }
            else {
                Task { await store.start() }
            }
        }
        #if PACEMARK_BENCH
        if let reportURL = LoadingNativeBench.reportURL {
            AppDelegate.startUsageStore = {
                Task { await LoadingNativeBench.run(store: store, preferences: preferences, reportURL: reportURL) }
            }
        }
        #endif
        if let demoController {
            AppDelegate.stopDemo = { await demoController.shutdown() }
        } else {
            AppDelegate.stopDemo = nil
        }
    }

    // ML1: `--bench-ui scene` measures `BenchSceneStandIn` (UIBenchHarness.swift), not this body.
    // Mirror a change to what this body reads or builds into the stand-in before measuring it.
    var body: some Scene {
        let paceDate = DemoFixture.scenarioRequest() == .multiAccount(.paceStates) ? DemoFixture.paceStatesDate : nil
        MenuBarExtra {
            PopoverView(store: store, onOpenSettings: { openSettings() },
                        onOpenAPISpend: { openSettings(pane: .apiSpend) },
                        onOpenMenuBarSettings: { openSettings(pane: .menuBar) }, fitsMenuBarWindowHeight: true)
                .defaultAppStorage(AppComposition.menuBarControlDefaults)
                .environment(\.loadingDate, paceDate)
                // PC1 (Kyle, 2026-09-23): on Tahoe the MenuBarExtra window draws its own
                // Liquid Glass background behind the popover at the system's smaller corner
                // radius, so a second corner and rim showed outside the r22 shell. The shell
                // owns the whole surface (`PopoverSurfaceModifier`); the scene's default
                // container background goes. Verified in the bundled app — an unbundled
                // `swift run` gets a different host background, handled in `PopoverView`.
                // `popoverSurfaceHost()` is exactly that clear background unless a DialKit
                // build switches to the system surface (PC2).
                .popoverSurfaceHost()
                .modifier(CapturedDemoLinks(isReplaying: store.isReplayingDemoCapture))

                .task {
                    await store.start()
                    // R2M2: `start()` is idempotent and early-returns once the loop
                    // exists, so this is the only place the popover can freshen on open.
                    // The store decides whether it's worth a poll (oldest live capture
                    // older than one interval) and re-phases the cadence if it is.
                    store.refreshOnPopoverOpen()
                }
        } label: {
            MenuBarStatusLabel(store: store)
                .defaultAppStorage(AppComposition.menuBarControlDefaults)

                .task { await store.start() }
                .task {
                    if !store.isReplayingDemoCapture { PopoverTuningModel.shared.showPinnedPopover(store: store) }
                }
                // Attach to the status item's own window once the scene exists (L1A). The menu
                // bar's appearance is not the process appearance: a light system appearance over
                // a dark wallpaper still gets a dark menu bar, which is exactly the case the old
                // dark pin got right by accident and a system-appearance check would get wrong.
                .task {
                    AppDelegate.reopenSettings = { openSettings() }
                    MenuBarAppearanceMonitor.shared.start()
                }
                // Track OS light/dark flips so `.system` content re-resolves live (chrome
                // follows the OS on its own via `NSApp.appearance == nil`). Attached to the
                // always-present label, not the on-demand popover, so it never misses a change.
                .onReceive(DistributedNotificationCenter.default().publisher(
                    for: Notification.Name("AppleInterfaceThemeChangedNotification")
                )) { _ in
                    // An OS theme flip repaints the menu bar backplate; re-read it in case the
                    // status window was replaced and the KVO has nothing to fire from (L1A).
                    MenuBarAppearanceMonitor.shared.refresh()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Pacemark Settings", id: "settings") {
            SettingsView(
                store: store,
                softwareUpdates: softwareUpdates,
                preferences: preferences,
                credentialStore: AppComposition.settingsCredentialStore,
                launchControl: AppComposition.settingsLaunchControl,
                duplicateDetector: AppComposition.settingsDuplicateDetector,
                // U6: the one client per launch; inert under `--demo` and unbundled runs (KTD9).
                notificationClient: AppComposition.notificationClient
            )
            .defaultAppStorage(AppComposition.menuBarControlDefaults)
            .environment(\.loadingDate, paceDate)
            .modifier(CapturedDemoLinks(isReplaying: store.isReplayingDemoCapture))

            // L9A (revising KTD2): the window opens at 800 × 700 and is resizable on
            // both axes down to 720 × 600, with no ceiling. It no longer changes size
            // with the selected pane — every pane body is a `ScrollView`, so the room
            // scrolls inside whatever frame the user left the window at. Only minimizing
            // is withdrawn, since a settings sheet in the Dock is a dead end;
            // `windowResizeBehavior` is deliberately *not* disabled.
            .windowMinimizeBehavior(.disabled)
        }
        // Hidden title bar: the settings window draws its own identity block (icon, name,
        // version) at the top of the sidebar, so traffic lights float on a transparent
        // strip. Avoids Tahoe wrapping a toolbar item in a Liquid Glass container.
        // (Standard modern-macOS utility pattern.)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .defaultSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight)
        .defaultPosition(.center)
    }

    /// Open (or re-focus) the Settings window. An accessory / `LSUIElement` app is not
    /// activated by `openWindow` alone, so the window would open *behind* the frontmost
    /// app or never take keyboard focus — and clicking the gear a second time would look
    /// like a no-op because the already-open window stays buried. Activating brings it
    /// forward and makes it key on both first open and re-open. (`Done`/⌘W close it via
    /// the view's `dismiss`; this method reopens cleanly afterward.)
    private func openSettings(pane: SettingsPane? = nil) {
        if let pane { preferences.settingsPane = pane }
        // SW1: a window that is already showing is only brought forward. One that is arriving
        // is shown at zero opacity, placed, then revealed, so the placement never shows.
        // `openWindow` orders the window front synchronously (measured, macOS 26), but nothing
        // reaches the screen before this runloop turn ends, so zeroing the alpha right after
        // it hides the first frame too. A reused window drops its close animation first so
        // AppKit adds nothing of its own to the order-in. KB1: from ⌘, the reveal is instant;
        // only a click fades.
        let existing = Self.settingsWindow
        let isArriving = existing?.isVisible != true
        let fades = isArriving && !PacemarkMotion.isKeyboardInitiated
        if isArriving, let existing {
            existing.animationBehavior = .none
            existing.alphaValue = 0
        }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        Self.settingsWindow?.hidesOnDeactivate = false
        NSApp.activate(ignoringOtherApps: true)
        if let pane, !isArriving {
            NotificationCenter.default.post(name: .openSettingsPane, object: pane)
        }
        if isArriving { Self.settingsWindow?.alphaValue = 0 }
        // `.defaultPosition(.center)` (and SwiftUI's persisted frame) can land the window on
        // whichever display it was last on — often the wrong one on a multi-monitor setup.
        // A menu-bar app is invoked from wherever the user is looking, so re-home it onto the
        // screen under the cursor. Deferred a runloop tick so SwiftUI has sized the window to
        // its content; while arriving it is still invisible, so the move never shows.
        DispatchQueue.main.async {
            Self.settingsWindow?.hidesOnDeactivate = false
            Self.placeSettingsWindowOnActiveScreen()
            guard isArriving, let window = Self.settingsWindow else { return }
            Self.reveal(window, fading: fades)
        }
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "settings" }
    }

    /// SW1: the entrance, then AppKit's utility-window fade for whichever way the user closes
    /// it (red button, ⌘W). The behavior only governs order-in and order-out, so setting it on
    /// a window that is already ordered in changes nothing about this entrance.
    private static func reveal(_ window: NSWindow, fading: Bool) {
        window.animationBehavior = .utilityWindow
        guard fading else {
            window.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PacemarkMotion.windowInDuration
            context.timingFunction = PacemarkMotion.windowCurve
            window.animator().alphaValue = 1
        }
    }

    /// Center the Settings window on the active screen (the one under the cursor). If the
    /// window is already showing on that screen, its current position is respected so a
    /// user's manual placement isn't yanked back to center on every re-open.
    private static func placeSettingsWindowOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let activeScreen, let window = settingsWindow else { return }

        if window.isVisible, activeScreen.frame.intersects(window.frame) { return }

        // Force the layout pass so SwiftUI has applied the Settings content's preferred size
        // before we read it. At open the window is briefly wider than its content, and reading
        // that transient frame centers ~50px off.
        window.layoutIfNeeded()
        let visible = activeScreen.visibleFrame
        let size = window.frame.size
        // Horizontally centered; nudged slightly above the vertical midpoint, matching the
        // weighting AppKit's own `NSWindow.center()` uses.
        let preferred = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + size.height * 0.05
        )
        // The window is fixed-width and only shrinks to 600pt tall, so on a short or narrow
        // screen the centered origin can push the title bar under the menu bar (or the edge
        // off-screen); clamping into `visibleFrame` is what keeps the traffic lights
        // reachable. The 5% upward weighting survives whenever it still fits.
        let origin = NSPoint(
            x: min(max(preferred.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
            y: min(max(preferred.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        )
        window.setFrameOrigin(origin)
    }
}

/// Two copies of the bundle (the installed app plus a dev build, or a stray copy left in
/// Downloads) share one bundle ID, but LaunchServices treats them as different apps: tapping
/// a reminder launched `/Applications/Pacemark.app` while a workspace build was already
/// running (2026-09-30). Both copies then poll every CLI and post the same reminders, so the
/// copy already running keeps the menu bar and a later launch exits. `swift run` has no
/// bundle ID and is never blocked.
enum SingleInstance {
    static func otherRunningCopy() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
    }
}

/// Pins the process to `.accessory` at launch so it behaves as a pure menu-bar app —
/// no Dock icon, no app-switcher entry — even when run via `swift run` (which has no
/// `LSUIElement` Info.plist). This also makes the Settings-window activation path
/// identical in development and in the shipped bundle, so "does the window open and
/// close properly" can be verified with `swift run Pacemark`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var startUsageStore: (() -> Void)?
    static var stopDemo: (@MainActor () async -> Void)?
    private var terminationTask: Task<Void, Never>?
    /// KTD10: the presentation delegate must be in place before launch completes, so a
    /// banner posted during the first refresh already presents while Settings is frontmost.
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppComposition.notificationClient.installPresentationDelegate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsClosing(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
        FirstLaunchImport.showIfImported()
        Self.startUsageStore?()
    }

    @objc private func settingsClosing(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.identifier?.rawValue == "settings" else { return }
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static var reopenSettings: (@MainActor () -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let reopen = Self.reopenSettings else { return true }
        reopen()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let stopDemo = Self.stopDemo
        guard stopDemo != nil else { return .terminateNow }
        if terminationTask == nil {
            terminationTask = Task {
                if let stopDemo {
                    await stopDemo()
                    Self.stopDemo = nil
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    private static let t3Installation = T3Installation()
    static let capturedDemoResult: Result<DemoCapture, Error>? = {
        guard case .captured(let path) = DemoFixture.scenarioRequest() else { return nil }
        return Result { try DevCaptureCommand.load(path: path) }
    }()
    static var capturedDemo: DemoCapture? { try? capturedDemoResult?.get() }

    static func isT3ClaudeAvailable() -> Bool {
        !usesInertAntigravity() && t3Installation.claudeInstanceName() != nil
    }

    struct SubscriptionProviderRegistration {
        let id: ProviderID
        /// KTD10 (2026-09-19 polling plan): the registry is read before any provider instance
        /// exists, so the capacity that truncates it lives here and must match the provider's.
        let accountCapacity: Int
        let factory: @MainActor (ProviderAccount, CredentialStore, URL) -> any UsageProvider
    }

    private static let cursorUsageSource = CursorUsageCaptureCache(source: CursorUsageCLIProbe())

    /// KTD8: the one OpenCode read path per launch. Every OpenCode account, built-in and extra,
    /// shares this cache and the one client source under it, so the resolved executable and
    /// the version memo are shared and a user request joins a timer read of the same home.
    static let openCodeUsageSource = OpenCodeUsageCaptureCache(source: makeOpenCodeCLISource())

    /// The launches that must never start the OpenCode client: demo runs, the render and
    /// bench harnesses and the XCTest host. Their stores are fixtures or must not touch the
    /// user's real OpenCode home (a 1.x client writes to it even for `--version`).
    static func usesInertOpenCode(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        usesIsolatedServices(arguments: arguments, environment: environment)
    }

    /// KTD18: a DEBUG launch with `--opencode-executable <path>` reads extra accounts through
    /// that client; the built-in account always resolves the user's own (the router decides
    /// by home, below the cache). Release builds never read the flag.
    static func makeOpenCodeCLISource(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        buildAllowsOverride: Bool = OpenCodeLaunchArguments.buildAllowsExecutableOverride
    ) -> any OpenCodeUsageSource {
        guard !usesInertOpenCode(arguments: arguments, environment: environment) else {
            return InertOpenCodeUsageSource()
        }
        let standard = OpenCodeCLIUsageSource()
        guard let path = OpenCodeLaunchArguments.executableOverride(
            arguments: arguments,
            buildAllowsOverride: buildAllowsOverride
        ) else { return standard }
        return OpenCodeExecutableOverrideRouter(
            standard: standard,
            overridden: OpenCodeCLIUsageSource(resolveExecutable: { path })
        )
    }
    static let claudeExecutableLocator = CLIExecutableLocator.claude()

    /// The one Antigravity read path per launch. One source keeps the resolved path, the
    /// version memo and the sticky stops (a turn-spending answer, a sign-in prompt) for every
    /// provider instance the store builds.
    static let antigravityUsageSource = makeAntigravityCLISource()

    /// The launches that must never start `agy`: demo runs, the render and bench harnesses
    /// and the XCTest host. A signed-out `agy` opens a browser sign-in on any read.
    static func usesInertAntigravity(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        usesIsolatedServices(arguments: arguments, environment: environment)
    }

    static func isT3AntigravityAvailable() -> Bool {
        !usesInertAntigravity() && t3Installation.antigravity() != nil
    }

    static func makeAntigravityCLISource(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any AntigravityUsageSource {
        guard !usesInertAntigravity(arguments: arguments, environment: environment) else {
            return InertAntigravityUsageSource()
        }
        let preferences = Preferences(defaults: launchDefaults)
        let resolver = AntigravityLaunchResolver(t3: t3Installation)
        return AntigravityCLIUsageSource(
            resolveLaunch: { resolver.resolve(preference: preferences.antigravitySourcePreference) },
            memory: .preferences(preferences)
        )
    }

    /// The one UserDefaults domain a launch may read or write. `.standard` in the shipping
    /// app; an isolated suite under `--demo`, because the App shell and the store have to
    /// agree on it. They did not: `PacemarkApp.init` built `Preferences()` on `.standard`
    /// while the store took the demo suite, so a demo run wrote `appearancePreference`,
    /// `settingsPane`, `showMenuBarPercentage`, and `menuBarFillSource` into the user's real
    /// domain, and read its theme from whatever a previous `swift run` had left there
    /// (2026-09-03 / round-3 residual).
    nonisolated(unsafe) static let launchDefaults: UserDefaults = resolveLaunchDefaults()

    /// Preferences over `launchDefaults`. `Preferences` is a value wrapper around the
    /// defaults object, so every call site shares one domain regardless of instance.
    static var launchPreferences: Preferences { Preferences(defaults: launchDefaults) }

    /// KTD14 (2026-09-19 sign-in plan): the sign-out record over that same one domain,
    /// so the running app and `--probe-claude` read and write the same entries. An
    /// unbundled `swift run Pacemark` resolves `.standard` to a different domain than
    /// the app bundle, so the record is read from the built app's binary.
    static var signOutRecord: SignOutRecord { SignOutRecord(defaults: launchDefaults) }
    static var bankedResetAcknowledgements: BankedResetAcknowledgements {
        BankedResetAcknowledgements(defaults: launchDefaults)
    }

    @MainActor static let menuBarControlDefaults = launchDefaults

    /// `arguments` is injected so the demo isolation can be tested from a process that was
    /// not itself launched with `--demo`.
    static func resolveLaunchDefaults(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        if arguments.contains("--qa-display") {
            let defaults = DemoMemoryDefaults()
            for key in [PopoverSummarySlot.firstKey, PopoverSummarySlot.secondKey] {
                if let value = QALaunch.argument("-" + key, in: arguments) { defaults.set(value, forKey: key) }
            }
            if DemoFixture.scenarioRequest(arguments: arguments) == .multiAccount(.paceStates) {
                MenuBarMeterControls.seedMenuBarDemo(defaults: defaults, showNumber: true)
            }
            return defaults
        }
        let request = DemoFixture.scenarioRequest(arguments: arguments)
        guard request != .notRequested || usesIsolatedServices(arguments: arguments, environment: environment)
                || arguments.contains("--render-menubar") else { return .standard }
        if case .multiAccount = request {
            let defaults = DemoMemoryDefaults()
            if request == .multiAccount(.menubar) {
                MenuBarMeterControls.seedMenuBarDemo(defaults: defaults)
            } else if request == .multiAccount(.paceStates) {
                MenuBarMeterControls.seedMenuBarDemo(defaults: defaults, showNumber: true)
            }
            return defaults
        }
        return DemoMemoryDefaults()
    }

    /// Ordered composition registry. Adding a provider extends this table; Settings,
    /// account management, polling, and presentation discover the resulting order from
    /// the store instead of maintaining parallel provider literals.
    @MainActor
    static var subscriptionProviderRegistry: [SubscriptionProviderRegistration] {
        [
            SubscriptionProviderRegistration(id: .claude, accountCapacity: AccountRegistry.testedEnvelope, factory: makeClaudeProvider),
            SubscriptionProviderRegistration(id: .codex, accountCapacity: AccountRegistry.testedEnvelope, factory: makeCodexProvider),
            SubscriptionProviderRegistration(id: .grok, accountCapacity: AccountRegistry.testedEnvelope, factory: makeGrokProvider),
            // Cursor has no config-home isolation, so it stays single-account (matches `CursorProvider.accountCapacity`).
            SubscriptionProviderRegistration(id: .cursor, accountCapacity: 1, factory: makeCursorProvider),
            // `agy` keeps one sign-in per Mac and isolating a second is unproven, so Antigravity
            // stays single-account (matches `AntigravityProvider.accountCapacity`).
            SubscriptionProviderRegistration(id: .antigravity, accountCapacity: 1, factory: makeAntigravityProvider),
            // A Pacemark-owned COPILOT_HOME never receives the session logs the meter reads, so
            // Copilot stays single-account (matches `CopilotProvider.accountCapacity`).
            SubscriptionProviderRegistration(id: .copilot, accountCapacity: 1, factory: makeCopilotProvider),
            // KTD10: each extra gets its own four XDG folders, so OpenCode carries the tested
            // envelope like Grok (matches `OpenCodeProvider.accountCapacity`).
            SubscriptionProviderRegistration(id: .opencode, accountCapacity: AccountRegistry.testedEnvelope, factory: makeOpenCodeProvider),
        ]
    }

    @MainActor
    static func store(
        preferences: Preferences = launchPreferences, demoController: LoadingDemoController? = nil,
        capturingDemo: Bool = false
    ) -> UsageStore {
        if let capturedDemo, let defaults = launchDefaults as? DemoMemoryDefaults {
            return capturedDemo.makeReplayStore(
                defaults: defaults, accountStorage: demoController?.accountStorage ?? DemoAccountStorage(),
                newAccountProvider: { [weak demoController] account in
                    demoController?.provider(for: account, needsSetup: true)
                        ?? DemoUsageProvider(id: account.providerID, displayName: account.providerID.displayName,
                                             snapshot: .pending(for: account.providerID), accountID: account.id)
                }
            )
        }
        if DemoFixture.isEnabled {
            // `--demo <scenario>` opts into the isolated multi-account preview; a bare `--demo`
            // keeps the single-account screenshot fixtures the marketing pipeline relies on.
            if case .multiAccount(let scenario) = DemoFixture.scenarioRequest() {
                return demoMultiAccountStore(scenario: scenario, controller: demoController)
            }
            return demoStore()
        }
        let credentials = CredentialStore()
        let registry = AccountRegistry(defaults: launchDefaults)
        let borrowedHomes: BorrowedHomeEnvironment?
        if usesIsolatedServices() {
            borrowedHomes = nil
        } else {
            let live = BorrowedHomeEnvironment.live(t3: t3Installation)
            T3DiscoveryCache(defaults: launchDefaults).record(live.scanT3())
            borrowedHomes = live
        }
        return UsageStore(
            providers: providers(credentials: credentials, registry: registry),
            apiSpendProviders: apiSpendProviders(credentials: credentials),
            preferences: preferences,
            accountRegistry: registry,
            borrowedHomes: borrowedHomes,
            providerFactory: { account in provider(for: account, credentials: credentials) },
            continuityCache: UsageContinuityCache(),
            defaultLoginRecords: makeDefaultLoginRecordStore(isDemo: DemoFixture.isEnabled),
            signOutRecord: signOutRecord,
            sessionReliabilityRecord: capturingDemo ? nil : makeSessionReliabilityRecord(),
            bankedResetAcknowledgements: bankedResetAcknowledgements,
            notificationCoordinator: capturingDemo ? nil : NotificationCoordinator(
                poster: notificationClient,
                useItUpLedger: UseItUpLedger(defaults: launchDefaults),
                bankedResetBaseline: BankedResetNotificationBaseline(defaults: launchDefaults)
            ),
            warmUp: capturingDemo || usesInertWarmUp() ? WarmUpAutomation() : WarmUpAutomation(
                defaults: launchDefaults, sender: WarmUpCLISender(claudeLocator: claudeExecutableLocator, antigravity: antigravityUsageSource as? AntigravityCLIUsageSource)
            ),
            capturesAllAccounts: capturingDemo
        )
    }

    @MainActor
    private static func demoStore() -> UsageStore {
        let prefs = launchPreferences
        let meterStyle = demoMeterStyle()
        prefs.meterStyle = meterStyle
        prefs.accountLayout = demoAccountLayout()
        prefs.useEmailAsAccountName = ProcessInfo.processInfo.arguments.contains("--email-account-names")
        prefs.expandAccountsHorizontally = !ProcessInfo.processInfo.arguments.contains("--vertical-accounts")
        prefs.showMenuBarPercentage = true
        prefs.menuBarFillSource = .both            // show both Claude + Codex meters side by side in the menu bar
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)   // API spend surfaces are off by default
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        prefs.setRenewalDate(DemoFixture.renewalDate(for: .claude), for: .claude)
        prefs.setRenewalDate(DemoFixture.renewalDate(for: .codex), for: .codex)
        return UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: prefs,
            accountStorage: DemoAccountStorage(),
            defaultLoginRecords: DemoDefaultLoginRecordStore(),
            now: { DemoFixture.now },
            previewAccountLayout: prefs.accountLayout
        )
    }

    @MainActor
    static func demoMultiAccountStore(scenario: DemoFixture.MultiAccountScenario,
                                     controller: LoadingDemoController? = nil,
                                     defaults: UserDefaults? = nil) -> UsageStore {
        let prefsDefaults = defaults ?? launchDefaults
        let prefs = Preferences(defaults: prefsDefaults)
        let meterStyle = demoMeterStyle()
        prefs.meterStyle = meterStyle
        prefs.accountLayout = demoAccountLayout()
        prefs.useEmailAsAccountName = ProcessInfo.processInfo.arguments.contains("--email-account-names")
        prefs.expandAccountsHorizontally = !ProcessInfo.processInfo.arguments.contains("--vertical-accounts")
        prefs.showMenuBarPercentage = true
        prefs.menuBarFillSource = .both            // show both Claude + Codex meters in the menu bar
        if scenario == .menubar { DemoFixture.applyMenuBarDemoPreferences(to: prefs) }
        if scenario == .paceStates { DemoFixture.applyPaceStatesPreferences(to: prefs) }
        let paceDate = scenario == .paceStates ? DemoFixture.paceStatesDate : nil
        // API spend surfaces are off by default, so enable exactly the ones this scenario
        // wires — derived from the providers rather than a hardcoded Claude/Codex pair, so
        // `spend-states`' xAI balance row is not silently filtered out of the card.
        let spendProviders = scenario == .loading ? (controller?.spendProviders() ?? demoSpendProviders(for: scenario)) : demoSpendProviders(for: scenario)
        for provider in spendProviders {
            if let surface = UsageSurface.api(for: provider.id) {
                prefs.setSurfaceEnabled(true, for: surface)
            }
        }

        let fixture = DemoFixture.multiFixture(for: scenario, includesLedgerDetails: prefs.accountLayout == .ledger)
        let continuityCache = UsageContinuityCache(defaults: prefsDefaults)
        for (key, snapshot) in fixture.continuitySnapshots {
            continuityCache.save(snapshot, for: key)
        }
        // Enable the subscription surface for every provider present in the scenario. Grok and
        // Cursor default OFF (upgrade-safety), so the four-provider scenario would otherwise
        // render only the Claude/Codex cards even though all four fixtures are wired.
        for providerID in Set(fixture.accounts.map(\.providerID)) {
            if let surface = UsageSurface.subscription(for: providerID) {
                prefs.setSurfaceEnabled(true, for: surface)
            }
        }
        // Demo account changes live only for the duration of this fixture.
        let registry = AccountRegistry(defaults: DemoMemoryDefaults())
        registry.seed(fixture.accounts)
        let factory: @MainActor (ProviderAccount) -> any UsageProvider = { [weak controller] account in
            if let controller { return controller.provider(for: account, needsSetup: true) }
            return DemoUsageProvider(
                id: account.providerID,
                displayName: account.providerID.displayName,
                snapshot: .pending(for: account.providerID),
                accountID: account.id
            )
        }
        let providers: [any UsageProvider]
        if scenario == .loading, let controller { providers = fixture.accounts.map { controller.provider(for: $0) } }
        else { providers = fixture.providers }
        return UsageStore(
            providers: providers,
            apiSpendProviders: spendProviders,
            preferences: prefs,
            accounts: fixture.accounts,
            accountRegistry: registry,
            accountStorage: controller?.accountStorage ?? DemoAccountStorage(),
            providerFactory: factory,
            continuityCache: continuityCache,
            // Default-login U11: in memory, seeded from the fixture; never the user's
            // `defaultLoginRecords.v1`. Fixture providers carry no identity, so no reader runs.
            defaultLoginRecords: fixture.makeDefaultLoginRecordStore(),
            bankedResetAcknowledgements: BankedResetAcknowledgements(defaults: prefsDefaults),
            now: { [clock = controller?.clock] in paceDate ?? clock?.now() ?? Date() },
            previewAccountLayout: prefs.accountLayout
        )
    }

    /// The spend rows a live preview scenario poses. Every other scenario keeps the two
    /// `.live` period-spend rows the demo has always shown; `spend-states` (S5A) is the one
    /// that exercises the card's other states, because nothing else in the tree ever renders
    /// a stale spend row or a `.balance` row. Cursor rides along last because it is the only
    /// spend provider with no `addCreditsURL`: its row is what proves the reserved-empty
    /// top-up slot keeps all four amounts on one right edge.
    static func demoSpendProviders(
        for scenario: DemoFixture.MultiAccountScenario
    ) -> [any APISpendProvider] {
        switch scenario {
        case .paceStates:
            []
        case .spendStates:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejected),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        // X5: the retained-figure counterpart — a rejected key that still shows its last
        // total (so the column and the glyph-less top-up slot hold) beside a retryable stale
        // row. `spend-states` poses the nil-amount collapse; one row cannot show both.
        case .spendRetained:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpendKeyRejectedRetained),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpendStaleRetained),
                DemoSpendProvider(id: .grok, displayName: "xAI API", snapshot: DemoFixture.xaiBalanceSpend),
                DemoSpendProvider(id: .cursor, displayName: "Cursor on-demand", snapshot: DemoFixture.cursorOnDemandSpend),
            ]
        default:
            [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ]
        }
    }

    /// Demo-only launch override. An absent flag always reseeds the landed default so a
    /// previous demo run cannot change a later capture; Entry rejects malformed tokens.
    static func demoMeterStyle(arguments: [String] = CommandLine.arguments) -> MeterStyle {
        guard let index = arguments.firstIndex(of: "--meter-style"),
              arguments.indices.contains(index + 1),
              let style = MeterStyle(launchToken: arguments[index + 1])
        else { return .default }
        return style
    }


    /// `--account-title-ink <neutral|brand>`, the review seam for `AccountTitleInk.brand`.
    /// Reseeds the landed default when absent for the same reason `demoMeterStyle` does.
    static func demoAccountTitleInk(arguments: [String] = CommandLine.arguments) -> AccountTitleInk {
        guard let index = arguments.firstIndex(of: "--account-title-ink"),
              arguments.indices.contains(index + 1),
              let ink = AccountTitleInk(rawValue: arguments[index + 1])
        else { return .neutral }
        return ink
    }

    /// `--account-layout <standard|compact|ledger>`, reseeding Ledger when absent or malformed so
    /// one capture cannot leak into the next.
    static func demoAccountLayout(arguments: [String] = CommandLine.arguments) -> AccountLayout {
        guard let index = arguments.firstIndex(of: "--account-layout"),
              arguments.indices.contains(index + 1),
              let layout = AccountLayout(rawValue: arguments[index + 1])
        else { return .ledger }
        return layout
    }

    /// One provider instance per configured account, in registry order (built-in first).
    @MainActor
    private static func providers(credentials: CredentialStore, registry: AccountRegistry) -> [any UsageProvider] {
        subscriptionProviderRegistry.flatMap { registration in
            registry.accounts(for: registration.id, capacity: registration.accountCapacity)
                .map { provider(for: $0, credentials: credentials) }
        }
    }

    /// The concrete provider for one account. Built-in accounts read the CLI's default
    /// config (`~/.claude` / `~/.codex` / `~/.grok` / `~/.local/share/opencode`) exactly as
    /// before; extra accounts route the same paths at their Pacemark-owned config home
    /// (`CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `GROK_HOME` / the four OpenCode XDG folders) that
    /// the user signed into via the official CLI.
    @MainActor
    static func provider(
        for account: ProviderAccount,
        credentials: CredentialStore,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> any UsageProvider {
        guard let registration = subscriptionProviderRegistry.first(where: { $0.id == account.providerID }) else {
            return UnavailableAccountProvider(account: account)
        }
        return registration.factory(account, credentials, builtInClaudeWorkspace)
    }

    @MainActor
    private static func makeCodexProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        switch ProviderAccountConfiguration.make(for: account).codexTransport {
        case .authFile(let url):
            let credentials = CredentialStore(codexReader: CodexAuthFileReader(path: url))
            return CodexProvider(credentials: credentials, accountID: account.id)
        case .appServer(let home):
            return CodexAppServerProvider(accountID: account.id, home: home)
        case nil:
            return UnavailableAccountProvider(account: account)
        }
    }

    @MainActor
    private static func makeClaudeProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace: URL
    ) -> any UsageProvider {
        let configuration = ProviderAccountConfiguration.make(
            for: account,
            builtInClaudeWorkspace: builtInClaudeWorkspace
        )
        guard let workspace = configuration.claudeWorkspaceDirectory else {
            return UnavailableAccountProvider(account: account)
        }
        // Provider configuration describes the path but deliberately has no file-system
        // side effects. Provision it before the PTY receives it as its working directory.
        guard (try? ClaudeUsageWorkspace.ensureDirectory(at: workspace)) != nil else {
            return UnavailableAccountProvider(account: account)
        }
        guard !account.isBuiltIn else {
            return ClaudeProvider(
                source: ClaudeUsageCLIProbe(
                    locator: claudeExecutableLocator,
                    workingDirectory: workspace.path
                ),
                emailSource: claudeIdentityReader(configDirectory: nil)
            )
        }
        guard let configDirectory = configuration.claudeConfigDirectory else {
            return UnavailableAccountProvider(account: account)
        }
        return ClaudeProvider(
            source: ClaudeUsageCLIProbe(
                locator: claudeExecutableLocator,
                workingDirectory: workspace.path,
                environmentOverrides: ["CLAUDE_CONFIG_DIR": configDirectory.path]
            ),
            accountID: account.id,
            emailSource: claudeIdentityReader(configDirectory: configDirectory)
        )
    }

    /// Default-login plan U2: the `.claude.json` reader for one Claude row. The built-in
    /// row (`configDirectory` nil) reads `~/.claude.json`; an extra reads the root of the
    /// same `CLAUDE_CONFIG_DIR` its probe is handed, so each row reads its own file. Demo,
    /// render, bench and XCTest-host launches get no reader and read no file.
    static func claudeIdentityReader(
        configDirectory: URL?,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ClaudeAccountEmailReading)? {
        guard !usesIsolatedServices(arguments: arguments, environment: environment) else { return nil }
        return ClaudeAccountEmailFileReader(configDirectory: configDirectory)
    }

    @MainActor
    private static func makeGrokProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        let configuration = ProviderAccountConfiguration.make(for: account)
        guard let authFile = configuration.grokAuthFile else {
            return UnavailableAccountProvider(account: account)
        }
        let overrides = configuration.grokHomeDirectory.map { ["GROK_HOME": $0.path] } ?? [:]
        // One reader for this account's `auth.json`: the billing fallback takes the token
        // from it, the email source takes the identity from the same record. No second
        // path resolution.
        let authReader = GrokAuthFileReader(path: authFile)
        return GrokProvider(
            source: GrokFallbackUsageSource(
                primary: GrokACPUsageSource(environmentOverrides: overrides),
                fallback: GrokHTTPUsageSource(authReader: authReader)
            ),
            accountID: account.id,
            emailSource: GrokCredentialEmailReader(authReader: authReader)
        )
    }

    /// KTD10: the built-in account reads the default home (all four XDG variables unset); an
    /// extra reads only its own `…/Accounts/opencode/<id>/` folders. `OpenCodeProvider.home` has
    /// no default, so an extra can never fall back to the built-in home.
    @MainActor
    private static func makeOpenCodeProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard let home = ProviderAccountConfiguration.make(for: account).opencodeHome else {
            return UnavailableAccountProvider(account: account)
        }
        return OpenCodeProvider(source: openCodeUsageSource, accountID: account.id, home: home)
    }

    @MainActor
    private static func makeCursorProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard account.isBuiltIn else { return UnavailableAccountProvider(account: account) }
        return CursorProvider(source: cursorUsageSource, emailSource: CursorStatusEmailProbe())
    }

    /// One ledger for the launch: its per-file memo is what keeps polls from rereading
    /// unchanged session logs (KTD10).
    private static let copilotLedger = CopilotUsageLedger(
        copilotHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot", isDirectory: true)
    )
    private static let copilotStatusSource = CopilotStatusSource()

    @MainActor
    private static func makeCopilotProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard account.isBuiltIn else { return UnavailableAccountProvider(account: account) }
        return CopilotProvider(
            statusSource: copilotStatusSource,
            ledger: copilotLedger,
            loginMemory: UserDefaultsCopilotLoginMemory(defaults: launchDefaults)
        )
    }

    @MainActor
    private static func makeAntigravityProvider(
        account: ProviderAccount,
        credentials _: CredentialStore,
        builtInClaudeWorkspace _: URL
    ) -> any UsageProvider {
        guard account.isBuiltIn else { return UnavailableAccountProvider(account: account) }
        return AntigravityProvider(source: antigravityUsageSource)
    }

    private static func apiSpendProviders(credentials: CredentialStore) -> [any APISpendProvider] {
        [
            AnthropicAPISpendProvider(credentials: credentials),
            OpenAIAPISpendProvider(credentials: credentials),
            XAIAPISpendProvider(credentials: credentials),
            CursorOnDemandSpendProvider(source: cursorUsageSource),
        ]
    }

    static func isTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    /// The Settings window's key store, one per launch rather than one per scene-body pass.
    /// Demo runs stay off the real Keychain: the unsigned debug binary would otherwise raise
    /// one prompt per API-key provider every time Settings opens.
    static let settingsCredentialStore = makeSettingsCredentialStore(isDemo: DemoFixture.isEnabled)

    /// U5: the one notification client per launch. The store's coordinator posts through
    /// it and `SettingsView` reads and requests permission through it (U6).
    @MainActor static let notificationClient: any NotificationClient = makeNotificationClient()

    static func usesInertNotificationClient(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: NotificationBundleDescriptor = .main
    ) -> Bool {
        arguments.contains("--demo")
            || arguments.contains("--render-popover")
            || arguments.contains("--render-loading-preview")
            || arguments.contains("--bench-ui")
            || isTestHost(environment: environment)
            || !bundle.supportsUserNotifications
    }

    static func makeNotificationClient(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: NotificationBundleDescriptor = .main
    ) -> any NotificationClient {
        guard !usesInertNotificationClient(arguments: arguments, environment: environment, bundle: bundle) else {
            return InertNotificationClient()
        }
        return UserNotificationClient.make(bundle: bundle)
    }


    static func usesIsolatedServices(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--demo")
            || arguments.contains("--render-popover")
            || arguments.contains("--render-loading-preview")
            || arguments.contains("--bench-ui")
            || isTestHost(environment: environment)
    }

    /// Feedback plan R8: the same launches that never touch iCloud also never read CLI
    /// versions or open a GitHub issue draft.
    static func usesInertFeedback(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        usesIsolatedServices(arguments: arguments, environment: environment)
    }

    static func usesInertWarmUp(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        usesIsolatedServices(arguments: arguments, environment: environment)
    }

    @MainActor
    static func makeSessionReliabilityRecord(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = launchDefaults
    ) -> SessionReliabilityRecord? {
        guard !usesIsolatedServices(arguments: arguments, environment: environment) else { return nil }
        return SessionReliabilityRecord(defaults: defaults)
    }


}


private struct UnavailableAccountProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String

    init(account: ProviderAccount) {
        id = account.providerID
        accountID = account.id
        displayName = account.providerID.raw.capitalized
    }

    func fetchSnapshot() async -> UsageSnapshot {
        .stale(for: id, reason: .transient("This provider is not available in this Pacemark build"))
    }
}

/// `--probe-opencode` turns its one capture into a snapshot without a second spawn.
private struct CapturedOpenCodeUsageSource: OpenCodeUsageSource {
    let capture: OpenCodeCapture
    func capture(home _: OpenCodeAccountHome) async -> OpenCodeCapture { capture }
}

/// `--probe-antigravity` turns its one capture into a snapshot without a second spawn.
private struct CapturedAntigravityUsageSource: AntigravityUsageSource {
    let capture: AntigravityCapture
    func capture() async -> AntigravityCapture { capture }
}

/// What an inert launch (`AppComposition.usesInertAntigravity`) reads instead of `agy`. No
/// process is started; the row simply stays "will retry".
struct InertAntigravityUsageSource: AntigravityUsageSource {
    func capture() async -> AntigravityCapture { .failed(.transient(.spawnFailed)) }
}

/// What an inert launch (`AppComposition.usesInertOpenCode`) reads instead of the client. No
/// process is started; the row simply stays "will retry".
struct InertOpenCodeUsageSource: OpenCodeUsageSource {
    func capture(home _: OpenCodeAccountHome) async -> OpenCodeCapture { .failed(.transient(.spawnFailed)) }
}

private struct CapturedGrokUsageSource: GrokUsageSource {
    let data: Data
    let transport: GrokUsageTransport

    func fetchUsage() async -> GrokUsageSourceResult {
        .payload(data, transport: transport)
    }
}

/// Diagnostic-only key store: serves one in-memory key for one provider so `--probe-xai`
/// can validate a raw management key without persisting it to the Keychain. Save/delete are
/// intentionally unsupported — the probe never writes.
private struct SingleAPIKeyStore: APIKeyStoring {
    let key: String
    let provider: APIKeyProvider

    func readAPIKey(for provider: APIKeyProvider) throws -> String {
        guard provider == self.provider else { throw CredentialError.notLoggedIn }
        return key
    }

    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        throw CredentialError.notLoggedIn
    }

    func deleteAPIKey(for provider: APIKeyProvider) throws {
        throw CredentialError.notLoggedIn
    }
}

/// Fixture-only AppKit entry point. No SwiftUI app scenes or status item are constructed.
private enum QALaunch {
    private final class CapturePanel: NSPanel {
        override var canBecomeKey: Bool { CommandLine.arguments.contains("--qa-key") }
        override var canBecomeMain: Bool { false }
    }

    static func argument(_ name: String, in arguments: [String] = CommandLine.arguments) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.dropFirst($0 + 1).first }
    }

    private struct PaceStatusComparison: View {
        let date: Date
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let kind = WindowKind.fiveHour
            let window = UsageWindow(kind: kind, utilization: 75, resetsAt: date.addingTimeInterval(9_000))
            let pace = MenuBarPace(window: window, now: date)
            let reading = UsageMeterReading(window: window)
            PDSCard("Pace and status", accessory: { EmptyView() }) {
                VStack(alignment: .leading, spacing: PDS.Space.m) {
                    HStack(spacing: PDS.Space.s) {
                        LedgerPaceBar(remaining: reading.fraction(for: .remaining), pace: pace,
                                      severity: reading.severity ?? .healthy)
                        Text("\(reading.roundedPercentage(for: .remaining) ?? 0)%")
                            .font(PopoverLedgerType.value)
                            .foregroundStyle(LedgerInk.usage(pace?.tier, fallback: reading.severity, scheme: scheme))
                        PDSHelpText("Using very fast")
                    }
                    if let limit = UsageLimitSentence(snapshot: DemoFixture.opencodeLimitedSnapshot, now: date) {
                        StatusSentence(text: limit.text, severity: .critical, indented: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, PDS.Space.s)
                // Leave room for StatusSentence's optical leading adjustment.
                .padding(.horizontal, PDS.Space.xs)
            }
            .frame(width: CGFloat(LedgerMetrics.columns.columnWidth))
            .padding(PDS.Space.s)
            // Compare the two production inks on a controlled plate in each appearance.
            .background(scheme == .dark ? Color.black : .white)
        }
    }

    @MainActor static func run() {
        guard Bundle.main.bundleIdentifier == "org.pacemark.qa.fixture" else { exit(64) }
        if AppComposition.isTestHost(), DemoFixture.isEnabled {
            // A re-identified XCTest host runs the app tests with their own windows and fixtures.
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.run()
            return
        }
        guard let id = argument("--qa-display").flatMap(UInt32.init),
              id != CGMainDisplayID(), CGDisplayModelNumber(id) == 0x5141,
              CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[.init("NSScreenNumber")] as? UInt32) == id })
        else { exit(64) }
        switch DemoFixture.scenarioRequest() {
        case .singleAccount, .multiAccount: break
        default: exit(64)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let fixtureDate = DemoFixture.now
        let controller = LoadingDemoController(loading: DemoFixture.scenarioRequest() == .multiAccount(.loading),
                                               clock: LoadingDemoClock(pinned: fixtureDate))
        let preferences = AppComposition.launchPreferences
        let store: UsageStore
        if argument("--pane") == SettingsPane.warmUp.rawValue && DemoFixture.scenarioRequest() == .multiAccount(.menubar) {
            store = MenuBarRenderHarness.fixtureStore(preferences: preferences, warmUpSample: true)
        } else {
            store = AppComposition.store(preferences: preferences, demoController: controller)
        }
        if let pose = argument("--qa-labels") {
            for (index, row) in store.menuBarMeterRows.filter(\.isShown).enumerated() {
                let label = pose == "numbers" ? String((index + 1) * 100) : (index == 0 && pose == "one" ? "Work" : "")
                store.setMeterLabel(label, for: row)
            }
            store.showMenuBarLabels = pose != "off"
        }
        controller.configure(store: store)
        let dark = argument("--appearance") == "dark"
        let increasedContrast = CommandLine.arguments.contains("--qa-increase-contrast")
        let appearanceName: NSAppearance.Name = switch (dark, increasedContrast) {
        case (true, true): .accessibilityHighContrastDarkAqua
        case (false, true): .accessibilityHighContrastAqua
        case (true, false): .darkAqua
        case (false, false): .aqua
        }
        let appearance = NSAppearance(named: appearanceName)
        if increasedContrast { app.appearance = appearance }

        let panel: NSPanel
        if CommandLine.arguments.contains("--qa-pace-status-comparison") {
            let host = NSHostingController(rootView: PaceStatusComparison(date: fixtureDate))
            panel = CapturePanel(contentViewController: host)
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.title = "QA Popover"
        } else if CommandLine.arguments.contains("--status-item") {
            // The virtual display has no system status bar. Model its button inset around the production label.
            let view = MenuBarStatusLabel(store: store, appearanceOverride: dark)
                .defaultAppStorage(AppComposition.launchDefaults)
                .transformEnvironment(\._colorSchemeContrast) { if increasedContrast { $0 = .increased } }
                .padding(.horizontal, MenuBarGaugeRenderer.meterGap / 2)
                .background {
                    if DemoFixture.scenarioRequest() != .multiAccount(.paceStates) {
                        Capsule().fill(.selection.opacity(0.3))
                    }
                }
                .padding(PDS.Space.s)
            panel = CapturePanel(contentViewController: NSHostingController(rootView: view))
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.title = "QA Status"
        } else if CommandLine.arguments.contains("--gallery") {
            let view = PDSGallery().frame(width: 660, height: 860)
            panel = CapturePanel(contentViewController: NSHostingController(rootView: view))
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.title = "QA Gallery"
        } else if CommandLine.arguments.contains("--popover") {
            panel = PopoverTuningModel.pinnedPanel(store: store, fixtureDate: fixtureDate,
                                                  qaIncreasedContrast: increasedContrast)
            panel.title = "QA Popover"
        } else {
            guard let pane = SettingsPane(rawValue: argument("--pane") ?? "general") else { exit(64) }
            preferences.settingsPane = pane
            let view = SettingsView(store: store, softwareUpdates: SoftwareUpdateController(enabled: false),
                preferences: preferences, credentialStore: AppComposition.settingsCredentialStore,
                launchControl: AppComposition.settingsLaunchControl, duplicateDetector: AppComposition.settingsDuplicateDetector,
                notificationClient: ScriptedNotificationClient(status: .authorized))
                .defaultAppStorage(AppComposition.launchDefaults)
                .environment(\.loadingDate, fixtureDate)
                .environment(\.openURL, OpenURLAction { _ in .discarded })
            panel = CapturePanel(contentViewController: NSHostingController(rootView: view))
            panel.styleMask = [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.setContentSize(NSSize(width: SettingsView.windowWidth, height: SettingsView.windowHeight))
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.title = "QA Settings"
        }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        if CommandLine.arguments.contains("--qa-midgrey") {
            panel.backgroundColor = .darkGray
            panel.isOpaque = true
        }
        // Glass samples windows beneath the panel. A solid panel background alone
        // still allows the wallpaper to influence its tint.
        let backdrop = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        backdrop.title = "QA Backdrop"
        backdrop.backgroundColor = dark ? NSColor(white: 0.13, alpha: 1)
            : NSColor(white: 0.91, alpha: 1)
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.hidesOnDeactivate = false
        backdrop.setFrame(screen.frame, display: false)
        backdrop.orderFrontRegardless()
        panel.appearance = appearance
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.setFrameTopLeftPoint(NSPoint(x: screen.frame.minX + 24, y: screen.frame.maxY - 24))
        panel.orderFrontRegardless()
        if CommandLine.arguments.contains("--qa-key") { panel.makeKey() }
        Task {
            await store.start()
            try? await Task.sleep(for: .milliseconds(500))
            // The hosting controller can resize around the old centre as fixtures settle.
            panel.setFrameTopLeftPoint(NSPoint(x: screen.frame.minX + 24, y: screen.frame.maxY - 24))
            if screen.frame.contains(panel.frame), !panel.isVisible { panel.orderFrontRegardless() }
            guard screen.frame.contains(panel.frame), panel.isVisible else {
                FileHandle.standardError.write(Data("QA fixture outside virtual display: \(panel.frame) in \(screen.frame)\n".utf8))
                exit(65)
            }
            guard !CommandLine.arguments.contains("--qa-key") || panel.isKeyWindow else { exit(65) }
            print("QA ready \(id)")
            fflush(nil)
        }
        withExtendedLifetime((backdrop, panel, controller)) { app.run() }
    }
}
