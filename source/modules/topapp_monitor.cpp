/*
 * Copyright (C) 2021-2022 Matt Yang
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "topapp_monitor.h"
#include "utils/atrace.h"
#include "utils/misc.h"
#include "utils/misc_android.h"
#include <algorithm>
#include <spdlog/spdlog.h>

constexpr char MODULE_NAME[] = "TopappMonitor";
constexpr int64_t TOP_APP_PROC_DELAY_MS = 60;     // wait cpuset tasks settle
constexpr int64_t TOP_APP_SWITCH_DELAY_MS = 800;  // dumpsys confirm delay
constexpr int64_t DUMPSYS_MIN_INTERVAL_MS = 2000; // rate limit of dumpsys

TopappMonitor::TopappMonitor()
    : hw_(HwCreate(MODULE_NAME)), dwProc_(DwCreate(MODULE_NAME)), dwDumpsys_(DwCreate(MODULE_NAME)) {}

TopappMonitor::~TopappMonitor() {}

void TopappMonitor::Start(void) {
    using namespace std::placeholders;
    CoSubscribe("cgroup.ta.list", std::bind(&TopappMonitor::OnTopappList, this, _1));
}

void TopappMonitor::OnTopappList(const void *data) {
    if (CoHasSubscriber("topapp.pkgName") == false) {
        return;
    }

    const auto &pl = CoBridge::Get<PidList>(data);
    // Trigger on any tasklist content change instead of a thread count
    // threshold, so that switching between apps with similar thread counts
    // is still detected. The cost is bounded by the debounced delay below.
    PidSet tasks(pl.begin(), pl.end());
    if (tasks == prevTasks_) {
        return;
    }
    prevTasks_ = std::move(tasks);

    // Fast path: identify the top app from /proc, which is cheap enough to
    // run on every tasklist change. SetWork on the same handle replaces the
    // pending one, so bursts of updates are debounced.
    DwSetWork(dwProc_, [this]() { IdentifyByProc(); }, GetNowTs() + MsToUs(TOP_APP_PROC_DELAY_MS));
}

void TopappMonitor::IdentifyByProc(void) {
    ATRACE_SCOPE(GetTopAppNameProc);
    auto pkgName = GetTopAppNameProc(PidList(prevTasks_.begin(), prevTasks_.end()));
    if (pkgName.empty()) {
        // /proc is unreliable here, fall back to dumpsys
        ScheduleDumpsysConfirm();
        return;
    }
    if (PublishPkgNameIfChanged(pkgName)) {
        // confirm the fast path result with the AMS ground truth
        ScheduleDumpsysConfirm();
    }
}

void TopappMonitor::ScheduleDumpsysConfirm(void) {
    // dumpsys costs ~40ms, rate limit it to avoid system overhead
    auto elapsed = dumpsysTm_.ElapsedMs();
    auto delayMs = TOP_APP_SWITCH_DELAY_MS;
    if (elapsed < DUMPSYS_MIN_INTERVAL_MS) {
        delayMs = std::max(delayMs, DUMPSYS_MIN_INTERVAL_MS - elapsed);
    }

    auto delayed = [this]() {
        dumpsysTm_.Reset();
        auto heavywork = [this]() {
            ATRACE_SCOPE(GetTopAppName);
            SPDLOG_INFO("confirm topapp by dumpsys");
            auto pkgName = GetTopAppNameDumpsys();
            if (pkgName.empty()) {
                return;
            }
            PublishPkgNameIfChanged(pkgName);
        };
        HwSetWork(hw_, heavywork);
    };
    DwSetWork(dwDumpsys_, delayed, GetNowTs() + MsToUs(delayMs));
}

bool TopappMonitor::PublishPkgNameIfChanged(const std::string &pkgName) {
    std::lock_guard<std::mutex> lk(pkgMut_);
    if (pkgName == prevPkgName_) {
        return false;
    }
    prevPkgName_ = pkgName;
    SPDLOG_INFO("topapp.pkgName {}", pkgName);
    CoPublish("topapp.pkgName", &pkgName);
    return true;
}
