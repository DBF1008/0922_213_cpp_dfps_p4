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

#pragma once

#include "cobridge_type.h"
#include "platform/module_base.h"
#include "topapp_policy.h"
#include "utils/time_counter.h"

class TopappMonitor : public ModuleBase {
public:
    TopappMonitor();
    ~TopappMonitor();
    void Start(void) override;

private:
    void OnTopappList(const void *data);
    void ScanAndTrigger(const PidList &pl);
    void ScheduleQuery(void);
    void QueryTopapp(void);

    TopappQueryPolicy policy_;
    TimeCounter scanTimer_;
    std::string prevPkgName_;
    HeavyWorker::Handle hwScan_;
    HeavyWorker::Handle hwQuery_;
    DelayedWorker::Handle dw_;
};
