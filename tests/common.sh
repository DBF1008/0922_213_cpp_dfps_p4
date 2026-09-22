#!/bin/bash
# Common helpers for dfps on-device regression tests.
# All tests run on the host and drive the Android device through adb.

DFPS_DIR="/sdcard/Android/yc/dfps"
DFPS_LOG="$DFPS_DIR/dfps_log.txt"
DFPS_CUR="$DFPS_DIR/dfps_cur.txt"
# shellcheck disable=SC2034 # used by test scripts sourcing this file
DFPS_CFG="$DFPS_DIR/dfps.txt"
TA_TASKS="/dev/cpuset/top-app/tasks"

info() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
fail() {
    echo "[FAIL] $*"
    exit 1
}

# Run a command string as root on the device.
rootsh() {
    printf '%s\n' "$*" | adb shell su 2>/dev/null
}

require_env() {
    command -v adb >/dev/null 2>&1 || {
        echo "adb not found in PATH"
        exit 2
    }
    adb get-state >/dev/null 2>&1 || {
        echo "no adb device connected"
        exit 2
    }
    rootsh "id" | grep -q "uid=0" || {
        echo "root shell required (magisk su)"
        exit 2
    }
    [ -n "$(adb shell pidof dfps 2>/dev/null | tr -d '\r')" ] || {
        echo "dfps is not running on the device"
        exit 2
    }
    rootsh "test -f $DFPS_LOG && echo ok" | grep -q ok || {
        echo "dfps log $DFPS_LOG not found"
        exit 2
    }
}

# Current line count of the dfps log, used as a marker.
log_mark() {
    rootsh "wc -l < $DFPS_LOG" | tr -dc '0-9'
}

# Log lines appended after the given marker.
log_since() {
    local mark=$1
    rootsh "tail -n +$((mark + 1)) $DFPS_LOG" | tr -d '\r'
}

# Wait until a log line matching the pattern appears after the marker.
wait_log_since() {
    local mark=$1 pattern=$2 timeout=$3 elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if log_since "$mark" | grep -q "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Count log lines matching the pattern after the marker.
count_log_since() {
    local mark=$1 pattern=$2
    log_since "$mark" | grep -c "$pattern"
}

# Host-side re-implementation of GetTopAppNameProc(): vote on the base
# process name of the top-app cpuset tasks read from /proc/<tid>/cmdline.
proc_topapp() {
    rootsh 'for p in $(cat '"$TA_TASKS"' | head -64); do tr "\0" "\n" < /proc/$p/cmdline 2>/dev/null | head -1; done' |
        tr -d '\r' |
        awk '
            {
                raw = $1
                name = raw
                sub(/:.*/, "", name)
                if (name == "" || index(name, "/") > 0) next
                votes[name]++
                if (index(raw, ":") == 0) exact[name]++
            }
            END {
                top = ""; tv = 0; te = 0
                for (n in votes) {
                    e = exact[n] + 0
                    if (votes[n] > tv || (votes[n] == tv && e > te)) {
                        top = n; tv = votes[n]; te = e
                    }
                }
                print top
            }'
}

# Ground truth from AMS, same source as GetTopAppNameDumpsys() (Android 10+).
dumpsys_topapp() {
    adb shell dumpsys activity lru 2>/dev/null |
        tr -d '\r' |
        grep ' TOP' |
        head -1 |
        sed -E 's/.*[ :][0-9]+:([^\/: ]+)[\/:].*/\1/'
}

home_pkg() {
    adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME \
        2>/dev/null | tr -d '\r' | grep -o 'packageName=[^ ;]*' | head -1 | cut -d= -f2
}

launch_app() {
    adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

# First N installed packages that have a launcher activity.
detect_apps() {
    local count=${1:-4}
    {
        echo com.android.settings
        adb shell pm list packages -3 2>/dev/null | tr -d '\r' | sed 's/^package://'
    } | while read -r pkg; do
        [ -z "$pkg" ] && continue
        adb shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $pkg 2>/dev/null" |
            tr -d '\r' | grep -q "$pkg/" && echo "$pkg"
    done | awk '!seen[$0]++' | head -"$count"
}

ta_thread_count() {
    rootsh "wc -l < $TA_TASKS" | tr -dc '0-9'
}

# Wait until dfps writes the given refresh rate into the notify file.
wait_cur_hz() {
    local hz=$1 timeout=$2 elapsed=0 cur
    while [ "$elapsed" -lt "$timeout" ]; do
        cur=$(rootsh "cat $DFPS_CUR" | tr -dc '0-9')
        [ "$cur" = "$hz" ] && return 0
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
