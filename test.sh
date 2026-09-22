#!/bin/bash
# dfps top-app 识别链路回归测试入口。
#
# 前置条件:
#   1. 设备已安装基于本仓库构建的 dfps(magisk 模块)并正在运行;
#   2. 设备已连接 adb 且 su 可用;
#   3. 屏幕保持点亮、解锁状态。
#
# 用法:
#   ./test.sh            # 顺序执行 tests/ 下全部单元脚本
#   ./test.sh t01 t04    # 只执行指定用例
# 环境变量:
#   APP_A / APP_B        # 指定被测应用包名(默认自动探测)
#   TEST_APPS            # t01 使用的应用列表
#
# 注意: t03 为手动用例, 运行期间需要在设备上执行手势返回。

cd "$(dirname "$0")" || exit 1

# environment sanity check before running anything
bash -c 'source tests/common.sh; require_env' || exit 2

if [ "$#" -gt 0 ]; then
    tests=""
    for name in "$@"; do
        script="tests/${name}.sh"
        [ -f "$script" ] || script="tests/t${name}.sh"
        [ -f "$script" ] || script="$name"
        [ -f "$script" ] || {
            echo "unknown test: $name"
            exit 2
        }
        tests="$tests $script"
    done
else
    tests=$(ls tests/t[0-9]*.sh | sort)
fi

pass_count=0
fail_count=0
failed=""
for t in $tests; do
    echo "===== $t ====="
    if bash "$t"; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
        failed="$failed $t"
    fi
    echo
done

echo "================================"
echo "passed: $pass_count, failed: $fail_count"
[ -n "$failed" ] && echo "failed cases:$failed"
[ "$fail_count" -eq 0 ]
