// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Outline parts of large functions into sub-functions
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
// V3Outline's Transformations:
//
// A timed process or task is emitted as a C++ coroutine, and the time and memory a C++
// compiler needs for a coroutine grow much faster than its size. V3Sched splits a large
// process only between its top level statements, so when most of a coroutine is inside one
// statement, such as the branches of an 'if' that call inlined tasks, the coroutine stays as
// large as the whole process. C++ compilers also need super-linear time for a very large
// ordinary function, such as one made for a process whose logic is all under one 'if' on a
// reset. This pass moves parts of such statements into sub-functions, until each is no larger
// than --output-split-cfuncs.
//
// For each coroutine, and each function of a module without arguments or local variables, as
// the scheduler makes for ordered logic:
//  1. Analysis: one traversal records the estimated emitted size of each statement (see
//     V3Sched::util::emittedSizeEstimate), and whether it can move into another function: it
//     cannot if it jumps out of itself, tests the condition of a loop around it, or contains
//     user C++ text, which may use C++ locals or return.
//  2. Decision: for each top level statement larger than the limit, take the statement lists
//     directly under it. Their statements larger than the limit stay in place, and the same is
//     done in each of them first; one of them that is movable, with nothing inside it to move,
//     such as one large assignment, moves alone instead. A wide assignment over the limit with
//     nothing inside it to move, also at the top level, is first split into assignments of
//     ranges of whole words, each moving like a statement, if its value is made by operations
//     V3Expand evaluates a word at a time, so no wide operation is evaluated in two parts, and
//     does not read the variable assigned (see sliceOf). The consecutive movable statements in
//     between form runs. Starting with the largest run, runs are cut into groups no larger
//     than the limit to move, until the statement is within the limit. A statement moves only
//     with nothing inside it moved, so groups never nest, and new functions need no further
//     splitting.
//  3. Rewrite: each group moves into a new function, called in its place, with co_await if it
//     suspends. Local variables of the coroutine that the group references are passed by
//     reference. This runs before V3Localize, while most variables are module variables, so
//     only the arguments and locals of tasks that are not inlined need passing.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Outline.h"

#include "V3EmitCBase.h"
#include "V3Localize.h"
#include "V3Sched.h"
#include "V3Stats.h"
#include "V3VNUserAllocator.h"

#include <algorithm>
#include <limits>
#include <unordered_set>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Pass to a new function the local variables of the coroutine that its statements reference

class OutlineArgsVisitor final : public VNVisitor {
    // STATE
    AstCFunc* const m_funcp;  // New function
    AstCCall* const m_callp;  // Call of the new function
    // Module variables to pass, as V3Localize may make them local to the function -> whether
    // the function only writes them
    const std::unordered_map<const AstVarScope*, bool>& m_passVscps;
    // Local variable -> argument passing it, nullptr if declared in the new function
    std::unordered_map<const AstVar*, AstVarScope*> m_argVscps;
    // Module variable -> argument passing it; one declaration has a variable in each scope
    std::unordered_map<const AstVarScope*, AstVarScope*> m_moduleArgVscps;
    std::unordered_set<const AstVarScope*> m_writtenps;  // Variables the new function writes
    bool m_hasAwait = false;  // The new function suspends

    // VISITORS
    void visit(AstCAwait* nodep) override {
        m_hasAwait = true;
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        m_argVscps.emplace(nodep, nullptr);
        iterateChildren(nodep);
    }
    void visit(AstVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        AstVarScope* const vscp = nodep->varScopep();
        const auto passIt = m_passVscps.find(vscp);
        const bool passModuleVar = passIt != m_passVscps.end();
        if (!varp->isFuncLocal() && !passModuleVar) return;
        bool inserted;
        AstVarScope** argVscpp;
        if (passModuleVar) {
            const auto pair = m_moduleArgVscps.emplace(vscp, nullptr);
            inserted = pair.second;
            argVscpp = &pair.first->second;
        } else {
            const auto pair = m_argVscps.emplace(varp, nullptr);
            inserted = pair.second;
            argVscpp = &pair.first->second;
        }
        if (inserted) {
            const bool written = m_writtenps.count(vscp);
            // A module variable only read is passed by value, which the new function can keep
            // in registers, as it cannot change during the call
            const VDirection dir = passModuleVar && !written ? VDirection::INPUT
                                   : varp->isConstRef()      ? VDirection::CONSTREF
                                                             : VDirection::REF;
            // Variables of other scopes may share the name, so are named by their scope
            const std::string name
                = vscp->scopep() == m_funcp->scopep()
                      ? varp->name()
                      : vscp->scopep()->nameDotless() + "__DOT__" + varp->name();
            *argVscpp = V3Sched::util::newArgument(m_funcp, varp->dtypep(), name, dir);
            // Read-only at the call if the function only reads it
            // Written at the call if the function writes it, and only written if the function
            // never reads it, so V3Localize can still make it local to the caller
            const VAccess access = !written                          ? VAccess::READ
                                   : passModuleVar && passIt->second ? VAccess::WRITE
                                                                     : VAccess::READWRITE;
            m_callp->addArgsp(new AstVarRef{m_callp->fileline(), vscp, access});
        }
        if (AstVarScope* const argVscp = *argVscpp) {
            nodep->varp(argVscp->varp());
            nodep->varScopep(argVscp);
        }
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    OutlineArgsVisitor(AstCFunc* funcp, AstCCall* callp,
                       const std::unordered_map<const AstVarScope*, bool>& passVscps)
        : m_funcp{funcp}
        , m_callp{callp}
        , m_passVscps{passVscps} {
        funcp->stmtsp()->foreachAndNext([this](const AstVarRef* refp) {
            if (refp->access().isWriteOrRW()) m_writtenps.emplace(refp->varScopep());
        });
        iterateAndNextNull(funcp->stmtsp());
    }
    ~OutlineArgsVisitor() override = default;

    bool hasAwait() const { return m_hasAwait; }
};

//######################################################################
// Find the only function referencing each module variable

class OutlineSoleFuncVisitor final : public VNVisitorConst {
    // STATE
    // Module variable -> the only function referencing it, nullptr if several, or if referenced
    // outside of any function, e.g. by tracing
    std::unordered_map<const AstVarScope*, const AstCFunc*>& m_soleFuncps;
    const AstCFunc* m_funcp = nullptr;  // Current function

