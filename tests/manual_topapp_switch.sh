#!/bin/bash
# Manual regression test for the dfps top-app identification chain.
#
# Run on a host with adb access to a device where dfps is installed and
# running. Covers: app switch, back (gesture return) and home/launcher
# switch. For the best regression value, pick two apps with a SIMILAR
# number of threads (the old count-diff trigger missed those switches).
#
# Usage: tests/manual_topapp_switch.sh [PKG_A] [PKG_B]
set -u

LOG=/sdcard/Android/yc/dfps/dfps_log.txt
CUR=/sdcard/Android/yc/dfps/dfps_cur.txt
TIMEOUT_S=8
PKG_A="${1:-com.android.settings}"
PKG_B="${2:-}"
FAILED=0

note() { printf '\n== %s ==\n' "$*"; }
report_pass() { printf 'PASS: %s\n' "$*"; }
report_fail() { printf 'FAIL: %s\n' "$*"; FAILED=1; }

# package name of the current top app according to ActivityManager
actual_topapp() {
    adb shell dumpsys activity lru 2>/dev/null | grep -m1 ' TOP ' | sed -E 's/.* [0-9]+:([^/ ]+)\/.*/\1/'
}

# last package name published by dfps
dfps_topapp() {
    adb shell "grep 'topapp.pkgName' $LOG | tail -n 1" | sed -E 's/.*topapp\.pkgName //' | tr -d '\r'
}

# wait until dfps catches up with ActivityManager
check_follows() { # $1: scene description
    local expect
    expect="$(actual_topapp)"
    if [ -z "$expect" ]; then
        report_fail "$1: cannot read top app from dumpsys"
        return
    fi
    local i
    for i in $(seq 1 "$TIMEOUT_S"); do
        if [ "$(dfps_topapp)" = "$expect" ]; then
            report_pass "$1: dfps followed '$expect' within ${i}s"
            return
        fi
        sleep 1
    done
    report_fail "$1: dfps shows '$(dfps_topapp)', expected '$expect' after ${TIMEOUT_S}s"
}

launch() { # $1: package
    adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 1
}

note "preconditions"
if ! adb get-state 1>/dev/null 2>&1; then
    echo "FAIL: no adb device connected"
    exit 1
fi
if [ -z "$(adb shell pidof dfps | tr -d '\r')" ]; then
    echo "FAIL: dfps is not running on the device"
    exit 1
fi
if ! adb shell "[ -f $LOG ]" 2>/dev/null; then
    echo "FAIL: dfps log $LOG not found"
    exit 1
fi
echo "dfps is running, log: $LOG"

if [ -z "$PKG_B" ]; then
    for c in com.android.chrome com.android.calculator2 com.android.deskclock com.android.contacts; do
        if [ "$c" != "$PKG_A" ] && adb shell pm list package "$c" 2>/dev/null | grep -q "$c"; then
            PKG_B="$c"
            break
        fi
    done
fi
if [ -z "$PKG_B" ]; then
    echo "FAIL: no candidate PKG_B installed, pass one explicitly"
    exit 1
fi
echo "PKG_A=$PKG_A PKG_B=$PKG_B"

adb shell input keyevent KEYCODE_WAKEUP
sleep 1

note "scene 1: launch app A"
launch "$PKG_A"
check_follows "launch $PKG_A"

note "scene 2: switch to app B (similar thread count recommended)"
launch "$PKG_B"
check_follows "switch $PKG_A -> $PKG_B"

note "scene 3: back / gesture return"
adb shell input keyevent KEYCODE_BACK
sleep 1
check_follows "back to previous"

note "scene 4: home / launcher switch"
adb shell input keyevent KEYCODE_HOME
sleep 1
check_follows "home switch"

note "current refresh rate decision"
adb shell "cat $CUR" 2>/dev/null || echo "(notify file unavailable)"

if [ "$FAILED" -eq 0 ]; then
    echo
    echo "PASS manual_topapp_switch"
else
    echo
    echo "FAIL manual_topapp_switch"
fi
exit "$FAILED"
