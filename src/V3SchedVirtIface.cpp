// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Create triggers necessary for scheduling across
//                         virtual interfaces
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2003-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
// V3SchedVirtIface's Transformations:
//
// Identify interface members written through virtual interface variables (VIF writes),
// or read through them by combinational logic, which references only the VIF variable.
// For each such member, collect all VarScopes across all instantiations of that
// interface type. Each VarScope gets its own value-change trigger in the scheduler.
//
// Also disables lifetime optimization for variables in AlwaysPost blocks that
// write through virtual interfaces.
//
// Also identify interface members read through virtual interface variables by clocked logic,
// directly, in methods called through them, or in functions it calls, for V3Order to order
// such a read before the commit of nonblocking assignments to the member, as it does a direct
// read. These keep the shadow variable of those assignments, as
// V3LifePost does not see the read.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3AstNodeExpr.h"
#include "V3CallTargets.h"
#include "V3Sched.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

namespace {

// Hash a std::pair automatically
struct PairHash final {
    template <typename T, typename U>
    std::size_t operator()(const std::pair<T, U>& x) const {
        return std::hash<T>()(x.first) + std::hash<U>()(x.second);
    }
};

class VirtIfaceVisitor final : public VNVisitor {
private:
    // STATE
    using IfaceMember = std::pair<const AstIface*, std::string>;
    using IfaceCallable = std::pair<AstIface*, AstCFunc*>;

    // (iface, member) pairs written through VIF, in the order found -- defines which members need
    // triggers, and the order of the triggers
    std::vector<IfaceMember> m_vifWrittenMembers;
    // Members already added to m_vifWrittenMembers
    std::set<IfaceMember> m_seenVifWrittenMembers;
    // All candidate VarScopes of interface members (keyed by interface type + member name)
    std::map<IfaceMember, std::vector<AstVarScope*>> m_candidateVscps;
    std::set<std::pair<IfaceMember, AstVarScope*>> m_seenCandidateVscps;
    // VarScope index and callable worklist for VIF method-body writes.
    std::map<const AstVar*, std::vector<AstVarScope*>> m_vscpsByVar;
    // Worklist of reachable interface callables
    std::vector<IfaceCallable> m_reachableIfaceCallables;
    // Callables already added to the worklist
    std::set<IfaceCallable> m_seenReachableIfaceCallables;
    // (iface, member) pairs read through VIF by combinational logic, in the order found. These
    // need triggers too, as such logic references the VIF variable, not the member.
    std::vector<IfaceMember> m_vifCombReadMembers;
    // Members already added to m_vifCombReadMembers
    std::unordered_set<IfaceMember, PairHash> m_seenVifCombReadMembers;
    // Interface variables whose VarScopes are already candidates for a combinational VIF read
    std::unordered_set<std::pair<const AstIface*, const AstVar*>, PairHash> m_combReadVars;
    // Worklist of interface callables called through VIF by combinational logic
    std::vector<IfaceCallable> m_combIfaceCallables;
    // Callables already added to the worklist
    std::unordered_set<IfaceCallable, PairHash> m_seenCombIfaceCallables;
    // Functions called by combinational logic, visited as part of it -> the interfaces they read
    // through VIF
    std::unordered_map<const AstCFunc*, std::set<const AstIface*>> m_combCalleeIfaces;
    // Interfaces read through VIF by the function being visited as part of combinational logic
    std::set<const AstIface*>* m_calleeIfacesp = nullptr;
    bool m_inComb = false;  // Under combinational or hybrid logic
    // Members read through VIF by clocked logic
    std::vector<const AstVar*> m_clockedReadVarps;
    std::unordered_set<const AstVar*> m_seenClockedReadVarps;
    // Methods called through VIF by clocked logic, with the functions such a call may run
    struct MethodCall final {
        const AstCFunc* m_funcp = nullptr;  // Method called
        std::vector<AstCFunc*> m_targetps;  // Functions the call may run
        bool m_viaVif = false;  // Called through VIF
    };
    std::vector<MethodCall> m_clockedMethodCalls;
    std::unordered_set<const AstCFunc*> m_seenClockedMethodCalls;
    // Functions called directly by clocked logic
    std::vector<AstCFunc*> m_clockedCalls;
    std::unordered_set<const AstCFunc*> m_seenClockedCalls;
    // What each function called by clocked logic reads and calls, as found by calleeAccess()
    struct CalleeAccess final {
        std::vector<const AstVar*> m_vifMemberps;  // Members read through VIF
        std::vector<const AstVar*> m_ifaceVarps;  // Interface variables read, not through VIF
        std::vector<AstCFunc*> m_calleeps;  // Functions called
        std::vector<AstCFunc*> m_vifCalleeps;  // Functions a call through VIF may run
    };
    std::unordered_map<const AstCFunc*, CalleeAccess> m_calleeAccess;
    // Vertex of the call graph for reads through VIF: a function, and whether it runs for a call
    // through VIF, so reads the interface variables of its own instance as members read through
    // VIF
    using ReadNode = std::pair<AstCFunc*, bool>;
    struct ReadNodeHash final {
        size_t operator()(const ReadNode& node) const {
            return std::hash<const AstCFunc*>{}(node.first) ^ static_cast<size_t>(node.second);
        }
    };
    static constexpr size_t NO_INDEX = ~static_cast<size_t>(0);  // No index
    // Search of the call graph each vertex was last visited by (see reachedMembers())
    std::unordered_map<ReadNode, uint64_t, ReadNodeHash> m_readNodeSearch;
    uint64_t m_readSearch = 0;  // Current search of the call graph
    size_t m_readSteps = 0;  // Vertices, calls and members visited, for statistics
    // State of each vertex of the call graph when memoizing closures (see closureOf())
    struct ReadNodeState final {
        size_t m_index = NO_INDEX;  // Order of discovery
        size_t m_lowlink = NO_INDEX;  // Lowest index reachable, in the same component
        bool m_onStack = false;  // On the stack of the search
        size_t m_closure = NO_INDEX;  // Index of the closure of its component, once found
    };
    std::unordered_map<ReadNode, ReadNodeState, ReadNodeHash> m_readNodeStates;
    size_t m_nextReadIndex = 0;  // Next index of discovery
    // The members each strongly connected component of the call graph may read through VIF,
    // including in the components it calls, in order of encounter
    std::vector<std::vector<const AstVar*>> m_closures;
    // Member read through VIF -> its set in VirtIfaceClockedReads, NO_INDEX if not instantiated
    std::unordered_map<const AstVar*, size_t> m_memberSets;
    std::vector<bool> m_setsRead;  // Set index -> whether read, so its NBA shadows are kept
    bool m_inClocked = false;  // Under clocked logic
    VirtIfaceTriggers m_triggers;  // Triggers found for virtual interface writes
    const AstIface* m_ifacep = nullptr;  // Current interface
    const std::unique_ptr<V3CallTargets> m_callTargetsp;  // For the methods a call may run

