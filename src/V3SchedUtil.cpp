// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Utility functions used by code scheduling
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
//
//
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3EmitCBase.h"
#include "V3EmitV.h"
#include "V3Order.h"
#include "V3Sched.h"
#include "V3SenExprBuilder.h"
#include "V3SenTree.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {
namespace util {

AstCFunc* makeSubFunction(AstNetlist* netlistp, const string& name, bool slow) {
    AstScope* const scopeTopp = netlistp->topScopep()->scopep();
    AstCFunc* const funcp = new AstCFunc{netlistp->fileline(), name, scopeTopp, ""};
    funcp->dontCombine(true);
    funcp->isStatic(false);
    funcp->isLoose(true);
    funcp->slow(slow);
    funcp->isConst(false);
    funcp->declPrivate(true);
    scopeTopp->addBlocksp(funcp);
    return funcp;
}

AstVarScope* newArgument(AstCFunc* funcp, AstNodeDType* dtypep, const string& name,
                         VDirection direction) {
    FileLine* const flp = funcp->fileline();
    AstScope* const scopep = funcp->scopep();
    AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP, name, dtypep};
    varp->funcLocal(true);
    varp->direction(direction);
    funcp->addArgsp(varp);
    AstVarScope* const vscp = new AstVarScope{flp, scopep, varp};
    scopep->addVarsp(vscp);
    return vscp;
}

AstNodeStmt* setVar(AstVarScope* vscp, uint32_t val) {
    FileLine* const flp = vscp->fileline();
    AstVarRef* const refp = new AstVarRef{flp, vscp, VAccess::WRITE};
    AstConst* const valp = new AstConst{flp, AstConst::DTyped{}, vscp->dtypep()};
    valp->num().setLong(val);
    return new AstAssign{flp, refp, valp};
}

AstNodeStmt* incrementVar(AstVarScope* vscp) {
    FileLine* const flp = vscp->fileline();
    AstVarRef* const wrefp = new AstVarRef{flp, vscp, VAccess::WRITE};
    AstVarRef* const rrefp = new AstVarRef{flp, vscp, VAccess::READ};
    AstConst* const onep = new AstConst{flp, AstConst::DTyped{}, vscp->dtypep()};
    onep->num().setLong(1);
    return new AstAssign{flp, wrefp, new AstAdd{flp, rrefp, onep}};
}

AstNodeStmt* callVoidFunc(AstCFunc* funcp) {
    if (!funcp) return nullptr;
    AstCCall* const callp = new AstCCall{funcp->fileline(), funcp};
    callp->dtypeSetVoid();
    return callp->makeStmt();
}

static AstCFunc* splitCheckCreateNewSubFunc(AstCFunc* ofuncp) {
    static std::map<AstCFunc*, uint32_t> s_funcNums;  // What split number to attach to a function
    const uint32_t funcNum = s_funcNums[ofuncp]++;
    const std::string name = ofuncp->name() + "__" + cvtToStr(funcNum);
    AstScope* const scopep = ofuncp->scopep();
    AstCFunc* const subFuncp = new AstCFunc{ofuncp->fileline(), name, scopep};
    scopep->addBlocksp(subFuncp);
    // Combinable if the original is, so instances of a module share the parts of their code
    subFuncp->dontCombine(ofuncp->dontCombine());
    subFuncp->isStatic(ofuncp->isStatic());
    subFuncp->isLoose(true);
    subFuncp->slow(ofuncp->slow());
    subFuncp->ifdef(ofuncp->ifdef());
    subFuncp->declPrivate(ofuncp->declPrivate());
    if (ofuncp->needsVlProcess()) subFuncp->setNeedsVlProcess();
    for (AstVar* const argp : ofuncp->argspList()) {
        AstVar* const clonep = argp->cloneTree(false);
        subFuncp->addArgsp(clonep);
        AstVarScope* const vscp = new AstVarScope{clonep->fileline(), scopep, clonep};
        scopep->addVarsp(vscp);
        argp->user3p(vscp);
    }
    return subFuncp;
};

