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
// for very large functions. This pass moves parts of such functions into sub-functions, to
// bring each down to --output-split-cfuncs, as far as the statements that cannot move allow.
//
// For each coroutine, and each function made from a task or function, other than one that makes
// its own process for its calls:
//  1. Analysis: one traversal records the size of each statement in nodes, and whether it can
//     move into another function: it cannot if it jumps out of itself, returns, tests the
//     condition of a loop around it, contains user C++ text, which may use C++ locals or
//     return, uses an argument of a public function, or must stay in the function itself
//     (VL_KEEP_THIS, the super.new call of a constructor).
//  2. Decision: if the function is larger than the limit, take its statement list. Its
//     statements larger than the limit stay in place, and the same is done first in each of
//     them, with the statement lists directly under it. The consecutive movable statements in
//     between form runs. Starting with the largest run, runs are cut into groups no larger
//     than the limit to move, until the function or statement is within the limit. Moved
//     statements are within the limit, so groups never nest, and new functions need no
//     further splitting.
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
    // Local variable -> argument passing it, nullptr if declared in the new function
    std::unordered_map<const AstVar*, AstVarScope*> m_argVscps;
    std::unordered_set<const AstVar*> m_writtenps;  // Variables the new function writes
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
        if (!varp->isFuncLocal()) return;
        const auto pair = m_argVscps.emplace(varp, nullptr);
        if (pair.second) {
            const bool constRef = varp->isConstRef();
            // Combining does not compare argument directions, and an argument passed by const
            // reference cannot be passed on by reference
            if (constRef) m_funcp->dontCombine(true);
            pair.first->second
                = V3Sched::util::newArgument(m_funcp, varp->dtypep(), varp->name(),
                                             constRef ? VDirection::CONSTREF : VDirection::REF);
            // Passed by reference either way; read-only at the call if the function only reads it
            const bool written = m_writtenps.count(varp);
            m_callp->addArgsp(new AstVarRef{m_callp->fileline(), nodep->varScopep(),
                                            written ? VAccess::READWRITE : VAccess::READ});
        }
        if (AstVarScope* const vscp = pair.first->second) {
            nodep->varp(vscp->varp());
            nodep->varScopep(vscp);
        }
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    OutlineArgsVisitor(AstCFunc* funcp, AstCCall* callp)
        : m_funcp{funcp}
        , m_callp{callp} {
        funcp->stmtsp()->foreachAndNext([this](const AstVarRef* refp) {
            if (refp->access().isWriteOrRW()) m_writtenps.emplace(refp->varp());
        });
        iterateAndNextNull(funcp->varsp());
        iterateAndNextNull(funcp->stmtsp());
    }
    ~OutlineArgsVisitor() override = default;

    bool hasAwait() const { return m_hasAwait; }
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
        size_t m_size = 0;  // Number of nodes in the statement
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
        size_t m_size;  // Number of nodes in the statements
    };

    // STATE
    VNUser1Allocator<AstNodeStmt, StmtInfo> m_info;
    VNUser2Allocator<AstVar, VarInfo> m_vars;
    const size_t m_limit = static_cast<size_t>(v3Global.opt.outputSplitCFuncs());
    AstCFunc* m_funcp = nullptr;  // Current function
    size_t m_funcNum = 0;  // Number of functions outlined from the current function
    std::string m_nameSuffix;  // Suffix of the names of functions outlined from the current one
    std::vector<StmtRange> m_groups;  // Statements to move, each group into a new function
    size_t m_count = 0;  // Number of nodes analyzed
    int m_depth = 0;  // Nesting depth of the statement being analyzed
    int m_targetDepth = 0;  // Least depth of the jump and loop test targets in the statement
    // Variables assigned whole on every path so far in the group being considered, and the
    // order they were added in, to undo additions in branches
    std::unordered_set<const AstVar*> m_assignedps;
    std::vector<const AstVar*> m_assignedOrder;
    std::vector<AstVar*> m_groupVarps;  // Variables of the group, in order of first reference
    std::vector<std::vector<AstVar*>> m_groupLocals;  // Locals of each group in m_groups
    VDouble0 m_statFuncs;  // Number of functions created
    VDouble0 m_statLocals;  // Number of variables declared in functions created
    VDouble0 m_statArgs;  // Number of variables passed to functions created

    // METHODS - analysis
    // Analyze 'nodep', which jumps to or tests the loop of the statement at 'targetDepth'
    void analyze(AstNodeStmt* nodep, int targetDepth) {
        StmtInfo& info = m_info(nodep);
        VL_RESTORER(m_depth);
        info.m_depth = ++m_depth;
        const size_t startCount = m_count++;
        const int outerTargetDepth = m_targetDepth;
        m_targetDepth = targetDepth;
        iterateChildren(nodep);
        info.m_size = m_count - startCount;
        info.m_movable = m_targetDepth >= info.m_depth;
        m_targetDepth = std::min(m_targetDepth, outerTargetDepth);
    }

    // METHODS - decision
    // Cut 'run' into groups no larger than the limit, to move
    void groupRun(const StmtRange& run) {
        StmtRange group{run.m_firstp, nullptr, 0};
        for (AstNode* nodep = run.m_firstp; nodep != run.m_lastp->nextp();
             nodep = nodep->nextp()) {
            AstNodeStmt* const stmtp = VN_AS(nodep, NodeStmt);
            const size_t size = m_info(stmtp).m_size;
            if (group.m_size + size > m_limit) {
                m_groups.push_back(group);
                group = StmtRange{stmtp, nullptr, 0};
            }
            group.m_lastp = stmtp;
            group.m_size += size;
        }
        m_groups.push_back(group);
    }
    // Choose statements under 'stmtp' to move until it is within the limit, return its size left
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
            size -= m_info(largep).m_size - reduce(largep);
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
        const OutlineArgsVisitor argsVisitor{subFuncp, callp};
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
        ++m_count;
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
        ++m_count;
        iterateChildren(nodep);
    }
    // The C++ types of the arguments of a public function differ from those of their
    // variables, so no statement using them can move
    void visit(AstVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        if (m_funcp->funcPublic() && varp->isIO() && !varp->isFuncReturn()) m_targetDepth = 0;
        ++m_count;
        ++m_vars(varp).m_refs;
    }
    void visit(AstNode* nodep) override {
        ++m_count;
        iterateChildren(nodep);
    }

    // CONSTRUCTORS
    explicit OutlineVisitor(AstNetlist* netlistp) {
        // Gather the functions first, as outlining adds functions
        std::vector<AstCFunc*> funcps;
        for (AstNodeModule* const modp : netlistp->modulespList()) {
            for (AstNode* const nodep : modp->stmtspList()) {
                AstScope* scopep = VN_CAST(nodep, Scope);
                if (AstTopScope* const topp = VN_CAST(nodep, TopScope)) scopep = topp->scopep();
                if (!scopep) continue;
                for (AstNode* const blockp : scopep->blockspList()) {
                    AstCFunc* const funcp = VN_AS(blockp, CFunc);
                    if (!funcp->isCoroutine() && !funcp->fromFTask()) continue;
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
