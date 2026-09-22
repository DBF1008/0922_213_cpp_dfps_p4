#!/bin/bash
# t03: 手势返回(手动用例)
# 依次打开 APP_A、APP_B 后, 提示测试者在设备上做手势返回,
# 断言 dfps 在超时时间内识别到回到 APP_A。
# 可选环境变量: APP_A, APP_B, GESTURE_TIMEOUT(默认 20 秒)。

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
GESTURE_TIMEOUT=${GESTURE_TIMEOUT:-20}

launch_app "$APP_A"
sleep 2
launch_app "$APP_B"
sleep 2

mark=$(log_mark)
echo ">>> 请在 ${GESTURE_TIMEOUT}s 内在设备上执行手势返回(侧滑返回)回到 $APP_A ..."
wait_log_since "$mark" "topapp.pkgName $APP_A" "$GESTURE_TIMEOUT" ||
    fail "gesture back to $APP_A not detected within ${GESTURE_TIMEOUT}s"
pass "gesture back detected in time"
