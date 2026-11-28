# Pacemark Design System

Read before adding or changing UI. The tokens live in code, and the comments beside each one
hold its rationale (anchors like `R2C19`, `PA11b`). This file is the index: where each token
lives, which component does which job, and the rules for extending them.

## Mac Settings and popover

The shared SwiftUI components live in `Sources/PacemarkSharedUI/DesignSystem/PDS.swift`.
Use `Space` (4, 8, 12, 16 and 24 pt), `Radius`, `Typography`, `Ink` and `Metrics`.
Pane titles use 20 pt semibold, rows use 13 pt, help uses 11 pt and caps use
10 pt semibold with 0.6 pt tracking. Account rows are 28 pt tall. Settings panes
start 24 pt from the top and separate tiles by 16 pt. Both surfaces share the
glass and native material selection in `PDSSurface`. Card headers use a fixed height and centre marks, titles, chips and small controls between the top edge and divider. Centre row content between its boundaries. The Mac host supplies the existing tuning and accessibility overrides.

Section headers contain the title, an optional count chip and an optional read-only caption. A caps header must never repeat the first row label. Place a single setting in its related tile as a normal row. Place interactive controls in content rows. Accounts provider cards keep the provider switch and Add Source action together in their header because both apply to the whole provider.

`PDSCard` and `PDSCapsHeader` define section chrome. `PDSRow`, `PDSPickerRow`
and `PDSToggleRow` centre controls and share a divider. `PDSColumns` aligns
text to the leading edge and tabular numbers to the trailing edge. A menu column
has a fixed width, a leading truncated value and a trailing chevron. Its header
uses the same width. Use `PDSChip` for metadata, `PDSHelpText` for explanations,
`PDSHoverTip` for delayed panel help and `PDSSidebarRow` for navigation.

Run `swift run Pacemark --render-design-system <directory>` for both gallery sheets.
`Scripts/check-design-system.sh` checks Mac UI and shared views in CI. Document
measured renderer exceptions in `Scripts/design-system-allowlist.txt`.
Add a token when an existing role cannot express a need shared by multiple views.

## Rules

1. **Use a token or say why not.** Before writing a literal size, gap, radius, colour, or
   curve, look for it in the tables below. If a one-off literal is genuinely right, give it a
   one-line WHY comment. A bare magic number is a review finding.
2. **A new token needs a second call site.** A value used in one place stays a commented local
   constant. Once a second site needs it, promote it into the surface's `…Metrics`/`…Style`
   enum. If a Settings pane also needs it, move it to Core
   (`PacemarkColorValues`, `PacemarkBrandRamp`).
3. **Colours are WCAG-checked and scheme-paired.** Every ink/fill token takes `dark:` or
   `scheme:`. Don't use `.secondary`/`.tertiary` for text on cards; use
   `ProviderStyle.secondaryText`/`tertiaryText` (system tertiary measures ~2.3:1 on a dark tile).
   Brand values are OKLCH stops, and contrast is asserted in `BrandColorValuesTests`.
4. **One meaning per colour.** The Ledger and menu bar compare displayed remaining quota
   with the pace tick for live windows with a known future reset and duration. Either
   direction uses green within 5 percentage points, yellow up to 15 points, and red beyond
   15 points. Without pace evidence, green means above 50% left, yellow means above 15%
   through 50%, and red means 15% or less. Both dark critical fills have accepted contrast
   exceptions on the neutral track and Ledger card. The numeral has its own contrast-checked ink.
   Account and lifecycle states use neutral ink. Provider refusals, limit-reached sentences
   and spend alerts retain their separate critical status ink.
5. **Things that look the same behave the same.** A filled, outlined chip is *state*; a flat
   pill is a *metadata label* (`IdentityCapsuleStyle`). Every text button has a resting
   container; bare glyph buttons only in toolbar/title rows.