    // VISITORS
    void visit(AstCFunc* nodep) override {
        VL_RESTORER(m_funcp);
        m_funcp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstVarRef* nodep) override {
        const auto pair = m_soleFuncps.emplace(nodep->varScopep(), m_funcp);
        if (pair.first->second != m_funcp) pair.first->second = nullptr;
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    OutlineSoleFuncVisitor(AstNetlist* netlistp,
                           std::unordered_map<const AstVarScope*, const AstCFunc*>& soleFuncps)
        : m_soleFuncps{soleFuncps} {
        iterateConst(netlistp);
    }
    ~OutlineSoleFuncVisitor() override = default;
};

//######################################################################
// Outline parts of large coroutines

class OutlineVisitor final : public VNVisitor {
    // NODE STATE
    //  AstNodeStmt::user1p()  -> StmtInfo. Analysis of statement in the current coroutine
    const VNUser1InUse m_user1InUse;

    // TYPES
    struct StmtInfo final {
        size_t m_size = 0;  // Estimated emitted size of the statement
        int m_depth = 0;  // Nesting depth of the statement in the coroutine
        bool m_movable = false;  // Can move into another function
    };
    struct StmtRange final {
        AstNodeStmt* m_firstp;  // First statement
        AstNodeStmt* m_lastp;  // Last statement
        size_t m_size;  // Estimated emitted size of the statements
    };

    // STATE
    VNUser1Allocator<AstNodeStmt, StmtInfo> m_info;
    const size_t m_limit = static_cast<size_t>(v3Global.opt.outputSplitCFuncs());
    AstCFunc* m_funcp = nullptr;  // Current coroutine
    size_t m_funcNum = 0;  // Number of functions outlined from the current coroutine
    std::vector<StmtRange> m_groups;  // Statements to move, each group into a new function
    size_t m_count = 0;  // Estimated emitted size of the nodes analyzed
    int m_depth = 0;  // Nesting depth of the statement being analyzed
    int m_targetDepth = 0;  // Least depth of the jump and loop test targets in the statement
    VDouble0 m_statFuncs;  // Number of functions created
    VDouble0 m_statSplits;  // Number of wide assignments split
    VDouble0 m_statMovedBounds;  // Number of part boundaries moved off costly operands
    // Module variable -> the only function referencing it, nullptr if several, see findSoleFuncps
    std::unordered_map<const AstVarScope*, const AstCFunc*> m_soleFuncps;
    bool m_soleFuncpsFound = false;  // m_soleFuncps is complete
    AstNetlist* const m_netlistp;  // The design, for findSoleFuncps
    // Module variables referenced only by the current function, that V3Localize may make local
    // -> whether the function only writes it
    std::unordered_map<const AstVarScope*, bool> m_passVscps;

    // METHODS - analysis
    // Analyze 'nodep', which jumps to or tests the loop of the statement at 'targetDepth'
    void analyze(AstNodeStmt* nodep, int targetDepth) {
        StmtInfo& info = m_info(nodep);
        VL_RESTORER(m_depth);
        info.m_depth = ++m_depth;
        const size_t startCount = m_count;
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        const int outerTargetDepth = m_targetDepth;
        m_targetDepth = targetDepth;
        iterateChildren(nodep);
        info.m_size = m_count - startCount;
        info.m_movable = m_targetDepth >= info.m_depth;
        m_targetDepth = std::min(m_targetDepth, outerTargetDepth);
    }

