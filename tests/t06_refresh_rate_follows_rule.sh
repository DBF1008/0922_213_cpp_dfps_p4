#!/bin/bash
# t06: 刷新率规则跟随(端到端回归)
# 备份并替换 dfps 配置, 给 APP_B 设置与默认规则不同的刷新率,
# 断言切到 APP_B 后 dfps 通知文件及时变为对应值, 结束后恢复原配置。
# 可选环境变量: APP_A, APP_B, TEST_HZ_A(默认 60), TEST_HZ_B(默认 120)。

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
TEST_HZ_A=${TEST_HZ_A:-60}
TEST_HZ_B=${TEST_HZ_B:-120}
[ "$TEST_HZ_A" != "$TEST_HZ_B" ] || fail "TEST_HZ_A and TEST_HZ_B must differ"

BAK="/data/local/tmp/dfps_cfg_backup.txt"
rootsh "cp $DFPS_CFG $BAK"
restore() {
    rootsh "cp $BAK $DFPS_CFG && rm -f $BAK"
    info "original config restored"
}
trap restore EXIT

info "applying test config: '*'/$APP_A -> $TEST_HZ_A, $APP_B -> $TEST_HZ_B"
{
    echo "* $TEST_HZ_A $TEST_HZ_A"
    echo "- $TEST_HZ_A $TEST_HZ_A"
    echo "$APP_A $TEST_HZ_A $TEST_HZ_A"
    echo "$APP_B $TEST_HZ_B $TEST_HZ_B"
} > /tmp/dfps_test_cfg.txt
adb push /tmp/dfps_test_cfg.txt /data/local/tmp/dfps_test_cfg.txt >/dev/null
rootsh "cp /data/local/tmp/dfps_test_cfg.txt $DFPS_CFG && rm -f /data/local/tmp/dfps_test_cfg.txt"
rm -f /tmp/dfps_test_cfg.txt
# dfps daemon watches the config file and restarts automatically
sleep 3

launch_app "$APP_B"
wait_cur_hz "$TEST_HZ_B" 10 || fail "refresh rate did not follow rule of $APP_B ($TEST_HZ_B)"

launch_app "$APP_A"
wait_cur_hz "$TEST_HZ_A" 10 || fail "refresh rate did not follow rule of $APP_A ($TEST_HZ_A)"

pass "refresh rate follows per-app rule after app switch"
