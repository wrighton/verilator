// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Prepare AST for timing features
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
// TimingSuspendableVisitor does not perform any AST transformations.
// Instead it propagates two types of flags:
// - flag "suspendable": (for detecting what will need to become a coroutine)
//     The visitor locates all C++ functions and processes that contain timing controls,
//     and marks them as suspendable. If a process calls a suspendable function,
//     then it is also marked as suspendable. If a function calls or overrides
//     a suspendable function, it is also marked as suspendable.
//     TimingSuspendableVisitor creates a dependency graph to propagate this property.
// - flag "needs process": (for detecting what needs a VlProcess argument in signature)
//   The visitor distinguishes 4 types of nodes:
//     - T_ALLOCS_PROC: nodes that can allocate VlProcess (forks, always, initial etc.),
//     - T_FORCES_PROC: nodes that make it necessary for the previous type to allocate VlProcess
//       (like process::self which then wraps it, allowing use inside Verilog).
//     - T_NEEDS_PROC: nodes that should obtain VlProcess if it will be allocated
//       (all of the previous type + timing controls, so they could update process state),
//     - T_HAS_PROC: nodes that are going to be emitted with a VlProcess argument.
//   T_FORCES_PROC and T_NEEDS_PROC are propagated upwards up to the nodes of type T_ALLOCS_PROC,
//   this is to detect which processes have to allocate VlProcess. Then nodes of these processes
//   get marked as T_HAS_PROC and the flag is propagated downwards through nodes
//   type T_NEEDS_PROC. Using only nodes type T_NEEDS_PROC assures the flags are only propagated
//   through paths leading to nodes that actually use VlProcess.
//
// TimingControlVisitor is the one that actually performs transformations:
// - for each intra-assignment timing control:
//     - if it's a continuous assignment, transform it into an always
//     - introduce an intermediate variable
//     - write the original RHS to the intermediate variable before the timing control
//     - write the intermediate variable to the original LHS after the timing control
// - for each delay:
//     - scale it according to the module's timescale
//     - replace it with a CAwait statement waiting on the global delay scheduler (with the
//       specified delay value)
//       - if there is no global delay scheduler (see verilated_timing.{h,cpp}), create it
// - for each event control:
//     - if there is no corresponding trigger scheduler (see verilated_timing.{h,cpp}), create it
//     - replace with a CAwait statement waiting on the corresponding trigger scheduler
//     - if a trigger scheduler cannot be used (e.g. in a class), a wait only on an event variable
//       whose storage outlives the wait, not through a handle and without 'iff', becomes a CAwait
//       on the event's wait list in the dynamic trigger scheduler, resumed after the event fires;
//       a wait on a wait queue of std::mailbox becomes a CAwait for its turn on the queue's wait
//       list; other waits evaluate their trigger on every trigger evaluation
//     - a wait only on a clocking block event of a virtual interface never assigned another
//       event, through a chain of up to 16 class and virtual interface handle variables whose
//       every write is a blocking assignment ("tracked handles", see TimingHandleVisitor), with
//       an 'iff' without effects if any, still evaluates its trigger, but only at the trigger
//       evaluations after the event fires or a tracked handle is written: while the handles are
//       set, it awaits the event's wait list instead of every trigger evaluation, and each write
//       of a tracked handle notifies the dynamic trigger scheduler (an assignment of a variable
//       as a whole with a pure value only if it changed it). No wait is listed this way if
//       evaluating a trigger may start or end a process, fire an event, or call a DPI import not
//       declared pure, or if the design has user C++ code ('$c' not declared pure, '`systemc_*')
//       or DPI export tasks that may suspend. In a model with a wait listed this way, the waits
//       awaiting trigger evaluation are ordered among the listed ones (evaluationKeyed).
// - for each wait(cond) statement:
//     - replace it with a loop like: while (!cond) @(<vars from cond>)
// - for each fork:
//     - if it's not a fork..join_none:
//         - create a join sync variable
//         - create statements that sync the main process with its children
//
// MailboxWaitVisitor, which runs earlier, before calls of functions become calls of C++
// functions, chooses how std::mailbox waits: on the wait queues of the mailbox, unless the
// condition of a wait or the expression of an event control, outside the std package, may have
// side effects, or the design references a variable of the std package, such as a member of a
// mailbox. Such a condition could change a mailbox while the triggers are evaluated, or kill a
// process, which may resume another one, and a member changed directly does not wake the
// waiters, which would then resume otherwise than if they tested their conditions, so they
// then do (see verilated_std.sv and VlWaitQueue). Each subroutine that a condition may call is
// scanned once, so the choice is linear in the size of the design, apart from isPure() of a
// chain of member selects in a subroutine, which is quadratic in the length of the chain (see
// MailboxWaitVisitor::scanCondition).
//
// See the internals documentation docs/internals.rst for more details.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Timing.h"

#include "V3CallTargets.h"
#include "V3Const.h"
#include "V3EmitV.h"
#include "V3File.h"
#include "V3Global.h"
#include "V3Graph.h"
#include "V3MemberMap.h"
#include "V3SenExprBuilder.h"
#include "V3SenTree.h"
#include "V3SharedTmps.h"
#include "V3Stats.h"
#include "V3UniqueNames.h"

#include <limits>
#include <queue>
#include <unordered_map>
#include <unordered_set>

VL_DEFINE_DEBUG_FUNCTIONS;

// ######################################################################

enum NodeFlag : uint8_t {
    T_SUSPENDEE = 1 << 0,  // Suspendable (due to dependence on another suspendable)
    T_SUSPENDER = 1 << 1,  // Suspendable (has timing control)
    T_ALLOCS_PROC = 1 << 2,  // Can allocate VlProcess
    T_FORCES_PROC = 1 << 3,  // Forces VlProcess allocation
    T_NEEDS_PROC = 1 << 4,  // Needs access to VlProcess if it's allocated
    T_HAS_PROC = 1 << 5,  // Has VlProcess argument in the signature
    T_NBA_UPDATE = 1 << 6,  // Fork branch of a pending NBA update, which is not a subprocess
    T_DPI_CALL = 1 << 7,  // Calls a context DPI imported task, directly or indirectly
};

enum ForkType : uint8_t {
    F_NONE = 0,  // Not under a fork
    F_MIGHT_SUSPEND = 1 << 0,  // Fork might suspend the execution of current process
    F_MIGHT_NEED_PROC = 1 << 1,  // Fork might need a process (any fork really)
};

enum PropagationType : uint8_t {
    P_CALL = 1,  // Propagation through call to a function/task/method
    P_FORK = 2,  // Propagation due to fork's behavior
    P_SIGNATURE = 3,  // Propagation required to maintain C++ function's signature requirements
};

// Add timing flag to a node
static void addFlags(AstNode* const nodep, uint8_t flags) { nodep->user2Or(flags); }
// Check if a node has ALL of the expected flags set
static bool hasFlags(AstNode* const nodep, uint8_t flags) { return !(~nodep->user2() & flags); }
// Whether calling the function may suspend the caller: the functions TimingControlVisitor makes
// coroutines. Shared by the analysis of handle writes and the notifications after them, which
// must agree, as a write the analysis takes as complete when the call returns is notified then.
static bool callSuspends(AstCFunc* const funcp) { return hasFlags(funcp, T_SUSPENDEE); }

static AstDeferredAssertFlush* takeDeferredAssertFlush(AstNode* nodep) {
    AstDeferredAssertFlush* const flushp = VN_CAST(nodep, DeferredAssertFlush);
    return flushp ? flushp->unlinkFrBack() : nullptr;
}

// ######################################################################
//  Detect nodes affected by timing and/or requiring a process

class TimingSuspendableVisitor final : public VNVisitor {
    // TYPES
    // Vertex of a dependency graph of suspendable nodes, e.g. if a node (process or task) is
    // suspendable, all its dependents should also be suspendable
    class DepVtx VL_NOT_FINAL : public V3GraphVertex {
        VL_RTTI_IMPL(DepVtx, V3GraphVertex)
        AstClass* const m_classp;  // Class associated with a method
        AstNode* const m_nodep;  // AST node represented by this graph vertex

        // ACCESSORS
        string name() const override {
            if (m_classp) {
                if (VN_IS(nodep(), CFunc)) {
                    return cvtToHex(nodep()) + ' ' + classp()->name() + "::" + nodep()->name();
                }
            }
            return cvtToHex(nodep()) + ' ' + nodep()->prettyTypeNameQ();
        }
        FileLine* fileline() const override { return nodep()->fileline(); }

    public:
        // CONSTRUCTORS
        DepVtx(V3Graph* graphp, AstNode* nodep, AstClass* classp)
            : V3GraphVertex{graphp}
            , m_classp{classp}
            , m_nodep{nodep} {}
        ~DepVtx() override = default;

        // ACCESSORS
        virtual AstNode* nodep() const VL_MT_STABLE { return m_nodep; }
        virtual AstNode* classp() const VL_MT_STABLE { return m_classp; }
    };

    class SuspendDepVtx final : public DepVtx {
        VL_RTTI_IMPL(SuspendDepVtx, DepVtx)
        string dotColor() const override {
            if (hasFlags(nodep(), T_SUSPENDER)) return "red";
            if (hasFlags(nodep(), T_SUSPENDEE)) return "blue";
            return "black";
        }

    public:
        SuspendDepVtx(V3Graph* graphp, AstNode* nodep, AstClass* classp)
            : DepVtx{graphp, nodep, classp} {}
        ~SuspendDepVtx() override = default;
    };

    class NeedsProcDepVtx final : public DepVtx {
        VL_RTTI_IMPL(NeedsProcDepVtx, DepVtx)
        string dotColor() const override {
            if (hasFlags(nodep(), T_HAS_PROC)) return "blue";
            if (hasFlags(nodep(), T_NEEDS_PROC)) return "green";
            if (hasFlags(nodep(), T_FORCES_PROC)) return "red";
            return "black";
        }

    public:
        NeedsProcDepVtx(V3Graph* graphp, AstNode* nodep, AstClass* classp)
            : DepVtx{graphp, nodep, classp} {}
        ~NeedsProcDepVtx() override = default;
    };

    // NODE STATE
    //  AstClass::user1() -> bool.  Class member cache has been refreshed.
    //  Ast{NodeProcedure,CFunc,ForkItem}::user2()  -> uint64_t.  Set to >= T_SUSP if
    //                                                            process/task suspendable
    //                                                            and to T_PROC if it
    //                                                            needs process metadata.
    //  Ast{NodeProcedure,CFunc,ForkItem}::user3()  -> DependencyVertex*.  Vertex in m_suspGraph
    //  Ast{NodeProcedure,CFunc,ForkItem}::user4()  -> DependencyVertex*.  Vertex in m_procGraph
    const VNUser3InUse m_user3InUse;
    const VNUser4InUse m_user4InUse;

    // STATE
    VMemberMap m_memberMap;  // Member names cached for fast lookup
    AstClass* m_classp = nullptr;  // Current class
    AstNode* m_procp = nullptr;  // NodeProcedure/CFunc/ForkItem we're under
    uint8_t m_underFork = F_NONE;  // F_NONE or flags of a fork we are under
    V3Graph m_suspGraph;  // Dependency graph where a node is a dependency of another if it being
                          // suspendable makes the other node suspendable
    V3Graph m_procGraph;  // Dependency graph where a node is a dependency of another if it being
                          // suspendable makes the other node suspendable
    std::vector<AstCFunc*> m_dpiImportTaskCallers;  // Process/functions containing DPI task calls
    std::vector<AstCFunc*> m_dpiExports;  // Contains DPI exports
    unsigned m_suspendableExports = 0;  // Suspendable DPI exports counted for statistics

    // METHODS
    // Get or create the dependency vertex for the given node
    DepVtx* getSuspendDepVtx(AstNode* const nodep) {
        AstClass* classp = nullptr;
        if (AstCFunc* funcp = VN_CAST(nodep, CFunc)) {
            if (funcp->scopep() && funcp->scopep()->modp()) {
                classp = VN_CAST(funcp->scopep()->modp(), Class);
            }
        }
        if (!nodep->user3p()) nodep->user3p(new SuspendDepVtx{&m_suspGraph, nodep, classp});
        return nodep->user3u().to<SuspendDepVtx*>();
    }
    DepVtx* getNeedsProcDepVtx(AstNode* const nodep) {
        AstClass* classp = nullptr;
        if (AstCFunc* funcp = VN_CAST(nodep, CFunc)) {
            if (funcp->scopep() && funcp->scopep()->modp()) {
                classp = VN_CAST(funcp->scopep()->modp(), Class);
            }
        }
        if (!nodep->user4p()) nodep->user4p(new NeedsProcDepVtx{&m_procGraph, nodep, classp});
        return nodep->user4u().to<NeedsProcDepVtx*>();
    }
    // Pass timing flag between nodes
    bool passFlag(const AstNode* fromp, AstNode* top, NodeFlag flag) {
        if ((fromp->user2() & flag) && !(top->user2() & flag)) {
            addFlags(top, flag);
            return true;
        }
        return false;
    }
    // Propagate flag to all nodes that depend on the given one
    void propagateFlags(DepVtx* const vxp, NodeFlag flag) {
        auto* const parentp = vxp->nodep();
        for (V3GraphEdge& edge : vxp->outEdges()) {
            auto* const depVxp = static_cast<DepVtx*>(edge.top());
            AstNode* const depp = depVxp->nodep();
            if (passFlag(parentp, depp, flag)) propagateFlags(depVxp, flag);
        }
    }
    template <typename T_Predicate>
    void propagateFlagsIf(DepVtx* const vxp, NodeFlag flag, T_Predicate p) {
        auto* const parentp = vxp->nodep();
        for (V3GraphEdge& edge : vxp->outEdges()) {
            auto* const depVxp = static_cast<DepVtx*>(edge.top());
            AstNode* const depp = depVxp->nodep();
            if (p(&edge) && passFlag(parentp, depp, flag)) propagateFlagsIf(depVxp, flag, p);
        }
    }
    template <typename T_Predicate>
    void propagateFlagsReversedIf(DepVtx* const vxp, NodeFlag flag, T_Predicate p) {
        auto* const parentp = vxp->nodep();
        for (V3GraphEdge& edge : vxp->inEdges()) {
            auto* const depVxp = static_cast<DepVtx*>(edge.fromp());
            AstNode* const depp = depVxp->nodep();
            if (p(&edge) && passFlag(parentp, depp, flag))
                propagateFlagsReversedIf(depVxp, flag, p);
        }
    }

