#!/bin/bash
# t01: /proc 快路径识别准确性
# 对多个前台应用, 比较 GetTopAppNameProc 同算法(shell 复刻)与 dumpsys 真值,
# 验证新的 /proc 投票识别结果与 AMS 一致。
# 可选环境变量: TEST_APPS="pkg1 pkg2 ..." 指定被测应用。

source "$(dirname "$0")/common.sh"
require_env

if [ -n "$TEST_APPS" ]; then
    apps="$TEST_APPS"
else
    info "detecting launchable apps on device..."
    apps=$(detect_apps 4)
fi
[ -n "$apps" ] || fail "no launchable app found, set TEST_APPS manually"

rounds=0
mismatch=0
for pkg in $apps; do
    info "launching $pkg"
    launch_app "$pkg"
    sleep 3

    proc_result=$(proc_topapp)
    dumpsys_result=$(dumpsys_topapp)
    info "proc=$proc_result dumpsys=$dumpsys_result"

    rounds=$((rounds + 1))
    if [ -z "$proc_result" ]; then
        info "proc path returned empty (would fall back to dumpsys)"
        mismatch=$((mismatch + 1))
    elif [ -n "$dumpsys_result" ] && [ "$proc_result" != "$dumpsys_result" ]; then
        info "MISMATCH: proc=$proc_result dumpsys=$dumpsys_result"
        mismatch=$((mismatch + 1))
    fi
done

[ "$rounds" -gt 0 ] || fail "no test round executed"
info "$((rounds - mismatch))/$rounds rounds matched"
[ "$mismatch" -eq 0 ] || fail "$mismatch/$rounds rounds mismatched"
pass "proc identification matches dumpsys ground truth"