6. **Motion only from `PacemarkMotion`**. Never declare
   your own curve, duration, or spring in a view. No pulsing, breathing, or looping
   attention animations, ever. The loading drip is the approved exception: one falling
   drop per 1.8s while waiting on the user, with a 0.45s fall and 0.6s ripple; no scale or
   opacity pulse. Slosh, print, ghost wipe, end hold and drain durations live in
   `PacemarkCore/Models/LoadingMotion.swift` (loading-language KTD21).
7. **Provider parity** (AGENTS.md): styling reaches Claude, Codex, Grok, Cursor, Antigravity, Copilot, and OpenCode alike.
   Per-provider values go through `ProviderStyle`. Never special-case one provider's look inline.
8. **Chrome is restrained and layered.** Low-alpha fill + faint ring + 1pt inset lip + 1pt
   shadow. Never a bright rim (keep it ≤ ~0.15 white in dark). Content tiles are never a
   second `.glassEffect` (glass is only for the shell and controls).

## Settings and ledger alignment

- A form row includes its title, optional help and trailing control. Center the control on the entire row and use 8 pt of padding above and below its content. Place dividers between complete rows.
- Use a bordered native pop-up for form choices. Reserve the borderless menu and chevron for dense table cells. Use the PDS scheme-specific link ink on translucent cards.
- Align account headers with names. Provider marks and disclosure arrows occupy the same leading slot. Align numeric headings with the trailing edge of their values. Leave 12 pt between adjacent reading headers and truncate long headings at the tail.
- The Settings header mark is 32 pt and begins at the destination icon column. Separate the title from the mark by 8 pt and the list from the header by 12 pt.
- Beside percentages use a font size equal to half the rendered ring diameter. Label size controls only the label band. Reserve at least 2 pt above and below labeled status-item artwork.
- Center pane specimens in a full-width Preview card. Summary tiles and their pickers share equal columns.

A menu-bar strip reserves one shared label band whenever any meter has a label. Unlabelled gauges in that strip share the labelled gauge’s baseline.

## Where tokens live

All paths are under `Sources/`.