    // VISITORS
    void visit(AstClass* nodep) override {
        UASSERT_OBJ(!m_classp, nodep, "Class under class");
        VL_RESTORER(m_classp);
        m_classp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_procp);
        m_procp = nodep;
        getNeedsProcDepVtx(nodep);
        addFlags(nodep, T_ALLOCS_PROC);
        if (VN_IS(nodep, Always)) {
            UINFO(9, "Always does " << (nodep->needsVlProcess() ? "" : "NOT ") << "need process");
        }
        iterateChildren(nodep);
    }
    void visit(AstDisableFork* nodep) override {
        visit(static_cast<AstNode*>(nodep));
        addFlags(m_procp, T_FORCES_PROC | T_NEEDS_PROC);
    }
    void visit(AstWaitFork* nodep) override {
        visit(static_cast<AstNode*>(nodep));
        addFlags(m_procp, T_FORCES_PROC | T_NEEDS_PROC);
    }
    void visit(AstWait* nodep) override {
        UINFO(9, "suspendable-visit " << nodep);
        AstNodeExpr* const condp = V3Const::constifyEdit(nodep->condp());
        if (AstConst* const constp = VN_CAST(condp, Const)) {
            if (!nodep->fileline()->warnIsOff(V3ErrorCode::WAITCONST)) {
                condp->v3warn(WAITCONST, "Wait statement condition is constant");
            }
            if (!constp->isZero()) {
                // Remove AstWait before we track process as T_SUSPENDER
                if (AstNode* const flushp = takeDeferredAssertFlush(nodep->stmtsp())) {
                    VL_DO_DANGLING(pushDeletep(flushp), flushp);
                }
                if (AstNode* const stmtsp = nodep->stmtsp()) {
                    stmtsp->unlinkFrBackWithNext();
                    nodep->replaceWith(stmtsp);
                } else {
                    nodep->unlinkFrBack();
                }
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
                return;
            }
        }
        v3Global.setUsesTiming();
        if (m_procp) addFlags(m_procp, T_SUSPENDEE | T_SUSPENDER | T_NEEDS_PROC);
        iterateChildren(nodep);
    }
    void visit(AstCFunc* nodep) override {
        VL_RESTORER(m_procp);
        m_procp = nodep;
        iterateChildren(nodep);
        if (nodep->dpiExportImpl()) m_dpiExports.push_back(nodep);
        if (nodep->needsVlProcess()) addFlags(nodep, T_FORCES_PROC | T_NEEDS_PROC);
        DepVtx* const sVxp = getSuspendDepVtx(nodep);
        DepVtx* const pVxp = getNeedsProcDepVtx(nodep);
        if (nodep->dpiImportWrapper() || nodep->dpiExportImpl()) {
            // Assume C/C++ can call any export.
            AstNetlist* const netlistp = v3Global.rootp();
            addFlags(nodep, T_NEEDS_PROC);
            DepVtx* const dpiVxp = getNeedsProcDepVtx(netlistp);
            if (nodep->dpiExportImpl()) {
                new V3GraphEdge{&m_procGraph, pVxp, dpiVxp, P_CALL};
            } else {
                new V3GraphEdge{&m_procGraph, dpiVxp, pVxp, P_CALL};
            }
        }
        if (!m_classp) return;

        // Go over overridden functions. Visit each base class once, as interface classes can
        // inherit the same class along many paths.

        std::set<const AstClass*> visited;
        std::queue<AstClassExtends*> extends;
        if (m_classp->extendsp()) extends.push(m_classp->extendsp());

        while (!extends.empty()) {
            AstClassExtends* ext_listp = extends.front();
            extends.pop();

            for (AstClassExtends* cextp = ext_listp; cextp;
                 cextp = VN_AS(cextp->nextp(), ClassExtends)) {
                if (!visited.emplace(cextp->classp()).second) continue;
                // TODO: It is possible that a methods the same name in the base class is not
                // actually overridden by our method. If this causes a problem, traverse to
                // the root of the inheritance hierarchy and check if the original method is
                // virtual or not.
                if (auto* const overriddenp
                    = VN_CAST(m_memberMap.findMember(cextp->classp(), nodep->name()), CFunc)) {
                    // Suspendability and process affects typing, so they propagate both ways
                    DepVtx* const overriddenSVxp = getSuspendDepVtx(overriddenp);
                    DepVtx* const overriddenPVxp = getNeedsProcDepVtx(overriddenp);
                    new V3GraphEdge{&m_suspGraph, sVxp, overriddenSVxp, P_SIGNATURE};
                    new V3GraphEdge{&m_suspGraph, overriddenSVxp, sVxp, P_SIGNATURE};
                    new V3GraphEdge{&m_procGraph, pVxp, overriddenPVxp, P_SIGNATURE};
                    new V3GraphEdge{&m_procGraph, overriddenPVxp, pVxp, P_SIGNATURE};
                } else {
                    AstClassExtends* more_extendsp = cextp->classp()->extendsp();
                    if (more_extendsp) extends.push(more_extendsp);
                }
            }
        }
    }
    void visit(AstNodeCCall* nodep) override {
        AstCFunc* const funcp = nodep->funcp();
        UASSERT_OBJ(funcp, nodep, "AstNodeCCall must have non-null funcp post-link");
        UASSERT_OBJ(m_procp, nodep, "AstNodeCCall must be inside a procedure/CFunc/ForkItem");

        UINFO(9, "V3Timing: Processing CCall to " << funcp->name() << " in dependency graph\n");
        new V3GraphEdge{&m_suspGraph, getSuspendDepVtx(funcp), getSuspendDepVtx(m_procp), P_CALL};

        new V3GraphEdge{&m_procGraph, getNeedsProcDepVtx(funcp), getNeedsProcDepVtx(m_procp),
                        P_CALL};

        iterateChildren(nodep);
    }
    void visit(AstForkItem* nodep) override {
        VL_RESTORER(m_procp);
        VL_RESTORER(m_underFork);

        if (m_underFork & F_MIGHT_SUSPEND) {
            new V3GraphEdge{&m_suspGraph, getSuspendDepVtx(nodep), getSuspendDepVtx(m_procp),
                            P_FORK};
        }

        new V3GraphEdge{&m_procGraph, getNeedsProcDepVtx(nodep), getNeedsProcDepVtx(m_procp),
                        P_CALL};

        addFlags(nodep, T_NEEDS_PROC | T_ALLOCS_PROC);

        m_procp = nodep;
        m_underFork = 0;
        iterateChildren(nodep);
    }
    void visit(AstFork* nodep) override {
        UINFO(9, "suspendable-visit " << nodep);
        VL_RESTORER(m_underFork);

        v3Global.setUsesTiming();  // Even if there are no event controls, we have to set this flag
                                   // so that transformForks() in V3SchedTiming gets called and
                                   // removes all forks
        if (nodep->isTimingControl() && m_procp) {
            addFlags(m_procp, T_SUSPENDEE | T_SUSPENDER);
            m_underFork |= F_MIGHT_SUSPEND;
        }
        m_underFork |= F_MIGHT_NEED_PROC;
        iterateChildren(nodep);
    }
    void visit(AstAssignW* nodep) override {
        if (nodep->timingControlp()) v3Global.setUsesTiming();
        // Containing process will not suspend, don't mark it
    }
    void visit(AstCFuncHard* nodep) override {
        if (!VN_IS(m_procp, CFunc)) return;
        AstCFunc* const cfuncp = VN_AS(m_procp, CFunc);
        if (nodep->function() == VCFunction::CALL_IMPORT_TASK && cfuncp->dpiContext()) {
            m_dpiImportTaskCallers.push_back(cfuncp);
        }
    }
    void visit(AstNode* nodep) override {
        if (nodep->isTimingControl()) {
            v3Global.setUsesTiming();
            if (m_procp) addFlags(m_procp, T_SUSPENDEE | T_SUSPENDER | T_NEEDS_PROC);
        }
        iterateChildren(nodep);
    }

    //--------------------
    void visit(AstVar*) override {}  // Accelerate

public:
    // CONSTRUCTORS
    explicit TimingSuspendableVisitor(AstNetlist* nodep) {
        iterate(nodep);
        // Process pruning is incorrect: flags stop at T_ALLOCS_PROC, so a direct call edge is
        // not implied through a fork. Suspendability pruning is correct but unnecessary:
        // propagation is linear, while transitive reduction dominates this pass's cost.
        // Opaque DPI calls may invoke any export, so link them through the netlist.
        for (AstCFunc* const dpiExportp : m_dpiExports) {
            new V3GraphEdge{&m_suspGraph, getSuspendDepVtx(dpiExportp), getSuspendDepVtx(nodep),
                            P_CALL};
        }
        for (AstCFunc* const cfuncp : m_dpiImportTaskCallers) {
            addFlags(cfuncp, T_DPI_CALL);
            new V3GraphEdge{&m_suspGraph, getSuspendDepVtx(nodep), getSuspendDepVtx(cfuncp),
                            P_CALL};
        }

        // Propagate suspendability
        for (V3GraphVertex& vtx : m_suspGraph.vertices()) {
            DepVtx& depVtx = static_cast<DepVtx&>(vtx);
            if (hasFlags(depVtx.nodep(), T_SUSPENDEE)) propagateFlags(&depVtx, T_SUSPENDEE);
            if (hasFlags(depVtx.nodep(), T_DPI_CALL)) propagateFlags(&depVtx, T_DPI_CALL);
        }

        for (AstCFunc* const dpiExportp : m_dpiExports) {
            if (hasFlags(dpiExportp, T_SUSPENDEE) || hasFlags(dpiExportp, T_SUSPENDER)) {
                ++m_suspendableExports;
                v3Global.setUsesSuspendableExports();
            }
        }

        if (dumpGraphLevel() >= 6) m_suspGraph.dumpDotFilePrefixed("timing_deps");

        // Propagate T_HAS_PROCESS
        for (V3GraphVertex& vtx : m_procGraph.vertices()) {
            DepVtx& depVtx = static_cast<DepVtx&>(vtx);
            // Find processes that'll allocate VlProcess
            if (hasFlags(depVtx.nodep(), T_FORCES_PROC)) {
                propagateFlagsIf(&depVtx, T_FORCES_PROC, [&](const V3GraphEdge* ep) -> bool {
                    return !hasFlags(static_cast<DepVtx*>(ep->fromp())->nodep(), T_ALLOCS_PROC);
                });
            }
            // Mark nodes on paths between processes and statements that use VlProcess
            if (hasFlags(depVtx.nodep(), T_NEEDS_PROC)) {
                propagateFlagsIf(&depVtx, T_NEEDS_PROC, [&](const V3GraphEdge* ep) -> bool {
                    return !hasFlags(static_cast<DepVtx*>(ep->top())->nodep(), T_ALLOCS_PROC);
                });
            }
        }
        for (V3GraphVertex& vtx : m_procGraph.vertices()) {
            DepVtx& depVtx = static_cast<DepVtx&>(vtx);
            // Mark nodes that will be emitted with a VlProcess argument
            const AstCFunc* const cfuncp = VN_CAST(depVtx.nodep(), CFunc);
            // An export entered directly from C receives its process from the dispatcher.
            if (hasFlags(depVtx.nodep(), T_FORCES_PROC)
                && (hasFlags(depVtx.nodep(), T_ALLOCS_PROC)
                    || (cfuncp && cfuncp->dpiExportImpl()))) {
                addFlags(depVtx.nodep(), T_HAS_PROC);
                propagateFlagsReversedIf(&depVtx, T_HAS_PROC, [&](const V3GraphEdge* ep) -> bool {
                    return hasFlags(static_cast<DepVtx*>(ep->fromp())->nodep(), T_NEEDS_PROC);
                });
            }
        }
        if (dumpGraphLevel() >= 6) m_procGraph.dumpDotFilePrefixed("proc_deps");
    }
    ~TimingSuspendableVisitor() override {
        V3Stats::addStat("Timing, suspendable DPI exports", m_suspendableExports);
    }
};

// ######################################################################
//  Find the class and virtual interface handle variables whose writes can be tracked

class TimingHandleVisitor final : public VNVisitorConst {
    // A wait through class and virtual interface handles follows the handles when they change
    // (IEEE 1800-2023 9.4.2). A handle variable is a tracked handle if each of its writes is a
    // blocking assignment to the whole variable, after which the scheduler is notified (V3Task
    // already turned the output arguments of calls into such assignments), and it cannot be
    // written from outside the model. The objects and interfaces themselves stay in place while
    // referenced, so the handles reach another event only after a tracked handle is written. An
    // event waited on this way must never be assigned another event, so it stays the event
    // waited on. User '$c' code not declared pure, and '`systemc_*' code, may write any variable,
    // assign any event, or fire it, by name or through others, so no wait is listed in a design
    // with such code, other than the std package's (see isStdModule). No wait is listed either in
    // a design with DPI export tasks that may suspend: killing a process suspended in one runs
    // the C++ code that called it, which may fire an event, while the killed waiter is dropped
    // from its wait list at a trigger evaluation.
    // A wait woken on a wait list evaluates its trigger at its place among the triggers
    // evaluated at every trigger evaluation (see VlDynamicTriggerScheduler::startWait). This
    // needs the handles not to change, no wait to start, and no event to fire while triggers are
    // evaluated: a handle written by evaluating a trigger, through any function it calls, is not
    // a tracked handle, and no wait is listed if evaluating a trigger may start or end a process,
    // fire an event, or call a DPI import not declared pure, whose C++ code may call back into
    // the model, through DPI exports or the public functions of the model, and do either.

    // TYPES
    struct Writer final {  // A function, or all trigger expressions
        std::vector<const AstVar*> m_handleps;  // Handle variables it writes
        std::vector<const AstCFunc*> m_calleeps;  // Functions it calls
        bool m_procControl = false;  // Starts or ends processes
        bool m_fires = false;  // Fires events
    };

    // STATE
    // Handle variables written in another way, with why
    std::unordered_map<const AstVar*, std::string> m_untracked;
    std::unordered_set<const AstVar*> m_assignedEvents;  // Events assigned another event
    std::unordered_map<const AstCFunc*, Writer> m_funcWriters;  // Writes of each function
    std::unordered_map<std::string, std::vector<const AstCFunc*>> m_virtualps;  // By name
    Writer m_triggerWriter;  // Writes of the trigger expressions
    Writer* m_writerp = nullptr;  // The writer of the code being visited, if any
    const AstClass* m_classp = nullptr;  // The class being visited, if any
    bool m_inFire = false;  // Under firing an event, which does not assign it
    bool m_inStd = false;  // In the std package, or a class declared in it
    std::string m_userCReason;  // Why no wait may be listed, if the design has user '$c' code
                                // not declared pure, else empty
    std::unordered_set<const AstNodeExpr*> m_trackedRefps;  // References written trackably
    std::string m_orderReason;  // Why no wait may be listed, if evaluating a trigger may change
                                // the order of evaluation, else empty

    // METHODS
    static bool isHandle(const AstVar* const varp) {
        const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
        const AstIfaceRefDType* const ifacep = VN_CAST(dtypep, IfaceRefDType);
        return VN_IS(dtypep, ClassRefDType) || (ifacep && ifacep->isVirtual());
    }
    static bool isEvent(const AstVar* const varp) {
        const AstBasicDType* const basicp = varp->dtypep()->skipRefp()->basicp();
        return basicp && basicp->isEvent();
    }
    void noteWrite(const AstNodeExpr* const refp, const AstVar* const varp) {
        if (isHandle(varp)) {
            // The reason is kept as text, as the write may be deleted before it is used
            const auto pair = m_untracked.emplace(varp, "");
            if (pair.second) {
                pair.first->second = "written other than as a whole by a blocking assignment at "
                                     + refp->fileline()->ascii();
            }
            if (m_writerp) m_writerp->m_handleps.push_back(varp);
        }
        if (!m_inFire && isEvent(varp)) m_assignedEvents.emplace(varp);
    }
    // Whether the module is the std package, a class declared in it, or the package of such a
    // class. V3Class moved the classes out of the packages declaring them, but the scope of a
    // class, and of its package, stays under the scope of the package declaring it.
    // Only the built-in std package counts: without it, a package named std is the user's.
    static bool isStdModule(const AstNodeModule* const modp) {
        const AstPackage* const stdp = v3Global.rootp()->stdPackagep();
        if (!stdp || !v3Global.opt.stdPackage()) return false;
        if (modp == stdp) return true;
        const AstClass* const classp = VN_CAST(modp, Class);
        if (!classp && !VN_IS(modp, ClassPackage)) return false;
        const AstScope* scopep = nullptr;
        for (const AstNode* itemp = classp ? classp->membersp() : modp->stmtsp(); itemp && !scopep;
             itemp = itemp->nextp()) {
            scopep = VN_CAST(itemp, Scope);
        }
        // Without a scope it is not known to be std, so its C++ code counts as the user's
        return scopep && scopep->aboveScopep() && scopep->aboveScopep()->modp() == stdp;
    }
    void noteProcControl() {
        if (m_writerp) m_writerp->m_procControl = true;
    }
    // Iterate a trigger expression
    void iterateTrigger(AstNode* const nodep) {
        VL_RESTORER(m_writerp);
        m_writerp = &m_triggerWriter;
        iterateAndNextConstNull(nodep);
    }
    // Untrack the handles that functions called while evaluating triggers write, and note if
    // they may start or end processes, or fire events
    void untrackTriggerWrites() {
        std::unordered_set<const AstCFunc*> visited;
        std::unordered_set<std::string> expandedNames;  // Of virtual methods
        std::vector<const AstCFunc*> pending;
        const auto addCallee = [&](const AstCFunc* const funcp) {
            if (visited.emplace(funcp).second) pending.push_back(funcp);
        };
        const auto addWriter = [&](const Writer& writer) {
            for (const AstVar* const varp : writer.m_handleps) {
                m_untracked[varp] = "written while evaluating a trigger";
            }
            if (m_orderReason.empty() && writer.m_procControl) {
                m_orderReason = "evaluating a trigger may start or end a process";
            }
            if (m_orderReason.empty() && writer.m_fires) {
                m_orderReason = "evaluating a trigger may fire an event";
            }
            for (const AstCFunc* const calleep : writer.m_calleeps) {
                addCallee(calleep);
                // A virtual method may be overridden by any method of the same name, each
                // name expanded once
                if (calleep->isVirtual() && expandedNames.emplace(calleep->name()).second) {
                    for (const AstCFunc* const overp : m_virtualps[calleep->name()]) {
                        addCallee(overp);
                    }
                }
                // The C++ code of a DPI import may call back into the model, not only through
                // DPI exports, unless it is declared pure (IEEE 1800-2023 35.5.2)
                if (m_orderReason.empty() && calleep->dpiImportWrapper() && !calleep->dpiPure()) {
                    m_orderReason = "evaluating a trigger may call a DPI import";
                }
            }
        };
        addWriter(m_triggerWriter);
        while (!pending.empty()) {
            const AstCFunc* const funcp = pending.back();
            pending.pop_back();
            const auto it = m_funcWriters.find(funcp);
            if (it != m_funcWriters.end()) addWriter(it->second);
        }
    }
    // Iterate the handles selecting a written member, which are marked as written, but are only
    // read
    void iterateMemberBase(AstNodeExpr* const fromp) {
        if (VN_IS(fromp, NodeVarRef)) return;
        if (AstMemberRef* const memberp = VN_CAST(fromp, MemberRef)) {
            iterateMemberBase(memberp->fromp());
            return;
        }
        iterateAndNextConstNull(fromp);
    }
    // Iterate the value of an assignment. A variable as a whole is only read, even if it is
    // marked as also written: V3Task copies an inout argument in by such an assignment, and back
    // by another.
    void iterateAssignedValue(AstNodeExpr* const rhsp) {
        if (VN_IS(rhsp, NodeVarRef)) return;
        if (AstMemberRef* const memberp = VN_CAST(rhsp, MemberRef)) {
            iterateMemberBase(memberp->fromp());
            return;
        }
        iterateAndNextConstNull(rhsp);
    }

