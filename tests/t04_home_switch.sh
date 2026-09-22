#!/bin/bash
# t04: 桌面切换
# 先打开一个应用, 再按 HOME 回桌面, 断言 dfps 识别到 launcher。

source "$(dirname "$0")/common.sh"
require_env

launcher=$(home_pkg)
[ -n "$launcher" ] || fail "cannot resolve launcher package"
info "launcher=$launcher"

app=${APP_A:-com.android.settings}
launch_app "$app"
sleep 2

mark=$(log_mark)
adb shell input keyevent KEYCODE_HOME
wait_log_since "$mark" "topapp.pkgName $launcher" 10 ||
    fail "home switch to $launcher not detected"
pass "home switch detected"
