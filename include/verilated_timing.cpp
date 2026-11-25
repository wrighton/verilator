// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// Code available from: https://verilator.org
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2001-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//=========================================================================
///
/// \file
/// \brief Verilated timing implementation code
///
/// This file must be compiled and linked against all Verilated objects
/// that use timing features.
///
/// See the internals documentation docs/internals.rst for details.
///
//=========================================================================

#include "verilated_timing.h"

#if VM_DPI
//======================================================================
// Aborted calls must resume their blocked imports before their workers can be released.
namespace VerilatedDpiCall {
static VerilatedMutex s_mutex;
static std::vector<std::function<void()>> s_aborted VL_GUARDED_BY(s_mutex);

void enqueueAborted(std::function<void()> resume) VL_MT_SAFE {
    const VerilatedLockGuard lock{s_mutex};
    s_aborted.push_back(std::move(resume));
}

// This function calls resume() which contains call to handoffWorker(), therefore it is marked
// VL_MT_UNSAFE_ONE
void resumeAborted() VL_MT_UNSAFE_ONE {
    while (true) {
        std::function<void()> resume;
        {
            const VerilatedLockGuard lock{s_mutex};
            if (s_aborted.empty()) return;
            resume = std::move(s_aborted.back());
            s_aborted.pop_back();
        }
        resume();
    }
}
}  // namespace VerilatedDpiCall
#endif

//======================================================================
// VlCoroutineHandle:: Methods

void VlCoroutineHandle::destroy() {
    // Usually these coroutines should get resumed; we only need to clean up if we destroy a
    // model with some coroutines suspended
    if (m_process && m_process->state() != VlProcess::KILLED && !m_coro.promise().m_forever) {
        m_process->state(VlProcess::FINISHED);
    }
    m_coro.destroy();
#if VM_DPI
    VerilatedDpiCall::resumeAborted();
#endif
}

void VlCoroutineHandle::resume() {
    // Only null if we have a fork..join_any and one of the other child processes resumed the
    // main process
    if (VL_LIKELY(m_coro)) {
        VL_DEBUG_IF(VL_DBG_MSGF("             Resuming: "); dump(););
        if (m_process) {  // If process state is managed with std::process
            if (m_process->isKilled()) {
                m_coro.destroy();
                m_coro = nullptr;
#if VM_DPI
                // Killing a process might leak a thread if
                // it was in the middle of executing a DPI import.
                // This function resumes those threads.
                VerilatedDpiCall::resumeAborted();
#endif
            } else {
                m_process->state(VlProcess::RUNNING);
                VlProcess::currentp(m_process.get());
                m_coro();
                VlProcess::currentp(nullptr);
            }
        } else {
            VlProcess::currentp(nullptr);
            m_coro();
        }
        m_coro = nullptr;
    }
}

#ifdef VL_DEBUG
void VlCoroutineHandle::dump() const {
    VL_PRINTF("Process waiting at %s:%d\n", m_fileline.filename(), m_fileline.lineno());
}
#endif

//======================================================================
// VlDelayScheduler:: Methods

void VlDelayScheduler::resume() {
#ifdef VL_DEBUG
    VL_DEBUG_IF(dump(); VL_DBG_MSGF("         Resuming delayed processes\n"););
#endif
    if (VL_UNLIKELY(m_context.gotFinish())) {
        m_queue.clear();
        m_zeroDelayed.clear();
        m_zeroDelayesSwap.clear();
        return;
    }
    bool resumed = false;

    while (!m_queue.empty() && (m_queue.cbegin()->first == m_context.time())) {
        VlCoroutineHandle handle = std::move(m_queue.begin()->second);
        m_queue.erase(m_queue.begin());
        handle.resume();
        resumed = true;
    }

    if (!resumed) {
        if (m_context.time() == 0) {
            // Nothing was scheduled at time 0, but resume() got called due to --x-initial-edge
            return;
        }

        VL_FATAL_MT(__FILE__, __LINE__, "",
                    "%Error: Encountered process that should've been resumed at an "
                    "earlier simulation time. Missed a time slot?\n");
    }
}

