# Pacemark UI work with a local model

Pacemark is a macOS menu bar app written in Swift 6 and SwiftUI.
The menu bar and popover show subscription usage and reset times.
Settings › Accounts manages which provider logins appear.

## Build and replay

Run `swift build` and `swift test` with Xcode 27 selected. Use a built-in demo such as `swift run Pacemark --demo single-account` for fixture data. Captured replay reads a local developer capture and keeps account edits in memory. Use `swift run Pacemark --demo captured` after creating a capture with the app's `--capture-demo` option. Keep real captures out of the repository.

## Find the UI

The popover and menu bar label live in [the Mac UI directory](../../Sources/PacemarkApp/UI). The [Settings panes](../../Sources/PacemarkApp/UI/Settings) bind to preferences through UsageStore. Read the [design guide](../../DESIGN.md) for tokens and layout rules.

## Live-window QA

From the checkout, run the light and dark fixture pass into a fresh directory.

```bash
./Scripts/pacemark.sh build
Scripts/qa/ui-pass.sh .build/qa-run-1
```

For the five pace states and their Settings previews, run
`Scripts/qa/ui-pass.sh .build/qa-pace-states --pace-states`. The menu bar capture uses the
production status artwork in an inactive fixture panel because the virtual display has no system
menu bar. The pace pass also captures both Increase Contrast appearances and a limit-reached
sentence beside a critical pace meter. Headless checks use `--render-popover <dir> --render-scenario pace-states` and
`--render-menubar <dir> --render-scenario pace-states`.

Open the resulting `index.html` to inspect the captured windows. To drive a single fixture, use the checkout's controller.

```bash
qa=Scripts/qa/pacemark-qa
"$qa" display up
"$qa" launch --scenario multi-20 --appearance dark --popover --long-lists scroll
"$qa" ax tree --window popover
"$qa" ax scroll popover.cards bottom
"$qa" shot .build/popover.png --window popover
"$qa" launch --scenario single-account --appearance light --pane general
"$qa" ax select-pane appearance
"$qa" ax tree --window settings
"$qa" ax press <identifier-or-title>
"$qa" ax set <identifier> <value>
"$qa" shot .build/display.png
"$qa" quit
"$qa" display down
```

Use a built-in demo scenario or `single-account`. The launch command accepts `--long-lists columns|scroll` and `--meter-style micro.chip.event` (or another supported meter token). Each launch replaces this session's previous QA window. The controller copies the built app to a separately identified fixture bundle, runs it with a fresh QA defaults suite, and places a nonactivating panel on a 1512 × 982 point virtual display. The display uses private CoreGraphics classes and requires a logged-in graphical session.

AX commands require Accessibility permission. Capture requires Screen Recording permission. The helper checks each permission without prompting and prints the responsible process name and path on denial. In System Settings → Privacy & Security, grant the indicated permission to that host. The pass records missing permissions in the contact sheet and exits unsuccessfully if captures remain outstanding.

The pinned popover uses the app's own shell. Final acceptance of the system MenuBarExtra glass requires a human look.

Each capture has a JSON layout report linked by its image stem (`.check.json`).
The comparison uses ImageMagick, blurs both captures by one pixel, and counts pixels
whose grayscale difference exceeds 4%. The contact sheet flags every nonzero score.
After reviewing a complete pass, run `Scripts/qa/baseline.sh approve <run-dir>`
to store its reference images under `~/Library/Application Support/Pacemark/QA/baseline/`.
Hand off the build only when measured checks pass, every changed capture is explained
in the round's change list or fixed, and independent visual review has no high or medium findings.

The acceptance matrix covers the eight Settings panes and the popover.

The fixture keeps Settings inactive and uses a nonactivating solid window behind
the captured panel on its virtual display. The app and its demo data use a pinned
clock. The layout report measures a 12pt horizontal card inset, 8pt divider
clearance, row-padding and column-edge differences up to 1pt, intersecting
controls, and misplaced dividers. It checks visible text ranges where AX supplies
them. With a capture supplied via `check --image <png>`, disabled AX text is
sampled for a minimum 3:1 luminance contrast. Capture geometry is in points.

Each report retains the capture-relative accessibility tree and per-rule measurements.
The checker aligns trailing controls to within 1pt (B7). It samples rendered glyphs against
their local background in labelled controls and uses Vision word rectangles to separate text
inside combined accessibility elements (B8). The floor is 4.5:1 for enabled text and links,
and 3:1 for disabled labels and checkbox outlines. Headers need at least 8pt above and below
their content, with at most 1pt difference (B9). Rows of one kind can differ in height by up
to 1pt (B10), adjacent table columns require at least 8pt of clearance (B11), and the sidebar
identity-to-first-row gap is 12pt with 1pt tolerance (B12). The matrix includes menu labels,
enabled Warm-up, and a dark API Spend capture on a midgrey substrate.
