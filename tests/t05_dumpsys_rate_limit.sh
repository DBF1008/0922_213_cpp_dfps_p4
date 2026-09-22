#!/bin/bash
# t05: dumpsys 限频(开销回归)
# 在两个应用间快速来回切换约 20s, 统计 dfps 的 dumpsys 确认次数,
# 断言其不超过 DUMPSYS_MIN_INTERVAL_MS(2s) 限频上限, 且至少生效一次。
# 可选环境变量: APP_A, APP_B。

source "$(dirname "$0")/common.sh"
require_env

if [ -z "$APP_A" ] || [ -z "$APP_B" ]; then
    info "detecting launchable apps on device..."
    apps=$(detect_apps 2)
    APP_A=${APP_A:-$(echo "$apps" | sed -n 1p)}
    APP_B=${APP_B:-$(echo "$apps" | sed -n 2p)}
fi
[ -n "$APP_A" ] && [ -n "$APP_B" ] && [ "$APP_A" != "$APP_B" ] ||
    fail "need two distinct apps, set APP_A and APP_B manually"

mark=$(log_mark)
start_ts=$(date +%s)
i=0
while [ "$i" -lt 6 ]; do
    launch_app "$APP_A"
    sleep 1.5
    launch_app "$APP_B"
    sleep 1.5
    i=$((i + 1))
done
# wait for the last pending confirm to fire
sleep 3
elapsed=$(( $(date +%s) - start_ts ))

count=$(count_log_since "$mark" "confirm topapp by dumpsys")
# DUMPSYS_MIN_INTERVAL_MS=2000 -> at most one dumpsys per 2s, plus slack
limit=$((elapsed / 2 + 2))
info "dumpsys confirm count=$count in ${elapsed}s (limit=$limit)"

[ "$count" -ge 1 ] || fail "dumpsys confirm never ran (dfps binary not updated?)"
[ "$count" -le "$limit" ] || fail "dumpsys not rate limited: $count > $limit"
pass "dumpsys confirm is rate limited"
