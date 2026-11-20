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

#include <iterator>

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
            if (m_process->state() == VlProcess::KILLED) {
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

void VlCoroutineHandle::dropKilled(std::vector<VlCoroutineHandle>& handles) {
    size_t kept = 0;
    for (VlCoroutineHandle& handle : handles) {
        if (handle.m_process && handle.m_process->state() == VlProcess::KILLED) {
            handle.resume();  // Destroys the coroutine
        } else {
            handles[kept++] = std::move(handle);
        }
    }
    handles.erase(handles.begin() + kept, handles.end());
    // Keep growth geometric when few were dropped, so repeated calls stay amortized O(1)
    if (kept > handles.capacity() / 2) handles.reserve(2 * handles.capacity());
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

bool VlDynamicTriggerScheduler::evaluate() {
    if (VL_UNLIKELY(Verilated::threadContextp()->gotFinish())) {
        m_anyTriggered = false;
        shutdown();
        m_suspended.clear();
        m_evaluated.clear();
        m_triggered.clear();
        m_post.clear();
        return false;
    }
    // As the trigger of an evaluated named-event wait (see V3SenExprBuilder), resume no waiter
    // once $finish is pending
    bool woken = false;
    if (VL_UNLIKELY(m_pendingHeadp.load(std::memory_order_relaxed)
                    && !Verilated::threadContextp()->finishPending())) {
        VlCoroutineVec killed;  // Destroyed after the wait lists are released
        woken = wakePending(killed);
        VlCoroutineHandle::dropKilled(killed);
    }
    // The waits through a handle written since may now refer to another event, or none. Not once
    // $finish is pending, as the pending wait lists were not drained then, and event triggers
    // are not set then anyway.
    if (VL_UNLIKELY(m_handlesWritten.load(std::memory_order_relaxed)
                    && !Verilated::threadContextp()->finishPending())) {
        m_handlesWritten.store(false, std::memory_order_relaxed);
        takeHandleWaiters();
    }
    m_anyTriggered = false;
    VL_DEBUG_IF(dump(););
    std::swap(m_suspended, m_evaluated);
    m_step = Step::EVALUATE;
    if (m_listWoken.empty()) {
        for (auto& coro : m_evaluated) coro.resume();
    } else {
        evaluateWithListWoken();
    }
    m_step = Step::OTHER;
    m_evaluated.clear();
    m_seqAtEvaluate = m_lastWaitSeq;
    return m_anyTriggered || woken;
}

void VlDynamicTriggerScheduler::takeHandleWaiters() {
    // The killed waiters of every list were dropped just before, as killing a waiter makes its
    // list pending (see evaluate), so each waiter left has its slot. Lists with waiters to
    // evaluate are live, as fired ones were drained just before. This takes all waiters to
    // evaluate on any handle write: it evaluates them all, as without wait lists, plus a pass
    // over their slots in the lists that have had waiters to evaluate since the last time, and
    // the sort of the waiters taken. The waiters to resume stay in their slots.
    for (VlEventWaitList* const listp : m_evaluatorLists) {
        VlEventWaitList& list = *listp;
        list.m_evaluatorsListed = false;
        VlCoroutineVec& waiters = list.m_waiters;
        const size_t emptySlots = list.m_emptySlots;
        for (const size_t index : list.m_evaluatorSlots) {
            VlCoroutineHandle& coro = waiters[index];
            if (!coro.framep()) continue;
            coro.waitListp(nullptr);
            m_listWoken.push_back(std::move(coro));
            ++list.m_emptySlots;
        }
        releaseEvaluatorSlots(list);
        if (list.m_emptySlots == emptySlots) continue;
        if (list.m_emptySlots >= waiters.size() - list.m_emptySlots) compact(list);
        if (waiters.empty()) {
            VL_DEBUG_IFDEF(assert(list.m_eventp););
            detach(list);
            recycle(list);
        }
    }
    m_evaluatorLists.clear();
}

uint64_t VlDynamicTriggerScheduler::listWokenKey(const VlCoroutineHandle& coro) const {
    // A wait that started before the last evaluate() would have awaited trigger evaluation
    // again when resumed for its post update, as waits on events have one
    const uint64_t key = coro.waitKey();
    if ((key & ~WAIT_KEY_SEQ) == WAIT_KEY_STARTED && (key & WAIT_KEY_SEQ) <= m_seqAtEvaluate) {
        return (key & WAIT_KEY_SEQ) | WAIT_KEY_POST_UPDATED;
    }
    return key;
}

void VlDynamicTriggerScheduler::evaluateWithListWoken() {
    // The coroutines awaiting trigger evaluation are in the order of their keys (see
    // startWait). Resume each coroutine woken on a wait list among them at its key, so all
    // triggers are evaluated in the same order as if all had been evaluated at every
    // evaluate(), with the same side effects, and the post updates follow that order.
    m_listOrder.clear();
    m_listOrder.reserve(m_listWoken.size());
    for (size_t i = 0; i < m_listWoken.size(); ++i) {
        m_listOrder.emplace_back(listWokenKey(m_listWoken[i]), i);
    }
    std::sort(m_listOrder.begin(), m_listOrder.end());
    // Only the coroutines not resumed yet are searched, as resuming one rekeys it
    auto nextIt = m_evaluated.begin();
    for (const std::pair<uint64_t, size_t>& keySlot : m_listOrder) {
        const auto endIt = std::upper_bound(
            nextIt, m_evaluated.end(), keySlot.first,
            [](uint64_t key, const VlCoroutineHandle& coro) { return key < coro.waitKey(); });
        for (; nextIt != endIt; ++nextIt) nextIt->resume();
        m_listWoken[keySlot.second].resume();
    }
    for (; nextIt != m_evaluated.end(); ++nextIt) nextIt->resume();
    m_listWoken.clear();
}

void VlDynamicTriggerScheduler::shutdown() {
    // Only the newest wait list of an event refers to it (see waitListOf), and the two unlink
    // each other, so the scheduler and the events may be destroyed in either order.
    // The coroutines are destroyed after every wait list is released, and every process is
    // unlinked from its list.
    VlCoroutineVec waiters;
    m_pendingHeadp.store(nullptr, std::memory_order_relaxed);
    for (VlEventWaitList& list : m_waitLists) {
        // A free list has neither an event nor waiters. A fired list that a newer one replaced
        // on its event has only waiters (see waitListOf).
        if (!list.m_eventp && list.m_waiters.empty()) continue;
        if (list.m_eventp) detach(list);
        for (VlCoroutineHandle& coro : list.m_waiters) {
            coro.waitListp(nullptr);
            waiters.push_back(std::move(coro));
        }
        recycle(list);
    }
    for (VlEventWaitList* const listp : m_evaluatorLists) listp->m_evaluatorsListed = false;
    m_evaluatorLists.clear();
    m_firedEventps.clear();
    m_firedKeepps.clear();
}

VlEventWaitList& VlDynamicTriggerScheduler::waitListOf(VlEvent& event) {
    VlEventWaitList* listp = static_cast<VlEventWaitList*>(event.waitp());
    // A fire only unblocks processes that were already waiting (IEEE 1800-2023 15.5.2), so a
    // fired wait list takes no new waiters
    if (!listp || listp->m_fired.load(std::memory_order_relaxed)) {
        if (listp) {
            // Only the list the event refers to refers to the event, so whichever of the two
            // goes first unlinks the other (see ~VlEvent). The fired list keeps its waiters
            // until it drains; the fired state of the event is retired as if it had drained.
            if (listp->m_resumers) {
                m_firedEventps.push_back(&event);
                if (listp->m_keepp) m_firedKeepps.push_back(std::move(listp->m_keepp));
            }
            listp->m_eventp = nullptr;
        }
        if (m_freeWaitLists.empty()) {
            m_waitLists.emplace_back();
            listp = &m_waitLists.back();
            listp->m_headpp = &m_pendingHeadp;
            listp->m_reevaluatep = &m_handlesWritten;
        } else {
            listp = m_freeWaitLists.back();
            m_freeWaitLists.pop_back();
        }
        listp->m_eventp = &event;
        event.waitp(listp);
    }
    return *listp;
}

void VlDynamicTriggerScheduler::addWaiter(VlEvent& event, std::shared_ptr<VlEvent>&& keepp,
                                          std::coroutine_handle<VlPromise> coro,
                                          VlProcessRef process, VlFileLineDebug fileline) {
    VlEventWaitList& list = waitListOf(event);
    if (keepp && !list.m_keepp) list.m_keepp = std::move(keepp);
    // A waiter that evaluates its trigger retires the fired state of the event by its own post
    // update, as when evaluating its trigger at every evaluate()
    const size_t index = list.m_waiters.size();
    if (!coro.promise().m_listEvaluates) {
        // The waiters to resume are resumed in the order their lists got their first such
        // waiter, as when only they were on wait lists, whatever waiters to evaluate the lists
        // got before (see wakePending)
        if (!list.m_resumers) list.m_seq = m_nextSeq++;
        ++list.m_resumers;
    } else {
        list.m_evaluatorSlots.push_back(index);
        if (!list.m_evaluatorsListed) {
            list.m_evaluatorsListed = true;
            m_evaluatorLists.push_back(&list);
        }
    }
    list.m_waiters.emplace_back(coro, process, fileline);
    // A killed process runs on until it waits, which only leaves its destruction
    if (VlProcess* const processp = list.m_waiters[index].processp()) {
        processp->waitIndex(index);
        processp->waitEvaluates(coro.promise().m_listEvaluates);
        processp->waitListp(&list);
        if (VL_UNLIKELY(processp->state() == VlProcess::KILLED)) list.noteKilled(*processp);
    }
}

void VlDynamicTriggerScheduler::compact(VlEventWaitList& list) {
    VlCoroutineVec& waiters = list.m_waiters;
    list.m_evaluatorSlots.clear();
    size_t kept = 0;
    for (size_t i = 0; i < waiters.size(); ++i) {
        if (!waiters[i].framep()) continue;
        if (kept != i) waiters[kept] = std::move(waiters[i]);
        waiters[kept].waitIndex(kept);
        if (waiters[kept].listEvaluates()) list.m_evaluatorSlots.push_back(kept);
        ++kept;
    }
    waiters.erase(waiters.begin() + kept, waiters.end());
    // Release most of the storage of a list left with few waiters, so a list does not keep the
    // storage for the waiters to evaluate that once moved through it, for example while a
    // waiter to resume keeps it live
    shrinkStorage(waiters);
    shrinkStorage(list.m_evaluatorSlots);
    list.m_emptySlots = 0;
}

template <typename T>
void VlDynamicTriggerScheduler::shrinkStorage(std::vector<T>& vec) {
    // Only below a quarter, so the storage still grows in amortized constant time. Not by
    // shrink_to_fit(), which the library may ignore, as it does without exceptions.
    if (vec.capacity() > MAX_FREE_CAPACITY && vec.capacity() / 4 > vec.size()) {
        std::vector<T>{std::make_move_iterator(vec.begin()), std::make_move_iterator(vec.end())}
            .swap(vec);
    }
}

void VlDynamicTriggerScheduler::releaseEvaluatorSlots(VlEventWaitList& list) {
    // The waiters to evaluate come back to the list only if their handles still reach its event,
    // so its storage for their slots is released, as for the storage of its waiters (see recycle)
    if (list.m_evaluatorSlots.capacity() > MAX_FREE_CAPACITY) {
        std::vector<size_t>{}.swap(list.m_evaluatorSlots);
    } else {
        list.m_evaluatorSlots.clear();
    }
}

void VlDynamicTriggerScheduler::detach(VlEventWaitList& list) {
    // The waiters still keep the event's storage alive. A newer wait list may already have
    // replaced this one on the event.
    if (list.m_eventp->waitp() == &list) list.m_eventp->waitp(nullptr);
    list.m_eventp = nullptr;
}

void VlDynamicTriggerScheduler::recycle(VlEventWaitList& list) {
    if (list.m_waiters.capacity() > MAX_FREE_CAPACITY) {
        VlCoroutineVec{}.swap(list.m_waiters);
    } else {
        list.m_waiters.clear();
    }
    list.m_pending.store(false, std::memory_order_relaxed);
    list.m_fired.store(false, std::memory_order_relaxed);
    list.m_keepp.reset();
    list.m_resumers = 0;
    releaseEvaluatorSlots(list);
    // Its killed chain is dropped unread: its waiters are gone, or the model finished
    list.m_killedHeadp = nullptr;
    list.m_emptySlots = 0;
    m_freeWaitLists.push_back(&list);
}

bool VlDynamicTriggerScheduler::wakePending(VlCoroutineVec& killed) {
    // Any thread may have fired an event or killed a waiter, but all have finished before trigger
    // evaluation. Parallel MTasks push in any order, so the lists are drained in the order they
    // got their first waiter to resume, and their waiters resume in the same order on any number
    // of threads.
    VlEventWaitLink* linkp = m_pendingHeadp.exchange(nullptr, std::memory_order_acquire);
    m_drainedLists.clear();
    for (; linkp; linkp = linkp->m_nextp) {
        m_drainedLists.push_back(static_cast<VlEventWaitList*>(linkp));
    }
    std::sort(m_drainedLists.begin(), m_drainedLists.end(),
              [](const VlEventWaitList* ap, const VlEventWaitList* bp) {  //
                  return ap->m_seq < bp->m_seq;
              });
    bool woken = false;
    for (VlEventWaitList* const listp : m_drainedLists) {
        VlEventWaitList& list = *listp;
        list.m_pending.store(false, std::memory_order_relaxed);
        VlCoroutineVec& waiters = list.m_waiters;
        if (list.m_fired.load(std::memory_order_relaxed)) {
            woken = woken || list.m_resumers;
            // A fired list takes no new waiters, so it is freed. Resuming destroys the killed
            // waiters, so its killed chain is dropped unread.
            list.takeKilled();
            for (VlCoroutineHandle& coro : waiters) {
                if (!coro.framep()) continue;  // Left empty by a dropped killed waiter
                coro.waitListp(nullptr);
                (coro.listEvaluates() ? m_listWoken : m_triggered).push_back(std::move(coro));
            }
            // The waiters keep the event alive until the post update step, but not an
            // assignable event, which the list keeps alive. A list replaced on its event
            // handed these over already (see waitListOf).
            if (list.m_eventp) {
                if (list.m_resumers) {
                    m_firedEventps.push_back(list.m_eventp);
                    if (list.m_keepp) m_firedKeepps.push_back(std::move(list.m_keepp));
                }
                detach(list);
            }
            recycle(list);
            continue;
        }
        // Drop each killed waiter from its slot, leaving the slot empty, and compact once half
        // the slots are empty: each kill costs O(1) amortized. In ordinary evaluation this is the
        // first trigger evaluation after the kill; while $finish is pending this drain waits, and
        // finishing removes the waiter instead. A process on the killed chain has its handle in
        // its slot on this list, as it is noted only while it waits here, and never waits again.
        for (VlProcess* processp = list.takeKilled(); processp;) {
            VlProcess* const nextp = processp->nextKilledp();
            const size_t index = processp->waitIndex();
            VL_DEBUG_IFDEF(
                assert(index < waiters.size() && waiters[index].processp() == processp););
            waiters[index].waitListp(nullptr);
            if (!waiters[index].listEvaluates()) --list.m_resumers;
            killed.push_back(std::move(waiters[index]));
            ++list.m_emptySlots;
            processp = nextp;
        }
        // Each empty slot was a waiter's, so they are no more than the slots
        if (list.m_emptySlots >= waiters.size() - list.m_emptySlots) compact(list);
        // Waiters left keep the event's storage alive, else detach while the killed ones do
        if (waiters.empty()) {
            detach(list);
            recycle(list);
        }
    }
    return woken;
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
        m_firedEventps.clear();
        m_firedKeepps.clear();
        return;
    }
    m_step = Step::POST_UPDATE;
    for (auto& coro : m_post) coro.resume();
    m_step = Step::OTHER;
    m_post.clear();
    // Retire the fired state of the events whose wait lists fired, as the post update of a
    // waiter evaluating its trigger would, so a later wait evaluating its trigger, for example
    // through a handle that comes to refer to the event, does not see this fire
    // (IEEE 1800-2023 15.5.2). All triggers have been sampled by now.
    for (VlEvent* const eventp : m_firedEventps) eventp->clearFired();
    m_firedEventps.clear();
    m_firedKeepps.clear();
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
    bool listed = false;
    for (const VlEventWaitList& list : m_waitLists) {
        for (const auto& susp : list.m_waiters) {
            if (!susp.framep()) continue;  // Left empty by a dropped killed waiter
            if (!listed) {
                VL_DBG_MSGF("         Suspended processes waiting on event wait lists:\n");
                listed = true;
            }
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
    detachIfDone();
    if (s == KILLED && m_waitListp) m_waitListp->noteKilled(*this);
    // A process waiting to evaluate its trigger, set running, for example by resume(), is set
    // back to waiting when it evaluates its trigger, at every trigger evaluation when polling
    if (VL_UNLIKELY(m_waitEvaluates) && s != KILLED && m_waitListp) {
        m_waitListp->noteStateChanged();
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