    // METHODS - decision
    // Cut 'run' into groups no larger than the limit, to move; a statement over the limit by
    // itself is a group alone
    void groupRun(const StmtRange& run) {
        StmtRange group{run.m_firstp, nullptr, 0};
        for (AstNode* nodep = run.m_firstp; nodep != run.m_lastp->nextp();
             nodep = nodep->nextp()) {
            AstNodeStmt* const stmtp = VN_AS(nodep, NodeStmt);
            const size_t size = m_info(stmtp).m_size;
            if (group.m_lastp && group.m_size + size > m_limit) {
                m_groups.push_back(group);
                group = StmtRange{stmtp, nullptr, 0};
            }
            group.m_lastp = stmtp;
            group.m_size += size;
        }
        m_groups.push_back(group);
    }
    // Whether 'nodep' is cheap enough to evaluate in every part of a split assignment: a
    // narrow variable, constant or constant select of one, or a negation or an equality of such
    static bool isCheap(const AstNodeExpr* nodep) {
        if (const AstSel* const selp = VN_CAST(nodep, Sel)) {
            return !selp->isWide() && VN_IS(selp->lsbp(), Const)
                   && (VN_IS(selp->fromp(), VarRef) || VN_IS(selp->fromp(), Const));
        }
        if (nodep->isWide()) return false;
        if (VN_IS(nodep, VarRef) || VN_IS(nodep, Const)) return true;
        if (const AstNot* const notp = VN_CAST(nodep, Not)) return isCheap(notp->lhsp());
        if (const AstLogNot* const notp = VN_CAST(nodep, LogNot)) return isCheap(notp->lhsp());
        if (VN_IS(nodep, Eq) || VN_IS(nodep, Neq)) {
            const AstNodeBiop* const biopp = VN_AS(nodep, NodeBiop);
            return isCheap(biopp->lhsp()) && isCheap(biopp->rhsp());
        }
        return false;
    }
    // Whether narrow 'nodep' is cheap to evaluate in two parts: it has no wide operation,
    // reading wide values only by constant selects of variables or constants, and no division,
    // power or call. The costly operations are listed, so one not listed is only evaluated in
    // two parts, still correctly.
    static bool isCheapToRepeat(const AstNodeExpr* nodep) {
        size_t wideLeaves = 0;  // Wide variables and constants
        bool costly = false;  // Has a wide operation, a division, a power or a call
        nodep->foreach([&](const AstNodeExpr* exprp) {
            if (VN_IS(exprp, VarRef) || VN_IS(exprp, Const)) {
                if (exprp->isWide()) ++wideLeaves;
            } else if (exprp->isWide() || VN_IS(exprp, Div) || VN_IS(exprp, DivS)
                       || VN_IS(exprp, DivD) || VN_IS(exprp, ModDiv) || VN_IS(exprp, ModDivS)
                       || VN_IS(exprp, Pow) || VN_IS(exprp, PowD) || VN_IS(exprp, PowSS)
                       || VN_IS(exprp, PowSU) || VN_IS(exprp, PowUS) || VN_IS(exprp, NodeCCall)
                       || VN_IS(exprp, NodeFTaskRef) || VN_IS(exprp, CMethodHard)) {
                costly = true;
            }
        });
        if (costly) return false;
        // Each wide variable or constant must be read by a constant select
        size_t selectedLeaves = 0;
        nodep->foreach([&](const AstSel* selp) {
            const AstNodeExpr* const fromp = selp->fromp();
            if (fromp->isWide() && (VN_IS(fromp, VarRef) || VN_IS(fromp, Const))
                && VN_IS(selp->lsbp(), Const)) {
                ++selectedLeaves;
            }
        });
        return selectedLeaves == wideLeaves;
    }
    // Slices of 'lhsp' and 'rhsp' as sliceOf, both nullptr if either cannot be taken
    static std::pair<AstNodeExpr*, AstNodeExpr*> slicesOf(AstNodeExpr* lhsp, int lhsLsb,
                                                          int lhsWidth, AstNodeExpr* rhsp,
                                                          int rhsLsb, int rhsWidth) {
        AstNodeExpr* const lhsSlicep = sliceOf(lhsp, lhsLsb, lhsWidth);
        if (!lhsSlicep) return {nullptr, nullptr};
        AstNodeExpr* const rhsSlicep = sliceOf(rhsp, rhsLsb, rhsWidth);
        if (!rhsSlicep) {
            VL_DO_DANGLING(lhsSlicep->deleteTree(), lhsSlicep);
            return {nullptr, nullptr};
        }
        return {lhsSlicep, rhsSlicep};
    }
    // Return bits ['lsb', 'lsb' + 'width') of 'nodep', selecting them from the operands of the
    // operations that V3Expand evaluates a word at a time, so no wide operation is evaluated in
    // two parts, or nullptr if it cannot be split so. A narrow operand across the boundary of
    // two parts is evaluated in both, so it must be cheap to repeat, and a condition is
    // evaluated in every part, so it must be cheap.
    static AstNodeExpr* sliceOf(AstNodeExpr* nodep, int lsb, int width) {
        FileLine* const flp = nodep->fileline();
        if (lsb == 0 && width == nodep->width()) return nodep->cloneTreePure(false);
        if (VN_IS(nodep, VarRef) || VN_IS(nodep, Const)
            || (!nodep->isWide() && isCheapToRepeat(nodep))) {
            return new AstSel{flp, nodep->cloneTreePure(false), lsb, width};
        }
        if (AstConcat* const catp = VN_CAST(nodep, Concat)) {
            const int lowWidth = catp->rhsp()->width();
            if (lsb + width <= lowWidth) return sliceOf(catp->rhsp(), lsb, width);
            if (lsb >= lowWidth) return sliceOf(catp->lhsp(), lsb - lowWidth, width);
            const auto pair = slicesOf(catp->lhsp(), 0, lsb + width - lowWidth, catp->rhsp(), lsb,
                                       lowWidth - lsb);
            return pair.first ? new AstConcat{flp, pair.first, pair.second} : nullptr;
        }
        if (!nodep->isWide()) return nullptr;
        if (AstSel* const selp = VN_CAST(nodep, Sel)) {
            const AstConst* const lsbp = VN_CAST(selp->lsbp(), Const);
            if (!lsbp || lsbp->num().isFourState() || !lsbp->num().fitsInUInt()) return nullptr;
            const uint64_t fromLsb = uint64_t{lsbp->toUInt()} + lsb;
            if (fromLsb + width > static_cast<uint64_t>(selp->fromp()->width())) return nullptr;
            return sliceOf(selp->fromp(), static_cast<int>(fromLsb), width);
        }
        if (AstCond* const condp = VN_CAST(nodep, Cond)) {
            if (!isCheap(condp->condp())) return nullptr;
            const auto pair = slicesOf(condp->thenp(), lsb, width, condp->elsep(), lsb, width);
            if (!pair.first) return nullptr;
            return new AstCond{flp, condp->condp()->cloneTreePure(false), pair.first, pair.second};
        }
        if (AstNot* const notp = VN_CAST(nodep, Not)) {
            AstNodeExpr* const lhsp = sliceOf(notp->lhsp(), lsb, width);
            return lhsp ? new AstNot{flp, lhsp} : nullptr;
        }
        if (VN_IS(nodep, And) || VN_IS(nodep, Or) || VN_IS(nodep, Xor)) {
            AstNodeBiop* const biopp = VN_AS(nodep, NodeBiop);
            const auto pair = slicesOf(biopp->lhsp(), lsb, width, biopp->rhsp(), lsb, width);
            if (!pair.first) return nullptr;
            if (VN_IS(nodep, And)) return new AstAnd{flp, pair.first, pair.second};
            if (VN_IS(nodep, Or)) return new AstOr{flp, pair.first, pair.second};
            return new AstXor{flp, pair.first, pair.second};
        }
        if (AstExtend* const extendp = VN_CAST(nodep, Extend)) {
            AstNodeExpr* const fromp = extendp->lhsp();
            const int fromWidth = fromp->width();
            if (lsb >= fromWidth) return new AstConst{flp, AstConst::WidthedValue{}, width, 0};
            if (lsb + width <= fromWidth) return sliceOf(fromp, lsb, width);
            AstNodeExpr* const lowp = sliceOf(fromp, lsb, fromWidth - lsb);
            if (!lowp) return nullptr;
            const int zeroWidth = lsb + width - fromWidth;
            return new AstConcat{flp, new AstConst{flp, AstConst::WidthedValue{}, zeroWidth, 0},
                                 lowp};
        }
        return nullptr;
    }
    // Whether wide 'nodep', of the operations sliceOf splits, may have bits above the top of its
    // value set in its top word as V3Expand evaluates it: a variable may, as an input can have
    // them set, and bitwise operations and conditions pass them on; V3Expand masks the top word
    // of a negation or a select, constants and narrow values have them clear
    static bool topMayBeDirty(const AstNodeExpr* nodep) {
        if (!nodep->isWide() || VN_IS(nodep, Const) || VN_IS(nodep, Sel) || VN_IS(nodep, Not)) {
            return false;
        }
        if (const AstConcat* const catp = VN_CAST(nodep, Concat)) {
            return topMayBeDirty(catp->lhsp());
        }
        if (const AstExtend* const extendp = VN_CAST(nodep, Extend)) {
            return extendp->lhsp()->widthWords() == nodep->widthWords()
                   && topMayBeDirty(extendp->lhsp());
        }
        if (const AstCond* const condp = VN_CAST(nodep, Cond)) {
            return topMayBeDirty(condp->thenp()) || topMayBeDirty(condp->elsep());
        }
        if (VN_IS(nodep, And) || VN_IS(nodep, Or) || VN_IS(nodep, Xor)) {
            const AstNodeBiop* const biopp = VN_AS(nodep, NodeBiop);
            return topMayBeDirty(biopp->lhsp()) || topMayBeDirty(biopp->rhsp());
        }
        return true;  // A variable, or an operation sliceOf does not split
    }
    // Add to 'rangesr' the bits, of a value of which 'nodep' gives the bits from 'lsb', of its
    // narrow operands that are not cheap to repeat, so no part boundary may cut them
    static void findCostlyRanges(const AstNodeExpr* nodep, int lsb,
                                 std::vector<std::pair<int, int>>& rangesr) {
        if (VN_IS(nodep, VarRef) || VN_IS(nodep, Const)) return;
        if (!nodep->isWide()) {
            if (!isCheapToRepeat(nodep)) rangesr.emplace_back(lsb, lsb + nodep->width());
        } else if (const AstConcat* const catp = VN_CAST(nodep, Concat)) {
            findCostlyRanges(catp->rhsp(), lsb, rangesr);
            findCostlyRanges(catp->lhsp(), lsb + catp->rhsp()->width(), rangesr);
        } else if (const AstSel* const selp = VN_CAST(nodep, Sel)) {
            const AstConst* const fromLsbp = VN_CAST(selp->lsbp(), Const);
            if (!fromLsbp || !fromLsbp->num().fitsInUInt()) return;  // sliceOf keeps it whole
            // The select moves bits from its position to 'lsb'; keep those it selects
            std::vector<std::pair<int, int>> fromRanges;
            findCostlyRanges(selp->fromp(), lsb - static_cast<int>(fromLsbp->toUInt()),
                             fromRanges);
            const int end = lsb + selp->width();
            for (const auto& range : fromRanges) {
                const int first = std::max(range.first, lsb);
                const int last = std::min(range.second, end);
                if (first < last) rangesr.emplace_back(first, last);
            }
        } else if (const AstCond* const condp = VN_CAST(nodep, Cond)) {
            findCostlyRanges(condp->thenp(), lsb, rangesr);
            findCostlyRanges(condp->elsep(), lsb, rangesr);
        } else if (const AstNodeBiop* const biopp = VN_CAST(nodep, NodeBiop)) {
            if (VN_IS(nodep, And) || VN_IS(nodep, Or) || VN_IS(nodep, Xor)) {
                findCostlyRanges(biopp->lhsp(), lsb, rangesr);
                findCostlyRanges(biopp->rhsp(), lsb, rangesr);
            }
        } else if (const AstNot* const notp = VN_CAST(nodep, Not)) {
            findCostlyRanges(notp->lhsp(), lsb, rangesr);
        } else if (const AstExtend* const extendp = VN_CAST(nodep, Extend)) {
            findCostlyRanges(extendp->lhsp(), lsb, rangesr);
        }
    }
    // Split wide assignment 'stmtp' over the limit into assignments of ranges of whole words,
    // whose values V3Expand evaluates a word at a time, so each is computed once. Return the
    // new assignments, or a range without statements if 'stmtp' is kept whole.
    StmtRange splitWide(AstNodeStmt* stmtp) {
        const StmtRange keep{nullptr, nullptr, 0};
        if (!VN_IS(stmtp, Assign) && !VN_IS(stmtp, AssignDly)) return keep;
        AstNodeAssign* const assignp = VN_AS(stmtp, NodeAssign);
        AstVarRef* const lhsp = VN_CAST(assignp->lhsp(), VarRef);
        AstNodeExpr* const rhsp = assignp->rhsp();
        if (!lhsp || !lhsp->isWide() || assignp->timingControlp() || !rhsp->isPure()) return keep;
        // A part must not read what an earlier part wrote
        const AstVarScope* const vscp = lhsp->varScopep();
        if (rhsp->exists([vscp](const AstVarRef* refp) { return refp->varScopep() == vscp; })) {
            return keep;
        }
        // Twice as many parts as needed, so uneven parts can be grouped within the limit, but
        // at least a word each, so a part with a word of a large value can be over the limit
        const int words = lhsp->widthWords();
        const int parts = static_cast<int>(
            std::min<size_t>(words, 2 * ((m_info(stmtp).m_size + m_limit - 1) / m_limit)));
        const int partWords = (words + parts - 1) / parts;
        // Words starting within a narrow operand not cheap to repeat cannot start a part
        std::vector<std::pair<int, int>> costlyRanges;
        findCostlyRanges(rhsp, 0, costlyRanges);
        std::vector<bool> inside(words, false);
        for (const auto& range : costlyRanges) {
            for (int word = range.first / VL_EDATASIZE + 1;
                 word * VL_EDATASIZE < range.second && word < words; ++word) {
                inside[word] = true;
            }
        }
        // V3Expand assigns the top word of a value whole. A part with the top word assigns it so
        // too: a variable is copied with the bits above the top of its value, which an input can
        // have set; the bits a clean value has there are zero. A value that may have them set
        // otherwise, as bitwise operations of variables do, is kept whole.
        const bool partialTop = lhsp->width() % VL_EDATASIZE;
        if (partialTop && !VN_IS(rhsp, VarRef) && topMayBeDirty(rhsp)) return keep;
        const int endWord = partialTop ? words - 1 : words;  // End of the parts by ranges
        AstNode* newsp = nullptr;
        if (partialTop) {
            FileLine* const flp = lhsp->fileline();
            const int topLsb = (words - 1) * VL_EDATASIZE;
            AstNodeExpr* valuep;
            if (AstVarRef* const fromp = VN_CAST(rhsp, VarRef)) {
                valuep = new AstWordSel{flp, fromp->cloneTree(false),
                                        new AstConst{flp, static_cast<uint32_t>(words - 1)}};
            } else {
                valuep = sliceOf(rhsp, topLsb, lhsp->width() - topLsb);
                if (!valuep) return keep;
                valuep = new AstExtend{flp, valuep, VL_EDATASIZE};
            }
            newsp = assignp->cloneType(
                new AstWordSel{flp, lhsp->cloneTree(false),
                               new AstConst{flp, static_cast<uint32_t>(words - 1)}},
                valuep);
        }
        for (int word = 0; word < endWord;) {
            int nextWord = std::min(endWord, word + partWords);
            if (nextWord < endWord && inside[nextWord]) ++m_statMovedBounds;
            while (nextWord < endWord && inside[nextWord]) ++nextWord;
            const int lsb = word * VL_EDATASIZE;
            const int width = std::min(nextWord * VL_EDATASIZE, lhsp->width()) - lsb;
            word = nextWord;
            AstNodeExpr* const valuep = sliceOf(rhsp, lsb, width);
            if (!valuep) {
                if (newsp) VL_DO_DANGLING(newsp->deleteTree(), newsp);
                return keep;
            }
            AstSel* const targetp
                = new AstSel{lhsp->fileline(), lhsp->cloneTree(false), lsb, width};
            newsp = AstNode::addNext(newsp, assignp->cloneType(targetp, valuep));
        }
        ++m_statSplits;
        const int depth = m_info(stmtp).m_depth;
        const size_t size = m_info(stmtp).m_size;
        StmtRange run{VN_AS(newsp, NodeStmt), nullptr, 0};
        for (AstNode* nodep = newsp; nodep; nodep = nodep->nextp()) {
            AstNodeAssign* const newp = VN_AS(nodep, NodeAssign);
            StmtInfo& info = m_info(newp);
            // V3Expand emits the words of a part only, so its share of the size is that of its
            // words; the estimate of the part itself counts its wide operands whole
            const size_t width = static_cast<size_t>(newp->lhsp()->width());
            info.m_size = std::max<size_t>(1, size * width / lhsp->width());
            info.m_depth = depth;
            info.m_movable = true;
            run.m_lastp = newp;
            run.m_size += info.m_size;
        }
        stmtp->replaceWith(newsp);
        VL_DO_DANGLING(pushDeletep(stmtp), stmtp);
        return run;
    }
    // Move 'stmtp', over the limit with nothing inside it moved, alone or in parts if it is a
    // wide assignment that can be split
    void moveLarge(AstNodeStmt* stmtp) {
        const StmtRange run = splitWide(stmtp);
        if (run.m_firstp) {
            groupRun(run);
        } else {
            m_groups.push_back(StmtRange{stmtp, stmtp, m_info(stmtp).m_size});
        }
    }
    // Choose statements under 'stmtp' to move until it is within the limit, return its size left
    size_t reduce(AstNodeStmt* stmtp) {
        size_t size = m_info(stmtp).m_size;
        std::vector<AstNode*> listps;  // Statement lists directly under 'stmtp'
        if (AstIf* const ifp = VN_CAST(stmtp, If)) {
            listps = {ifp->thensp(), ifp->elsesp()};
        } else if (AstLoop* const loopp = VN_CAST(stmtp, Loop)) {
            listps = {loopp->stmtsp()};
        } else if (AstJumpBlock* const blockp = VN_CAST(stmtp, JumpBlock)) {
            listps = {blockp->stmtsp()};
        }
        std::vector<StmtRange> runs;  // Runs of movable statements no larger than the limit
        std::vector<AstNodeStmt*> largeps;  // Statements larger than the limit
        for (AstNode* const listp : listps) {
            StmtRange run{nullptr, nullptr, 0};
            for (AstNode* const nodep : VNList<AstNode>{listp}) {
                AstNodeStmt* const subp = VN_CAST(nodep, NodeStmt);  // Else a declaration
                if (subp && m_info(subp).m_size > m_limit) largeps.push_back(subp);
                if (subp && m_info(subp).m_movable && m_info(subp).m_size <= m_limit) {
                    if (!run.m_firstp) run.m_firstp = subp;
                    run.m_lastp = subp;
                    run.m_size += m_info(subp).m_size;
                    continue;
                }
                if (run.m_firstp) runs.push_back(run);
                run = StmtRange{nullptr, nullptr, 0};
            }
            if (run.m_firstp) runs.push_back(run);
        }
        // Each of these alone is over the limit, so all need reducing
        for (AstNodeStmt* const largep : largeps) {
            const size_t groupsBefore = m_groups.size();
            const size_t left = reduce(largep);
            if (m_groups.size() == groupsBefore && m_info(largep).m_movable) {
                // Nothing inside it to move, so it moves, leaving its parent small
                moveLarge(largep);
                size -= left;
            } else {
                size -= m_info(largep).m_size - left;
            }
        }
        std::stable_sort(runs.begin(), runs.end(), [](const StmtRange& a, const StmtRange& b) {
            return a.m_size > b.m_size;
        });
        for (const StmtRange& run : runs) {
            if (size <= m_limit) break;
            groupRun(run);
            size -= run.m_size;
        }
        return size;
    }