    // Note the writes of handles by the statement that can be tracked, which are then iterated
    // as reads, returning the references writing them
    std::vector<const AstNodeExpr*> noteTrackedWrites(AstNode* const nodep) {
        std::vector<const AstNodeExpr*> refps;
        foreachTrackedWrite(
            nodep, [](AstCFunc* const funcp) { return callSuspends(funcp); },
            [&](const AstNodeExpr* refp, const AstVar* varp) {
                if (!isHandle(varp)) return;
                if (m_writerp) m_writerp->m_handleps.push_back(varp);
                if (m_trackedRefps.emplace(refp).second) refps.push_back(refp);
            });
        return refps;
    }
    void forgetTrackedWrites(const std::vector<const AstNodeExpr*>& refps) {
        for (const AstNodeExpr* const refp : refps) m_trackedRefps.erase(refp);
    }

    // VISITORS
    void visit(AstNodeAssign* const nodep) override {
        const std::vector<const AstNodeExpr*> refps = noteTrackedWrites(nodep);
        iterateAndNextConstNull(nodep->lhsp());
        iterateAssignedValue(nodep->rhsp());
        iterateAndNextConstNull(nodep->timingControlp());
        forgetTrackedWrites(refps);
    }
    void visit(AstStmtExpr* const nodep) override {
        const std::vector<const AstNodeExpr*> refps = noteTrackedWrites(nodep);
        iterateChildrenConst(nodep);
        forgetTrackedWrites(refps);
    }
    void visit(AstNodeVarRef* const nodep) override {
        if (m_trackedRefps.count(nodep)) return;
        if (nodep->access().isWriteOrRW()) noteWrite(nodep, nodep->varp());
    }
    void visit(AstMemberRef* const nodep) override {
        if (m_trackedRefps.count(nodep)) {
            iterateMemberBase(nodep->fromp());
            return;
        }
        if (nodep->access().isWriteOrRW()) {
            noteWrite(nodep, nodep->varp());
            iterateMemberBase(nodep->fromp());
            return;
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstFireEvent* const nodep) override {
        // A delayed fire only fires in the NBA region, not while triggers are evaluated
        if (m_writerp && !nodep->isDelayed()) m_writerp->m_fires = true;
        VL_RESTORER(m_inFire);
        m_inFire = true;
        iterateChildrenConst(nodep);
    }
    // Note user '$c' code not declared pure ('$cpure'), or '`systemc_*' code. The std package's
    // writes only the state of processes (std::process self(), set_status(), kill(),
    // set_randstate()) and reads mailbox messages: it writes no handle of a class or virtual
    // interface, and fires no event. Its methods that end processes or let them run again are
    // taken as process control (see visit(AstCFunc*)).
    void noteUserC(const AstNode* const nodep, const bool pure) {
        if (pure || m_inStd || !m_userCReason.empty()) return;
        m_userCReason = "the design has user C++ code at " + nodep->fileline()->ascii();
    }
    void visit(AstCStmtUser* const nodep) override {
        noteUserC(nodep, false);
        iterateChildrenConst(nodep);
    }
    void visit(AstCExprUser* const nodep) override {
        noteUserC(nodep, nodep->isPure());
        iterateChildrenConst(nodep);
    }
    void visit(AstSystemCSection* const nodep) override { noteUserC(nodep, false); }
    void visit(AstNodeModule* const nodep) override {
        VL_RESTORER(m_inStd);
        m_inStd = isStdModule(nodep);
        iterateChildrenConst(nodep);
    }
    void visit(AstClass* const nodep) override {
        VL_RESTORER(m_classp);
        VL_RESTORER(m_inStd);
        m_classp = nodep;
        m_inStd = isStdModule(nodep);
        iterateChildrenConst(nodep);
    }
    void visit(AstCFunc* const nodep) override {
        VL_RESTORER(m_writerp);
        Writer& writer = m_funcWriters[nodep];
        m_writerp = &writer;
        if (nodep->isVirtual()) m_virtualps[nodep->name()].push_back(nodep);
        // The methods of the std::process class that end processes or let them run again, in
        // their '$c' code: kill() and set_status(). The others reach these through calls
        // (killQueue(), resume()), or only read the state of a process (status(), self()), and a
        // pure status() is often called in a wait condition (as in UVM), so not every method of
        // the class referencing a process is taken as a control.
        if (m_classp && m_classp == v3Global.rootp()->stdPackageProcessp()) {
            // The name of the method, as V3Task names the function of a method not inlined
            const std::string& name = nodep->name();
            static const std::string prefix = "__VnoInFunc_";  // See V3Task
            const std::string methodName
                = VString::startsWith(name, prefix) ? name.substr(prefix.size()) : name;
            if (methodName == "kill" || methodName == "set_status") writer.m_procControl = true;
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeCCall* const nodep) override {
        if (m_writerp) m_writerp->m_calleeps.push_back(nodep->funcp());
        iterateChildrenConst(nodep);
    }
    void visit(AstFork* const nodep) override {
        noteProcControl();
        iterateChildrenConst(nodep);
    }
    void visit(AstDisableFork* const nodep) override {
        noteProcControl();
        iterateChildrenConst(nodep);
    }
    void visit(AstSenItem* const nodep) override {
        iterateTrigger(nodep->sensp());
        iterateTrigger(nodep->condp());
    }
    void visit(AstWait* const nodep) override {
        // Its condition may become a trigger (see TimingControlVisitor::visit(AstWait))
        iterateTrigger(nodep->condp());
        iterateAndNextConstNull(nodep->stmtsp());
    }
    void visit(AstNode* const nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit TimingHandleVisitor(AstNetlist* const nodep) {
        iterateConst(nodep);
        untrackTriggerWrites();
    }
    ~TimingHandleVisitor() override = default;

    // METHODS
    // The variable a reference writes as a whole, else nullptr
    static const AstVar* wholeWriteVarp(const AstNodeExpr* const exprp) {
        if (const AstNodeVarRef* const refp = VN_CAST(exprp, NodeVarRef)) {
            if (refp->access().isWriteOrRW()) return refp->varp();
        } else if (const AstMemberRef* const memberp = VN_CAST(exprp, MemberRef)) {
            if (memberp->access().isWriteOrRW()) return memberp->varp();
        }
        return nullptr;
    }
    // Call 'f' with each reference, and its variable, that the statement writes as a whole in a
    // way that may be tracked, after which a notification can follow it: a blocking assignment
    // to it, a '$cast' to it whose result is assigned or ignored, or an argument written by
    // reference by a function call statement, if the function cannot suspend (see 'suspends')
    template <typename T_Suspends, typename T_Func>
    static void foreachTrackedWrite(AstNode* const stmtp, T_Suspends suspends, T_Func f) {
        if (const AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
            if (assignp->timingControlp()) return;
            if (const AstVar* const varp = wholeWriteVarp(assignp->lhsp()))
                f(assignp->lhsp(), varp);
            if (const AstCastDynamic* const castp = VN_CAST(assignp->rhsp(), CastDynamic)) {
                if (const AstVar* const varp = wholeWriteVarp(castp->top())) f(castp->top(), varp);
            }
        } else if (const AstStmtExpr* const stmtExprp = VN_CAST(stmtp, StmtExpr)) {
            if (const AstCastDynamic* const castp = VN_CAST(stmtExprp->exprp(), CastDynamic)) {
                if (const AstVar* const varp = wholeWriteVarp(castp->top())) f(castp->top(), varp);
                return;
            }
            const AstNodeCCall* const callp = VN_CAST(stmtExprp->exprp(), NodeCCall);
            if (!callp || suspends(callp->funcp())) return;
            for (const AstNodeExpr* argp = callp->argsp(); argp;
                 argp = VN_AS(argp->nextp(), NodeExpr)) {
                if (const AstVar* const varp = wholeWriteVarp(argp)) f(argp, varp);
            }
        }
    }
    // Whether all writes of the variable are seen, so it is a tracked handle. Not a port
    // other than an input, which a reference argument would alias, nor visible from outside the
    // model (a forceable handle is not supported).
    bool isTracked(const AstVar* const varp) const {
        return isHandle(varp) && !m_untracked.count(varp) && (!varp->isIO() || varp->isInput())
               && !varp->isSigPublic();
    }
    // Why the variable is not a tracked handle, for debug
    string untrackedReason(const AstVar* const varp) const {
        const auto it = m_untracked.find(varp);
        if (it != m_untracked.end()) return it->second;
        if (varp->isSigPublic()) return "public";
        return "a port";
    }
    // Whether the event may be assigned another event
    bool isAssignedEvent(const AstVar* const varp) const { return m_assignedEvents.count(varp); }
    // Why no wait may be listed, as evaluating a trigger may change the order of evaluation, or
    // empty if none
    const std::string& orderReason() const { return m_orderReason; }
    // Why no wait may be listed, as the design has user C++ code, or empty if none
    const std::string& userCReason() const { return m_userCReason; }
    // Why no wait may be listed, as the design has DPI export tasks that may suspend, or empty
    static std::string exportReason() {
        return v3Global.usesSuspendableExports()
                   ? "the design has DPI export tasks that may suspend"
                   : "";
    }
};

// ######################################################################
//  Transform nodes affected by timing

class TimingControlVisitor final : public VNVisitor {
    // NODE STATE
    //  Ast{Initial,NodeCCall,Fork,NodeAssign}::user1() -> bool.         Set true if the node has
    //                                                                   been processed.
    //  AstAssignW::user1()                             -> bool.         Set true if the assignment
    //                                                                   represents the net delay
    //  AstSenTree::user1()                             -> AstVarScope*. Trigger scheduler assigned
    //                                                                   to this sentree
    //  Ast{NodeProcedure,CFunc,ForkItem}::user2()      -> bool.         Set true if process/task
    //                                                                   is suspendable
    //  Ast{EventControl}::user2()                      -> bool.         Set true if event control
    //                                                                   should immediately be
    //                                                                   committed
    //  AstSenTree::user2()                             -> AstCExpr*.    Debug info passed to the
    //                                                                   timing schedulers
    // const VNUser1InUse m_user1InUse;      (Allocated for use in SuspendableVisitor)
    // const VNUser2InUse m_user2InUse;      (Allocated for use in SuspendableVisitor)

    // STATE
    // Current context
    AstNetlist* const m_netlistp;  // Root node
    AstTopScope* const m_topScopep = m_netlistp->topScopep();  // The AstTopScope
    AstScope* const m_scopeTopp = m_topScopep->scopep();  // Scope at the top
    AstClass* m_classp = nullptr;  // Current class
    AstScope* m_scopep = nullptr;  // Current scope
    AstActive* m_activep = nullptr;  // Current active
    AstNode* m_procp = nullptr;  // NodeProcedure/CFunc/ForkItem we're under
    bool m_hasProcess = false;  // True if current scope has a VlProcess handle available
    int m_forkCnt = 0;  // Number of forks inside a module
    bool m_underProcedure = false;  // True if we are under an always or initial
    bool m_hasStaticZeroDelay = false;  // True if we have a static #0 delay
    std::vector<FileLine*> m_unknownDelayFlps;  // Locations of AstDelay with non-constant value

    // Unique names
    V3UniqueNames m_dlyforkNames{"__Vdlyfork"};  // Names for temp AssignW vars
    V3UniqueNames m_intraValueNames{"__Vintraval"};  // Intra assign delay value var names
    V3UniqueNames m_intraIndexNames{"__Vintraidx"};  // Intra assign delay index var names
    V3UniqueNames m_intraLsbNames{"__Vintralsb"};  // Intra assign delay LSB var names
    V3UniqueNames m_trigSchedNames{"__VtrigSched"};  // Trigger scheduler name generator
    V3UniqueNames m_dynTrigNames{"__VdynTrigger"};  // Dynamic trigger name generator
    V3UniqueNames m_eventCountNames{"__VeventCount"};  // Event control count var names
    V3UniqueNames m_handlePrevNames{"__VhandlePrev"};  // Handle values before writes
    // Module level temporary variables, shared by instances
    V3SharedTmps m_assignWTmps{"__VassignWtmp", VVarType::MODULETEMP};  // Delayed AssignW values
    V3SharedTmps m_assignWGens{"__VassignWgen", VVarType::MODULETEMP};  // AssignW generations

    // DTypes
    AstBasicDType* m_forkDtp = nullptr;  // Fork variable type
    AstBasicDType* m_trigSchedDtp = nullptr;  // Trigger scheduler type

    // CONSTANTS
    // Most handles in a chain of a listed wait (see notListedReason)
    static constexpr int MAX_HANDLE_LINKS = 16;
    // Why a wait whose 'iff' has effects is not listed (see notListedReason)
    static constexpr const char* IFF_EFFECTS_REASON = "'iff' with effects";

    // Timing-related globals
    AstVarScope* m_delaySchedp = nullptr;  // Global delay scheduler
    AstVarScope* m_dynamicSchedp = nullptr;  // Global dynamic trigger scheduler
    AstSenTree* m_delaySensesp = nullptr;  // Domain to trigger if a delayed coroutine is resumed
    AstSenTree* m_dynamicSensesp = nullptr;  // Domain to trigger if a dynamic trigger is set

    // Other
    SenTreeFinder m_finder{m_netlistp};  // Sentree finder and uniquifier
    // Tracked class and interface handles, if any wait on a clocking block event through handles
    const std::unique_ptr<const TimingHandleVisitor> m_handlesp;
    std::unordered_set<const AstVar*> m_waitedHandles;  // Tracked handles waited through
    SenExprBuilder* m_senExprBuilderp = nullptr;  // Sens expression builder for current m_scope

    // Stats
    size_t m_statZeroDelays = 0;  // Number of statically known #0 delays
    size_t m_statConstDelays = 0;  // Number of statically known #const (non-zero) delays
    size_t m_statVariableDelays = 0;  // Number of delays with value unknown at compile time
    size_t m_statSuspendableProcs = 0;  // Number of suspendable processes
    size_t m_statEventListWaits = 0;  // Number of event controls on an event's wait list
    size_t m_statQueueWaits = 0;  // Number of event controls on a wait queue
    size_t m_statHandleEventWaits = 0;  // Number of event controls on an interface event's list
    size_t m_statHandleWrites = 0;  // Number of writes of tracked handles notifying the scheduler
    size_t m_statHandleChangedWrites = 0;  // Number of those notifying only if the value changed
    size_t m_statHandleEffectWaits = 0;  // Number of those event controls whose 'iff' has effects
    size_t m_statHandlePolledWaits = 0;  // Number of event controls on clocking events polled

    // METHODS
    // Transform an assignment with an intra timing control into a timing control with the
    // assignment under it
    AstNodeStmt* factorOutTimingControl(AstNodeAssign* nodep) const {
        AstNodeStmt* stmtp = nodep;
        AstNode* const controlp = nodep->timingControlp();
        if (AstDelay* const delayp = VN_CAST(controlp, Delay)) {
            stmtp->replaceWith(delayp->unlinkFrBack());
            delayp->addStmtsp(stmtp);
            stmtp = delayp;
        } else if (AstSenTree* const sentreep = VN_CAST(controlp, SenTree)) {
            AstEventControl* const eventControlp
                = new AstEventControl{sentreep->fileline(), sentreep->unlinkFrBack(), nullptr};
            stmtp->replaceWith(eventControlp);
            eventControlp->addStmtsp(stmtp);
            stmtp = eventControlp;
        } else if (AstEventControl* const eventControlp = VN_CAST(controlp, EventControl)) {
            // Cycle delay from V3AssertPre
            stmtp->replaceWith(eventControlp->unlinkFrBack());
            eventControlp->addStmtsp(stmtp);
            stmtp = eventControlp;
        }
        return stmtp == nodep ? nullptr : stmtp;
    }
    static bool staticallyNonZeroDelay(const AstNodeExpr* valuep) {
        if (const AstConst* const constp = VN_CAST(valuep, Const)) return !constp->isZero();
        if (const AstCond* const condp = VN_CAST(valuep, Cond)) {
            return staticallyNonZeroDelay(condp->thenp())
                   && staticallyNonZeroDelay(condp->elsep());
        }
        if (const AstMul* const mulp = VN_CAST(valuep, Mul)) {
            const AstConst* const lhsConstp = VN_CAST(mulp->lhsp(), Const);
            const AstConst* const rhsConstp = VN_CAST(mulp->rhsp(), Const);
            if (lhsConstp && !lhsConstp->isZero()) return staticallyNonZeroDelay(mulp->rhsp());
            if (rhsConstp && !rhsConstp->isZero()) return staticallyNonZeroDelay(mulp->lhsp());
        }
        return false;
    }
    // Creates the global delay scheduler variable
    AstVarScope* getCreateDelayScheduler() {
        if (m_delaySchedp) return m_delaySchedp;
        auto* const dlySchedDtp = new AstBasicDType{
            m_scopeTopp->fileline(), VBasicDTypeKwd::DELAY_SCHEDULER, VSigning::UNSIGNED};
        m_netlistp->typeTablep()->addTypesp(dlySchedDtp);
        m_delaySchedp = m_topScopep->createTemp("__VdlySched", dlySchedDtp);
        // Delay scheduler has to be accessible from top
        m_delaySchedp->varp()->sigPublic(true);
        m_netlistp->delaySchedulerp(m_delaySchedp->varp());
        return m_delaySchedp;
    }
    // Creates the delay sentree
    AstSenTree* getCreateDelaySenTree() {
        if (m_delaySensesp) return m_delaySensesp;
        FileLine* const flp = m_scopeTopp->fileline();
        auto* const awaitingCurrentTimep
            = new AstCMethodHard{flp, new AstVarRef{flp, getCreateDelayScheduler(), VAccess::READ},
                                 VCMethod::SCHED_AWAITING_CURRENT_TIME};
        awaitingCurrentTimep->dtypeSetBit();
        m_delaySensesp
            = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_TRUE, awaitingCurrentTimep}};
        m_netlistp->topScopep()->addSenTreesp(m_delaySensesp);
        return m_delaySensesp;
    }
    // Creates the global dynamic trigger scheduler variable
    AstVarScope* getCreateDynamicTriggerScheduler() {
        if (m_dynamicSchedp) return m_dynamicSchedp;
        auto* const dynSchedDtp
            = new AstBasicDType{m_scopeTopp->fileline(), VBasicDTypeKwd::DYNAMIC_TRIGGER_SCHEDULER,
                                VSigning::UNSIGNED};
        m_netlistp->typeTablep()->addTypesp(dynSchedDtp);
        m_dynamicSchedp = m_topScopep->createTemp("__VdynSched", dynSchedDtp);
        return m_dynamicSchedp;
    }
    // Creates the dynamic trigger sentree
    AstSenTree* getCreateDynamicTriggerSenTree() {
        if (m_dynamicSensesp) return m_dynamicSensesp;
        FileLine* const flp = m_scopeTopp->fileline();
        auto* const awaitingCurrentTimep = new AstCMethodHard{
            flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::READ},
            VCMethod::SCHED_EVALUATE};
        awaitingCurrentTimep->dtypeSetBit();
        m_dynamicSensesp
            = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_TRUE, awaitingCurrentTimep}};
        m_netlistp->topScopep()->addSenTreesp(m_dynamicSensesp);
        return m_dynamicSensesp;
    }
    // Returns true if we are under a class or the given tree has any references to locals. These
    // are cases where static, globally-evaluated triggers are not suitable. A fork branch may run
    // as several processes at once, so its automatic variables are local to each process.
    bool needDynamicTrigger(AstNode* const nodep) const {
        const bool inForkItem = VN_IS(m_procp, ForkItem);
        return m_classp || nodep->exists([inForkItem](AstNode* const nodep) {
            if (AstNodeVarRef* varp = VN_CAST(nodep, NodeVarRef)) {
                return varp->varp()->isFuncLocal()
                       || (inForkItem && varp->varp()->lifetime().isAutomatic());
            }
            return !nodep->isPure();
        });
    }
    // Return the event variable if the sentree only waits on it, and its storage outlives the
    // wait, so the process can wait on the event's own list (IEEE 1800-2023 15.5), else nullptr.
    // That is static storage, a member of 'this' (kept alive by VL_KEEP_THIS), or any event when
    // events are assignable, as the list then shares ownership. An event reached through a class
    // or virtual interface handle is not listed, as the wait follows the handle if it changes
    // (IEEE 1800-2023 9.4.2). Neither is an 'iff' wait, whose condition is evaluated when the
    // event occurs (IEEE 1800-2023 9.4.2.3).
    static AstVarRef* listedEventp(const AstSenTree* const sentreep) {
        const AstSenItem* const itemp = sentreep->sensesp();
        if (itemp->nextp() || itemp->condp() || itemp->edgeType() != VEdgeType::ET_EVENT) {
            return nullptr;
        }
        AstVarRef* const refp = VN_CAST(itemp->sensp(), VarRef);
        if (!refp) return nullptr;
        const AstVar* const varp = refp->varp();
        if (varp->lifetime().isStatic() || varp->isClassMember() || v3Global.assignsEvents()) {
            return refp;
        }
        return nullptr;
    }
    // Return the wait queue if the sentree only waits on one, else nullptr. Only std::mailbox
    // has wait queues (see V3Param::markStdMailboxInternals).
    static AstVarRef* waitQueuep(const AstSenTree* const sentreep) {
        const AstSenItem* const itemp = sentreep->sensesp();
        if (itemp->nextp() || itemp->condp()) return nullptr;
        AstVarRef* const refp = VN_CAST(itemp->sensp(), VarRef);
        if (!refp) return nullptr;
        const AstBasicDType* const basicp = refp->varp()->basicp();
        if (!basicp || !basicp->isWaitQueue()) return nullptr;
        UASSERT_OBJ(refp->varp()->isInternal(), refp, "Wait queue outside std::mailbox");
        return refp;
    }
    // Create the wait of an event control on the wait list of its event, or for its turn on a
    // wait queue. The event or queue is only read: the wait list it links is runtime state of
    // the scheduler, not of the design.
    AstCAwait* createEventListWait(AstSenTree* const sentreep, AstVarRef* const eventp,
                                   const VCMethod method) {
        FileLine* const flp = sentreep->fileline();
        AstCMethodHard* const methodp = new AstCMethodHard{
            flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::WRITE}, method,
            eventp->cloneTree(false)};
        methodp->dtypeSetVoid();
        addProcessInfo(methodp);
        addEventDebugInfo(methodp, sentreep);
        return new AstCAwait{flp, methodp, getCreateDynamicTriggerSenTree()};
    }
    // Why a wait on the sentree, which waits on a clocking block event, does not wait on the wait
    // list of the event, or "" if it does
    string notListedReason(const AstSenTree* const sentreep) const {
        if (!m_handlesp->userCReason().empty()) return m_handlesp->userCReason();
        if (v3Global.usesSuspendableExports()) return TimingHandleVisitor::exportReason();
        if (!m_handlesp->orderReason().empty()) return m_handlesp->orderReason();
        const AstSenItem* const itemp = sentreep->sensesp();
        const AstMemberRef* const eventp = VN_CAST(itemp->sensp(), MemberRef);
        if (itemp->nextp() || itemp->edgeType() != VEdgeType::ET_EVENT || !eventp
            || !isClockingEvent(eventp)) {
            return "not only on a clocking block event";
        }
        // The event of a clocking block lives as long as its interface. It stays the event waited
        // on unless it is assigned another event.
        if (m_handlesp->isAssignedEvent(eventp->varp())) {
            return "the clocking block event is assigned another event";
        }
        const AstNodeExpr* linkp = eventp->fromp();
        int links = 0;
        while (const AstMemberRef* const memberp = VN_CAST(linkp, MemberRef)) {
            // The null check of a chain clones each prefix of it (see createHandleEventWait), as
            // when the trigger is evaluated, so only short chains are listed
            if (++links >= MAX_HANDLE_LINKS) {
                return "a chain of more than " + std::to_string(MAX_HANDLE_LINKS) + " handles";
            }
            if (!m_handlesp->isTracked(memberp->varp())) {
                return memberp->prettyNameQ() + " " + m_handlesp->untrackedReason(memberp->varp());
            }
            linkp = memberp->fromp();
        }
        const AstVarRef* const rootp = VN_CAST(linkp, VarRef);
        if (!rootp) return "not through variables";
        if (!m_handlesp->isTracked(rootp->varp())) {
            return rootp->prettyNameQ() + " " + m_handlesp->untrackedReason(rootp->varp());
        }
        // Its trigger is evaluated less often, which must not be observable: impure nodes, and
        // drawing a random number, which advances the random generator, are effects
        if (itemp->condp() && itemp->condp()->exists([](AstNode* const np) {
                return !np->isPure() || VN_IS(np, Rand);
            })) {
            return IFF_EFFECTS_REASON;
        }
        return "";
    }
    // Whether the event is the event of a clocking block, which the compiler creates, of a
    // virtual interface
    static bool isClockingEvent(const AstMemberRef* const refp) {
        return refp->varp()->isTemp() && VN_IS(refp->fromp()->dtypep()->skipRefp(), IfaceRefDType);
    }
    // Whether any event control waits on a clocking block event through handles
    static bool hasHandleClockingWaits(AstNetlist* const netlistp) {
        return netlistp->exists([](const AstSenItem* const itemp) {
            const AstMemberRef* const refp = VN_CAST(itemp->sensp(), MemberRef);
            return refp && isClockingEvent(refp);
        });
    }
    // Return the event if the sentree only waits on a clocking block event of a virtual
    // interface, through a chain of tracked handles (see TimingHandleVisitor), with an 'iff'
    // without effects if any, else nullptr. Then the trigger can only be set at a trigger
    // evaluation after the event fired or a tracked handle was written, so only these evaluate
    // it, in the same order as all triggers (see VlDynamicTriggerScheduler::evaluate).
    AstMemberRef* handleEventp(const AstSenTree* const sentreep) {
        if (!m_handlesp) return nullptr;
        bool onClocking = false;
        for (const AstSenItem* itemp = sentreep->sensesp(); itemp;
             itemp = VN_AS(itemp->nextp(), SenItem)) {
            const AstMemberRef* const refp = VN_CAST(itemp->sensp(), MemberRef);
            onClocking = onClocking || (refp && isClockingEvent(refp));
        }
        if (!onClocking) return nullptr;
        const string reason = notListedReason(sentreep);
        if (!reason.empty()) {
            UINFO(4, "Polled, " << reason << ", wait at " << sentreep->fileline());
            if (reason == IFF_EFFECTS_REASON) ++m_statHandleEffectWaits;
            ++m_statHandlePolledWaits;
            return nullptr;
        }
        return VN_AS(sentreep->sensesp()->sensp(), MemberRef);
    }
    // Create the await of the trigger evaluation of an event control on an event of a virtual
    // interface: while the handles are set, await the wait list of the event, else the evaluation
    // step. Either way the trigger is then evaluated as usual.
    AstIf* createHandleEventWait(AstSenTree* const sentreep, AstMemberRef* const eventp,
                                 AstCAwait* const evalAwaitp) {
        FileLine* const flp = sentreep->fileline();
        ++m_statHandleEventWaits;
        // The handles are set if each is not null, as when the trigger is evaluated
        AstNodeExpr* const setp = SenExprBuilder::newNullGuard(eventp);
        UASSERT_OBJ(setp, eventp, "No handle to check");
        for (AstNodeExpr* linkp = eventp->fromp(); linkp;) {
            AstMemberRef* const memberp = VN_CAST(linkp, MemberRef);
            const AstVar* const varp = memberp ? memberp->varp() : VN_AS(linkp, VarRef)->varp();
            m_waitedHandles.emplace(varp);
            linkp = memberp ? memberp->fromp() : nullptr;
        }
        AstCMethodHard* const methodp = new AstCMethodHard{
            flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::WRITE},
            VCMethod::SCHED_EVENT_EVALUATION, eventp->cloneTree(false)};
        methodp->dtypeSetVoid();
        addProcessInfo(methodp);
        addEventDebugInfo(methodp, sentreep);
        return new AstIf{flp, setp, new AstCAwait{flp, methodp, getCreateDynamicTriggerSenTree()},
                         evalAwaitp};
    }
    // Notify the dynamic trigger scheduler after each write of a tracked handle waited through.
    // Done after the transformation, which may delete or copy writes. The notification only sets
    // an atomic flag, so logic writing such a handle may still run in parallel MTasks (see
    // V3OrderMTaskFixHazards).
    void notifyHandleWrites() {
        if (m_waitedHandles.empty()) return;
        std::vector<std::pair<AstNodeStmt*, AstScope*>> writeps;
        std::unordered_set<const AstNodeStmt*> collected;
        const auto collect = [&](AstNodeStmt* const stmtp, AstScope* const scopep) {
            if (!collected.emplace(stmtp).second) return;
            bool notify = false;
            TimingHandleVisitor::foreachTrackedWrite(
                stmtp,
                [](AstCFunc* const funcp) {
                    UDEBUGONLY(UASSERT_OBJ(callSuspends(funcp) == funcp->isCoroutine(), funcp,
                                           "Suspending call not a coroutine, or the reverse"););
                    return callSuspends(funcp);
                },
                [&](const AstNodeExpr*, const AstVar* varp) {
                    // Also for an automatic variable of a task, which the branches of a fork
                    // within it may share, so another process may wait through it
                    notify = notify || m_waitedHandles.count(varp);
                });
            if (notify) writeps.emplace_back(stmtp, scopep);
        };
        m_netlistp->foreach([&](AstScope* const scopep) {
            scopep->foreach([&](AstAssign* const assignp) { collect(assignp, scopep); });
            scopep->foreach([&](AstStmtExpr* const stmtp) { collect(stmtp, scopep); });
        });
        m_netlistp->foreach([&](AstAssign* const assignp) { collect(assignp, nullptr); });
        m_netlistp->foreach([&](AstStmtExpr* const stmtp) { collect(stmtp, nullptr); });
        for (const auto& pair : writeps) {
            AstNodeStmt* const stmtp = pair.first;
            FileLine* const flp = stmtp->fileline();
            // Only a read, as the notification is safe in parallel MTasks
            AstCMethodHard* const methodp = new AstCMethodHard{
                flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::READ},
                VCMethod::SCHED_HANDLES_WRITTEN};
            methodp->dtypeSetVoid();
            if (AstNodeExpr* const changedp = makeHandleChanged(stmtp, pair.second)) {
                ++m_statHandleChangedWrites;
                stmtp->addNextHere(new AstIf{flp, changedp, methodp->makeStmt()});
            } else {
                stmtp->addNextHere(methodp->makeStmt());
            }
        }
        m_statHandleWrites += writeps.size();
    }
    // For a blocking assignment of a waited handle variable as a whole, not of a member, which
    // the write may move, with a pure value, save the variable before the assignment, and return
    // whether the assignment changed it, else nullptr. A handle written its own value reaches no
    // other event, so the waits through it need not evaluate their triggers, as in a loop like
    // 'forever begin vif = m_cfg.vif; @(vif.cb); ... end'.
    AstNodeExpr* makeHandleChanged(AstNodeStmt* const stmtp, AstScope* const scopep) {
        AstAssign* const assignp = VN_CAST(stmtp, Assign);
        if (!assignp || !scopep) return nullptr;
        AstVarRef* const lhsp = VN_CAST(assignp->lhsp(), VarRef);
        if (!lhsp || !lhsp->access().isWriteOrRW()) return nullptr;
        if (assignp->rhsp()->exists([](AstNode* const np) { return !np->isPure(); })) {
            return nullptr;
        }
        FileLine* const flp = assignp->fileline();
        AstVarScope* const prevVscp = createTemp(flp, m_handlePrevNames.get(lhsp), lhsp->dtypep(),
                                                 addCLocalScope(flp, assignp), scopep);
        assignp->addHereThisAsNext(
            new AstAssign{flp, new AstVarRef{flp, prevVscp, VAccess::WRITE},
                          new AstVarRef{flp, lhsp->varScopep(), VAccess::READ}});
        return new AstNeq{flp, new AstVarRef{flp, lhsp->varScopep(), VAccess::READ},
                          new AstVarRef{flp, prevVscp, VAccess::READ}};
    }
    // Creates a trigger scheduler variable
    AstVarScope* getCreateTriggerSchedulerp(AstSenTree* const sentreep) {
        if (!sentreep->user1p()) {
            if (!m_trigSchedDtp) {
                m_trigSchedDtp
                    = new AstBasicDType{m_scopeTopp->fileline(), VBasicDTypeKwd::TRIGGER_SCHEDULER,
                                        VSigning::UNSIGNED};
                m_netlistp->typeTablep()->addTypesp(m_trigSchedDtp);
            }
            AstVarScope* const trigSchedp
                = m_topScopep->createTemp(m_trigSchedNames.get(sentreep), m_trigSchedDtp);
            sentreep->user1p(trigSchedp);
        }
        return VN_AS(sentreep->user1p(), VarScope);
    }
    // Creates a string describing the sentree
    AstCExpr* createEventDescription(AstSenTree* const sentreep) const {
        if (!sentreep->user2p()) {
            std::stringstream ss;
            V3EmitV::verilogForTree(sentreep, ss);
            // possibly a multiline string
            // Names were hashed by V3Name, show the user the original text
            std::string comment = VName::dehash(ss.str());
            std::replace(comment.begin(), comment.end(), '\n', ' ');
            // Escape quotes, e.g. from string-indexed event array selects
            comment = '"' + V3OutFormatter::quoteNameControls(comment) + '"';
            AstCExpr* const commentp = new AstCExpr{sentreep->fileline(), comment};
            commentp->dtypeSetString();
            sentreep->user2p(commentp);
            return commentp;
        }
        return VN_AS(sentreep->user2p(), CExpr)->cloneTree(false);
    }
    // Adds debug info to a hardcoded method call
    void addDebugInfo(AstCMethodHard* const methodp) const {
        FileLine* const flp = methodp->fileline();
        const bool protectIds = v3Global.opt.protectIds();
        AstCExpr* const ap = new AstCExpr{flp, protectIds ? "VL_UNKNOWN_FILENAME"
                                                          : '"' + flp->filenameEsc() + '"'};
        ap->dtypeSetString();
        methodp->addPinsp(ap);
        AstCExpr* const bp = new AstCExpr{flp, protectIds ? "0" : cvtToStr(flp->lineno())};
        bp->dtypeSetString();
        methodp->addPinsp(bp);
    }
    // Adds debug info to a trigSched.trigger() call
    void addEventDebugInfo(AstCMethodHard* const methodp, AstSenTree* const sentreep) const {
        if (v3Global.opt.protectIds()) {
            FileLine* const flp = sentreep->fileline();
            AstCExpr* const descp = new AstCExpr{flp, "VL_UNKNOWN_FILENAME"};
            descp->dtypeSetString();
            methodp->addPinsp(descp);
            addDebugInfo(methodp);
            return;
        }
        methodp->addPinsp(createEventDescription(sentreep));
        addDebugInfo(methodp);
    }
    // Adds process pointer to a hardcoded method call
    void addProcessInfo(AstCMethodHard* const methodp) const {
        FileLine* const flp = methodp->fileline();
        AstCExpr* const ap
            = new AstCExpr{flp, (m_procp && m_hasProcess) ? "vlProcess" : "nullptr"};
        methodp->addPinsp(ap);
    }
    // Creates the fork handle type and returns it
    AstBasicDType* getCreateForkSyncDTypep() {
        if (m_forkDtp) return m_forkDtp;
        m_forkDtp = new AstBasicDType{m_scopeTopp->fileline(), VBasicDTypeKwd::FORK_SYNC,
                                      VSigning::UNSIGNED};
        m_netlistp->typeTablep()->addTypesp(m_forkDtp);
        return m_forkDtp;
    }
    // Move `nodep` into `AstCLocalScope`.
    AstCLocalScope* addCLocalScope(FileLine* const flp, AstNodeStmt* const nodep) const {
        if (!nodep) return nullptr;
        VNRelinker handle;
        nodep->unlinkFrBack(&handle);
        AstCLocalScope* const cscopep = new AstCLocalScope{flp, nodep};
        handle.relink(cscopep);
        return cscopep;
    }
    // Create a temp variable and optionally put it in the specified local scope (mark local if so)
    AstVarScope* createTemp(FileLine* const flp, const std::string& name,
                            AstNodeDType* const dtypep, AstCLocalScope* const cscopep = nullptr,
                            AstScope* scopep = nullptr) {
        if (!scopep) scopep = m_scopep;
        AstVar* varp;
        if (cscopep) {
            varp = new AstVar{flp, VVarType::BLOCKTEMP, name, dtypep};
            varp->funcLocal(true);
            cscopep->addVarsp(varp);
        } else {
            varp = new AstVar{flp, VVarType::MODULETEMP, name, dtypep};
            scopep->modp()->addStmtsp(varp);
        }
        AstVarScope* const vscp = new AstVarScope{flp, scopep, varp};
        scopep->addVarsp(vscp);
        return vscp;
    }
    // Add a done() call on the fork sync
    void addForkDone(AstForkItem* const itemp, AstVarScope* const forkVscp) const {
        FileLine* const flp = itemp->fileline();
        auto* const donep = new AstCMethodHard{
            itemp->fileline(), new AstVarRef{flp, forkVscp, VAccess::WRITE}, VCMethod::FORK_DONE};
        donep->dtypeSetVoid();
        addDebugInfo(donep);
        itemp->addStmtsp(donep->makeStmt());
    }
    static bool hasDisableQueuePushSelfPrefix(AstForkItem* const itemp) {
        // LinkJump prepends disable-by-name registration as:
        //   __VprocessQueue_*.push_back(std::process::self())
        // V3LiftExpr lifts std::process::self() into an assignment to a temporary, then V3Task
        // lowers that assignment's function call into a leading comment and AstStmtExpr. Thus the
        // push_back is no longer necessarily the first statement. Scan across this generated
        // prefix for it, stopping at the fork-start sentinel or the branch body. Registrations for
        // nested forks live in sub-blocks and so are not in this statement list.
        for (AstNode* const stmtp : itemp->stmtspList()) {
            if (VN_IS(stmtp, Comment)) continue;
            AstStmtExpr* const stmtExprp = VN_CAST(stmtp, StmtExpr);
            if (!stmtExprp) break;
            if (stmtExprp->isDisableQueuePushSelfStmt()) return true;
        }
        return false;
    }
    // Register a callback so killing a process-backed fork branch decrements the join counter
    void addForkOnKill(AstForkItem* const itemp, AstVarScope* const forkVscp) const {
        if (!itemp->needsVlProcess() && !hasDisableQueuePushSelfPrefix(itemp)) return;
        FileLine* const flp = itemp->fileline();
        AstCMethodHard* const onKillp = new AstCMethodHard{
            flp, new AstVarRef{flp, forkVscp, VAccess::WRITE}, VCMethod::FORK_ON_KILL};
        onKillp->dtypeSetVoid();
        AstCExpr* const processp = new AstCExpr{flp, "vlProcess"};
        processp
            ->dtypeSetVoid();  // Opaque process reference; type is irrelevant for hardcoded emit
        onKillp->addPinsp(processp);
        AstNodeStmt* const stmtp = onKillp->makeStmt();
        itemp->prependStmtsp(stmtp);
    }
    // Handle the 'join' part of a fork..join
    void makeForkJoin(AstFork* const forkp) {
        // Create a fork sync var
        FileLine* const flp = forkp->fileline();
        // Declare the sync var in a scope around the fork. Make sure all references to the fork
        // var are contained within a single scope to prevent moving statements accessing it in
        // case of large functions splitting.
        AstCLocalScope* const cscopep = addCLocalScope(flp, forkp);
        AstVarScope* forkVscp
            = createTemp(flp, forkp->name() + "__sync", getCreateForkSyncDTypep(), cscopep);
        unsigned joinCount = 0;  // Needed for join counter
        // Add a <fork sync>.done() to each fork item
        for (AstForkItem* const itemp : forkp->forkspList()) {
            addForkOnKill(itemp, forkVscp);
            addForkDone(itemp, forkVscp);
            joinCount++;
        }
        if (forkp->joinType().joinAny()) joinCount = 1;
        // Set the join counter
        auto* const initp = new AstCMethodHard{flp, new AstVarRef{flp, forkVscp, VAccess::WRITE},
                                               VCMethod::FORK_INIT, new AstConst{flp, joinCount}};
        initp->dtypeSetVoid();
        addProcessInfo(initp);
        forkp->addHereThisAsNext(initp->makeStmt());
        // Await the join at the end
        auto* const joinp = new AstCMethodHard{flp, new AstVarRef{flp, forkVscp, VAccess::WRITE},
                                               VCMethod::FORK_JOIN};
        joinp->dtypeSetVoid();
        addProcessInfo(joinp);
        addDebugInfo(joinp);
        forkp->addNextHere(new AstCAwait{flp, joinp});
    }

    // `procp` shall be a NodeProcedure/CFunc/ForkItem, in which the vars from `varsp` are placed.
    // `varsp` vector of vars which shall be localized.
    static void localizeVars(AstNode* const procp, const std::vector<AstVar*>& varsp) {
        UASSERT(procp, "procp is nullptr");
        // A process is not re-entered, so its vars can stay in the module
        if (VN_IS(procp, NodeProcedure)) return;
        AstVar* newVarsp = nullptr;
        for (AstVar* const varp : varsp) {
            varp->funcLocal(true);
            newVarsp = AstNode::addNextNull(newVarsp, varp->unlinkFrBack());
        }
        if (AstCFunc* const cfuncp = VN_CAST(procp, CFunc)) {
            cfuncp->prependVarsp(newVarsp);
        } else if (AstForkItem* const itemp = VN_CAST(procp, ForkItem)) {
            itemp->addDeclsp(newVarsp);
        } else {
            procp->v3fatalSrc(
                procp->prettyNameQ()
                << " is not of an expected type NodeProcedure/CFunc/ForkItem instead it is: "
                << procp->prettyTypeNameQ());
        }
    }

    AstNodeExpr* delayToIntegral(AstDelay* nodep, AstNodeExpr* valuep) {
        const AstConst* const constp = VN_CAST(valuep, Const);
        // The fork start sentinel is already in ticks
        if (constp && constp->toUQuad() == std::numeric_limits<uint64_t>::max()) return valuep;
        return V3Timing::delayToTicks(valuep, nodep->timeunit());
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        UASSERT_OBJ(!m_classp, nodep, "Module or class under class");
        VL_RESTORER(m_classp);
        m_classp = VN_CAST(nodep, Class);
        VL_RESTORER(m_forkCnt);
        m_forkCnt = 0;
        iterateChildren(nodep);
    }
    void visit(AstScope* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        SenExprBuilder senExprBuilder{m_scopep};
        {  // Restore m_senExprBuilderp before destroying senExprBuilder
            VL_RESTORER(m_senExprBuilderp);
            m_senExprBuilderp = &senExprBuilder;
            iterateChildren(nodep);
        }
    }
    void visit(AstActive* nodep) override {
        VL_RESTORER(m_activep);
        m_activep = nodep;
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_procp);
        VL_RESTORER(m_hasProcess);
        m_procp = nodep;
        m_hasProcess = hasFlags(nodep, T_HAS_PROC);
        VL_RESTORER(m_underProcedure);
        m_underProcedure = true;
        iterateChildren(nodep);
        if (hasFlags(nodep, T_SUSPENDEE)) {
            nodep->setSuspendable();
            ++m_statSuspendableProcs;
        }
        if (hasFlags(nodep, T_HAS_PROC)) nodep->setNeedsVlProcess();
    }
    void visit(AstInitial* nodep) override {
        if (nodep->user1SetOnce()) return;
        visit(static_cast<AstNodeProcedure*>(nodep));
        if (nodep->needsVlProcess()) {
            nodep->addStmtsp(
                new AstCStmt{nodep->fileline(), "vlProcess->state(VlProcess::FINISHED);"});
        }
    }
    void visit(AstAlways* nodep) override {
        if (v3Global.usesSuspendableExports() && hasFlags(nodep, T_DPI_CALL)) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: Potentially suspending DPI import in always process.");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        VL_RESTORER(m_procp);
        VL_RESTORER(m_hasProcess);
        m_procp = nodep;
        m_hasProcess = hasFlags(nodep, T_HAS_PROC);
        VL_RESTORER(m_underProcedure);
        m_underProcedure = true;
        // Workaround for killing `always` processes (doing that is pretty much UB)
        // TODO: Disallow killing `always` at runtime (throw an error)
        // Skip for combinational blocks; if the body has timing controls
        // iterateChildren will add T_SUSPENDEE, otherwise it would spin.
        if (hasFlags(nodep, T_HAS_PROC)
            && !(m_activep && m_activep->sentreep() && m_activep->sentreep()->hasCombo()))
            addFlags(nodep, T_SUSPENDEE);

        iterateChildren(nodep);
        if (hasFlags(nodep, T_HAS_PROC)) nodep->setNeedsVlProcess();
        if (!hasFlags(nodep, T_SUSPENDEE)) return;
        FileLine* const flp = nodep->fileline();
        AstSenTree* const sentreep = m_activep->sentreep();
        if (sentreep->hasClocked()) {
            AstNodeStmt* const bodysp = nodep->stmtsp()->unlinkFrBackWithNext();
            auto* const controlp = new AstEventControl{flp, sentreep->cloneTree(false), bodysp};
            nodep->addStmtsp(controlp);
            iterate(controlp);
        }
        // A suspendable 'always' is an 'initial forever', which stops on $finish
        AstLoop* const loopp = new AstLoop{flp};
        loopp->addStmtsp(new AstLoopTest{
            flp, loopp, new AstCExpr{flp, "VL_LIKELY(!vlSymsp->_vm_contextp__->gotFinish())", 1}});
        loopp->addStmtsp(nodep->stmtsp()->unlinkFrBackWithNext());
        AstInitial* const initialp = new AstInitial{flp, loopp};
        initialp->user1(true);  // Already processed
        initialp->setSuspendable();
        ++m_statSuspendableProcs;
        if (nodep->needsVlProcess()) initialp->setNeedsVlProcess();
        auto* const activep = new AstActive{
            flp, "", new AstSenTree{flp, new AstSenItem{flp, AstSenItem::Initial{}}}};
        activep->senTreeStorep(activep->sentreep());
        activep->addProcsp(initialp);
        m_activep->addNextHere(activep);
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }
    void visit(AstCFunc* nodep) override {
        VL_RESTORER(m_procp);
        VL_RESTORER(m_hasProcess);
        m_procp = nodep;
        m_hasProcess = hasFlags(nodep, T_HAS_PROC);
        iterateChildren(nodep);
        if (hasFlags(nodep, T_HAS_PROC)) nodep->setNeedsVlProcess();
        if (!hasFlags(nodep, T_SUSPENDEE)) return;

        nodep->rtnType("VlCoroutine");
        // If in a class, create a shared pointer to 'this'
        if (m_classp) {
            AstCStmt* const cstmtp
                = new AstCStmt{nodep->fileline(), "VL_KEEP_THIS;", VCStmtType::KEEP_THIS};
            nodep->prependStmtsp(cstmtp);
        }
    }
    void visit(AstCFuncHard* nodep) override {
        if (nodep->function() == VCFunction::CALL_IMPORT_FUNCTION
            || nodep->function() == VCFunction::CALL_IMPORT_TASK) {
            if (m_hasProcess) {
                AstCExpr* const processp = VN_AS(nodep->pinsp(), CExpr);
                processp->replaceWith(new AstCExpr{nodep->fileline(), "vlProcess"});
                VL_DO_DANGLING(pushDeletep(processp), processp);
            }
        }
        if (nodep->function() == VCFunction::CALL_IMPORT_TASK) {
            // Do not use awaitable DPI dispatcher, if there are no suspendable DPI exports
            if (!v3Global.usesSuspendableExports()) return;
            // Only emit awaitable dispatcher when the enclosing scope can suspend
            if (!hasFlags(m_procp, T_SUSPENDEE)) return;
            AstStmtExpr* const stmtExprp = VN_AS(nodep->backp(), StmtExpr);
            nodep->function(VCFunction::AWAIT_IMPORT_TASK);
            AstCFuncHard* const cFuncp = nodep->unlinkFrBack();
            stmtExprp->replaceWith(new AstCAwait{nodep->fileline(), cFuncp});
            VL_DO_DANGLING(pushDeletep(stmtExprp), stmtExprp);
        }
    }
    void visit(AstNodeCCall* nodep) override {
        AstCFunc* const funcp = nodep->funcp();

        // Skip automatic covergroup sampling calls
        if (funcp->isCovergroupSample()) {
            iterateChildren(nodep);
            return;
        }

        if (funcp->needsVlProcess()) m_hasProcess = true;
        if (hasFlags(funcp, T_SUSPENDEE) && !nodep->user1SetOnce()) {  // If suspendable
            // Calls to suspendables are always void return type, hence parent must be StmtExpr
            AstStmtExpr* const stmtp = VN_AS(nodep->backp(), StmtExpr);
            stmtp->replaceWith(new AstCAwait{nodep->fileline(), nodep->unlinkFrBack()});
            VL_DO_DANGLING(pushDeletep(stmtp), stmtp);
        }
        iterateChildren(nodep);
    }
    void visit(AstDelay* nodep) override {
        UASSERT_OBJ(!nodep->isCycleDelay(), nodep,
                    "Cycle delays should have been handled in V3AssertPre");
        FileLine* const flp = nodep->fileline();

        AstNodeExpr* valuep = delayToIntegral(nodep, nodep->lhsp()->unlinkFrBack());

        // Statistics
        if (valuep->isZero()) {
            ++m_statZeroDelays;
        } else if (VN_IS(valuep, Const)) {
            ++m_statConstDelays;
        } else {
            ++m_statVariableDelays;
        }

        // Decide scheduling support for #0
        if (v3Global.opt.schedZeroDelay().isSetTrue()) {
            // User said to schedule for #0 support, nothing else to do
            v3Global.setUsesZeroDelay();
        } else if (v3Global.opt.schedZeroDelay().isSetFalse()) {
            // User said to schedule without #0 support. Still warn if a static #0 delay exists
            if (valuep->isZero()) {
                nodep->v3warn(
                    ZERODLY,
                    "Static #0 delay exists, but '--no-sched-zero-delay' was given.\n"
                        << nodep->warnMore()  //
                        << "... Can proceed, but this will fail at runtime if executed.");
            }
        } else {
            // User did not express preference, decide based on presence of delays
            if (valuep->isZero()) {
                // Statically known #0 delay exists, schedule for #0 support
                v3Global.setUsesZeroDelay();
                m_hasStaticZeroDelay = true;
                // Don't warn on variable delays, as no point
                m_unknownDelayFlps.clear();
            } else if (staticallyNonZeroDelay(valuep)) {
                // Delay is dynamic, but every statically known outcome is non-zero.
                // So we don't need #0 delay support and there should be no warning.
            } else if (!VN_IS(valuep, Const)) {
                // Delay is not known at compiile time. Conservatively schedule for #0 support,
                // but warn if no static #0 delays used as performance might be improved
                v3Global.setUsesZeroDelay();
                if (!m_hasStaticZeroDelay) m_unknownDelayFlps.push_back(nodep->fileline());
            }
        }

        // Replace self with a 'co_await dlySched.delay(<valuep>)'
        AstCMethodHard* const delayMethodp = new AstCMethodHard{
            flp, new AstVarRef{flp, getCreateDelayScheduler(), VAccess::WRITE},
            VCMethod::SCHED_DELAY, valuep};
        delayMethodp->dtypeSetVoid();
        addProcessInfo(delayMethodp);
        addDebugInfo(delayMethodp);
        // Create the co_await
        AstNode* const awaitp = new AstCAwait{flp, delayMethodp, getCreateDelaySenTree()};
        // Relink child statements after the co_await
        if (AstNode* const stmtsp = nodep->stmtsp()) {
            awaitp->addNext(stmtsp->unlinkFrBackWithNext());
        }
        nodep->replaceWith(awaitp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstEventControl* nodep) override {
        // Do not allow waiting on local named events, as they get enqueued for clearing, but can
        // go out of scope before that happens
        if (!nodep->sentreep()) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: Event control with implicit sensitivity (@*)"
                          " in this context; use an explicit sensitivity list instead");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        FileLine* const flp = nodep->fileline();
        if (AstNodeExpr* const countp = nodep->countp()) {
            // Wait for the event as many times, counted in a variable of this process, as a
            // cycle delay of a pending synchronous drive runs in parallel with others
            AstVarScope* const cntVscp
                = createTemp(flp, m_eventCountNames.get(nodep), countp->dtypep());
            localizeVars(m_procp, {cntVscp->varp()});
            AstNode* const stmtsp
                = nodep->stmtsp() ? nodep->stmtsp()->unlinkFrBackWithNext() : nullptr;
            AstAssign* const initp = new AstAssign{
                flp, new AstVarRef{flp, cntVscp, VAccess::WRITE}, countp->unlinkFrBack()};
            nodep->replaceWith(initp);
            AstLoop* const loopp = new AstLoop{flp};
            loopp->addStmtsp(new AstLoopTest{
                flp, loopp,
                new AstGt{flp, new AstVarRef{flp, cntVscp, VAccess::READ}, new AstConst{flp, 0}}});
            loopp->addStmtsp(nodep);
            loopp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, cntVscp, VAccess::WRITE},
                              new AstSub{flp, new AstVarRef{flp, cntVscp, VAccess::READ},
                                         new AstConst{flp, 1}}});
            initp->addNextHere(loopp);
            if (stmtsp) loopp->addNextHere(stmtsp);
            // The loop is visited next, as the replacement of this event control
            return;
        }
        // Relink child statements after the event control
        if (nodep->stmtsp()) nodep->addNextHere(nodep->stmtsp()->unlinkFrBackWithNext());
        if (AstVarRef* const queuep = waitQueuep(nodep->sentreep())) {
            ++m_statQueueWaits;
            nodep->replaceWith(
                createEventListWait(nodep->sentreep(), queuep, VCMethod::SCHED_QUEUE_WAIT));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        const bool dynamic = needDynamicTrigger(nodep->sentreep());
        if (AstVarRef* const eventp = dynamic ? listedEventp(nodep->sentreep()) : nullptr) {
            ++m_statEventListWaits;
            nodep->replaceWith(
                createEventListWait(nodep->sentreep(), eventp, VCMethod::SCHED_EVENT_TRIGGER));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (dynamic) {
            // Create the trigger variable and init it with 0
            AstVarScope* const trigvscp
                = createTemp(flp, m_dynTrigNames.get(nodep), nodep->findBitDType());
            localizeVars(m_procp, {trigvscp->varp()});
            auto* const initp = new AstAssign{flp, new AstVarRef{flp, trigvscp, VAccess::WRITE},
                                              new AstConst{flp, AstConst::BitFalse{}}};
            // Await the eval step with the dynamic trigger scheduler. First, create the method
            // call
            auto* const evalMethodp = new AstCMethodHard{
                flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::WRITE},
                VCMethod::SCHED_EVALUATION};
            evalMethodp->dtypeSetVoid();
            addProcessInfo(evalMethodp);
            auto* const sentreep = nodep->sentreep();
            addEventDebugInfo(evalMethodp, sentreep);
            // Create the co_await
            AstCAwait* const awaitEvalp
                = new AstCAwait{flp, evalMethodp, getCreateDynamicTriggerSenTree()};
            // Construct the sen expression for this sentree
            UASSERT_OBJ(m_senExprBuilderp, nodep, "No SenExprBuilder for this scope");
            auto* const assignp = new AstAssign{flp, new AstVarRef{flp, trigvscp, VAccess::WRITE},
                                                m_senExprBuilderp->build(sentreep).first};
            // Get the SenExprBuilder results
            const SenExprBuilder::Results senResults = m_senExprBuilderp->getAndClearResults();
            localizeVars(m_procp, senResults.m_vars);
            // If post updates are destructive (e.g. clearFired on events), perform a
            // conservative pre-clear once before entering the wait loop so stale state from a
            // previous wait does not cause an immediate false-positive trigger.
            const bool hasDestructivePostUpdates = !senResults.m_destructivePostUpdates.empty();
            // Create the trigger eval loop, which will await the evaluation step and check the
            // trigger
            AstNodeExpr* const condp
                = new AstLogNot{flp, new AstVarRef{flp, trigvscp, VAccess::READ}};
            AstLoop* const loopp = new AstLoop{flp};
            loopp->addStmtsp(new AstLoopTest{flp, loopp, condp});
            AstMemberRef* const handleEventRefp = handleEventp(sentreep);
            loopp->addStmtsp(handleEventRefp
                                 ? createHandleEventWait(sentreep, handleEventRefp, awaitEvalp)
                                 : static_cast<AstNodeStmt*>(awaitEvalp));
            // Put pre updates before the trigger check and assignment
            for (AstNodeStmt* const stmtp : senResults.m_preUpdates) loopp->addStmtsp(stmtp);
            // Then the trigger check and assignment
            loopp->addStmtsp(assignp);
            // Let the dynamic trigger scheduler know if this trigger was set
            // If it was, a call to the scheduler's evaluate() will return true
            AstCMethodHard* const anyTriggeredMethodp = new AstCMethodHard{
                flp, new AstVarRef{flp, getCreateDynamicTriggerScheduler(), VAccess::WRITE},
                VCMethod::SCHED_ANY_TRIGGERED, new AstVarRef{flp, trigvscp, VAccess::READ}};
            anyTriggeredMethodp->dtypeSetVoid();
            loopp->addStmtsp(anyTriggeredMethodp->makeStmt());
            // If the post update is destructive (e.g. event vars are cleared), create an await for
            // the post update step
            if (hasDestructivePostUpdates) {
                AstCAwait* const awaitPostUpdatep = awaitEvalp->cloneTree(false);
                VN_AS(awaitPostUpdatep->exprp(), CMethodHard)->method(VCMethod::SCHED_POST_UPDATE);
                loopp->addStmtsp(awaitPostUpdatep);
            }
            // Put the post updates at the end of the loop
            for (AstNodeStmt* const stmtp : senResults.m_postUpdates) loopp->addStmtsp(stmtp);
            // Finally, await the resumption step in 'act'
            AstCAwait* const awaitResumep = awaitEvalp->cloneTree(false);
            VN_AS(awaitResumep->exprp(), CMethodHard)->method(VCMethod::SCHED_RESUMPTION);
            AstNode::addNext<AstNodeStmt, AstNodeStmt>(loopp, awaitResumep);
            // Replace the event control with one explicit stmt chain:
            //   init -> [inits] -> [optional destructive pre-clears] -> loop -> awaitResumption
            AstNodeStmt* chainp = nullptr;
            chainp = AstNode::addNextNull(chainp, initp);
            for (AstNodeStmt* const stmtp : senResults.m_inits) {
                chainp = AstNode::addNextNull(chainp, stmtp);
            }
            if (hasDestructivePostUpdates) {
                for (AstNodeStmt* const stmtp : senResults.m_destructivePostUpdates) {
                    chainp = AstNode::addNextNull(chainp, stmtp->cloneTree(false));
                }
            }
            chainp = AstNode::addNextNull(chainp, loopp);
            nodep->replaceWith(chainp);
        } else {
            auto* const sentreep = m_finder.getSenTree(nodep->sentreep());
            nodep->sentreep()->unlinkFrBack()->deleteTree();
            // Get this sentree's trigger scheduler
            // Replace self with a 'co_await trigSched.trigger()'
            auto* const triggerMethodp = new AstCMethodHard{
                flp, new AstVarRef{flp, getCreateTriggerSchedulerp(sentreep), VAccess::WRITE},
                VCMethod::SCHED_TRIGGER};
            triggerMethodp->dtypeSetVoid();
            // If it should be committed immediately, pass true, otherwise false
            triggerMethodp->addPinsp(nodep->user2() ? new AstConst{flp, AstConst::BitTrue{}}
                                                    : new AstConst{flp, AstConst::BitFalse{}});
            addProcessInfo(triggerMethodp);
            addEventDebugInfo(triggerMethodp, sentreep);
            // Create the co_await
            AstCAwait* const awaitp = new AstCAwait{flp, triggerMethodp, sentreep};
            nodep->replaceWith(awaitp);
        }
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstNodeAssign* nodep) override {
        // Only process once to avoid infinite loops (due to the net delay)
        if (nodep->user1SetOnce()) return;
        UINFO(9, "control-visit " << nodep);
        FileLine* const flp = nodep->fileline();
        AstNodeStmt* controlp = factorOutTimingControl(nodep);
        const bool inAssignDly = VN_IS(nodep, AssignDly);
        // Handle the intra assignment timing control
        if (!controlp) {
            iterateChildren(nodep);
            return;
        }
        // The timing control, which is put in a fork for an NBA
        AstNode* const timingp = controlp;
        // The new vars are locals if we're in a function.
        // These intra-assignment vars will later be passed to forked processes by value.
        const bool localVars = !m_underProcedure;
        // Special case for NBA
        if (inAssignDly) {
            // Put it in a fork so it doesn't block
            // Could already be the only thing directly under a fork, reuse that if possible
            AstFork* forkp = !nodep->nextp() ? VN_CAST(nodep->firstAbovep(), Fork) : nullptr;
            if (!forkp) forkp = new AstFork{flp, VJoinType::JOIN_NONE};
            controlp->replaceWith(forkp);
            AstForkItem* const itemp = new AstForkItem{nodep->fileline(), controlp};
            forkp->addForksp(itemp);
            addFlags(itemp, T_NBA_UPDATE);
            controlp = forkp;
        }
        UASSERT_OBJ(nodep, controlp, "Assignment should have timing control");
        // Function for replacing values with intermediate variables
        const auto replaceWithIntermediate
            = [&](AstNodeExpr* const valuep, const std::string& name) {
                  AstVarScope* const newvscp = createTemp(flp, name, valuep->dtypep());
                  if (localVars) {
                      localizeVars(m_procp, {newvscp->varp()});
                  } else if (inAssignDly) {
                      // A pending update keeps its own value, even if its process schedules more
                      newvscp->forkByValue(true);
                  }
                  valuep->replaceWith(new AstVarRef{flp, newvscp, VAccess::READ});
                  controlp->addHereThisAsNext(
                      new AstAssign{flp, new AstVarRef{flp, newvscp, VAccess::WRITE}, valuep});
              };
        // NBAs with delays evaluate the indices selecting the target now (IEEE 1800-2023 10.4.2),
        // in order, each as a whole, also the selects and function calls in it. So follow the
        // selects of the target up from the variable, not into their indices. As an example, this
        // transforms 'x[a[i]][f(j)] <= #1 y' into 't0 = a[i]; t1 = f(j); x[t0][t1] <= #1 y'.
        // V3Const has split NBAs to concatenations, also streamed, into NBAs to each part.
        if (inAssignDly) {
            for (AstNode* exprp = nodep->lhsp()->baseFromp(true); exprp != nodep;
                 exprp = exprp->firstAbovep()) {
                if (AstSel* const selp = VN_CAST(exprp, Sel)) {
                    // widthp should be const
                    if (!VN_IS(selp->lsbp(), Const)) {
                        replaceWithIntermediate(selp->lsbp(), m_intraLsbNames.get(nodep));
                    }
                } else if (AstNodeSel* const selp = VN_CAST(exprp, NodeSel)) {
                    if (!VN_IS(selp->bitp(), Const)) {
                        replaceWithIntermediate(selp->bitp(), m_intraIndexNames.get(nodep));
                    }
                }
            }
        }
        // Replace the RHS with an intermediate value var
        replaceWithIntermediate(nodep->rhsp(), m_intraValueNames.get(nodep));
        if (!inAssignDly) return;
        // The process executing the NBA evaluates its delay (IEEE 1800-2023 4.9.4), not the forked
        // process, if it has side effects, e.g. calling a function that checks its process. A pure
        // one is evaluated as the forked process starts, at once.
        if (AstDelay* const delayp = VN_CAST(timingp, Delay)) {
            if (!delayp->lhsp()->isPure()) {
                replaceWithIntermediate(delayp->lhsp(), m_intraValueNames.get(nodep));
            }
        }
    }
    void visit(AstAssignW* nodep) override {
        FileLine* const flp = nodep->fileline();
        // Get the net delay unless this assignment was created for handling the net delay (user1)
        AstDelay* const netDelayp = nodep->user1() ? nullptr : nodep->getLhsNetDelay();
        if (netDelayp) {
            if (nodep->timingControlp()) {
                // If this assignment has a delay, create another one to handle the net delay
                AstVarScope* const newvscp = m_assignWTmps.make(flp, m_scopep, nodep->dtypep());
                AstAssignW* assignp = new AstAssignW{
                    nodep->fileline(), nodep->lhsp()->unlinkFrBack(),
                    new AstVarRef{flp, newvscp, VAccess::READ}, netDelayp->cloneTree(false)};
                assignp->user1(true);
                nodep->addNextHere(assignp);
                nodep->lhsp(new AstVarRef{flp, newvscp, VAccess::WRITE});
            } else {
                // Else just use this one with the net delay
                nodep->timingControlp(netDelayp->cloneTree(false));
            }
        }
        if (!nodep->timingControlp()) return;
        // There will be some circular logic here, suppress the warning for newly created vars
        flp->modifyWarnOff(V3ErrorCode::UNOPTFLAT, true);
        // Also suppress the warning for the LHS var, for cases like `assign #1 clk = ~clk;`
        // TODO: Restore the warning for other, non-delayed drivers
        nodep->lhsp()->foreach([](AstVarRef* refp) {
            if (refp->access().isWriteOrRW()) {
                refp->varp()->fileline()->modifyWarnOff(V3ErrorCode::UNOPTFLAT, true);
            }
        });
        // Should be under an always
        AstAlways* const alwaysp = VN_AS(m_procp, Always);
        // Convert it to an Assign; the new assign with intra delay will be handled by
        // visit(AstNodeAssign*)
        AstNodeExpr* const lhs1p = nodep->lhsp()->unlinkFrBack();
        AstNodeExpr* const rhs1p = nodep->rhsp()->unlinkFrBack();
        AstNode* const controlp = nodep->timingControlp()->unlinkFrBack();
        if (AstDelay* const delayp = VN_CAST(controlp, Delay)) {
            if (AstNodeExpr* fallDelayp = delayp->fallDelay()) {
                fallDelayp = fallDelayp->unlinkFrBack();
                AstNodeExpr* lhsp = delayp->lhsp()->unlinkFrBack();
                // Use fall only for an all-zero value, rise otherwise.
                lhsp = delayToIntegral(delayp, lhsp);
                fallDelayp = delayToIntegral(delayp, fallDelayp);
                delayp->lhsp(
                    new AstCond{flp, new AstEq{flp, rhs1p->cloneTree(false), new AstConst{flp, 0}},
                                fallDelayp, lhsp});
                // Both values are now in ticks, so visit(AstDelay) must not scale them again
                delayp->timeunit(v3Global.rootp()->timeprecision());
            }
        }
        AstAssign* const assignp = new AstAssign{nodep->fileline(), lhs1p, rhs1p, controlp};
        // Put the assignment in a fork..join_none.
        AstFork* const forkp = new AstFork{flp, VJoinType::JOIN_NONE};
        nodep->replaceWith(forkp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        AstForkItem* const itemp = new AstForkItem{flp, assignp};
        forkp->addForksp(itemp);
        visit(forkp);  // Visit now as we need to do some post-processing
        // IEEE 1800-2023 10.3.3 - if the RHS value differs from the currently scheduled value to
        // be assigned, the currently scheduled assignment is descheduled. To keep track if an
        // assignment should be descheduled, each scheduled assignment event has a 'generation',
        // and if at assignment time its generation differs from the current generation, it won't
        // be performed
        AstAssign* const preAssignp = VN_AS(itemp->stmtsp(), Assign);
        UASSERT_OBJ(preAssignp, alwaysp, "Pre-assign should be there from visit(AstFork)");
        AstAssign* const postAssignp = VN_AS(preAssignp->nextp()->nextp(), Assign);
        UASSERT_OBJ(postAssignp, alwaysp, "Post-assign should be there from visit(AstFork)");
        // Increment generation and copy it to a local
        AstVarScope* const generationVarp
            = m_assignWGens.make(flp, m_scopep, alwaysp->findUInt64DType());
        AstVarScope* const genLocalVarp = createTemp(
            flp, generationVarp->varp()->name() + "__local", alwaysp->findUInt64DType());
        localizeVars(itemp, {genLocalVarp->varp()});
        preAssignp->addHereThisAsNext(
            new AstAssign{flp, new AstVarRef{flp, generationVarp, VAccess::WRITE},
                          new AstAdd{flp, new AstVarRef{flp, generationVarp, VAccess::READ},
                                     new AstConst{flp, 1}}});
        preAssignp->addHereThisAsNext(
            new AstAssign{flp, new AstVarRef{flp, genLocalVarp, VAccess::WRITE},
                          new AstVarRef{flp, generationVarp, VAccess::READ}});
        // If the current generation is same as the one saved in the local var, assign
        itemp->addStmtsp(
            new AstIf{flp,
                      new AstEq{flp, new AstVarRef{flp, generationVarp, VAccess::READ},
                                new AstVarRef{flp, genLocalVarp, VAccess::READ}},
                      postAssignp->unlinkFrBack()});
        // Save scheduled RHS value before delay
        AstVarScope* const tmpVarp
            = m_assignWTmps.make(flp, m_scopep, preAssignp->rhsp()->dtypep());
        AstVarRef* const tmpAssignRhsp = VN_AS(preAssignp->lhsp(), VarRef)->cloneTree(false);
        tmpAssignRhsp->access(VAccess::WRITE);
        preAssignp->addNextHere(
            new AstAssign{flp, new AstVarRef{flp, tmpVarp, VAccess::WRITE}, tmpAssignRhsp});
        // If the RHS is different from the currently scheduled value, schedule the new assignment
        // The generation will increase, effectively 'descheduling' the previous assignment.
        AstNodeExpr* const didNotInitp
            = new AstLogNot{flp, new AstCExpr{flp, "vlSymsp->__Vm_didInit", 1}};
        AstVarRef* const firstIterp
            = new AstVarRef{flp, m_netlistp->stlFirstIterationp(), VAccess::READ};
        AstNodeExpr* const schedCondp
            = new AstLogOr{flp,
                           new AstNeq{flp, preAssignp->rhsp()->cloneTree(false),
                                      new AstVarRef{flp, tmpVarp, VAccess::READ}},
                           new AstLogAnd{flp, didNotInitp, firstIterp}};
        alwaysp->addStmtsp(new AstIf{flp, schedCondp, forkp->unlinkFrBack()});
    }
    void visit(AstDeferredAssertFlush* nodep) override {
        iterateChildren(nodep);
        nodep->replaceWith(nodep->stmtsp()->unlinkFrBackWithNext());
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstDisableFork* nodep) override {
        if (m_hasProcess) return;
        // never reached by any process; remove to avoid compilation error
        VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
    }
    void visit(AstWaitFork* nodep) override {
        if (m_hasProcess) {
            FileLine* const flp = nodep->fileline();
            AstCExpr* const exprp = new AstCExpr{flp, "vlProcess->completedFork()", 1};
            AstWait* const waitp
                = new AstWait{flp, exprp, takeDeferredAssertFlush(nodep->nextp())};
            nodep->replaceWith(waitp);
        } else {
            // never reached by any process; remove to avoid compilation error
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstWait* nodep) override {
        // Wait on changed events related to the vars in the wait statement
        UINFO(9, "control-visit " << nodep);
        FileLine* const flp = nodep->fileline();
        AstDeferredAssertFlush* const flushp = takeDeferredAssertFlush(nodep->stmtsp());
        AstNode* const stmtsp = nodep->stmtsp();
        if (stmtsp) stmtsp->unlinkFrBackWithNext();
        AstNodeExpr* const condp = V3Const::constifyEdit(nodep->condp()->unlinkFrBack());
        auto* const constp = VN_CAST(condp, Const);
        if (constp) {
            if (constp->isZero()) {
                // We have to await forever instead of simply returning in case we're deep in a
                // callstack
                AstCMethodHard* const foreverMethodp = new AstCMethodHard{
                    flp, new AstVarRef{flp, getCreateDelayScheduler(), VAccess::WRITE},
                    VCMethod::SCHED_WAIT_FOREVER};
                foreverMethodp->dtypeSetVoid();
                addProcessInfo(foreverMethodp);
                addDebugInfo(foreverMethodp);
                AstCAwait* const awaitp = new AstCAwait{flp, foreverMethodp};
                nodep->replaceWith(awaitp);
                if (flushp) VL_DO_DANGLING(flushp->deleteTree(), flushp);
                if (stmtsp) VL_DO_DANGLING(stmtsp->deleteTree(), stmtsp);
                VL_DO_DANGLING(condp->deleteTree(), condp);
            } else {
                nodep->v3fatalSrc("constant wait should have been removed in "
                                  "TimingSuspendableVisitor::visit(AstWait)");
            }
        } else if (needDynamicTrigger(condp)) {
            // No point in making a sentree, just use the expression as sensitivity
            // Put the event control in an if so we only wait if the condition isn't met already
            auto* const ifp = new AstIf{
                flp, new AstLogNot{flp, condp},
                new AstEventControl{flp,
                                    new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_TRUE,
                                                                       condp->cloneTree(false)}},
                                    flushp}};
            if (stmtsp) AstNode::addNext<AstNode, AstNode>(ifp, stmtsp);
            nodep->replaceWith(ifp);
        } else {
            // We are using a global sentree, so we cannot use ET_TRUE, as that could lead to the
            // active region never converging. Because of this, we need to use ET_CHANGED in a
            // loop.
            AstEventControl* const controlp = new AstEventControl{
                flp,
                new AstSenTree{
                    flp, new AstSenItem{flp, VEdgeType::ET_CHANGED, condp->cloneTree(false)}},
                nullptr};
            controlp->user2(true);  // Commit immediately
            AstLoop* const loopp = new AstLoop{flp};
            loopp->addStmtsp(new AstLoopTest{flp, loopp, new AstLogNot{flp, condp}});
            loopp->addStmtsp(controlp);
            if (flushp) controlp->addStmtsp(flushp);
            if (stmtsp) AstNode::addNext<AstNode, AstNode>(loopp, stmtsp);
            nodep->replaceWith(loopp);
        }
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstForkItem* nodep) override {
        VL_RESTORER(m_procp);
        VL_RESTORER(m_hasProcess);
        m_hasProcess |= hasFlags(nodep, T_HAS_PROC);
        // A pending NBA update is not a subprocess of the process that scheduled it, so it is
        // unaffected by 'disable fork' and 'wait fork' (IEEE 1800-2023 9.6.1, 9.6.3)
        if (hasFlags(nodep, T_NBA_UPDATE)) m_hasProcess = false;
        m_procp = nodep;
        if (m_hasProcess) nodep->setNeedsVlProcess();
        iterateChildren(nodep);
    }
    void visit(AstFork* nodep) override {
        if (nodep->user1SetOnce()) return;
        UINFO(9, "control-visit " << nodep);
        v3Global.setUsesTiming();

        // Create a unique name for this fork
        nodep->name("__Vfork_" + std::to_string(++m_forkCnt));

        // TODO: Should process nodep->stmtsp() in case an earlier pass
        //       inserted something there, but as of today we don't need to.

        // Process each fork item
        for (AstForkItem* const itemp : nodep->forkspList()) {
            iterate(itemp);
            // Note: Even if we do not find any awaits, we cannot simply inline
            // the process here, as new awaits could be added later.
            if (itemp->needsVlProcess()) {
                itemp->addStmtsp(
                    new AstCStmt{itemp->fileline(), "vlProcess->state(VlProcess::FINISHED);"});
            }
        }
        if (!nodep->joinType().joinNone()) makeForkJoin(nodep);
    }

    //--------------------
    void visit(AstVar*) override {}  // Accelerate
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit TimingControlVisitor(AstNetlist* nodep)
        : m_netlistp{nodep}
        , m_handlesp{hasHandleClockingWaits(nodep) ? new TimingHandleVisitor{nodep} : nullptr} {
        iterate(nodep);
        notifyHandleWrites();
        // Order the waits awaiting trigger evaluation among the waits woken on wait lists only if
        // any wait is listed, so a design listing none pays nothing for it
        if (m_statHandleEventWaits) {
            nodep->foreach([](AstCMethodHard* const methodp) {
                if (methodp->method() == VCMethod::SCHED_EVALUATION) {
                    methodp->method(VCMethod::SCHED_EVALUATION_KEYED);
                }
            });
        }

        // If there is no static #0 in the design, but an unknown delay was found,
        // and the user did not specify preference, then warn on all unknown delays
        // as we will be assuming they can be #0, which can cause performance degradation.
        for (FileLine* const flp : m_unknownDelayFlps) {
            flp->v3warn(ZERODLY,
                        "Value of # delay control statically unknown. Assuming it can be #0.\n"
                            << flp->warnMore()  //
                            << "... If all # delays are non-zero at runtime,\n"
                            << flp->warnMore()  //
                            << "... use '--no-sched-zero-delay' for improved performance.\n"
                            << flp->warnMore()  //
                            << "... If a real #0 is expected at runtime,\n"
                            << flp->warnMore()  //
                            << "... use '--sched-zero-delay' to suppress this warning.");
        }
    }
    ~TimingControlVisitor() override {
        V3Stats::addStat("Timing, known #0 delays", m_statZeroDelays);
        V3Stats::addStat("Timing, known #const delays", m_statConstDelays);
        V3Stats::addStat("Timing, unknown #variable delays", m_statVariableDelays);
        V3Stats::addStat("Timing, suspendable processes", m_statSuspendableProcs);
        V3Stats::addStat("Timing, event controls on event wait lists", m_statEventListWaits);
        V3Stats::addStat("Timing, event controls on wait queues", m_statQueueWaits);
        V3Stats::addStat("Timing, event controls on interface events through handles",
                         m_statHandleEventWaits);
        V3Stats::addStat("Timing, writes of handles notifying event controls", m_statHandleWrites);
        V3Stats::addStat("Timing, writes of handles notifying event controls if changed",
                         m_statHandleChangedWrites);
        V3Stats::addStat("Timing, event controls through handles with 'iff' effects",
                         m_statHandleEffectWaits);
        V3Stats::addStat("Timing, event controls on clocking block events evaluated always",
                         m_statHandlePolledWaits);
        V3Stats::addStat("Timing, triggers changing the order of evaluation, keeping all polling",
                         m_handlesp && !m_handlesp->orderReason().empty() ? 1 : 0);
        V3Stats::addStat("Timing, user C++ code, keeping all polling",
                         m_handlesp && !m_handlesp->userCReason().empty() ? 1 : 0);
        V3Stats::addStat("Timing, DPI export tasks that may suspend, keeping all polling",
                         m_handlesp && v3Global.usesSuspendableExports() ? 1 : 0);
    }
};