void splitCheckFinishSubFunc(AstCFunc* ofuncp, AstCFunc* subFuncp,
                             const std::unordered_map<const AstVar*, AstVarScope*>& argVscps) {
    FileLine* const flp = subFuncp->fileline();
    AstCCall* const callp = new AstCCall{subFuncp->fileline(), subFuncp};
    callp->dtypeSetVoid();
    // Pass arguments through to subfunction
    for (AstVar* const argp : ofuncp->argspList()) {
        UASSERT_OBJ(argp->direction() == VDirection::CONSTREF, argp, "Unexpected direction");
        callp->addArgsp(new AstVarRef{flp, argVscps.at(argp), VAccess::READ});
    }

    bool containsAwait = false;
    subFuncp->foreach([&](AstNode* nodep) {
        // Record if it has a CAwait
        if (VN_IS(nodep, CAwait)) containsAwait = true;
        // Redirect references to arguments to the clone in the sub-function
        if (AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
            if (AstVarScope* const vscp = VN_AS(refp->varp()->user3p(), VarScope)) {
                refp->varp(vscp->varp());
                refp->varScopep(vscp);
            }
        }
    });

    if (ofuncp->isCoroutine() && containsAwait) {  // Wrap call with co_await
        subFuncp->rtnType("VlCoroutine");
        ofuncp->addStmtsp(new AstCAwait{flp, callp});
    } else {
        ofuncp->addStmtsp(callp->makeStmt());
    }
}

// Compute, for each top level statement of 'ofuncp', whether a new sub-function may begin there.
// Sub-functions are emitted as separate C++ functions, so they cannot see each other's automatic
// storage. A function-local AstVar declared among the top level statements must therefore end up
// in the same sub-function as every reference to it, otherwise the emitted C++ refers to an
// undeclared identifier (and the AstVar can be deleted from under the still-live references).
static std::vector<bool> splitCheckBreakable(const AstCFunc* ofuncp) {
    // Gather the top level statements, and where each locally declared variable is declared
    std::vector<const AstNode*> stmtps;
    std::unordered_map<const AstVar*, size_t> declIdx;  // Local var -> index it is declared at
    for (const AstNode* const nodep : ofuncp->stmtspList()) {
        if (const AstVar* const varp = VN_CAST(nodep, Var)) declIdx.emplace(varp, stmtps.size());
        stmtps.push_back(nodep);
    }

    // Find the last statement referencing each locally declared variable
    std::vector<size_t> lastUse(stmtps.size());
    for (size_t i = 0; i < stmtps.size(); ++i) {
        lastUse[i] = i;  // A declaration is live at least where it is declared
        stmtps[i]->foreach([&](const AstNodeVarRef* refp) {
            const auto it = declIdx.find(refp->varp());  // 'end()' if not one of our locals
            if (it != declIdx.end()) lastUse[it->second] = std::max(lastUse[it->second], i);
        });
    }

    // A break before statement 'i' is allowed only if no local declared before 'i' is still live
    std::vector<bool> breakable(stmtps.size(), true);
    size_t liveEnd = 0;  // Last index any so far declared local is referenced at
    for (size_t i = 0; i < stmtps.size(); ++i) {
        breakable[i] = liveEnd < i;
        if (VN_IS(stmtps[i], Var)) liveEnd = std::max(liveEnd, lastUse[i]);
    }
    return breakable;
}

size_t emittedNodeSizeEstimate(const AstNode* nodep) {
    if (!nodep->isWide()) return 1;
    // V3Expand evaluates a concatenation, an extension or a constant select of a wide value by
    // taking the words of its operands, which are counted themselves, so it is not counted per
    // word, as a chain of them, each wider than the one under it, would be at each level. It
    // inserts a narrow operand of a concatenation into each word it spans, of at most one more
    // than its own words, with a shift, a mask and an OR.
    if (const AstConcat* const catp = VN_CAST(nodep, Concat)) {
        size_t size = 1;
        for (const AstNodeExpr* const opp : {catp->lhsp(), catp->rhsp()}) {
            if (!opp->isWide()) size += 3 * (VL_WORDS_I(opp->width()) + 1);
        }
        return size;
    }
    if (VN_IS(nodep, Extend) || VN_IS(nodep, ExtendS)) return 1;
    if (const AstSel* const selp = VN_CAST(nodep, Sel)) {
        if (VN_IS(selp->lsbp(), Const)) return 1;
    }
    return nodep->widthWords();
}

