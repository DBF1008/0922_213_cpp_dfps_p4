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
#include <cstdio>
#include <spdlog/spdlog.h>

constexpr char MODULE_NAME[] = "TopappMonitor";
constexpr int64_t TOP_APP_SWITCH_DELAY_MS = 800;
constexpr int64_t SCAN_MIN_INTERVAL_MS = 200;
constexpr size_t SCAN_TASKS_MAX = 512;
constexpr size_t PROC_CMDLINE_MAX_LEN = 256;

TopappMonitor::TopappMonitor()
    : hwScan_(HwCreate(MODULE_NAME)), hwQuery_(HwCreate(MODULE_NAME)), dw_(DwCreate(MODULE_NAME)) {}

TopappMonitor::~TopappMonitor() {}

void TopappMonitor::Start(void) {
    using namespace std::placeholders;
    CoSubscribe("cgroup.ta.list", std::bind(&TopappMonitor::OnTopappList, this, _1));
}

void TopappMonitor::OnTopappList(const void *data) {
    if (CoHasSubscriber("topapp.pkgName") == false) {
        return;
    }

    // HeavyWorker coalesces pending work per handle, so bursts of cgroup
    // events collapse into one scan on the low-priority worker thread
    PidList snapshot = CoBridge::Get<PidList>(data);
    HwSetWork(hwScan_, [this, snapshot]() { ScanAndTrigger(snapshot); });
}

static std::string ReadProcName(int pid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    std::string buf;
    if (ReadFile(path, &buf, PROC_CMDLINE_MAX_LEN) <= 0) {
        return {};
    }
    return buf.substr(0, buf.find('\0'));
}

void TopappMonitor::ScanAndTrigger(const PidList &pl) {
    // rate-limit /proc scans, the delayed query below is coalesced anyway
    if (scanTimer_.ElapsedMs() < SCAN_MIN_INTERVAL_MS) {
        return;
    }
    scanTimer_.Reset();

    // threads share the cmdline of their process, so the distinct cmdline
    // set of the top-app cpuset is the set of foreground processes;
    // an app switch always changes this set, even when the two apps have
    // a similar number of threads
    std::set<std::string> procNames;
    auto nr = std::min(pl.size(), SCAN_TASKS_MAX);
    for (size_t i = 0; i < nr; ++i) {
        auto name = ReadProcName(pl[i]);
        if (name.empty() == false) {
            procNames.insert(std::move(name));
        }
    }

    if (policy_.OnTopappTasks(procNames, static_cast<int>(pl.size()))) {
        ScheduleQuery();
    }
}

void TopappMonitor::ScheduleQuery(void) {
    auto delayed = [this]() { HwSetWork(hwQuery_, [this]() { QueryTopapp(); }); };
    DwSetWork(dw_, delayed, GetNowTs() + MsToUs(TOP_APP_SWITCH_DELAY_MS));
}

void TopappMonitor::QueryTopapp(void) {
    ATRACE_SCOPE(GetTopAppName);
    auto pkgName = GetTopAppNameDumpsys();
    bool changed = (pkgName.empty() == false) && (pkgName != prevPkgName_);
    if (changed) {
        prevPkgName_ = pkgName;
        SPDLOG_DEBUG("topapp.pkgName {}", pkgName);
        CoPublish("topapp.pkgName", &pkgName);
    }
    // the query may have run before ActivityManager settled the new top
    // activity; re-check a bounded number of times when a switch was expected
    if (policy_.OnQueryResult(changed)) {
        ScheduleQuery();
    }
}
