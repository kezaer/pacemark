#!/bin/bash
set -eu
out=${1:?Usage: ui-pass.sh output-directory [--pace-states]}
mode=${2:-}
if [[ -n "$mode" && "$mode" != --pace-states ]]; then
    echo 'Usage: ui-pass.sh output-directory [--pace-states]' >&2
    exit 64
fi
mkdir -p "$out"
out=$(cd "$out" && pwd)
if [[ -e "$out/index.html" ]]; then
    echo "Choose a fresh output directory for this pass" >&2
    exit 1
fi
cd "$(dirname "$0")/../.."
qa=Scripts/qa/pacemark-qa
export PACEMARK_QA_SESSION="pass-$$"
finish() {
    local status=$?
    "$qa" display down >/dev/null || true
    if [[ $status != 0 ]]; then
        echo '<p>Partial pass. Only completed captures are listed.</p>' >> "$out/index.html"
    fi
    echo '</main>' >> "$out/index.html"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cat > "$out/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Pacemark live-window QA</title>
<style>body{font:16px system-ui}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr))}img{width:100%}</style>
<h1>Pacemark live-window QA</h1><main>
HTML
"$qa" display up
checks_pass=1
can_ax=1
can_shoot=1
shot() {
    [[ $can_shoot == 1 ]] || return 0
    local name="$1-$look.png" window="$2" error
    if error=$("$qa" shot "$out/$name" --window "$window" 2>&1); then
        if [[ $can_ax == 1 ]]; then
            local status=0
            "$qa" check --image "$out/$name" --window "$window" > "$out/${name%.png}.check.json" || status=$?
            if [[ $status != 0 && $status != 2 ]]; then return "$status"; fi
            python3 Scripts/qa/report-capture.py "$out/$name" || checks_pass=0
        fi
    else
        echo "$error" >&2
        [[ "$error" == *'Screen Recording permission required'* ]] || exit 1
        can_shoot=0
        echo '<p>Screen Recording permission required. Capture stopped.</p>' >> "$out/index.html"
    fi
}
bottom() {
    [[ $can_ax == 1 ]] || return 0
    "$qa" ax scroll "$1" bottom
    # AppKit briefly flashes the overlay scrollbar after an accessibility scroll.
    sleep 2
    shot "$2-bottom" "$3"
}
launch_fixture() {
    local attempt error
    for attempt in 1 2 3; do
        if error=$("$qa" launch "$@" 2>&1); then echo "$error"; return 0; fi
        echo "$error" >&2
        [[ "$error" == *"QA child failed readiness check"* ]] || return 1
    done
    return 1
}
pace_states() {
    launch_fixture --scenario pace-states --appearance "$look" --popover --summary-slots tightest nextReset
    "$qa" ax tree --window popover > "$out/pace-states-popover-$look.ax.txt"
    shot pace-states-popover popover
    launch_fixture --scenario pace-states --appearance "$look" --status-item
    "$qa" ax tree --window status > "$out/pace-states-status-$look.ax.txt"
    shot pace-states-status status
    launch_fixture --scenario pace-states --appearance "$look" --increase-contrast --popover --summary-slots tightest nextReset
    shot pace-states-ic-popover popover
    launch_fixture --scenario pace-states --appearance "$look" --increase-contrast --status-item
    shot pace-states-ic-status status
    launch_fixture --scenario pace-states --appearance "$look" --pace-status-comparison
    shot pace-states-status-red popover
    for pane in general menuBar appearance; do
        launch_fixture --scenario pace-states --appearance "$look" --pane "$pane"
        "$qa" ax select-pane "$pane" --window settings
        sleep 0.3
        shot "pace-states-$pane" settings
        if [[ "$pane" == menuBar || "$pane" == appearance ]]; then
            bottom settings.scroll "pace-states-$pane" settings
        fi
    done

    # Match the names and fixture settings in the approved baseline for changed surfaces.
    launch_fixture --scenario single-account --appearance "$look" --popover
    shot single-account popover
    for pane in general menuBar appearance; do
        launch_fixture --scenario multi-20 --appearance "$look" --pane "$pane"
        "$qa" ax select-pane "$pane" --window settings
        sleep 0.3
        shot "$pane-top" settings
    done
}
for look in light dark; do
    if [[ "$mode" == --pace-states ]]; then
        pace_states
        continue
    fi
    for layout in columns scroll; do
        launch_fixture --scenario multi-20 --appearance "$look" --popover --long-lists "$layout"
        if [[ "$look-$layout" == light-columns ]]; then
            if ! "$qa" ax tree --window popover > "$out/popover-tree.txt" 2>"$out/ax-status.txt"; then
                cat "$out/ax-status.txt" >&2
                grep -q 'Accessibility permission required' "$out/ax-status.txt" || exit 1
                can_ax=0
                echo '<p>Accessibility permission required. Scrolled captures skipped.</p>' >> "$out/index.html"
            fi
        fi
        shot "multi-20-$layout" popover
        if [[ "$layout" == scroll ]]; then bottom popover.cards multi-20-scroll popover; fi
    done
    for scene in banked-resets single-account; do
        launch_fixture --scenario "$scene" --appearance "$look" --popover
        shot "$scene" popover
    done
    for pane in general appearance menuBar notifications warmUp accounts apiSpend about; do
        launch_fixture --scenario multi-20 --appearance "$look" --pane "$pane"
        if [[ $can_ax == 1 ]]; then
            "$qa" ax select-pane "$pane" --window settings
            sleep 0.3
        fi
        shot "$pane-top" settings
        bottom settings.scroll "$pane" settings
    done
    for labels in empty one off numbers; do
        launch_fixture --scenario menubar --appearance "$look" --pane menuBar --labels "$labels"
        shot "menuBar-labels-$labels" settings
    done
    if [[ $can_ax == 1 ]]; then
        launch_fixture --scenario menubar --appearance "$look" --pane general --key
        shot "sidebar-key" settings
        launch_fixture --scenario menubar --appearance "$look" --pane notifications
        shot "notifications-disabled" settings
        "$qa" ax press "Remind me before unused usage resets" --window settings
        sleep 2
        shot "notifications-enabled" settings
        launch_fixture --scenario menubar --appearance "$look" --pane warmUp
        shot "warmUp-disabled" settings
        "$qa" ax press "Warm up idle limits" --window settings
        # The native switch continues its spring animation after AXPress returns.
        sleep 2
        shot "warmUp-enabled" settings
        launch_fixture --scenario menubar --appearance "$look" --pane warmUp --twelve-hour
        "$qa" ax press "Warm up idle limits" --window settings
        sleep 2
        shot "warmUp-twelve-hour" settings
    fi
    if [[ $look == dark ]]; then
        launch_fixture --scenario multi-20 --appearance dark --pane apiSpend --midgrey
        shot "apiSpend-midgrey" settings
    fi
done
if [[ $can_ax != 1 || $can_shoot != 1 || $checks_pass != 1 ]]; then
    echo "The capture matrix has missing evidence or failed measurements." >&2
    exit 2
fi
python3 Scripts/qa/validate-run.py "$out"
touch "$out/complete"