size_t emittedSizeEstimate(const AstNode* nodep) {
    size_t size = 0;
    nodep->foreach([&](const AstNode* itemp) { size += emittedNodeSizeEstimate(itemp); });
    return size;
}

// Split large function according to --output-split-cfuncs
void splitCheck(AstCFunc* const ofuncp) {
    if (!ofuncp) return;
    UASSERT_OBJ(!ofuncp->varsp(), ofuncp, "Can't split function with local variables");
    if (!v3Global.opt.outputSplitCFuncs() || !ofuncp->stmtsp()) return;
    if (emittedSizeEstimate(ofuncp) < static_cast<size_t>(v3Global.opt.outputSplitCFuncs()))
        return;

    // Statement boundaries that would separate a local declaration from a reference to it
    const std::vector<bool> breakable = splitCheckBreakable(ofuncp);

    // Need to find the AstVarScopes for the function arguments. They should be in the same Scope.
    std::unordered_map<const AstVar*, AstVarScope*> argVscps;
    for (AstVar* const argp : ofuncp->argspList()) {
        UASSERT_OBJ(argVscps.size() < 2, argp, "There should be at most 2 arguments, or O(n^2)");
        bool found = false;
        for (AstVarScope* const vscp : ofuncp->scopep()->varspList()) {
            if (vscp->varp() != argp) continue;
            argVscps[argp] = vscp;
            found = true;
            break;
        }
        UASSERT_OBJ(found, argp, "Can't find VarScope for function argument");
    }

    // AstVar::user3p(): AstVarScope for function argument in clone
    const VNUser3InUse user3InUse;

    size_t size = 0;
    AstCFunc* subFuncp = nullptr;

    // Move statements one by one to the new sub-functions
    AstNodeStmt* stmtsp = ofuncp->stmtsp()->unlinkFrBackWithNext();
    for (size_t index = 0; AstNodeStmt* const itemp = stmtsp; ++index) {
        stmtsp = VN_AS(stmtsp->nextp(), NodeStmt);
        if (stmtsp) stmtsp->unlinkFrBackWithNext();
        const size_t itemSize = emittedSizeEstimate(itemp);
        size += itemSize;

        if (size > static_cast<size_t>(v3Global.opt.outputSplitCFuncs()) && breakable[index]) {
            if (subFuncp) splitCheckFinishSubFunc(ofuncp, subFuncp, argVscps);
            subFuncp = nullptr;
            size = itemSize;
        }

        if (!subFuncp) subFuncp = splitCheckCreateNewSubFunc(ofuncp);
        subFuncp->addStmtsp(itemp);
    }
    if (subFuncp) splitCheckFinishSubFunc(ofuncp, subFuncp, argVscps);
}

//######################################################################
// Visit the variable accesses of logic, following calls into the called functions

class SchedLogicAccessVisitor final : public VNVisitorConst {
    // STATE
    const LogicActionAccessFunc& m_f;  // Called on each access
    std::unordered_set<const AstCFunc*> m_calledps;  // Functions already followed
    std::unordered_set<const AstCFunc*> m_calledActionps;  // Followed only from action blocks
    bool m_inCallee = false;  // Under a called function
    bool m_readsOnly = false;  // Under a called static class method
    bool m_inAction = false;  // Under a call in an assertion action block

