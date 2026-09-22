#!/bin/bash
# Runs all host-side unit test scripts (tests/ut_*.sh).
# The on-device regression tests/manual_topapp_switch.sh requires an adb
# device and is intended to be run manually.
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
pass=0
failed=0
failed_list=""

for t in "$BASEDIR"/tests/ut_*.sh; do
    echo ">>> $(basename "$t")"
    if bash "$t"; then
        pass=$((pass + 1))
    else
        failed=$((failed + 1))
        failed_list="$failed_list $(basename "$t")"
    fi
    echo
done

echo "unit scripts: $pass passed, $failed failed"
if [ -n "$failed_list" ]; then
    echo "failed:$failed_list"
fi
[ "$failed" -eq 0 ]