    // METHODS - rewrite
    // Move statements 'firstp' to 'lastp' into a new function, and call it in their place
    void outline(AstNodeStmt* firstp, AstNodeStmt* lastp) {
        FileLine* const flp = firstp->fileline();
        VNRelinker relinker;
        firstp->unlinkFrBackWithNext(&relinker);
        AstNode* const restp = lastp->nextp();
        if (restp) restp->unlinkFrBackWithNext();

        AstScope* const scopep = m_funcp->scopep();
        const std::string name = m_funcp->name() + "__outline" + cvtToStr(m_funcNum++);
        AstCFunc* const subFuncp = new AstCFunc{flp, name, scopep};
        scopep->addBlocksp(subFuncp);
        subFuncp->isStatic(m_funcp->isStatic());
        subFuncp->isLoose(m_funcp->isLoose());
        subFuncp->slow(m_funcp->slow());
        if (m_funcp->needsVlProcess()) subFuncp->setNeedsVlProcess();
        subFuncp->addStmtsp(firstp);
        AstCCall* const callp = new AstCCall{flp, subFuncp};
        callp->dtypeSetVoid();
        if (VN_IS(scopep->modp(), Class)) {
            subFuncp->argTypes(EmitCUtil::symClassVar());
            callp->argTypes("vlSymsp");
        }

        const OutlineArgsVisitor argsVisitor{subFuncp, callp, m_passVscps};
        AstNode* stmtp;
        if (argsVisitor.hasAwait()) {
            subFuncp->rtnType("VlCoroutine");
            stmtp = new AstCAwait{flp, callp};
        } else {
            stmtp = callp->makeStmt();
        }
        if (restp) stmtp->addNext(restp);
        relinker.relink(stmtp);
        ++m_statFuncs;
    }