    // VISITORS
    void visit(AstVarRef* nodep) override {
        // Variables declared in a called function are excluded (IEEE 1800-2023 9.2.2.2.1)
        if (m_inCallee && nodep->varp()->isFuncLocal()) return;
        const bool inAction = m_inAction || nodep->inAssertAction();
        if (!m_readsOnly) {
            m_f(nodep->varScopep(), nodep->access(), inAction);
        } else if (nodep->access().isReadOrRW()) {
            m_f(nodep->varScopep(), VAccess::READ, inAction);
        }
    }
    void visit(AstCCall* nodep) override {
        iterateChildrenConst(nodep);
        followCall(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit SchedLogicAccessVisitor(const LogicActionAccessFunc& f)
        : m_f{f} {}

    // METHODS
    void iterateLogic(AstNode* nodep) { iterateConst(nodep); }
    void followCall(const AstCCall* callp) {
        AstCFunc* const funcp = callp->funcp();
        if (!isLogicCallee(funcp)) return;
        VL_RESTORER(m_inAction);
        m_inAction = m_inAction || callp->inAssertAction();
        // Each function is visited once per logic, like a once-inlined body: linear in the
        // total size of the called functions, as inlining all calls would be. One called from
        // an action block is visited again if also called from elsewhere.
        if (m_calledps.count(funcp)) return;
        if (m_inAction ? !m_calledActionps.emplace(funcp).second
                       : !m_calledps.emplace(funcp).second) {
            return;
        }
        VL_RESTORER(m_inCallee);
        VL_RESTORER(m_readsOnly);
        m_inCallee = true;
        // Static class methods often update static state shared by all callers, such as call
        // counters, which as writes of every caller would make them combinational loops
        if (VN_IS(funcp->scopep()->modp(), ClassPackage)) m_readsOnly = true;
        iterateChildrenConst(funcp);
    }
};

void foreachLogicAccess(AstNode* nodep, const LogicAccessFunc& f) {
    const LogicActionAccessFunc actionf
        = [&f](AstVarScope* vscp, VAccess access, bool) { f(vscp, access); };
    SchedLogicAccessVisitor{actionf}.iterateLogic(nodep);
}

void foreachLogicActionAccess(AstNode* nodep, const LogicActionAccessFunc& f) {
    SchedLogicAccessVisitor{f}.iterateLogic(nodep);
}

void foreachCallAccess(const AstCCall* callp, const LogicAccessFunc& f) {
    const LogicActionAccessFunc actionf
        = [&f](AstVarScope* vscp, VAccess access, bool) { f(vscp, access); };
    SchedLogicAccessVisitor{actionf}.followCall(callp);
}

AstSenTree* changeSenTree(SenTreeFinder& finder, AstNodeProcedure* procp,
                          const std::unordered_set<const AstVarScope*>& vscps) {
    FileLine* const flp = procp->fileline();
    AstSenItem* senItemsp = nullptr;
    std::unordered_set<const AstVarScope*> added;
    foreachLogicAccess(procp, [&](AstVarScope* vscp, VAccess) {
        if (!vscps.count(vscp) || !added.emplace(vscp).second) return;
        AstVarRef* const newRefp = new AstVarRef{flp, vscp, VAccess::READ};
        senItemsp
            = AstNode::addNext(senItemsp, new AstSenItem{flp, VEdgeType::ET_HYBRID, newRefp});
    });
    AstSenTree* const senTreep = new AstSenTree{flp, senItemsp};
    AstSenTree* const resultp = finder.getSenTree(senTreep);
    // SenTreeFinder::getSenTree clones, so clean up
    VL_DO_DANGLING(senTreep->deleteTree(), senTreep);
    return resultp;
}

SoleWriterMap computeSoleWriters(AstNetlist* netlistp) {
    SoleWriterMap soleWriters;
    // Static initializers run before any process, so do not count as writers
    netlistp->foreach([&](const AstActive* activep) {
        if (activep->sentreep()->hasStatic()) return;
        for (AstNodeProcedure* const procp : activep->procspList()) {
            foreachLogicAccess(procp, [&](const AstVarScope* vscp, VAccess access) {
                if (!access.isWriteOrRW()) return;
                const auto pair = soleWriters.emplace(vscp, procp);
                if (pair.second) return;
                if (pair.first->second != procp) pair.first->second = nullptr;
            });
        }
    });
    // Writes in functions called other than as logic, and outside the model, are other writers
    netlistp->foreach([&](AstCFunc* funcp) {
        if (isLogicCallee(funcp)) return;  // Of the processes calling it
        foreachLogicAccess(funcp, [&](const AstVarScope* vscp, VAccess access) {
            if (access.isWriteOrRW()) soleWriters[vscp] = nullptr;
        });
    });
    for (auto& pair : soleWriters) {
        const AstVar* const varp = pair.first->varp();
        if (varp->isForceable() || varp->isSigPublic() || varp->isWrittenByDpi()
            || varp->isInout()) {
            pair.second = nullptr;
        }
    }
    return soleWriters;
}

std::unordered_set<const AstVarScope*>
computeImplicitSensitivities(AstNodeProcedure* procp, const SoleWriterMap& soleWriters,
                             size_t& excludedr) {
    // Dangerous assumption:
    // A variable read after the process assigned it earlier (in tree order, with a read-write
    // reference counting as an assignment) is not an implicit sensitivity, considering it
    // something like:
    //      foo = 1
    //      foo = foo + 1
    // Note this will break though:
    //      if (sometimes) foo = 1
    //      foo = foo + 1
    // TODO: Do this properly with liveness analysis (i.e.: if live, it's an implicit sensitivity)
    const AstAlways* const alwaysp = VN_CAST(procp, Always);
    const bool userComb = alwaysp && alwaysp->userComb();
    std::unordered_set<const AstVarScope*> implicitSensitivities;
    std::unordered_set<const AstVarScope*> assigned;
    // "Expressions used in assertion action blocks do not contribute to the implicit sensitivity
    // list of an always_comb" (IEEE 1800-2023 9.2.2.2.1). Variables read only there:
    std::unordered_set<const AstVarScope*> actionReads;
    // Internal variables whose writes scheduling ignores, such as the pending reports of a
    // deferred assertion, wake no combinational logic. What they hold is the process's own state
    // between runs, so an always_comb reading one is not idempotent.
    std::unordered_set<const AstVarScope*> internalReads;
    const size_t excludedBefore = excludedr;
    foreachLogicActionAccess(procp, [&](const AstVarScope* vscp, VAccess access, bool inAction) {
        if (access.isWriteOrRW() && !vscp->varp()->ignoreSchedWrite()) assigned.emplace(vscp);
        if (access.isReadOrRW() && !assigned.count(vscp)) {
            if (vscp->varp()->isInternal() && vscp->varp()->ignoreSchedWrite()) {
                internalReads.emplace(vscp);
            } else if (userComb && inAction) {
                actionReads.emplace(vscp);
            } else {
                implicitSensitivities.emplace(vscp);
            }
        }
    });
    for (const AstVarScope* const vscp : actionReads) {
        if (!implicitSensitivities.count(vscp)) ++excludedr;
    }
    excludedr += userComb ? internalReads.size() : 0;
    std::unordered_set<const AstVarScope*> unexcluded;  // Before anything is left out
    // A user's always_comb is not sensitive to what it writes (IEEE 1800-2023 9.2.2.2.1), so does
    // not wake itself. Only the whole variables it alone writes are excluded, as another process
    // may drive other parts (IEEE 1800-2023 9.2.2.2). A task's writes count, being inlined.
    if (userComb) {
        unexcluded = implicitSensitivities;
        unexcluded.insert(actionReads.begin(), actionReads.end());
        unexcluded.insert(internalReads.begin(), internalReads.end());
        for (const AstVarScope* const vscp : assigned) {
            const auto it = soleWriters.find(vscp);
            if (it != soleWriters.end() && it->second == procp
                && implicitSensitivities.erase(vscp)) {
                ++excludedr;
            }
        }
    }
    // A user's always_comb leaving a variable out is run only by changes of the rest (see
    // V3Sched). If a change of one of those cannot be detected, is of a variable whose writes
    // scheduling ignores, or is of a public variable, which may be written from outside the model
    // and whose readers the 'ico' region runs, leave nothing out: it then stays as before, a
    // cycle that is reported, rather than logic silently running more often than IEEE allows.
    if (excludedr != excludedBefore
        && !std::all_of(implicitSensitivities.begin(), implicitSensitivities.end(),
                        [](const AstVarScope* vscp) {
                            return SenExprBuilder::isSupportedDType(vscp->dtypep())
                                   && !vscp->varp()->ignoreSchedWrite()
                                   && !vscp->varp()->isSigPublic();
                        })) {
        excludedr = excludedBefore;
        implicitSensitivities = std::move(unexcluded);
    }
    // Reads through forced values the process computes itself do not trigger it either
    VarScopeSet forceReadEdgeIgnores;
    collectForceReadEdgeIgnores(procp, forceReadEdgeIgnores);
    for (const AstVarScope* const vscp : forceReadEdgeIgnores) implicitSensitivities.erase(vscp);
    return implicitSensitivities;
}

}  // namespace util

}  // namespace V3Sched
