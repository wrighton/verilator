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
// large as the whole process. A task or function that is not inlined is emitted as one C++
// function, which V3Sched does not split at all, and C++ compilers also need super-linear time
// for very large functions, such as one made for a process whose logic is all under one 'if'
// on a reset. This pass moves parts of such functions into sub-functions, to bring each down to
// --output-split-cfuncs, as far as the statements that cannot move allow.
//
// For each coroutine, each function made from a task or function, and each function of a
// module without arguments or local variables, as the scheduler makes for ordered logic, other
// than one that makes its own process for its calls, or an MTask function, which V3ExecGraph
// needs whole:
//  1. Analysis: one traversal records the estimated emitted size of each statement (see
//     V3Sched::util::emittedSizeEstimate), and whether it can move into another function: it
//     cannot if it jumps out of itself, returns, tests the condition of a loop around it,
//     contains user C++ text, which may use C++ locals or return, uses an argument of a public
//     function, or must stay in the function itself (VL_KEEP_THIS, the super.new call of a
//     constructor).
//  2. Decision: if the function is larger than the limit, take its statement list. Its
//     statements larger than the limit stay in place, and the same is done first in each of
//     them, with the statement lists directly under it; one of them that is movable, with
//     nothing inside it to move, such as one large assignment, moves alone instead, split
//     first into assignments of ranges of whole words if it is a wide assignment whose value
//     is made by operations V3Expand evaluates a word at a time, so no wide operation is
//     evaluated in two parts, and that does not read the variable assigned (see sliceOf). The
//     consecutive movable statements in between form runs. Starting with the largest run, runs
//     are cut into groups no larger than the limit to move, until the function or statement is
//     within the limit. A statement moves only with nothing inside it moved, so groups never
//     nest, and new functions need no further splitting.
//  3. Locals: a local variable of the function that only a group uses, and that the group
//     never reads before assigning it whole, is declared in the new function instead of being
//     passed to it: its value from before a call of the new function is never read. A local
//     passed to a coroutine stays, as the coroutine may keep it after returning, as the
//     processes of a fork..join do until the join.
//  4. Rewrite: each group moves into a new function, an outline part, called in its place, with
//     co_await if it suspends. Other local variables of the function that the group references
//     are passed by reference, and so is the process of the function, leaving the current
//     process unchanged. This runs before V3Localize, while most variables are module
//     variables, so only the arguments and locals of tasks that are not inlined, including the
//     variables of calls inlined into them, need passing. Statements using the arguments of a
//     public function cannot move, so a public function using its arguments throughout is
//     split only between them.
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
// Pass to a new function the local variables of the function that its statements reference

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
            const bool constRef = varp->isConstRef();
            // Combining does not compare argument directions, and an argument passed by const
            // reference cannot be passed on by reference
            if (constRef) m_funcp->dontCombine(true);
            // A module variable only read is passed by value, which the new function can keep
            // in registers, as it cannot change during the call
            const VDirection dir = passModuleVar && !written ? VDirection::INPUT
                                   : constRef                ? VDirection::CONSTREF
                                                             : VDirection::REF;
            // Variables of other scopes may share the name, so are named by their scope
            const std::string name
                = vscp->scopep() == m_funcp->scopep()
                      ? varp->name()
                      : vscp->scopep()->nameDotless() + "__DOT__" + varp->name();
            *argVscpp = V3Sched::util::newArgument(m_funcp, varp->dtypep(), name, dir);
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
    // No module variables to pass
    static const std::unordered_map<const AstVarScope*, bool>& noPassVscps() {
        static const std::unordered_map<const AstVarScope*, bool> s_noPassVscps;
        return s_noPassVscps;
    }
    OutlineArgsVisitor(AstCFunc* funcp, AstCCall* callp,
                       const std::unordered_map<const AstVarScope*, bool>& passVscps
                       = noPassVscps())
        : m_funcp{funcp}
        , m_callp{callp}
        , m_passVscps{passVscps} {
        funcp->stmtsp()->foreachAndNext([this](const AstVarRef* refp) {
            if (refp->access().isWriteOrRW()) m_writtenps.emplace(refp->varScopep());
        });
        iterateAndNextNull(funcp->varsp());
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
// Outline parts of large functions

class OutlineVisitor final : public VNVisitor {
    // NODE STATE
    //  AstNodeStmt::user1p()  -> StmtInfo. Analysis of statement in the current function
    //  AstVar::user2p()       -> VarInfo. Analysis of variable in the current function
    const VNUser1InUse m_user1InUse;
    const VNUser2InUse m_user2InUse;

    // TYPES
    struct StmtInfo final {
        size_t m_size = 0;  // Estimated emitted size of the statement
        int m_depth = 0;  // Nesting depth of the statement in the function
        bool m_movable = false;  // Can move into another function
    };
    struct VarInfo final {
        bool m_local = false;  // Declared in the variables of the current function
        bool m_passed = false;  // Passed to a coroutine, which may keep it after returning
        size_t m_refs = 0;  // References in the current function
        // Analysis of the group being considered
        size_t m_groupRefs = 0;  // References in the group
        bool m_groupReadFirst = false;  // The group may read it before assigning it whole
    };
    struct StmtRange final {
        AstNodeStmt* m_firstp;  // First statement
        AstNodeStmt* m_lastp;  // Last statement
        size_t m_size;  // Estimated emitted size of the statements
    };

    // STATE
    VNUser1Allocator<AstNodeStmt, StmtInfo> m_info;
    VNUser2Allocator<AstVar, VarInfo> m_vars;
    const size_t m_limit = static_cast<size_t>(v3Global.opt.outputSplitCFuncs());
    AstCFunc* m_funcp = nullptr;  // Current function
    size_t m_funcNum = 0;  // Number of functions outlined from the current function
    std::string m_nameSuffix;  // Suffix of the names of functions outlined from the current one
    std::vector<StmtRange> m_groups;  // Statements to move, each group into a new function
    size_t m_count = 0;  // Estimated emitted size of the nodes analyzed
    int m_depth = 0;  // Nesting depth of the statement being analyzed
    int m_targetDepth = 0;  // Least depth of the jump and loop test targets in the statement
    // Variables assigned whole on every path so far in the group being considered, and the
    // order they were added in, to undo additions in branches
    std::unordered_set<const AstVar*> m_assignedps;
    std::vector<const AstVar*> m_assignedOrder;
    std::vector<AstVar*> m_groupVarps;  // Variables of the group, in order of first reference
    std::vector<std::vector<AstVar*>> m_groupLocals;  // Locals of each group in m_groups
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
    VDouble0 m_statLocals;  // Number of variables declared in functions created
    VDouble0 m_statArgs;  // Number of variables passed to functions created

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
    // Choose statements under 'stmtp' to move until it is within the limit, return its size left
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
    size_t reduce(AstNodeStmt* stmtp) {
        std::vector<AstNode*> listps;  // Statement lists directly under 'stmtp'
        if (AstIf* const ifp = VN_CAST(stmtp, If)) {
            listps = {ifp->thensp(), ifp->elsesp()};
        } else if (AstLoop* const loopp = VN_CAST(stmtp, Loop)) {
            listps = {loopp->stmtsp()};
        } else if (AstJumpBlock* const blockp = VN_CAST(stmtp, JumpBlock)) {
            listps = {blockp->stmtsp()};
        } else if (AstCLocalScope* const scopep = VN_CAST(stmtp, CLocalScope)) {
            listps = {scopep->stmtsp()};
        }
        return reduceLists(m_info(stmtp).m_size, listps);
    }
    // Choose statements in 'listps' to move until 'size' is within the limit, return size left
    size_t reduceLists(size_t size, const std::vector<AstNode*>& listps) {
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

    // METHODS - locals
    // Count a reference in the group being considered
    VarInfo& groupRef(const AstVarRef* refp) {
        VarInfo& info = m_vars(refp->varp());
        if (!info.m_groupRefs++) m_groupVarps.push_back(refp->varp());
        return info;
    }
    // Count the references under 'nodep', which may read their variables
    void groupReads(AstNode* nodep) {
        nodep->foreach([this](const AstVarRef* refp) {
            VarInfo& info = groupRef(refp);
            if (!m_assignedps.count(refp->varp())) info.m_groupReadFirst = true;
        });
    }
    // Undo the additions to m_assignedps since 'mark', return them
    std::vector<const AstVar*> undoAssigned(const size_t mark) {
        std::vector<const AstVar*> varps{m_assignedOrder.begin() + mark, m_assignedOrder.end()};
        m_assignedOrder.resize(mark);
        for (const AstVar* const varp : varps) m_assignedps.erase(varp);
        return varps;
    }
    // Analyze 'stmtp', which assigns 'lhsp' from 'rhsp'
    void groupAssign(AstNode* stmtp, AstNode* lhsp, AstNode* rhsp) {
        const AstVarRef* const refp = VN_CAST(lhsp, VarRef);
        if (!refp) {  // Not a whole variable
            groupReads(stmtp);
            return;
        }
        // The right hand side is evaluated before the variable is assigned
        groupReads(rhsp);
        groupRef(refp);
        if (m_assignedps.emplace(refp->varp()).second) m_assignedOrder.push_back(refp->varp());
    }
    void groupStmts(AstNode* stmtsp) {
        for (AstNode* const stmtp : VNList<AstNode>{stmtsp}) groupStmt(stmtp);
    }
    // Analyze 'stmtp' of the group being considered, following its paths for the variables it
    // assigns
    void groupStmt(AstNode* stmtp) {
        if (AstCLocalScope* const scopep = VN_CAST(stmtp, CLocalScope)) {
            groupStmts(scopep->stmtsp());
        } else if (AstIf* const ifp = VN_CAST(stmtp, If)) {
            groupReads(ifp->condp());
            const size_t mark = m_assignedOrder.size();
            groupStmts(ifp->thensp());
            const std::vector<const AstVar*> thenps = undoAssigned(mark);
            groupStmts(ifp->elsesp());
            const std::vector<const AstVar*> elseps = undoAssigned(mark);
            // Assigned after the 'if' if assigned in both branches. The reset where such a
            // variable is declared is removed as unused.
            const std::unordered_set<const AstVar*> elseSet{elseps.begin(), elseps.end()};
            for (const AstVar* const varp : thenps) {
                if (!elseSet.count(varp)) continue;
                m_assignedps.emplace(varp);
                m_assignedOrder.push_back(varp);
            }
        } else if (AstLoop* const loopp = VN_CAST(stmtp, Loop)) {
            // Assignments in it may be skipped by the loop test
            const size_t mark = m_assignedOrder.size();
            groupStmts(loopp->stmtsp());
            undoAssigned(mark);
        } else if (AstJumpBlock* const blockp = VN_CAST(stmtp, JumpBlock)) {
            // Assignments in it may be skipped by a jump
            const size_t mark = m_assignedOrder.size();
            groupStmts(blockp->stmtsp());
            undoAssigned(mark);
        } else if (AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
            groupAssign(assignp, assignp->lhsp(), assignp->rhsp());
        } else if (AstSFormat* const sformatp = VN_CAST(stmtp, SFormat)) {
            groupAssign(sformatp, sformatp->lhsp(), sformatp->fmtp());
        } else {
            groupReads(stmtp);
        }
    }
    // Choose the locals that only a group uses, and that it does not read before assigning.
    // This keeps out variables the group may read with a value from before, such as ones
    // declared on a path the group does not always take, temporaries passed to calls, and
    // other variables made by Verilator that are not assigned where they are declared.
    void chooseLocals() {
        m_groupLocals.assign(m_groups.size(), {});
        for (size_t i = 0; i < m_groups.size(); ++i) {
            const StmtRange& group = m_groups[i];
            for (AstNode* nodep = group.m_firstp; nodep != group.m_lastp->nextp();
                 nodep = nodep->nextp()) {
                groupStmt(nodep);
            }
            for (AstVar* const varp : m_groupVarps) {
                VarInfo& info = m_vars(varp);
                if (info.m_local && !info.m_passed && info.m_refs == info.m_groupRefs
                    && !info.m_groupReadFirst) {
                    m_groupLocals[i].push_back(varp);
                }
                info.m_groupRefs = 0;
                info.m_groupReadFirst = false;
            }
            m_groupVarps.clear();
            m_assignedps.clear();
            m_assignedOrder.clear();
        }
    }

    // METHODS - rewrite
    // Move statements 'firstp' to 'lastp' into a new function, and call it in their place,
    // declaring 'localps' in it
    void outline(AstNodeStmt* firstp, AstNodeStmt* lastp, const std::vector<AstVar*>& localps) {
        FileLine* const flp = firstp->fileline();
        AstScope* const scopep = m_funcp->scopep();
        const std::string name
            = m_funcp->name() + "__outline" + cvtToStr(m_funcNum++) + m_nameSuffix;
        AstCFunc* const subFuncp = new AstCFunc{flp, name, scopep};
        scopep->addBlocksp(subFuncp);
        subFuncp->isStatic(m_funcp->isStatic());
        subFuncp->isLoose(m_funcp->isLoose());
        subFuncp->slow(m_funcp->slow());
        subFuncp->isOutlinePart(true);
        if (m_funcp->needsVlProcess()) subFuncp->setNeedsVlProcess();
        // Move the statements one by one, as unlinking with the rest of a list takes time linear
        // in the length of the rest
        VNRelinker relinker;
        AstNode* const endp = lastp->nextp();
        for (AstNode *nodep = firstp, *nextp; nodep != endp; nodep = nextp) {
            nextp = nodep->nextp();
            nodep->unlinkFrBack(nodep == firstp ? &relinker : nullptr);
            subFuncp->addStmtsp(VN_AS(nodep, NodeStmt));
        }
        AstCCall* const callp = new AstCCall{flp, subFuncp};
        callp->dtypeSetVoid();
        // Not all class methods take vlSymsp, and DPI exports, which are static, take it
        if (m_funcp->argTypes() == EmitCUtil::symClassVar()) {
            subFuncp->argTypes(m_funcp->argTypes());
            callp->argTypes("vlSymsp");
        }

        for (AstVar* const varp : localps) {
            subFuncp->addVarsp(varp->unlinkFrBack());
            ++m_statLocals;
        }
        const OutlineArgsVisitor argsVisitor{subFuncp, callp, m_passVscps};
        for (AstNode* argp = callp->argsp(); argp; argp = argp->nextp()) ++m_statArgs;
        AstNode* stmtp;
        if (argsVisitor.hasAwait()) {
            subFuncp->rtnType("VlCoroutine");
            stmtp = new AstCAwait{flp, callp};
        } else {
            stmtp = callp->makeStmt();
        }
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
            // V3Localize keeps strings of hot functions in the module
            if (!funcp->slow() && vscp->dtypep()->skipRefp()->isString()) continue;
            if (readFirstps.count(vscp) && vscp->varp()->varType() != VVarType::BLOCKTEMP) {
                continue;
            }
            m_passVscps.emplace(vscp, !readps.count(vscp));
        }
    }
    void outlineFunc(AstCFunc* funcp) {
        m_funcp = funcp;
        m_funcNum = 0;
        // V3Descope makes the names of public functions unique, but not of these
        m_nameSuffix = funcp->funcPublic() ? "_" + funcp->scopep()->nameDotless() : "";
        m_count = 0;
        m_targetDepth = std::numeric_limits<int>::max();
        for (AstVar* const varp : funcp->varspList()) m_vars(varp) = VarInfo{true};
        iterateAndNextNull(funcp->stmtsp());
        reduceLists(m_count, {funcp->stmtsp()});
        chooseLocals();
        // Module variables that V3Localize may make local to an ordinary function are passed to
        // its parts, keeping them local. Not for coroutines, whose locals must outlive a part.
        m_passVscps.clear();
        if (!m_groups.empty() && !funcp->isCoroutine() && !funcp->fromFTask()) {
            findPassVscps(funcp);
        }
        for (size_t i = 0; i < m_groups.size(); ++i) {
            outline(m_groups[i].m_firstp, m_groups[i].m_lastp, m_groupLocals[i]);
        }
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
    // VL_KEEP_THIS stays in the function
    void visit(AstCStmt* nodep) override {
        // It keeps 'this' alive until the coroutine ends
        analyze(nodep,
                nodep->stmtType() == VCStmtType::KEEP_THIS ? 0 : std::numeric_limits<int>::max());
    }
    // The super.new call of a constructor stays in the function
    void visit(AstStmtExpr* nodep) override {
        // EmitC looks for it in the statements of the constructor, to initialize the base class
        analyze(nodep, VN_IS(nodep->exprp(), CNew) ? 0 : std::numeric_limits<int>::max());
    }
    // User C++ text stays in the function
    void visit(AstCStmtUser* nodep) override {
        // It may use C++ locals declared by other user text, or return
        analyze(nodep, 0);
    }
    // User C++ text stays in the function
    void visit(AstCExprUser* nodep) override {
        // It may use C++ locals declared by other user text
        m_targetDepth = 0;
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        iterateChildren(nodep);
    }
    void visit(AstNodeCCall* nodep) override {
        // A coroutine may keep a variable it is passed by reference after it returns, while
        // suspended, as the processes of a fork..join do until the join
        if (nodep->funcp()->isCoroutine()) {
            for (AstNode* argp = nodep->argsp(); argp; argp = argp->nextp()) {
                if (const AstVarRef* const refp = VN_CAST(argp, VarRef)) {
                    m_vars(refp->varp()).m_passed = true;
                }
            }
        }
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        iterateChildren(nodep);
    }
    // The C++ types of the arguments of a public function differ from those of their
    // variables, so no statement using them can move
    void visit(AstVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        if (m_funcp->funcPublic() && varp->isIO() && !varp->isFuncReturn()) m_targetDepth = 0;
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        ++m_vars(varp).m_refs;
    }
    void visit(AstNode* nodep) override {
        m_count += V3Sched::util::emittedNodeSizeEstimate(nodep);
        iterateChildren(nodep);
    }

    // CONSTRUCTORS
    explicit OutlineVisitor(AstNetlist* netlistp)
        : m_netlistp{netlistp} {
        // An MTask function stays whole: its statements are the tests of the triggers of the
        // logic it calls, from which V3ExecGraph gives the run-time the triggers it tests, to
        // skip it when none is set
        std::unordered_set<const AstCFunc*> mtaskFuncps;
        netlistp->foreach([&](AstExecGraph* graphp) {
            for (const AstCCall* const callp : graphp->callspList()) {
                mtaskFuncps.emplace(callp->funcp());
            }
        });
        // Gather the functions first, as outlining adds functions
        std::vector<AstCFunc*> funcps;
        for (AstNodeModule* const modp : netlistp->modulespList()) {
            const bool isClass = VN_IS(modp, Class);
            for (AstNode* const nodep : modp->stmtspList()) {
                AstScope* scopep = VN_CAST(nodep, Scope);
                if (AstTopScope* const topp = VN_CAST(nodep, TopScope)) scopep = topp->scopep();
                if (!scopep) continue;
                for (AstNode* const blockp : scopep->blockspList()) {
                    AstCFunc* const funcp = VN_AS(blockp, CFunc);
                    // Functions made for ordered logic have no arguments or local variables. Of
                    // C++ arguments, the parts are given only the model. A DPI export
                    // dispatcher declares C++ locals in text its other statements use.
                    const bool ordinary = !isClass && !funcp->argsp() && !funcp->varsp()
                                          && (funcp->argTypes().empty()
                                              || funcp->argTypes() == EmitCUtil::symClassVar())
                                          && !funcp->dpiExportDispatcher();
                    if (!funcp->isCoroutine() && !funcp->fromFTask() && !ordinary) continue;
                    if (mtaskFuncps.count(funcp)) continue;
                    // A function without a process argument that makes its own process for its
                    // calls stays whole, as code emitted for its parts would not see that process
                    if (!funcp->needsVlProcess() && funcp->exists([](const AstNodeCCall* callp) {
                            return callp->passesVlProcess();
                        })) {
                        continue;
                    }
                    funcps.push_back(funcp);
                }
            }
        }
        for (AstCFunc* const funcp : funcps) outlineFunc(funcp);
    }
    ~OutlineVisitor() override {
        V3Stats::addStat("Outline, functions created", m_statFuncs);
        V3Stats::addStat("Outline, wide assignments split", m_statSplits);
        V3Stats::addStat("Outline, wide assignment part boundaries moved", m_statMovedBounds);
        V3Stats::addStat("Outline, variables declared in functions created", m_statLocals);
        V3Stats::addStat("Outline, variables passed to functions created", m_statArgs);
    }

public:
    static void apply(AstNetlist* netlistp) { OutlineVisitor{netlistp}; }
};

//######################################################################
// Outline class functions

bool V3Outline::passLocals(AstCFunc* funcp, AstCCall* callp) {
    return OutlineArgsVisitor{funcp, callp}.hasAwait();
}

void V3Outline::outlineAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    OutlineVisitor::apply(nodep);
    V3Global::dumpCheckGlobalTree("outline", 0, dumpTreeEitherLevel() >= 3);
}