void VlDelayScheduler::resumeZeroDelay() {
    if (VL_UNLIKELY(m_context.gotFinish())) {
        m_zeroDelayed.clear();
        m_zeroDelayesSwap.clear();
        return;
    }
    m_zeroDelayesSwap.swap(m_zeroDelayed);
    for (VlCoroutineHandle& handle : m_zeroDelayesSwap) handle.resume();
    m_zeroDelayesSwap.clear();
}

uint64_t VlDelayScheduler::nextTimeSlot() const {
    if (!m_queue.empty()) return m_queue.cbegin()->first;
    if (m_zeroDelayed.empty())
        VL_FATAL_MT(__FILE__, __LINE__, "", "There is no next time slot scheduled");
    return m_context.time();
}

#ifdef VL_DEBUG
void VlDelayScheduler::dump() const {
    if (m_queue.empty() && m_zeroDelayed.empty()) {
        VL_DBG_MSGF("         No delayed processes:\n");
    } else {
        VL_DBG_MSGF("         Delayed processes:\n");
        for (const auto& susp : m_zeroDelayed) {
            VL_DBG_MSGF("             Awaiting #0-delayed resumption, "
                        "time () %" PRIu64 ": ",
                        m_context.time());
            susp.dump();
        }
        for (const auto& susp : m_queue) {
            VL_DBG_MSGF("             Awaiting time %" PRIu64 ": ", susp.first);
            susp.second.dump();
        }
    }
}
#endif

//======================================================================
// VlTriggerScheduler:: Methods

void VlTriggerScheduler::resume(const char* eventDescription) {
#ifdef VL_DEBUG
    VL_DEBUG_IF(dump(eventDescription);
                VL_DBG_MSGF("         Resuming processes waiting for %s\n", eventDescription););
#endif
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_toResume.clear();
        m_fired.clear();
        m_awaiting.clear();
        return;
    }
    for (VlCoroutineHandle& coro : m_toResume) coro.resume();
    m_toResume.clear();
}

void VlTriggerScheduler::moveToResumeQueue(const char* eventDescription) {
#ifdef VL_DEBUG
    if (!m_fired.empty()) {
        VL_DEBUG_IF(VL_DBG_MSGF("         Moving to resume queue processes waiting for %s:\n",
                                eventDescription);
                    for (const auto& susp : m_fired) {
                        VL_DBG_MSGF("           - ");
                        susp.dump();
                    });
    }
#endif
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_toResume.clear();
        m_fired.clear();
        return;
    }
    std::swap(m_fired, m_toResume);
}

void VlTriggerScheduler::ready(const char* eventDescription) {
#ifdef VL_DEBUG
    if (!m_awaiting.empty()) {
        VL_DEBUG_IF(
            VL_DBG_MSGF("         Committing processes waiting for %s:\n", eventDescription);
            for (const auto& susp : m_awaiting) {
                VL_DBG_MSGF("           - ");
                susp.dump();
            });
    }
#endif
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_fired.clear();
        m_awaiting.clear();
        return;
    }
    const size_t expectedSize = m_fired.size() + m_awaiting.size();
    if (m_fired.capacity() < expectedSize) m_fired.reserve(expectedSize * 2);
    m_fired.insert(m_fired.end(), std::make_move_iterator(m_awaiting.begin()),
                   std::make_move_iterator(m_awaiting.end()));
    m_awaiting.clear();
}

#ifdef VL_DEBUG
void VlTriggerScheduler::dump(const char* eventDescription) const {
    if (m_toResume.empty()) {
        VL_DBG_MSGF("         No process to resume waiting for %s\n", eventDescription);
    } else {
        for (const auto& susp : m_toResume) {
            VL_DBG_MSGF("         Processes to resume waiting for %s:\n", eventDescription);
            VL_DBG_MSGF("           - ");
            susp.dump();
        }
    }
    if (!m_fired.empty()) {
        VL_DBG_MSGF("         Triggered processes waiting for %s:\n", eventDescription);
        for (const auto& susp : m_awaiting) {
            VL_DBG_MSGF("           - ");
            susp.dump();
        }
    }
    if (!m_awaiting.empty()) {
        VL_DBG_MSGF("         Not triggered processes waiting for %s:\n", eventDescription);
        for (const auto& susp : m_awaiting) {
            VL_DBG_MSGF("           - ");
            susp.dump();
        }
    }
}
#endif