    // METHODS
    // Returns true if statement writes across a virtual interface boundary
    static bool writesToVirtIface(const AstNode* const nodep) {
        return nodep->exists([](const AstMemberRef* const memberRefp) {
            if (!memberRefp->access().isWriteOrRW()) return false;
            AstIfaceRefDType* const dtypep
                = VN_CAST(memberRefp->fromp()->dtypep()->skipRefp(), IfaceRefDType);
            return dtypep && dtypep->isVirtual();
        });
    }

    // VISITORS
    void visit(AstActive* nodep) override {
        VL_RESTORER(m_inComb);
        VL_RESTORER(m_inClocked);
        m_inComb = nodep->sentreep()->hasCombo() || nodep->sentreep()->hasHybrid();
        m_inClocked = nodep->sentreep()->hasClocked();
        if (m_inClocked) {
            // A function called by clocked logic may read through a VIF argument
            nodep->foreach([&](const AstCCall* callp) {
                if (m_seenClockedCalls.emplace(callp->funcp()).second) {
                    m_clockedCalls.push_back(callp->funcp());
                }
            });
        }
        iterateChildren(nodep);
    }
    void visit(AstMemberRef* nodep) override {
        if (m_inClocked && nodep->access().isReadOrRW()
            && VirtIfaceClockedReads::isVirtIfaceRead(nodep)
            && m_seenClockedReadVarps.emplace(nodep->varp()).second) {
            m_clockedReadVarps.push_back(nodep->varp());
        }
        // Detect writes through VIF: the MemberRef's fromp resolves to a virtual interface type.
        // Handles both direct VIF access (vif.member) and class chain (obj.vif.member).
        if (nodep->access().isWriteOrRW()) {
            AstIfaceRefDType* const dtypep
                = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), IfaceRefDType);
            if (dtypep && dtypep->isVirtual()) {
                addVifWrittenMember(dtypep->ifacep(), nodep->varp()->name());
            }
        }
        // Detect reads through VIF by combinational logic (IEEE 1800-2023 9.2.2.2.1)
        if (m_inComb && nodep->access().isReadOrRW()) {
            const AstIfaceRefDType* const dtypep
                = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), IfaceRefDType);
            // A member that cannot have a trigger, such as a nested VIF, is not tracked
            if (dtypep && dtypep->isVirtual()
                && TriggerKit::supportsValueChange(nodep->varp()->dtypep()->skipRefp())) {
                addVifCombReadMember(dtypep->ifacep(), nodep->varp()->name());
                addCombReadSelect(dtypep->ifacep(), nodep->fromp());
            }
        }
        iterateChildren(nodep);
    }
    void visit(AstCCall* nodep) override {
        iterateChildren(nodep);
        AstCFunc* const funcp = nodep->funcp();
        if (!m_inComb || !util::isLogicCallee(funcp)) return;
        // The reads of a function called by combinational logic are reads of that logic
        const auto pair = m_combCalleeIfaces.emplace(funcp, std::set<const AstIface*>{});
        if (pair.second) {
            VL_RESTORER(m_calleeIfacesp);
            m_calleeIfacesp = &pair.first->second;
            iterateChildren(funcp);
        }
        // Its arguments select the virtual interfaces its formals refer to
        for (const AstIface* const ifacep : pair.first->second) addCombReadSelect(ifacep, nodep);
    }
    void visit(AstCMethodCall* nodep) override {
        // A method call on a member selected through a virtual interface. This includes the
        // calls through a virtual interface, which call a method of its dispatcher (V3Task)
        if (const AstMemberRef* const memberRefp = VN_CAST(nodep->fromp(), MemberRef)) {
            const AstIfaceRefDType* const dtypep
                = VN_CAST(memberRefp->fromp()->dtypep()->skipRefp(), IfaceRefDType);
            if (dtypep && dtypep->isVirtual()) {
                const std::vector<AstCFunc*>& targets = m_callTargetsp->getTargets(nodep);
                for (AstCFunc* const funcp : targets) {
                    addReachableIfaceCallable(dtypep->ifaceViaCellp(), funcp);
                    if (m_inComb && util::isLogicCallee(funcp)) {
                        addCombIfaceCallable(dtypep->ifaceViaCellp(), funcp);
                        addCombReadSelect(dtypep->ifaceViaCellp(), memberRefp->fromp());
                    }
                }
                if (m_inClocked && m_seenClockedMethodCalls.emplace(nodep->funcp()).second) {
                    m_clockedMethodCalls.push_back({nodep->funcp(), targets, true});
                }
                iterateChildren(nodep);
                return;
            }
        }
        // Another method called by clocked logic, such as of a class holding a VIF, may read
        // through VIF
        if (m_inClocked && m_seenClockedMethodCalls.emplace(nodep->funcp()).second) {
            m_clockedMethodCalls.push_back(
                {nodep->funcp(), m_callTargetsp->getTargets(nodep), false});
        }
        iterateChildren(nodep);
    }
    void visit(AstVarScope* nodep) override {
        // Collect candidate VarScopes. sensIfacep() is set on interface members
        // accessed via any MemberRef (virtual or non-virtual).
        AstVar* const varp = nodep->varp();
        if (varp->isTemp()) return;
        m_vscpsByVar[varp].push_back(nodep);
        if (const AstIface* const ifacep = varp->sensIfacep()) addCandidateVscp(ifacep, nodep);
    }
    void visit(AstIface* nodep) override {
        VL_RESTORER(m_ifacep);
        m_ifacep = nodep;
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        // Reads through a virtual interface may continue through this variable
        if (m_ifacep && nodep->isVirtIface()) {
            m_triggers.m_memberIfaces[m_ifacep].insert(
                VN_AS(nodep->dtypep()->skipRefp(), IfaceRefDType)->ifacep());
        }
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        // Disable lifetime optimization for variables in AlwaysPost blocks
        // that write to virtual interface members, as VIF reads may observe them
        if (VN_IS(nodep, AlwaysPost) && writesToVirtIface(nodep)) {
            nodep->foreach([](AstVarRef* refp) { refp->varScopep()->optimizeLifePost(false); });
        }
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

    void addVifWrittenMember(const AstIface* const ifacep, const std::string& name) {
        const IfaceMember member{ifacep, name};
        if (m_seenVifWrittenMembers.emplace(member).second) m_vifWrittenMembers.push_back(member);
    }

    void addCandidateVscp(const AstIface* const ifacep, AstVarScope* const vscp) {
        const IfaceMember member{ifacep, vscp->varp()->name()};
        if (m_seenCandidateVscps.emplace(member, vscp).second)
            m_candidateVscps[member].push_back(vscp);
    }

    void addReachableIfaceCallable(AstIface* const ifacep, AstCFunc* const funcp) {
        const IfaceCallable callable{ifacep, funcp};
        if (m_seenReachableIfaceCallables.emplace(callable).second) {
            m_reachableIfaceCallables.push_back(callable);
        }
    }

    // Record that combinational logic reads through a VIF of 'ifacep' that 'selp' selects
    void addCombReadSelect(const AstIface* const ifacep, const AstNode* const selp) {
        if (m_calleeIfacesp) m_calleeIfacesp->insert(ifacep);
        selp->foreach([&](const AstVarRef* const refp) {
            const AstVar* const varp = refp->varp();
            // A VIF variable connects by itself, and a formal is selected by the call's arguments
            if (varp->isVirtIface() || varp->isFuncLocal()) return;
            m_triggers.m_combReadRoots[refp->varScopep()].insert(ifacep);
        });
    }

    void addVifCombReadMember(const AstIface* const ifacep, const std::string& name) {
        const IfaceMember member{ifacep, name};
        if (m_seenVifCombReadMembers.emplace(member).second) {
            m_vifCombReadMembers.push_back(member);
        }
    }

    void addCombIfaceCallable(AstIface* const ifacep, AstCFunc* const funcp) {
        const IfaceCallable callable{ifacep, funcp};
        if (m_seenCombIfaceCallables.emplace(callable).second) {
            m_combIfaceCallables.push_back(callable);
        }
    }

    // Record the interface members read by a callable called through VIF by combinational logic
    void addCombReadMembers(const IfaceCallable callable) {
        callable.second->foreach([this, callable](AstNodeExpr* const nodep) {
            if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
                AstVar* const varp = refp->varp();
                // A member that cannot have a trigger, such as a nested VIF, is not tracked
                if (!refp->access().isReadOrRW() || varp->isFuncLocal() || varp->isTemp()
                    || !VN_IS(refp->varScopep()->scopep()->modp(), Iface)
                    || !TriggerKit::supportsValueChange(varp->dtypep()->skipRefp())) {
                    return;
                }
                if (!m_combReadVars.emplace(callable.first, varp).second) return;
                varp->sensIfacep(callable.first);
                addVifCombReadMember(callable.first, varp->name());
                const auto it = m_vscpsByVar.find(varp);
                UASSERT_OBJ(it != m_vscpsByVar.end(), varp, "No VarScope for interface member");
                for (AstVarScope* const vscp : it->second) addCandidateVscp(callable.first, vscp);
            } else if (const AstNodeCCall* const callp = VN_CAST(nodep, NodeCCall)) {
                if (util::isLogicCallee(callp->funcp())) {
                    addCombIfaceCallable(callable.first, callp->funcp());
                }
            }
        });
    }

    // Record the members read through VIF by clocked logic, and keep their NBA shadows. Each
    // read, or call of a function, points to the barrier of each member it may read, directly or
    // in the functions it calls, transitively. That is as many edges as reads of those members
    // the same logic would have if its functions were inlined.
    void buildClockedReads() {
        VirtIfaceClockedReads& reads = m_triggers.m_clockedReads;
        for (const AstVar* const varp : m_clockedReadVarps) {
            VirtIfaceClockedReads::Sets sets = memberSets({varp});
            if (!sets.empty()) reads.setMember(varp, std::move(sets));
        }
        // The functions each call by clocked logic may run
        struct Search final {
            std::vector<ReadNode> m_roots;  // Vertices of the functions the call may run
            const AstCFunc* m_funcp = nullptr;  // Function or method called
            bool m_method = false;  // Method call
        };
        std::vector<Search> searches;
        for (const MethodCall& call : m_clockedMethodCalls) {
            std::vector<ReadNode> roots;
            for (AstCFunc* const targetp : call.m_targetps) {
                roots.emplace_back(targetp, call.m_viaVif);
            }
            searches.push_back({std::move(roots), call.m_funcp, true});
        }
        for (AstCFunc* const funcp : m_clockedCalls) {
            searches.push_back({{{funcp, false}}, funcp, false});
        }
        // Search the call graph for each call, unless that visits more than memoizing the
        // closures may, then memoize them
        std::vector<std::vector<const AstVar*>> found;
        uint64_t budget = memoizeBound();
        bool memoize = false;
        for (const Search& search : searches) {
            found.emplace_back();
            if (!reachedMembers(search.m_roots, found.back(), nullptr, &budget)) {
                memoize = true;
                break;
            }
        }
        if (memoize) {
            found.clear();
            for (const Search& search : searches) {
                found.push_back(memoizedMembers(search.m_roots));
            }
        }
        for (size_t i = 0; i < searches.size(); ++i) {
            const Search& search = searches[i];
            VirtIfaceClockedReads::Sets sets = memberSets(found[i]);
            if (sets.empty()) continue;
            if (search.m_method) {
                reads.setMethodCall(search.m_funcp, std::move(sets));
            } else {
                reads.setCall(search.m_funcp, std::move(sets));
            }
        }
        V3Stats::addStat("Scheduling, virtual interface read closures memoized", memoize);
        V3Stats::addStatSum("Scheduling, virtual interface read call graph steps", m_readSteps);
    }

    // An upper bound of the vertices and members memoizing the closures of each strongly
    // connected component of the call graph (closureOf()) visits. With F functions and calls
    // between them reachable from the calls by clocked logic, E members in their lists of
    // distinct direct reads, T functions the calls by clocked logic may run, and M members read
    // through VIF in all, that is F+E, plus up to M members for each call between functions and
    // each of the T functions. The searches of the call graph for each of R calls visit up to
    // R*(F+E), and stop when they exceed this bound, so in all O(min(R*(F+E), (F+E+T)*M)).
    // Also makes the sets of all members found, so in the same order whichever finds them.
    uint64_t memoizeBound() {
        std::vector<ReadNode> roots;
        for (const MethodCall& call : m_clockedMethodCalls) {
            for (AstCFunc* const targetp : call.m_targetps) {
                roots.emplace_back(targetp, call.m_viaVif);
            }
        }
        for (AstCFunc* const funcp : m_clockedCalls) roots.emplace_back(funcp, false);
        std::vector<const AstVar*> varps;
        ReachedCounts counts;
        reachedMembers(roots, varps, &counts, nullptr);
        // Make the sets of the members in this order, whatever finds the members of each call
        for (const AstVar* const varp : varps) memberSet(varp);
        return counts.m_functions + counts.m_calls + counts.m_reads
               + static_cast<uint64_t>(counts.m_calls + roots.size()) * varps.size();
    }

    // What the given function reads and calls, found once
    const CalleeAccess& calleeAccess(AstCFunc* funcp) {
        const auto pair = m_calleeAccess.emplace(funcp, CalleeAccess{});
        CalleeAccess& access = pair.first->second;
        if (!pair.second) return access;
        std::unordered_set<const AstNode*> seenps;
        funcp->foreach([&](AstNodeExpr* const nodep) {
            if (const AstMemberRef* const refp = VN_CAST(nodep, MemberRef)) {
                if (refp->access().isReadOrRW() && VirtIfaceClockedReads::isVirtIfaceRead(refp)
                    && seenps.emplace(refp->varp()).second) {
                    access.m_vifMemberps.push_back(refp->varp());
                }
            } else if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
                const AstVar* const varp = refp->varp();
                if (refp->access().isReadOrRW() && !varp->isFuncLocal() && !varp->isTemp()
                    && VN_IS(refp->varScopep()->scopep()->modp(), Iface)
                    && seenps.emplace(varp).second) {
                    access.m_ifaceVarps.push_back(varp);
                }
            } else if (const AstNodeCCall* const callp = VN_CAST(nodep, NodeCCall)) {
                const AstMemberRef* const memberRefp
                    = VN_IS(callp, CMethodCall)
                          ? VN_CAST(VN_AS(callp, CMethodCall)->fromp(), MemberRef)
                          : nullptr;
                if (memberRefp && VirtIfaceClockedReads::isVirtIfaceRead(memberRefp)) {
                    for (AstCFunc* const targetp : m_callTargetsp->getTargets(callp)) {
                        access.m_vifCalleeps.push_back(targetp);
                    }
                } else {
                    for (AstCFunc* const targetp : m_callTargetsp->getTargets(callp)) {
                        access.m_calleeps.push_back(targetp);
                    }
                }
            }
        });
        return access;
    }

    // What a search of the call graph reached
    struct ReachedCounts final {
        size_t m_functions = 0;  // Vertices visited
        size_t m_calls = 0;  // Calls between them
        size_t m_reads = 0;  // Members in their lists of distinct direct reads
    };
    // The members the given vertices of the call graph may read through VIF, including in the
    // functions they call, transitively, in order of encounter. Each vertex is visited at most
    // once, which also ends recursion. Returns false, with a partial result, when the vertices,
    // calls and members visited exceed the given budget, if any, which is reduced by them.
    bool reachedMembers(const std::vector<ReadNode>& roots, std::vector<const AstVar*>& varps,
                        ReachedCounts* countsp, uint64_t* budgetp) {
        ++m_readSearch;
        std::unordered_set<const AstVar*> seenVarps;
        std::vector<ReadNode> work;
        const auto addNode = [&](const ReadNode& node) {
            uint64_t& search = m_readNodeSearch[node];
            if (search == m_readSearch) return;
            search = m_readSearch;
            work.push_back(node);
        };
        uint64_t steps = 0;
        const auto addVarp = [&](const AstVar* varp) {
            ++steps;
            if (seenVarps.emplace(varp).second) varps.push_back(varp);
        };
        for (const ReadNode& root : roots) addNode(root);
        while (!work.empty()) {
            if (budgetp && steps > *budgetp) break;
            const ReadNode node = work.back();
            work.pop_back();
            ++steps;
            const CalleeAccess& access = calleeAccess(node.first);
            for (const AstVar* const varp : access.m_vifMemberps) addVarp(varp);
            if (node.second) {
                for (const AstVar* const varp : access.m_ifaceVarps) addVarp(varp);
            }
            for (const ReadNode& succ : readSuccessors(node)) {
                ++steps;
                addNode(succ);
            }
            if (countsp) {
                ++countsp->m_functions;
                countsp->m_calls += access.m_calleeps.size() + access.m_vifCalleeps.size();
                countsp->m_reads += access.m_vifMemberps.size();
                if (node.second) countsp->m_reads += access.m_ifaceVarps.size();
            }
        }
        m_readSteps += steps;
        if (!budgetp) return true;
        if (steps > *budgetp) return false;
        *budgetp -= steps;
        return true;
    }

    // The vertices the given vertex of the call graph calls
    std::vector<ReadNode> readSuccessors(const ReadNode& node) {
        const CalleeAccess& access = calleeAccess(node.first);
        std::vector<ReadNode> succs;
        for (AstCFunc* const calleep : access.m_calleeps) succs.emplace_back(calleep, node.second);
        for (AstCFunc* const calleep : access.m_vifCalleeps) succs.emplace_back(calleep, true);
        return succs;
    }

    // The members the given vertices of the call graph may read through VIF, including in the
    // functions they call, transitively, from the memoized closures, in order of encounter
    std::vector<const AstVar*> memoizedMembers(const std::vector<ReadNode>& roots) {
        std::vector<const AstVar*> varps;
        std::unordered_set<const AstVar*> seenVarps;
        for (const ReadNode& root : roots) {
            for (const AstVar* const varp : m_closures[closureOf(root)]) {
                ++m_readSteps;
                if (seenVarps.emplace(varp).second) varps.push_back(varp);
            }
        }
        return varps;
    }

    // The index of the closure of the members the given vertex of the call graph may read
    // through VIF, including in the functions it calls. Found once for each strongly connected
    // component of the call graph (Tarjan), so mutually recursive functions share one closure.
    size_t closureOf(const ReadNode& root) {
        const auto rootIt = m_readNodeStates.find(root);
        if (rootIt != m_readNodeStates.end() && rootIt->second.m_closure != NO_INDEX) {
            return rootIt->second.m_closure;
        }
        // Depth-first search without recursion, as call chains may be deep
        struct Frame final {
            ReadNode m_node;  // Vertex visited
            std::vector<ReadNode> m_succs;  // Its successors
            size_t m_next = 0;  // Next successor to visit
        };
        std::vector<Frame> frames;
        std::vector<ReadNode> stack;  // Vertices of the components not yet complete
        const auto discover = [&](const ReadNode& node) {
            ReadNodeState& state = m_readNodeStates[node];
            state.m_index = state.m_lowlink = m_nextReadIndex++;
            state.m_onStack = true;
            stack.push_back(node);
            frames.push_back(Frame{node, readSuccessors(node)});
            ++m_readSteps;
        };
        discover(root);
        while (!frames.empty()) {
            Frame& frame = frames.back();
            if (frame.m_next < frame.m_succs.size()) {
                const ReadNode succ = frame.m_succs[frame.m_next++];
                ++m_readSteps;
                const auto it = m_readNodeStates.find(succ);
                if (it == m_readNodeStates.end()) {
                    discover(succ);
                } else if (it->second.m_onStack) {
                    ReadNodeState& state = m_readNodeStates.at(frame.m_node);
                    state.m_lowlink = std::min(state.m_lowlink, it->second.m_index);
                }
                continue;
            }
            const ReadNode node = frame.m_node;
            frames.pop_back();
            const ReadNodeState& state = m_readNodeStates.at(node);
            if (!frames.empty()) {
                ReadNodeState& parentState = m_readNodeStates.at(frames.back().m_node);
                parentState.m_lowlink = std::min(parentState.m_lowlink, state.m_lowlink);
            }
            if (state.m_lowlink != state.m_index) continue;
            // The root of a component: its closure is what its vertices read, and the closures
            // of the components they call, which are complete
            const size_t closure = m_closures.size();
            std::vector<ReadNode> members;
            while (true) {
                const ReadNode member = stack.back();
                stack.pop_back();
                ReadNodeState& memberState = m_readNodeStates.at(member);
                memberState.m_onStack = false;
                memberState.m_closure = closure;
                members.push_back(member);
                if (member == node) break;
            }
            std::vector<const AstVar*> varps;
            std::unordered_set<const AstVar*> seenVarps;
            const auto addVarp = [&](const AstVar* varp) {
                ++m_readSteps;
                if (seenVarps.emplace(varp).second) varps.push_back(varp);
            };
            for (const ReadNode& member : members) {
                const CalleeAccess& access = calleeAccess(member.first);
                for (const AstVar* const varp : access.m_vifMemberps) addVarp(varp);
                if (member.second) {
                    for (const AstVar* const varp : access.m_ifaceVarps) addVarp(varp);
                }
                for (const ReadNode& succ : readSuccessors(member)) {
                    ++m_readSteps;
                    const size_t succClosure = m_readNodeStates.at(succ).m_closure;
                    if (succClosure == closure) continue;
                    for (const AstVar* const varp : m_closures[succClosure]) addVarp(varp);
                }
            }
            m_closures.push_back(std::move(varps));
        }
        return m_readNodeStates.at(root).m_closure;
    }

    // The set of the VarScopes of the given member in every instance, made once
    size_t memberSet(const AstVar* varp) {
        const auto pair = m_memberSets.emplace(varp, NO_INDEX);
        if (!pair.second) return pair.first->second;
        const auto it = m_vscpsByVar.find(varp);
        if (it == m_vscpsByVar.end()) return NO_INDEX;  // Interface never instantiated
        m_setsRead.push_back(false);
        pair.first->second
            = m_triggers.m_clockedReads.addSet(VirtIfaceClockedReads::VarScopes{it->second});
        return pair.first->second;
    }
    // The sets of the given members
    VirtIfaceClockedReads::Sets memberSets(const std::vector<const AstVar*>& varps) {
        VirtIfaceClockedReads::Sets sets;
        for (const AstVar* const varp : varps) {
            const size_t index = memberSet(varp);
            if (index != NO_INDEX) sets.push_back(index);
        }
        // In order of creation, whatever order the members were found in
        std::sort(sets.begin(), sets.end());
        // Keep the NBA shadows of the members read
        for (const size_t index : sets) {
            if (m_setsRead[index]) continue;
            m_setsRead[index] = true;
            for (AstVarScope* const vscp : m_triggers.m_clockedReads.set(index)) {
                vscp->optimizeLifePost(false);
            }
        }
        return sets;
    }

    // Build final trigger list by intersecting the members written through VIF, or read through
    // VIF by combinational logic, with candidate VarScopes
    void buildTriggers() {
        std::unordered_set<IfaceMember, PairHash> triggeredMembers;
        const auto addTriggers = [&](const IfaceMember& member) {
            if (!triggeredMembers.emplace(member).second) return;
            const auto it = m_candidateVscps.find(member);
            if (it == m_candidateVscps.end()) return;
            for (AstVarScope* const vscp : it->second) {
                m_triggers.addTrigger(member.first, vscp->varp(), vscp);
            }
        };
        for (const IfaceMember& member : m_vifWrittenMembers) addTriggers(member);
        for (const IfaceMember& member : m_vifCombReadMembers) addTriggers(member);
    }

