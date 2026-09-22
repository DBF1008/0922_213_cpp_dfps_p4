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

#include <cstdlib>
#include <set>
#include <string>

// TopappQueryPolicy decides when the expensive dumpsys top-app query should
// be issued, based on lightweight observations of the top-app cpuset.
//
// Two trigger signals are combined:
//  1. task count jump (legacy): cheap, but misses switches between apps
//     with similar thread counts
//  2. foreground process name set change: robust to similar thread counts,
//     covers app switch, gesture back and home/launcher switch
//
// It also bounds confirm re-queries, which cover the race where dumpsys runs
// before ActivityManager has settled the new top activity.
class TopappQueryPolicy {
public:
    static constexpr int TASK_NR_DIFF_MIN = 10;
    static constexpr int MAX_CONFIRM_RETRY = 2;

    // Observes the latest top-app task list.
    // procNames: distinct process names (cmdline) of the top-app cpuset.
    // taskNr: number of tasks in the top-app cpuset.
    // Returns true when a dumpsys top-app query should be scheduled.
    bool OnTopappTasks(const std::set<std::string> &procNames, int taskNr) {
        bool countJump = std::abs(taskNr - prevTaskNr_) > TASK_NR_DIFF_MIN;
        // an empty set means screen-off or no foreground process, which is
        // not a reliable app-switch signal on its own
        bool procChanged = (procNames.empty() == false) && (procNames != prevProcNames_);

        prevProcNames_ = procNames;
        prevTaskNr_ = taskNr;

        if (countJump || procChanged) {
            // only a process set change is a reliable switch signal;
            // thread churn inside one app does not deserve confirm re-queries
            expectChange_ = procChanged;
            confirmNr_ = 0;
            return true;
        }
        return false;
    }

    // Reports the result of a dumpsys top-app query.
    // pkgChanged: queried package differs from the last published one.
    // Returns true when a bounded confirm re-query should be scheduled.
    bool OnQueryResult(bool pkgChanged) {
        if (pkgChanged) {
            expectChange_ = false;
            confirmNr_ = 0;
            return false;
        }
        if (expectChange_ && confirmNr_ < MAX_CONFIRM_RETRY) {
            ++confirmNr_;
            return true;
        }
        expectChange_ = false;
        confirmNr_ = 0;
        return false;
    }

private:
    std::set<std::string> prevProcNames_;
    int prevTaskNr_ = 0;
    bool expectChange_ = false;
    int confirmNr_ = 0;
};