//######################################################################
// MailboxWaitVisitor

class MailboxWaitVisitor final : public VNVisitorConst {
    // NODE STATE
    //  AstNodeFTask::user1()  -> bool. Queued to be scanned (see hiddenEffect)
    //  AstVar::user1()        -> bool. Declared in the std package
    const VNUser1InUse m_user1InUse;

    // STATE
    AstPackage* const m_stdp = v3Global.rootp()->stdPackagep();  // The std package
    bool m_inStd = false;  // Under the std package
    // If a condition or event expression may have side effects, or the design uses a variable
    // of the std package, such as a member of a mailbox, which its methods would not tell
    bool m_impure = false;
    std::vector<AstNodeFTask*> m_taskps;  // Subroutines that conditions may call, to scan
    // The ifs in the std package choosing to poll, in order
    std::vector<AstIf*> m_choiceps;
    size_t m_statTasks = 0;  // Subroutines scanned

    // METHODS
    // Notes if evaluating a condition 'nodep' may have side effects. isPure() of each node tells,
    // and of the subroutines called, as the one of a method call does not look at its receiver,
    // nor the one of an associative array select at its index, apart from what hiddenEffect()
    // looks for, which the subroutines are scanned for, once each. A select of a member, which
    // has no effect of its own, is not asked, as its isPure() asks the whole chain of selects
    // each time, so the scan is linear in the size of the design, apart from isPure() of a
    // subroutine that a condition calls, which asks each select of a chain in its body. That is
    // quadratic in the length of a chain written in the source, as for V3Const and the other
    // passes asking isPure(), which cache it per subroutine, so this computes it once more, and
    // a chain of 6400 selects takes 2 s to verilate with or without the choice.
    void scanCondition(AstNode* const nodep) {
        if (m_impure) return;
        m_impure = nodep->exists([this](AstNode* np) {
            if (VN_IS(np, MemberRef) || VN_IS(np, StructSel)) return false;
            return !np->isPure() || hiddenEffect(np);
        });
    }
    // If 'nodep' may have a side effect that isPure() does not tell: a call of a virtual method
    // may run a method overriding it, and 'disable fork' kills processes, which may resume
    // their parents. Queues a subroutine it calls to scan for these.
    bool hiddenEffect(AstNode* const nodep) {
        if (VN_IS(nodep, DisableFork)) return true;
        if (const AstNodeFTaskRef* const refp = VN_CAST(nodep, NodeFTaskRef)) {
            AstNodeFTask* const taskp = refp->taskp();
            // A call that is not linked is not pure, nor is a subroutine calling one
            UASSERT_OBJ(taskp, refp, "Unlinked call scanned");
            if (taskp->isVirtual()) return true;
            if (!taskp->user1()) {
                taskp->user1(true);
                m_taskps.push_back(taskp);
            }
        }
        return false;
    }