| Concern | Token home | Notes |
|---|---|---|
| Motion | `PacemarkSharedUI/PacemarkMotion.swift` | `settle` (house curve, 200ms), `quickSettle`, `pressDown` + `pressScale` 0.96, `hoverIn`/`hoverOut` (glyph pills), `rowHoverIn`/`rowHoverOut` (plain ease for full-width rows whose ink changes on hover), `valueSpring` (critically damped, never overshoots a value), `reorder`, `paneIn`/`paneOut`, `partIn`/`partOut`. Reduce Motion: wrap with `resolved(_:_:reduceMotion:)`, `fade`, `numericText`. AppKit event detection and window curve stay in `PacemarkApp/UI/PacemarkMotion+AppKit.swift`. |
| Brand & semantic colour | `PacemarkCore/Models/BrandColorValues.swift` | `PacemarkBrandColorValues`, `PacemarkBrandRamp` (OKLCH), `PacemarkColorValues` (text inks, hairlines, wells, fills), `PacemarkSeverityColorValues`. SwiftUI-free. |
| Colour call surface (shared by both apps) | `PacemarkSharedUI/ProviderStyle.swift` | `accent`, `textAccent`, `secondaryText`/`tertiaryText`, `accountTitleInk`, meter inks, `severityColor`/`severityFill`, `recessedWell`, CTA gradients, SVG mark per scheme. |
| Popover shell | `PopoverCardMetrics` (`PopoverView.swift`) | Shell width 384, margin 19, card width derived from them. `shellWidth(columns:)` is 384 for one column and 750 for two (two cards plus the 20pt gap); `cardsHeightCap` 640 is where one column becomes two, and where two columns scroll. With Scroll vertically, `verticalCardsHeightCap` scrolls at the screen's free height less `popoverChromeHeight`, at most 900 (a 300 guard covers a bad screen reading). |
| Popover columns | Core `AccountColumnsPlanner` (`Models/AccountColumnsPlan.swift`) → `PopoverPlanModel` → `PopoverColumnsLayout` | Card pad 13, card gap 20, account gap 26 (Standard) or 4 (Compact). Never more than two columns. |
| Compact account row | `PacemarkApp/UI/CompactAccountRow.swift` (`CompactAccountRow`, `CompactCardHeader`), decided by Core `CompactAccountRowRecipe` | Approved 2026-10-13: row 26, rows 4 apart, title 13 semibold, cells 84 wide and 12 apart, cell numeral 15 semibold, no per-cell label. One `CompactCardHeader` per card (26pt: 11pt tertiary "5h left"/"wk used" right-aligned over each number column, the provider name over the account names, one hairline) repeats in each column a split card occupies. Meters draw as the Micro twin of the user's style. A Standard section among Compact rows sits 11pt further out each side. |
| Ledger account row and summary | `PacemarkApp/UI/Ledger/`: `LedgerMetrics`, `PopoverLedgerType`, `LedgerAccountRow`, `LedgerSummaryStrip`. Decisions in Core `LedgerRowRecipe` and `PopoverSummaryRecipe`. | 36pt rows with a 70pt pace bar and monospaced percentage and reset columns. Expanded rows list the account’s individual windows. Optional summaries use the same pace bar for quota. Pace numerals use `PDS.Ink` warning and critical tokens. Ledger sections use `PDSCard`. Fixed-height summary tiles share `PDSCardSurface`. |
| Provider card | `PacemarkApp/UI/ProviderCardView.swift`, `PacemarkSharedUI/IdentityRow.swift`, `PacemarkSharedUI/IdentityCapsule.swift` (`IdentityRowMetrics`) | Card: `.padding(13)` + `.raisedTile(cornerRadius: 10)`. Identity row: mark slot 15, gap 6, title 15 semibold / −0.15 kern, capsule height 18, capsule label 10.5 medium / +0.2 kern. |
| Capsules & chips | `PacemarkSharedUI/IdentityCapsule.swift`: `IdentityCapsuleStyle`, `.identityCapsule(fill:horizontalPadding:border:)` | Metadata fill 0.12, stale fill 0.18, state border 0.35 @ 1pt. |
| Setup cards | `SetupCardMetrics`, `ClaudeSetupStyle`, `CodexSetupStyle` | Gaps 6 / 12 / 20. Body 12.5, notes 11. The two provider enums stay decoupled by design; their numbers live in `PacemarkBrandRamp`. |
| Settings copy | `SettingsCopy` | Any string two panes print. |
| Optical alignment | `PacemarkApp/UI/OpticalLeading.swift` | `.opticalLeading(_:size:weight:)` for text starting a card line; `.capHeightCentered(size:weight:)` for mixed-size rows. Not for chip labels. |
| Meter rendering | `PacemarkCore/Models/MeterStyle.swift` (`MeterRecipe`) → `PacemarkSharedUI/MeterGauge.swift` | The pure format × shape × fill contract. `MeterGauge` is the popover's only meter renderer. |

**Shared UI module ownership.** `PacemarkSharedUI/` holds the popover's stateless pieces.

**Known gaps:**
- The compatibility Standard and Compact layouts are retained for upstream sync. The fork resolves the shipped Mac popover to Ledger through `Preferences.effectiveAccountLayout`. Those compatibility layouts have no named type ramp or spacing scale. Its values
  are local literals with WHY comments (card pad 13, rhythm 9). Match the neighbouring
  card code, and if you add a second use of a value, promote it (rule 2).

## Components — which one for which job

