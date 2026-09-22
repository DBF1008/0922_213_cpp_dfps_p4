#!/bin/bash
# Unit test: TopappQueryPolicy trigger/retry decision logic (host-side).
set -e
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
CXX="${CXX:-c++}"
OUT="$(mktemp -d)/ut_topapp_policy"
"$CXX" -std=c++17 -Wall -Werror -I "$BASEDIR/source" \
    "$BASEDIR/tests/ut_topapp_policy.cpp" -o "$OUT"
"$OUT"