    // Find the only function referencing each module variable, once, when first needed
    void findSoleFuncps() {
        if (m_soleFuncpsFound) return;
        m_soleFuncpsFound = true;
        OutlineSoleFuncVisitor{m_netlistp, m_soleFuncps};
    }
    // Find the module variables that V3Localize may make local to 'funcp', as it does with the
    // variables used by one function only that it reads only after assigning them whole in a
    // statement at its top level, or never, and with block temporaries
    void findPassVscps(AstCFunc* funcp) {
        findSoleFuncps();
        std::unordered_set<const AstVarScope*> assignedps;  // Assigned whole so far
        std::unordered_set<const AstVarScope*> readFirstps;  // Read before assigned whole
        std::unordered_set<const AstVarScope*> readps;  // Read at all
        std::vector<const AstVarScope*> refVscps;  // Referenced, in order of first reference
        std::unordered_set<const AstVarScope*> refps;  // Referenced
        const auto refsOf = [&](const AstNode* nodep) {
            nodep->foreach([&](const AstVarRef* refp) {
                const AstVarScope* const vscp = refp->varScopep();
                if (refps.emplace(vscp).second) refVscps.push_back(vscp);
                if (!refp->access().isReadOrRW()) return;
                readps.emplace(vscp);
                if (!assignedps.count(vscp)) readFirstps.emplace(vscp);
            });
        };
        for (AstNode* const stmtp : funcp->stmtspList()) {
            const AstNodeAssign* const assignp = VN_CAST(stmtp, NodeAssign);
            const AstVarRef* const lhsp = assignp ? VN_CAST(assignp->lhsp(), VarRef) : nullptr;
            if (!lhsp) {
                refsOf(stmtp);
                continue;
            }
            refsOf(assignp->rhsp());
            assignedps.emplace(lhsp->varScopep());
            refsOf(lhsp);
        }
        for (const AstVarScope* const vscp : refVscps) {
            const auto it = m_soleFuncps.find(vscp);
            if (it == m_soleFuncps.end() || it->second != funcp) continue;
            if (!V3Localize::isCandidate(vscp)) continue;
            if (readFirstps.count(vscp) && vscp->varp()->varType() != VVarType::BLOCKTEMP) {
                continue;
            }
            m_passVscps.emplace(vscp, !readps.count(vscp));
        }
    }
    void outlineFunc(AstCFunc* funcp) {
        m_funcp = funcp;
        m_funcNum = 0;
        m_count = 0;
        m_targetDepth = std::numeric_limits<int>::max();
        iterateAndNextNull(funcp->stmtsp());
        std::vector<AstNodeStmt*> largeps;  // Top level statements larger than the limit
        for (AstNode* const nodep : funcp->stmtspList()) {
            AstNodeStmt* const stmtp = VN_CAST(nodep, NodeStmt);  // Else a declaration
            if (stmtp && m_info(stmtp).m_size > m_limit) largeps.push_back(stmtp);
        }
        for (AstNodeStmt* const largep : largeps) {
            const size_t groupsBefore = m_groups.size();
            reduce(largep);
            // One with nothing inside it to move is split if a wide assignment, else stays
            if (m_groups.size() == groupsBefore && m_info(largep).m_movable) {
                const StmtRange run = splitWide(largep);
                if (run.m_firstp) groupRun(run);
            }
        }
        if (m_groups.empty()) return;
        // Module variables that V3Localize may make local to an ordinary function are passed to
        // its parts, keeping them local. Not for coroutines, whose locals must outlive a part.
        m_passVscps.clear();
        if (!funcp->isCoroutine()) findPassVscps(funcp);
        for (const StmtRange& group : m_groups) outline(group.m_firstp, group.m_lastp);
        m_groups.clear();
    }