| Job | Use | Not |
|---|---|---|
| Content tile on the Mac popover or in Settings | `PDSCard` | Custom background + shadow; nested glass |
| Mac Settings section | `SettingsLedgerTile` inside `SettingsPaneScaffold` | Hand-rolled headers |
| Mac Settings row | `PDSRow`, `PDSToggleRow`, `PDSHelpText`, `PDSChip` | Raw `Toggle` + `Text` stacks |
| Swatch / thumbnail picker | `SettingsSwatchButtonStyle` + `.selectionChrome` + `.settingsSelectionGroup` | Custom selection borders |
| Primary action (one per card) | `ClaudePrimaryButtonStyle` / `CodexPrimaryButtonStyle` | A second primary |
| An account's status + its recovery (sign in, try again, install, check now) on a popover card | `CardRowAction` — the sentence is the primary action, the secondary trails as a glyph; `CardRowStatusLine` / `CardRowWaitingLine` when there is nothing to open | A status sentence with a chip row under it |
| Any other text-labelled secondary button | `SetupChipButtonStyle` (`.regular` card foot, `.small` account row, Settings) | `HoverButtonStyle` on a word |
| Glyph-only control (gear, +, …, copy, trash, chevron) | `HoverButtonStyle` | A chip container |
| A row of card actions | `CardActionRow` / `ActionChipFlow` | Manual `HStack` wrapping |
| Account / spend title line | `IdentityRow` | Re-deriving title recipe |
| Status line under an account | `StatusSentence` + `StatusSentenceSeverity` | Severity (meter) colours |
| Plan / period / stale capsule | `.identityCapsule`, `PlanCapsule` | Padding-sized capsules (they drift in height) |
| Usage meter | `UsageBarView` / `MeterGauge` via `MeterRecipe` | New bar drawing |
| One account on one line (Compact layout) | `CompactAccountRow` over a `CompactAccountRowRecipe`; its cells are `UsageBarView(compactLabel:)` | A new meter cell, or deciding windows in the view |
| Provider cards in one or two popover columns | `PopoverColumnsLayout` + `.layoutValue(key: PopoverColumn.self, ...)`, placed from `PopoverPlanModel` | A width that changes with data while open, `.offset` handovers |
| API spend line | `APISpendRow`, resolved from Core `APISpendPresentation` | A separate spend renderer |
| Provider cards across an iPad's width | `FlowingColumns` + `.flowingColumnsCard(id:)` | Fixed column counts, `.offset` handovers |
| Pending numeric-meter layout | Static `SkeletonMeter` beside the account's loading vessel | Animated skeletons, pulses |
| Loading and waiting vessel | `HalftoneVesselView` / `HalftonePillRow` (shared), `MiniPill` (macOS rows) | Slosh while working, drip while waiting on the user, ghost → print when a fresh reading lands; `SetupMotion` and `ReprintRecipe` decide states. |
| Provider mark | `ProviderLogoView` | Loading SVGs directly |
| Revealing a Settings sub-option | `.transition(.settingsReveal)` | Ad-hoc slide/scale |

## Verifying a UI change

- Fast headless check: `swift run Pacemark --render-popover <dir> [--meter-style …]`. This
  is a sanity check only, not final evidence (see `BUGS.md`).
- Final check: `swift run Pacemark --demo <scenario>` in the live popover, both light and
  dark appearances. Ask before driving the screen.
- Motion and performance: a still proves layout, not what moved or what it cost. Check frames
  and body counts offscreen, before and after, per
  `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md`.
- Check both appearances, and Increase Contrast/Reduce Transparency (tiles fall back to
  solid + separator).
- Design explorations and plans are kept outside the repo; the decision anchors cited in code
  comments (KTD, R, SM…) refer to them. Durable learnings live in `docs/solutions/`.

### Measured Mac layout

Rows in a form card share the same trailing control edge. Use one divider below a table’s column headings. Allow 8pt from header ink or controls to either vertical edge of the header and 8pt between table columns. Single-line rows share a height, as do rows with help in the same card. Enabled text and links need 4.5:1 contrast on the rendered surface. Disabled text and checkbox outlines need 3:1. When a master switch is off, show its row and help. Reveal dependent controls when it turns on, using standard Settings motion and respecting Reduce Motion. Preserve their stored values while hidden.