//======================================================================
// VlDynamicTriggerScheduler:: Methods

#ifdef VL_DEBUG
std::atomic<size_t> VlDynamicTriggerScheduler::s_evaluatedForTest{0};
#endif

void VlDynamicTriggerScheduler::forkDone(VlProcess* processp) {
    const VerilatedLockGuard lock{m_forkMutex};
    const auto it = m_forkWaiting.find(processp);
    if (it == m_forkWaiting.end()) return;
    processp->forkWaitp(nullptr);
    m_forkWoken.push_back(std::move(it->second));
    m_forkWaiting.erase(it);
}

void VlDynamicTriggerScheduler::mergeForkWoken() {
    std::vector<KeyedCoroutine> woken;
    {
        const VerilatedLockGuard lock{m_forkMutex};
        if (m_forkWoken.empty()) return;
        woken.swap(m_forkWoken);
    }
    std::sort(woken.begin(), woken.end(),
              [](const KeyedCoroutine& a, const KeyedCoroutine& b) { return a.first < b.first; });
    VlCoroutineVec merged;
    std::vector<uint64_t> mergedKeys;
    merged.reserve(m_suspended.size() + woken.size());
    mergedKeys.reserve(merged.capacity());
    size_t i = 0;
    for (KeyedCoroutine& keyed : woken) {
        for (; i < m_suspended.size() && m_suspendedKeys[i] < keyed.first; ++i) {
            merged.push_back(std::move(m_suspended[i]));
            mergedKeys.push_back(m_suspendedKeys[i]);
        }
        merged.push_back(std::move(keyed.second));
        mergedKeys.push_back(keyed.first);
    }
    for (; i < m_suspended.size(); ++i) {
        merged.push_back(std::move(m_suspended[i]));
        mergedKeys.push_back(m_suspendedKeys[i]);
    }
    m_suspended.swap(merged);
    m_suspendedKeys.swap(mergedKeys);
}

void VlDynamicTriggerScheduler::clearForkWaiting() {
    std::unordered_map<VlProcess*, KeyedCoroutine> waiting;
    std::vector<KeyedCoroutine> woken;
    {
        const VerilatedLockGuard lock{m_forkMutex};
        waiting.swap(m_forkWaiting);
        woken.swap(m_forkWoken);
    }
    // Unlink all processes first, as destroying a coroutine finishes its process, which may
    // wake its parent (see forkDone)
    for (const auto& procCoro : waiting) procCoro.first->forkWaitp(nullptr);
}

bool VlDynamicTriggerScheduler::evaluate() {
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_anyTriggered = false;
        clearForkWaiting();
        m_suspended.clear();
        m_suspendedKeys.clear();
        m_evaluated.clear();
        m_evaluatedKeys.clear();
        m_triggered.clear();
        m_post.clear();
        return false;
    }
    m_anyTriggered = false;
    VL_DEBUG_IF(dump(););
    mergeForkWoken();
    std::swap(m_suspended, m_evaluated);
    std::swap(m_suspendedKeys, m_evaluatedKeys);
#ifdef VL_DEBUG
    s_evaluatedForTest.fetch_add(m_evaluated.size(), std::memory_order_relaxed);
#endif
    for (size_t i = 0; i < m_evaluated.size(); ++i) {
        m_evaluatingKey = m_evaluatedKeys[i];
        m_evaluated[i].resume();
    }
    m_evaluatingKey = 0;
    m_evaluated.clear();
    m_evaluatedKeys.clear();
    return m_anyTriggered;
}

void VlDynamicTriggerScheduler::doPostUpdates() {
    VL_DEBUG_IF(if (!m_post.empty())
                    VL_DBG_MSGF("         Doing post updates for processes:\n");  //
                for (const auto& susp : m_post) {
                    VL_DBG_MSGF("           - ");
                    susp.dump();
                });
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_post.clear();
        return;
    }
    for (auto& coro : m_post) coro.resume();
    m_post.clear();
}

