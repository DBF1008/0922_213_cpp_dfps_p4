#!/bin/bash
# t02: 线程规模相近的应用切换(核心回归)
# 旧实现仅在 |线程数差| > 10 时才查询 top-app, 两个线程数相近的应用
# 互相切换会漏判。本用例在两个应用间切换, 断言 dfps 日志里出现
# 新应用的 topapp.pkgName 记录。
# 可选环境变量: APP_A, APP_B 指定被测应用。

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
info "APP_A=$APP_A APP_B=$APP_B"

launch_app "$APP_A"
sleep 3
count_a=$(ta_thread_count)
launch_app "$APP_B"
sleep 3
count_b=$(ta_thread_count)
info "top-app threads: $APP_A=$count_a $APP_B=$count_b (diff=$((count_a - count_b)), old threshold=10)"

# switch A -> B -> A and require both transitions to be detected
mark=$(log_mark)
launch_app "$APP_A"
sleep 2
launch_app "$APP_B"

wait_log_since "$mark" "topapp.pkgName $APP_A" 10 || fail "switch to $APP_A not detected"
wait_log_since "$mark" "topapp.pkgName $APP_B" 10 || fail "switch to $APP_B not detected"
pass "app switch detected even with similar thread counts"
