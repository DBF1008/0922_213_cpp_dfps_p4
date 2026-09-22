// Unit tests for TopappQueryPolicy (host-buildable, no Android deps).
// Build: c++ -std=c++17 -I source tests/ut_topapp_policy.cpp -o /tmp/ut_topapp_policy

#include "modules/topapp_policy.h"
#include <cstdio>

static int failures = 0;
static int checks = 0;

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        ++checks;                                                                                                      \
        if (!(cond)) {                                                                                                 \
            ++failures;                                                                                                \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                                                     \
        }                                                                                                              \
    } while (0)

using Names = std::set<std::string>;

// legacy behavior: a large task count jump triggers a query
static void TestCountJumpTriggers(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);  // initial observation
    CHECK(p.OnTopappTasks(Names{"com.a"}, 61) == true);  // +11 > 10
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);  // -11 > 10
}

// thread churn within one app must not trigger
static void TestSmallChurnIgnored(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);  // initial
    CHECK(p.OnTopappTasks(Names{"com.a"}, 55) == false); // +5, same proc set
    CHECK(p.OnTopappTasks(Names{"com.a"}, 45) == false); // -10, not > 10
    CHECK(p.OnTopappTasks(Names{"com.a"}, 45) == false); // steady state
}

// regression: switch between apps with similar thread counts must trigger
static void TestSimilarSizeSwitchTriggers(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);       // initial
    CHECK(p.OnTopappTasks(Names{"com.b"}, 48) == true);       // switch, |diff| = 2
    CHECK(p.OnQueryResult(true) == false);                    // query saw the change
    CHECK(p.OnTopappTasks(Names{"com.a"}, 51) == true);       // gesture back
    CHECK(p.OnTopappTasks(Names{"com.miui.home"}, 20) == true); // home switch
}

// multi-process apps: any foreground process set change triggers
static void TestMultiProcessSetChange(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a", "com.a:push"}, 60) == true);
    CHECK(p.OnTopappTasks(Names{"com.a"}, 55) == true);  // :push left the foreground set
    CHECK(p.OnTopappTasks(Names{"com.a"}, 56) == false); // steady again
}

// empty proc set (screen off / no foreground) is not a switch signal by itself
static void TestEmptyProcSetNotSwitchSignal(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true); // initial
    CHECK(p.OnTopappTasks(Names{}, 48) == false);       // empty set, small count diff
    CHECK(p.OnTopappTasks(Names{}, 10) == true);        // count jump still works (legacy)
}

// confirm re-query: expected change not observed -> bounded retries
static void TestConfirmRetryBounded(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);
    CHECK(p.OnTopappTasks(Names{"com.b"}, 50) == true); // switch expected
    CHECK(p.OnQueryResult(false) == true);              // stale result, retry 1
    CHECK(p.OnQueryResult(false) == true);              // stale result, retry 2
    CHECK(p.OnQueryResult(false) == false);             // bounded, give up
    // after giving up, further stale results do not re-arm retries
    CHECK(p.OnQueryResult(false) == false);
}

// a fresh trigger resets the confirm budget
static void TestNewTriggerResetsRetry(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);
    CHECK(p.OnTopappTasks(Names{"com.b"}, 50) == true);
    CHECK(p.OnQueryResult(false) == true);
    CHECK(p.OnQueryResult(false) == true);
    CHECK(p.OnQueryResult(false) == false);             // budget exhausted
    CHECK(p.OnTopappTasks(Names{"com.c"}, 50) == true); // new switch
    CHECK(p.OnQueryResult(false) == true);              // budget refilled
    CHECK(p.OnQueryResult(true) == false);              // change observed, done
}

// count-jump-only trigger (thread churn) does not arm confirm retries
static void TestCountJumpDoesNotArmRetry(void) {
    TopappQueryPolicy p;
    CHECK(p.OnTopappTasks(Names{"com.a"}, 50) == true);
    CHECK(p.OnTopappTasks(Names{"com.a"}, 70) == true); // +20, same proc set
    CHECK(p.OnQueryResult(false) == false);             // no confirm retry
}

int main(void) {
    TestCountJumpTriggers();
    TestSmallChurnIgnored();
    TestSimilarSizeSwitchTriggers();
    TestMultiProcessSetChange();
    TestEmptyProcSetNotSwitchSignal();
    TestConfirmRetryBounded();
    TestNewTriggerResetsRetry();
    TestCountJumpDoesNotArmRetry();

    printf("%d checks, %d failures\n", checks, failures);
    if (failures == 0) {
        printf("PASS ut_topapp_policy\n");
        return 0;
    }
    printf("FAIL ut_topapp_policy\n");
    return 1;
}