void VlDynamicTriggerScheduler::resume() {
    VL_DEBUG_IF(if (!m_triggered.empty()) VL_DBG_MSGF("         Resuming processes:\n");  //
                for (const auto& susp : m_triggered) {
                    VL_DBG_MSGF("           - ");
                    susp.dump();
                });
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_triggered.clear();
        return;
    }
    for (auto& coro : m_triggered) coro.resume();
    m_triggered.clear();
}

#ifdef VL_DEBUG
void VlDynamicTriggerScheduler::dump() const {
    if (m_suspended.empty()) {
        VL_DBG_MSGF("         No suspended processes waiting for dynamic trigger evaluation\n");
    } else {
        for (const auto& susp : m_suspended) {
            VL_DBG_MSGF("         Suspended processes waiting for dynamic trigger evaluation:\n");
            VL_DBG_MSGF("           - ");
            susp.dump();
        }
    }
}
#endif

//======================================================================
// VlForkSync:: Methods

void VlProcess::forkSyncOnKill(std::shared_ptr<VlForkSyncState> forkSyncp) {
    m_forkSyncOnKillp = forkSyncp;
    m_forkSyncOnKillDone = false;
}

void VlProcess::forkSyncOnKillClear(VlForkSyncState* forkSyncp) {
    if (m_forkSyncOnKillp.get() != forkSyncp) return;
    m_forkSyncOnKillp = nullptr;
    m_forkSyncOnKillDone = false;
}

void VlProcess::state(int s) {
    if (completed()) {
        // We can't change the sttaus of completed process
        return;
    }
    m_state = s;
    if (completed()) {
        // The parent's 'wait fork' may now proceed, and a killed one's own one ends
        if (m_parentp) {
            VlDynamicTriggerScheduler* const schedp
                = m_parentp->m_forkWaitp.load(std::memory_order_relaxed);
            if (schedp) schedp->forkDone(m_parentp.get());
        }
        VlDynamicTriggerScheduler* const schedp = m_forkWaitp.load(std::memory_order_relaxed);
        if (schedp) schedp->forkDone(this);
    }
    if (s == KILLED && m_forkSyncOnKillp && !m_forkSyncOnKillDone) {
        m_forkSyncOnKillDone = true;
        m_forkSyncOnKillp->done();
        m_forkSyncOnKillp = nullptr;
    }
}

void VlForkSync::onKill(VlProcessRef process) {
    if (!process) return;
    process->forkSyncOnKill(m_state);
}

void VlForkSyncState::done(const char* filename, int lineno) {
    VL_DEBUG_IF(VL_DBG_MSGF("             Process forked at %s:%d finished\n", filename, lineno););
    if (!m_inited) {
        ++m_pendingDones;
        return;
    }
    if (m_counter > 0) m_counter--;
    if (m_counter != 0) return;
    if (m_inDone) {
        m_resumePending = true;
        return;
    }
    m_inDone = true;
    do {
        m_resumePending = false;
        m_susp.resume();
    } while (m_resumePending && m_inited && m_counter == 0);
    m_inDone = false;
}

//======================================================================
// VlPromise:: Methods

VlCoroutine VlPromise::get_return_object() { return {this}; }

VlPromise::~VlPromise() {
    // Indicate to the return object that the coroutine has finished or been destroyed
    if (m_corop) m_corop->m_promisep = nullptr;
    // If there is a continuation, destroy it
    if (m_continuation) m_continuation.destroy();
}

std::suspend_never VlPromise::final_suspend() noexcept {
    // Indicate to the return object that the coroutine has finished
    if (m_corop) {
        m_corop->m_promisep = nullptr;
        // Forget the return value, we won't need it and it won't be able to let us know if
        // it's destroyed
        m_corop = nullptr;
    }
    // If there is a continuation, resume it
    if (m_continuation) {
        m_continuation();
        m_continuation = nullptr;
    }
    return {};
}