    // VISITORS
    void visit(AstPackage* nodep) override {
        VL_RESTORER(m_inStd);
        m_inStd = m_inStd || nodep == m_stdp;
        iterateChildrenConst(nodep);
    }
    void visit(AstIf* nodep) override {
        const AstCMethodHard* const methodp = VN_CAST(nodep->condp(), CMethodHard);
        if (methodp && methodp->method() == VCMethod::WAIT_QUEUE_POLLED) {
            m_choiceps.push_back(nodep);
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (!m_inStd && nodep->varp()->user1()) m_impure = true;
        iterateChildrenConst(nodep);
    }
    void visit(AstMemberRef* nodep) override {
        if (!m_inStd && nodep->varp()->user1()) m_impure = true;
        iterateChildrenConst(nodep);
    }
    void visit(AstWait* nodep) override {
        if (!m_inStd) scanCondition(nodep->condp());
        iterateChildrenConst(nodep);
    }
    void visit(AstSenItem* nodep) override {
        if (!m_inStd) {
            if (nodep->sensp()) scanCondition(nodep->sensp());
            if (nodep->condp()) scanCondition(nodep->condp());
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit MailboxWaitVisitor(AstNetlist* nodep) {
        // Earlier passes may have cached the purity of nodes they changed since
        VIsCached::clearCacheTree();
        if (m_stdp) m_stdp->foreach([](AstVar* varp) { varp->user1(true); });
        iterateConst(nodep);
        while (!m_impure && !m_taskps.empty()) {
            AstNodeFTask* const taskp = m_taskps.back();
            m_taskps.pop_back();
            ++m_statTasks;
            m_impure = taskp->exists([this](AstNode* np) { return hiddenEffect(np); });
        }
        V3Stats::addStat("Timing, mailbox wait subroutines scanned", m_statTasks);
    }
    ~MailboxWaitVisitor() = default;

    // ACCESSORS
    bool impure() const { return m_impure; }
    const std::vector<AstIf*>& choiceps() const { return m_choiceps; }
};

//######################################################################
// Keep the processes of reactive logic in the reactive region set

class TimingReactiveVisitor final : public VNVisitor {
    // A process started by reactive logic, such as a concurrent assertion action, is in the
    // reactive region set (IEEE 1800-2023 4.4.2.6), also after it suspends. V3Sched sets
    // __VinReactive while running the reactive region set. Before each await in reactive logic,
    // or in a function it may call, note whether the process runs in it, and if so make it
    // continue there: an event wait waits in a twin of its trigger scheduler, which V3Sched
    // resumes in the reactive region set, a #0 waits for the next pass of the reactive region
    // set, as for the Re-Inactive region (IEEE 1800-2023 4.4.2.7), and after other waits, the
    // process waits in a scheduler V3Sched resumes in the reactive region set, before any of
    // its statements run.

    // STATE
    AstNetlist* const m_netlistp;  // The netlist
    AstTopScope* const m_topScopep;  // The top scope
    std::unordered_set<const AstCFunc*> m_reactiveFuncps;  // Functions reactive logic may call
    AstNode* m_ownerp = nullptr;  // Current process, function or fork branch, owning the process
    AstCFunc* m_funcp = nullptr;  // Current function reactive logic may call
    bool m_inReactiveProc = false;  // In reactive logic, only running in the reactive region set
    AstScope* m_scopep = nullptr;  // Current scope
    size_t m_delayCount = 0;  // Delay values held
    struct Await final {
        AstCAwait* m_awaitp;  // The await
        AstCFunc* m_funcp;  // Its function, or nullptr in reactive logic
        const AstNode* m_ownerp;  // Owner of its process
        AstScope* m_scopep;  // Its scope
    };
    std::vector<Await> m_awaits;  // The awaits to keep in the reactive region set
    std::unordered_map<AstCFunc*, AstVarScope*> m_wasReactiveps;  // Origin before an await
    // Trigger scheduler -> its twin, for processes waiting in the reactive region set
    std::unordered_map<AstVarScope*, AstVarScope*> m_reactiveSchedps;

    // METHODS
    AstBasicDType* schedDTypep() const {
        return m_netlistp->typeTablep()->findBasicDType(m_netlistp->fileline(),
                                                        VBasicDTypeKwd::TRIGGER_SCHEDULER);
    }
    // The scheduler of the processes continuing in the next pass of the reactive region set,
    // for the Re-Inactive region, or else resumed outside it
    AstVarScope* getCreateSchedp(bool reInactive) {
        AstVarScope* vscp = reInactive ? m_netlistp->reInactSchedp() : m_netlistp->reactSchedp();
        if (vscp) return vscp;
        vscp = m_topScopep->createTemp(reInactive ? "__VreInactSched" : "__VreactSched",
                                       schedDTypep());
        if (reInactive) {
            m_netlistp->reInactSchedp(vscp);
        } else {
            m_netlistp->reactSchedp(vscp);
        }
        return vscp;
    }
    // The flag V3Sched sets while running the reactive region set
    AstVarScope* getCreateInReactivep() {
        if (!m_netlistp->inReactivep()) {
            m_netlistp->inReactivep(m_topScopep->createTemp("__VinReactive", 1));
        }
        return m_netlistp->inReactivep();
    }
    static bool hasProcess(const AstNode* ownerp) {
        if (const AstCFunc* const funcp = VN_CAST(ownerp, CFunc)) return funcp->needsVlProcess();
        if (const AstForkItem* const itemp = VN_CAST(ownerp, ForkItem)) {
            return itemp->needsVlProcess();
        }
        return VN_AS(ownerp, NodeProcedure)->needsVlProcess();
    }
    // An await resuming in the next pass of the reactive region set
    AstCAwait* newResumeAwaitp(FileLine* flp, bool reInactive, const AstNode* ownerp) {
        AstCMethodHard* const methodp = new AstCMethodHard{
            flp, new AstVarRef{flp, getCreateSchedp(reInactive), VAccess::WRITE},
            VCMethod::SCHED_TRIGGER};
        methodp->dtypeSetVoid();
        methodp->addPinsp(new AstConst{flp, AstConst::BitTrue{}});  // Ready at once
        methodp->addPinsp(new AstCExpr{flp, hasProcess(ownerp) ? "vlProcess" : "nullptr"});
        const bool protectIds = v3Global.opt.protectIds();
        AstCExpr* const descp
            = new AstCExpr{flp, protectIds ? "VL_UNKNOWN_FILENAME" : "\"reactive region set\""};
        descp->dtypeSetString();
        methodp->addPinsp(descp);
        AstCExpr* const filep = new AstCExpr{flp, protectIds ? "VL_UNKNOWN_FILENAME"
                                                             : '"' + flp->filenameEsc() + '"'};
        filep->dtypeSetString();
        methodp->addPinsp(filep);
        AstCExpr* const linep = new AstCExpr{flp, protectIds ? "0" : cvtToStr(flp->lineno())};
        linep->dtypeSetString();
        methodp->addPinsp(linep);
        return new AstCAwait{flp, methodp};
    }
    // Make the continuation of 'awaitp' in 'funcp', or in reactive logic if null, stay in the
    // reactive region set
    void keepReactive(AstCAwait* awaitp, AstCFunc* funcp, const AstNode* ownerp,
                      AstScope* scopeOfp) {
        FileLine* const flp = awaitp->fileline();
        AstVarScope* const inReactivep = getCreateInReactivep();
        AstCMethodHard* const methodp = VN_CAST(awaitp->exprp(), CMethodHard);
        const AstConst* const delayp = methodp && methodp->method() == VCMethod::SCHED_DELAY
                                           ? VN_CAST(methodp->pinsp(), Const)
                                           : nullptr;
        if (delayp && delayp->toUQuad() == std::numeric_limits<uint64_t>::max()) {
            // The start of a forked process (see V3Fork), which starts in the Reactive region
            VNRelinker handle;
            awaitp->unlinkFrBack(&handle);
            handle.relink(new AstIf{flp, new AstVarRef{flp, inReactivep, VAccess::READ},
                                    newResumeAwaitp(flp, false, ownerp), awaitp});
            return;
        }
        if (delayp && delayp->isZero()) {
            // Re-Inactive, if waiting in the reactive region set
            VNRelinker handle;
            awaitp->unlinkFrBack(&handle);
            handle.relink(new AstIf{flp, new AstVarRef{flp, inReactivep, VAccess::READ},
                                    newResumeAwaitp(flp, true, ownerp), awaitp});
            return;
        }
        AstNodeExpr* const valuep
            = methodp && methodp->method() == VCMethod::SCHED_DELAY ? methodp->pinsp() : nullptr;
        if (valuep && !delayp) {
            // Also for a delay that is zero when run: evaluate it once, into a local; otherwise
            // continue as below
            AstScope* const scopep = funcp ? funcp->scopep() : scopeOfp;
            AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP,
                                            "__VreactiveDelay" + std::to_string(m_delayCount++),
                                            valuep->dtypep()};
            varp->funcLocal(true);
            AstVarScope* const vscp = new AstVarScope{flp, scopep, varp};
            scopep->addVarsp(vscp);
            VNRelinker handle;
            awaitp->unlinkFrBack(&handle);
            valuep->replaceWith(new AstVarRef{flp, vscp, VAccess::READ});
            AstCLocalScope* const cscopep = new AstCLocalScope{
                flp, new AstAssign{flp, new AstVarRef{flp, vscp, VAccess::WRITE}, valuep}};
            cscopep->addVarsp(varp);
            AstNodeExpr* const zerop
                = new AstEq{flp, new AstVarRef{flp, vscp, VAccess::READ},
                            new AstConst{flp, AstConst::WidthedValue{}, valuep->width(), 0}};
            cscopep->addStmtsp(new AstIf{
                flp, new AstLogAnd{flp, new AstVarRef{flp, inReactivep, VAccess::READ}, zerop},
                newResumeAwaitp(flp, true, ownerp), awaitp});
            handle.relink(cscopep);
        }
        if (methodp && methodp->method() == VCMethod::SCHED_TRIGGER) {
            // Wait in the twin of the scheduler, which V3Sched resumes in the reactive region
            // set, also for a trigger the reactive region set fires
            AstVarScope* const schedp = VN_AS(methodp->fromp(), VarRef)->varScopep();
            AstVarScope*& twinpr = m_reactiveSchedps[schedp];
            if (!twinpr) {
                twinpr = m_topScopep->createTemp(schedp->varp()->name() + "__Vreactive",
                                                 schedp->dtypep());
            }
            AstCAwait* const twinp = awaitp->cloneTree(false);
            twinp->reactive(true);
            AstVarRef* const twinRefp = VN_AS(VN_AS(twinp->exprp(), CMethodHard)->fromp(), VarRef);
            twinRefp->varScopep(twinpr);
            twinRefp->varp(twinpr->varp());
            VNRelinker handle;
            awaitp->unlinkFrBack(&handle);
            handle.relink(
                new AstIf{flp, new AstVarRef{flp, inReactivep, VAccess::READ}, twinp, awaitp});
            return;
        }
        // A dynamic trigger found set when evaluated, also in the reactive region set, resumes
        // the process from the 'act' region; one of the reactive region set is resumed in it
        // instead (see V3Sched)
        const bool resumption = methodp && methodp->method() == VCMethod::SCHED_RESUMPTION;
        if (!funcp) {
            // Reactive logic only runs in the reactive region set
            if (resumption) {
                awaitp->replaceWith(newResumeAwaitp(flp, false, ownerp));
                VL_DO_DANGLING(pushDeletep(awaitp), awaitp);
                return;
            }
            awaitp->addNextHere(
                new AstIf{flp, new AstLogNot{flp, new AstVarRef{flp, inReactivep, VAccess::READ}},
                          newResumeAwaitp(flp, false, ownerp)});
            return;
        }
        // A function may run in both, so note where its call started, in its frame. A process
        // keeps its region set, so that is where it continues.
        AstVarScope*& wasp = m_wasReactiveps[funcp];
        if (!wasp) {
            AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP, "__VwasReactive",
                                            m_netlistp->findBitDType()};
            varp->funcLocal(true);
            varp->noReset(true);
            funcp->addVarsp(varp);
            wasp = new AstVarScope{flp, funcp->scopep(), varp};
            funcp->scopep()->addVarsp(wasp);
            AstAssign* const initp = new AstAssign{flp, new AstVarRef{flp, wasp, VAccess::WRITE},
                                                   new AstVarRef{flp, inReactivep, VAccess::READ}};
            // The function holds the await being handled, so it has statements
            AstNode* const stmtsp = funcp->stmtsp();
            UASSERT_OBJ(stmtsp, funcp, "Function with an await but no statements");
            stmtsp->addHereThisAsNext(initp);
        }
        if (resumption) {
            VNRelinker handle;
            awaitp->unlinkFrBack(&handle);
            handle.relink(new AstIf{flp, new AstVarRef{flp, wasp, VAccess::READ},
                                    newResumeAwaitp(flp, false, ownerp), awaitp});
            return;
        }
        awaitp->addNextHere(new AstIf{
            flp,
            new AstLogAnd{flp, new AstVarRef{flp, wasp, VAccess::READ},
                          new AstLogNot{flp, new AstVarRef{flp, inReactivep, VAccess::READ}}},
            newResumeAwaitp(flp, false, ownerp)});
    }

    // VISITORS
    void visit(AstCFunc* nodep) override {
        if (!m_reactiveFuncps.count(nodep)) return;
        VL_RESTORER(m_ownerp);
        VL_RESTORER(m_funcp);
        m_ownerp = nodep;
        m_funcp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstScope* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        iterateChildren(nodep);
    }
    void visit(AstAlwaysReactive* nodep) override {
        VL_RESTORER(m_ownerp);
        VL_RESTORER(m_inReactiveProc);
        m_ownerp = nodep;
        m_inReactiveProc = true;
        iterateChildren(nodep);
    }
    void visit(AstForkItem* nodep) override {
        VL_RESTORER(m_ownerp);
        m_ownerp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstCAwait* nodep) override {
        if (!m_funcp && !m_inReactiveProc) return;
        if (const AstCMethodHard* const methodp = VN_CAST(nodep->exprp(), CMethodHard)) {
            // Internal protocol of dynamic triggers, and waiting forever
            if (methodp->method() == VCMethod::SCHED_EVALUATION
                || methodp->method() == VCMethod::SCHED_POST_UPDATE
                || methodp->method() == VCMethod::SCHED_WAIT_FOREVER) {
                return;
            }
        }
        m_awaits.push_back({nodep, m_funcp, m_ownerp, m_scopep});
    }
    void visit(AstNodeExpr*) override {}  // Accelerate
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit TimingReactiveVisitor(AstNetlist* netlistp)
        : m_netlistp{netlistp}
        , m_topScopep{netlistp->topScopep()} {
        // Find the functions reactive logic may call
        const std::unique_ptr<V3CallTargets> callTargetsp = V3CallTargets::build();
        std::vector<AstCFunc*> todo;
        const auto addCalls = [&](AstNode* nodep) {
            nodep->foreach([&](AstNodeCCall* callp) {
                for (AstCFunc* const funcp : callTargetsp->getTargets(callp)) {
                    if (m_reactiveFuncps.insert(funcp).second) todo.push_back(funcp);
                }
            });
        };
        netlistp->foreach([&](AstAlwaysReactive* procp) { addCalls(procp); });
        while (!todo.empty()) {
            AstCFunc* const funcp = todo.back();
            todo.pop_back();
            addCalls(funcp);
        }
        iterate(netlistp);
        for (const Await& await : m_awaits) {
            keepReactive(await.m_awaitp, await.m_funcp, await.m_ownerp, await.m_scopep);
        }
    }
    ~TimingReactiveVisitor() override = default;
};

//######################################################################
// Timing class functions

AstNodeExpr* V3Timing::delayToTicks(AstNodeExpr* valuep, VTimescale timeunit) {
    FileLine* const flp = valuep->fileline();
    if (const AstConst* const constp = VN_CAST(valuep, Const)) {
        if (constp->num().is1Step()) {
            // A step is one tick of the global time precision (IEEE 1800-2023 3.14.3)
            VL_DO_DANGLING(valuep->deleteTree(), valuep);
            AstConst* const tickp = new AstConst{flp, AstConst::Unsized64{}, 1};
            tickp->dtypeSetBitSized(64, VSigning::UNSIGNED);
            return tickp;
        }
        if (constp->isZero()) return valuep;
    }
    UASSERT_OBJ(!timeunit.isNone(), valuep, "timeunit must be set");
    const double timescaleFactorD
        = std::pow(10.0, timeunit.powerOfTen() - v3Global.rootp()->timeprecision().powerOfTen());
    if (valuep->dtypep()->skipRefp()->isDouble()) {
        AstConst* const tsfp = new AstConst{flp, AstConst::RealDouble{}, timescaleFactorD};
        valuep = new AstMulD{flp, valuep, tsfp};
        valuep = new AstRToIRoundS{flp, valuep};
        valuep->dtypeSetBitSized(64, VSigning::UNSIGNED);
    } else {
        valuep->dtypeSetBitSized(64, VSigning::UNSIGNED);
        const uint64_t timescaleFactorU = static_cast<uint64_t>(timescaleFactorD);
        AstConst* const tsfp = new AstConst{flp, AstConst::Unsized64{}, timescaleFactorU};
        valuep = new AstMul{flp, valuep, tsfp};
    }
    return V3Const::constifyEdit(valuep);  // Simplify
}

void V3Timing::chooseMailboxWaits(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    {
        const MailboxWaitVisitor visitor{nodep};
        VNDeleter deleter;
        for (AstIf* const ifp : visitor.choiceps()) {
            AstNode* const keptp = visitor.impure() ? ifp->thensp() : ifp->elsesp();
            UASSERT_OBJ(keptp, ifp, "Mailbox wait without both forms");
            ifp->replaceWith(keptp->unlinkFrBackWithNext());
            VL_DO_DANGLING(deleter.pushDeletep(ifp), ifp);
        }
        V3Stats::addStat("Timing, mailbox waits polled",
                         visitor.impure() ? visitor.choiceps().size() : 0);
    }
    V3Global::dumpCheckGlobalTree("mailboxwait", 0, dumpTreeEitherLevel() >= 6);
}

void V3Timing::timingAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    {
        const VNUser1InUse m_user1InUse;
        const VNUser2InUse m_user2InUse;
        { TimingSuspendableVisitor{nodep}; }
        if (v3Global.usesTiming()) TimingControlVisitor{nodep};
    }
    if (v3Global.usesTiming() && nodep->exists([](const AstAlwaysReactive*) { return true; })) {
        TimingReactiveVisitor{nodep};
    }
    V3Global::dumpCheckGlobalTree("timing", 0, dumpTreeEitherLevel() >= 3);
}