    // VISITORS - analysis
    void visit(AstNodeStmt* nodep) override { analyze(nodep, std::numeric_limits<int>::max()); }
    void visit(AstJumpGo* nodep) override { analyze(nodep, m_info(nodep->blockp()).m_depth); }
    void visit(AstLoopTest* nodep) override { analyze(nodep, m_info(nodep->loopp()).m_depth); }
    // Returns from the coroutine, so no statement containing it can move
    void visit(AstFinishFork* nodep) override { analyze(nodep, 0); }
    // Returns from the function, so no statement containing it can move
    void visit(AstCReturn* nodep) override { analyze(nodep, 0); }
    // User C++ text stays in the function, as it may use C++ locals declared by other user
    // text, or return
    void visit(AstCStmtUser* nodep) override { analyze(nodep, 0); }
    void visit(AstCExprUser* nodep) override {
        m_targetDepth = 0;
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override {
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        iterateChildren(nodep);
    }

    // CONSTRUCTORS
    explicit OutlineVisitor(AstNetlist* netlistp)
        : m_netlistp{netlistp} {
        // A limit of zero disables splitting
        if (!m_limit) return;
        // Gather the functions first, as outlining adds functions
        std::vector<AstCFunc*> funcps;
        for (AstNodeModule* const modp : netlistp->modulespList()) {
            // Functions of a class made from tasks without arguments include constructors,
            // whose super.new call must stay in place
            const bool isClass = VN_IS(modp, Class);
            for (AstNode* const nodep : modp->stmtspList()) {
                AstScope* scopep = VN_CAST(nodep, Scope);
                if (AstTopScope* const topp = VN_CAST(nodep, TopScope)) scopep = topp->scopep();
                if (!scopep) continue;
                for (AstNode* const blockp : scopep->blockspList()) {
                    AstCFunc* const funcp = VN_AS(blockp, CFunc);
                    // A function taking C++ arguments, such as a DPI export implementation
                    // taking the model, would not pass them to its parts
                    if (funcp->isCoroutine()
                        || (!isClass && !funcp->argsp() && !funcp->varsp()
                            && funcp->argTypes().empty())) {
                        funcps.push_back(funcp);
                    }
                }
            }
        }
        for (AstCFunc* const funcp : funcps) outlineFunc(funcp);
    }
    ~OutlineVisitor() override {
        V3Stats::addStat("Outline, functions created", m_statFuncs);
        V3Stats::addStat("Outline, wide assignments split", m_statSplits);
        V3Stats::addStat("Outline, wide assignment part boundaries moved", m_statMovedBounds);
    }

public:
    static void apply(AstNetlist* netlistp) { OutlineVisitor{netlistp}; }
};

//######################################################################
// Outline class functions

void V3Outline::outlineAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    OutlineVisitor::apply(nodep);
    V3Global::dumpCheckGlobalTree("outline", 0, dumpTreeEitherLevel() >= 3);
}