public:
    // CONSTRUCTORS
    explicit VirtIfaceVisitor(AstNetlist* nodep)
        : m_callTargetsp{V3CallTargets::build()} {
        iterate(nodep);
        for (size_t i = 0; i < m_reachableIfaceCallables.size(); ++i) {
            const IfaceCallable callable = m_reachableIfaceCallables[i];
            callable.second->foreach([this, callable](AstNodeExpr* const nodep) {
                if (AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
                    // Only persistent interface storage is observable through a VIF read.
                    // Random generator state has no value a read can observe.
                    UASSERT_OBJ(refp->varScopep(), refp, "No var scope");
                    AstVar* const varp = refp->varp();
                    const AstBasicDType* const basicp = varp->basicp();
                    if (!refp->access().isWriteOrRW() || varp->isFuncLocal() || varp->isTemp()
                        || varp->isEvent() || (basicp && basicp->isStdRandomGenerator())
                        || !VN_IS(refp->varScopep()->scopep()->modp(), Iface)) {
                        return;
                    }
                    varp->sensIfacep(callable.first);
                    addVifWrittenMember(callable.first, varp->name());
                    const auto it = m_vscpsByVar.find(varp);
                    UASSERT_OBJ(it != m_vscpsByVar.end(), varp,
                                "No VarScope for interface member");
                    for (AstVarScope* const vscp : it->second)
                        addCandidateVscp(callable.first, vscp);
                } else if (AstNodeCCall* const callp = VN_CAST(nodep, NodeCCall)) {
                    addReachableIfaceCallable(callable.first, callp->funcp());
                }
            });
        }
        for (size_t i = 0; i < m_combIfaceCallables.size(); ++i) {
            addCombReadMembers(m_combIfaceCallables[i]);
        }
        buildTriggers();
        buildClockedReads();
    }
    ~VirtIfaceVisitor() override = default;

    // METHODS
    VirtIfaceTriggers take_triggers() { return std::move(m_triggers); }
};

}  //namespace

const VirtIfaceClockedReads::Sets VirtIfaceClockedReads::s_none;

bool VirtIfaceClockedReads::isVirtIfaceRead(const AstMemberRef* nodep) {
    const AstIfaceRefDType* const dtypep
        = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), IfaceRefDType);
    return dtypep && dtypep->isVirtual();
}

const VirtIfaceClockedReads::Sets&
VirtIfaceClockedReads::forMemberRef(const AstMemberRef* nodep) const {
    if (!isVirtIfaceRead(nodep)) return s_none;
    return setsFor<const AstVar*>(m_memberReads, nodep->varp());
}

VirtIfaceTriggers makeVirtIfaceTriggers(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    VirtIfaceTriggers triggers{};
    if (v3Global.hasVirtIfaces()) {
        triggers = VirtIfaceVisitor{nodep}.take_triggers();
        // Dump after destructor so VNDeleter runs
        V3Global::dumpCheckGlobalTree("sched_vif", 0, dumpTreeEitherLevel() >= 6);
    }
    return triggers;
}

}  //namespace V3Sched
