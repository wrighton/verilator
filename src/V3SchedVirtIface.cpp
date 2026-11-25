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
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3AstNodeExpr.h"
#include "V3CallTargets.h"
#include "V3Sched.h"

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

    // Set of (iface, member) pairs written through VIF -- defines which members need triggers
    std::set<IfaceMember> m_vifWrittenMembers;
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
    VirtIfaceTriggers m_triggers;  // Triggers found for virtual interface writes
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
        m_inComb = nodep->sentreep()->hasCombo() || nodep->sentreep()->hasHybrid();
        iterateChildren(nodep);
    }
    void visit(AstMemberRef* nodep) override {
        // Detect writes through VIF: the MemberRef's fromp resolves to a virtual interface type.
        // Handles both direct VIF access (vif.member) and class chain (obj.vif.member).
        if (nodep->access().isWriteOrRW()) {
            AstIfaceRefDType* const dtypep
                = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), IfaceRefDType);
            if (dtypep && dtypep->isVirtual()) {
                m_vifWrittenMembers.emplace(dtypep->ifacep(), nodep->varp()->name());
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
                for (AstCFunc* const funcp : m_callTargetsp->getTargets(nodep)) {
                    addReachableIfaceCallable(dtypep->ifaceViaCellp(), funcp);
                    if (m_inComb && util::isLogicCallee(funcp)) {
                        addCombIfaceCallable(dtypep->ifaceViaCellp(), funcp);
                        addCombReadSelect(dtypep->ifaceViaCellp(), memberRefp->fromp());
                    }
                }
            }
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
    void visit(AstNodeProcedure* nodep) override {
        // Disable lifetime optimization for variables in AlwaysPost blocks
        // that write to virtual interface members, as VIF reads may observe them
        if (VN_IS(nodep, AlwaysPost) && writesToVirtIface(nodep)) {
            nodep->foreach([](AstVarRef* refp) { refp->varScopep()->optimizeLifePost(false); });
        }
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

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
                    UASSERT_OBJ(refp->varScopep(), refp, "No var scope");
                    AstVar* const varp = refp->varp();
                    if (!refp->access().isWriteOrRW() || varp->isFuncLocal() || varp->isTemp()
                        || varp->isEvent() || !VN_IS(refp->varScopep()->scopep()->modp(), Iface)) {
                        return;
                    }
                    varp->sensIfacep(callable.first);
                    m_vifWrittenMembers.emplace(callable.first, varp->name());
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
    }
    ~VirtIfaceVisitor() override = default;

    // METHODS
    VirtIfaceTriggers take_triggers() { return std::move(m_triggers); }
};

}  //namespace

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
