// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Code scheduling
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
// Prepares the TimingKit used by V3Sched.cpp to integrate static scheduling
// with timing features. Creates the processes resuming the timing schedulers,
// and computes the variables written by suspendable processes, together with
// their external domains: the sentrees the writing processes can resume on.
// These are computed over the call graph of the code executed by suspendable
// processes, including the processes started by forks, condensed into its
// strongly connected components. Code that may run on resuming after a zero
// delay is also instrumented to flag its writes of what combinational logic
// reads, for the 'inact' region to trigger that logic.
//
// See the internals documentation docs/internals.rst for more details.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Ast.h"
#include "V3CallTargets.h"
#include "V3Graph.h"
#include "V3Sched.h"
#include "V3Stats.h"

#include <tuple>
#include <unordered_map>
#include <unordered_set>

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

//============================================================================
// Creates the processes resuming the timing schedulers

class ResumeProcessBuilder final {
    // NODE STATE
    //  AstVarScope::user1()  -> bool.  Set true if the scheduler has been visited.
    const VNUser1InUse m_inuser1;

    // STATE
    AstScope* const m_scopeTopp;  // Scope at the top
    ProcessList m_procList;  // Timing resume processes
    AstNodeStmt* m_postUpdatesp = nullptr;  // Post updates for the trigger eval function

    // METHODS
    // Create a process with a timing scheduler resume() call
    void createResumeProcess(AstCAwait* const awaitp) {
        AstCMethodHard* const methodp = VN_AS(awaitp->exprp(), CMethodHard);
        AstVarScope* const schedp = VN_AS(methodp->fromp(), VarRef)->varScopep();
        AstSenTree* const sentreep = awaitp->sentreep();
        FileLine* const flp = sentreep->fileline();
        // Create a resume() call on the timing scheduler
        AstNodeExpr* const schedRefp = new AstVarRef{flp, schedp, VAccess::READWRITE};
        AstCMethodHard* const resumep = new AstCMethodHard{flp, schedRefp, VCMethod::SCHED_RESUME};
        resumep->dtypeSetVoid();
        AstBasicDType* const basicp = schedp->dtypep()->basicp();
        if (basicp->isTriggerScheduler()) {
            // Pass on the event description, the third argument of trigger(), see V3Timing
            AstNode* const descp = methodp->pinsp()->nextp()->nextp();
            resumep->addPinsp(VN_AS(descp, NodeExpr)->cloneTree(false));
        } else if (basicp->isDynamicTriggerScheduler()) {
            AstCMethodHard* const postp = resumep->cloneTree(false);
            postp->method(VCMethod::SCHED_DO_POST_UPDATES);
            UASSERT_OBJ(!m_postUpdatesp, awaitp, "Multiple dynamic trigger schedulers");
            m_postUpdatesp = postp->makeStmt();
        }
        // Reactive twins have their own resumption process.
        AstNodeProcedure* const procp
            = awaitp->reactive()
                  ? static_cast<AstNodeProcedure*>(
                        new AstAlwaysReactive{flp, nullptr, resumep->makeStmt()})
                  : new AstAlways{flp, VAlwaysKwd::ALWAYS, nullptr, resumep->makeStmt()};
        m_procList.add({m_scopeTopp, sentreep, procp, {}});
    }

    // CONSTRUCTORS
    explicit ResumeProcessBuilder(AstNetlist* netlistp)
        : m_scopeTopp{netlistp->topScopep()->scopep()} {
        netlistp->foreach([&](AstCAwait* awaitp) {
            if (!awaitp->sentreep()) return;
            AstCMethodHard* const methodp = VN_AS(awaitp->exprp(), CMethodHard);
            if (!VN_AS(methodp->fromp(), VarRef)->varScopep()->user1SetOnce()) {
                createResumeProcess(awaitp);
            }
        });
    }

public:
    // Returns the resume processes and the post updates for the trigger eval function
    static std::pair<ProcessList, AstNodeStmt*> apply(AstNetlist* netlistp) {
        ResumeProcessBuilder builder{netlistp};
        return {std::move(builder.m_procList), builder.m_postUpdatesp};
    }
};

//============================================================================
// Computes the variables written by suspendables, and their external domains

class ExternalDomainsVisitor final : public VNVisitorConst {
    // TYPES
    // Vertex of what is approximately a call graph. Each vertex represents either a:
    // - suspendable process
    // - coroutine, or function called by suspendable code
    // - fork
    class Vertex final : public V3GraphVertex {
        VL_RTTI_IMPL(Vertex, V3GraphVertex)
    public:
        std::set<AstSenTree*> m_domains;  // Sentrees waited on
        std::set<AstVarScope*> m_writes;  // Variables written
        bool m_zeroDelay = false;  // May run on resuming after a zero delay
        std::set<AstSenTree*> m_waits;  // Sentrees waited on, other than for delays
        std::set<AstVarScope*> m_reads;  // Variables read
        std::set<const AstVar*> m_memberReads;  // Class members read
        std::set<const AstVar*> m_memberWrites;  // Class members written
        bool m_wakeAny = false;  // Awaits something other than a delay or a sentree
        // Variables written, and the statements writing them
        std::vector<std::pair<AstNodeStmt*, const AstVar*>> m_writeStmts;
        explicit Vertex(V3Graph* graphp)
            : V3GraphVertex{graphp} {}
    };

    // NODE STATE
    //  AstCFunc::user1()          -> Vertex*.  Vertex, if coroutine or called by suspendable code
    //  AstFork::user1()           -> Vertex*.  Vertex
    //  AstNodeProcedure::user1()  -> Vertex*.  Vertex, if suspendable
    const VNUser1InUse m_inuser1;

    // STATE
    // To get the functions a virtual call may call
    std::unique_ptr<V3CallTargets> m_callTargetsp;
    V3Graph m_graph;  // The call graph used for analysis
    Vertex* m_vtxp = nullptr;  // Vertex of the current body, if suspendable code
    bool m_inProcess = false;  // In a suspendable process, coroutine or fork
    bool m_inComb = false;  // In combinational logic, or a function it calls
    std::unordered_set<const AstCFunc*> m_combFuncps;  // Functions called by such logic
    AstNodeStmt* m_stmtp = nullptr;  // Current statement
    // Variables read by combinational logic, which the delay scheduler's triggers evaluate
    std::unordered_set<const AstVar*> m_readps;
    AstVarScope* m_dirtyp = nullptr;  // Flag set by writes after a zero delay, see instrument
    std::vector<AstCFunc*> m_funcps;  // Functions not yet recorded when visited
    // External domains of the variables written by suspendables
    std::map<const AstVarScope*, std::set<AstSenTree*>> m_externalDomains;
    std::vector<SuspendableCode> m_suspendables;  // Bodies, for partitioning around 'inact'

    // METHODS
    // Get the call graph vertex of the given function, process or fork. If it is new,
    // walk the body with it to record its contents and callees.
    Vertex* recordBody(AstNode* nodep) {
        if (!nodep->user1p()) {
            Vertex* const vtxp = new Vertex{&m_graph};
            nodep->user1p(vtxp);
            VL_RESTORER(m_vtxp);
            VL_RESTORER(m_inProcess);
            VL_RESTORER(m_stmtp);
            VL_RESTORER(m_inComb);
            m_vtxp = vtxp;
            m_inComb = false;
            const AstCFunc* const funcp = VN_CAST(nodep, CFunc);
            m_inProcess = !funcp || funcp->isCoroutine();
            m_stmtp = nullptr;
            iterateChildrenConst(nodep);
        }
        return nodep->user1u().to<Vertex*>();
    }

    // Add an edge from m_vtxp (current body) to the given vertex
    void addEdge(Vertex* const vtxp) { new V3GraphEdge{&m_graph, m_vtxp, vtxp, 1}; }

    // Contract each strongly connected component of the call graph (direct or mutual recursion,
    // including through forks) into a single vertex. This effectively treats the whole SCC as a
    // single body of code.
    void contractSCCs() {
        m_graph.removeRedundantEdgesMax(&V3GraphEdge::followAlwaysTrue);
        m_graph.stronglyConnected(&V3GraphEdge::followAlwaysTrue);
        std::unordered_map<uint32_t, Vertex*> colorToVtxp;
        for (V3GraphVertex* const vtxp : m_graph.vertices().unlinkable()) {
            // Zero color means the vertex is in no cycle, so it is a component on its own
            if (!vtxp->color()) continue;

            // The first vertex is the one all others of the same SCC are merged into
            Vertex*& keepp = colorToVtxp[vtxp->color()];
            if (!keepp) {
                keepp = vtxp->as<Vertex>();
                continue;
            }

            // Merge the other vertices into the first one
            Vertex* const mergep = vtxp->as<Vertex>();
            keepp->m_domains.insert(mergep->m_domains.begin(), mergep->m_domains.end());
            keepp->m_writes.insert(mergep->m_writes.begin(), mergep->m_writes.end());
            keepp->m_zeroDelay |= mergep->m_zeroDelay;
            keepp->m_waits.insert(mergep->m_waits.begin(), mergep->m_waits.end());
            keepp->m_reads.insert(mergep->m_reads.begin(), mergep->m_reads.end());
            keepp->m_memberReads.insert(mergep->m_memberReads.begin(),
                                        mergep->m_memberReads.end());
            keepp->m_memberWrites.insert(mergep->m_memberWrites.begin(),
                                         mergep->m_memberWrites.end());
            keepp->m_wakeAny |= mergep->m_wakeAny;
            keepp->m_writeStmts.insert(keepp->m_writeStmts.end(), mergep->m_writeStmts.begin(),
                                       mergep->m_writeStmts.end());
            for (V3GraphEdge* const ep : mergep->outEdges().unlinkable()) ep->relinkFromp(keepp);
            for (V3GraphEdge* const ep : mergep->inEdges().unlinkable()) ep->relinkTop(keepp);
            VL_DO_DANGLING(mergep->unlinkDelete(&m_graph), mergep);
        }
        // Edges within a component are now self loops on its vertex, remove them
        for (V3GraphVertex& vtx : m_graph.vertices()) {
            for (V3GraphEdge* const edgep : vtx.outEdges().unlinkable()) {
                if (edgep->top() == &vtx) VL_DO_DANGLING(edgep->unlinkDelete(), edgep);
            }
        }
    }

    void computeExternalDomains() {
        // Two passes over the graph to propagate the domains up and down, this ensures
        // a sensitivity anywhere in the call graph reaches all relevant variables. This
        // over-approximates: only the awaits that can precede a write ("reaching awaits")
        // are needed for correctness.

        // Propagate the domains up the graph
        for (const V3GraphVertex& vtx : vlstd::reverse_view(m_graph.vertices())) {
            const std::set<AstSenTree*>& domains = vtx.as<Vertex>()->m_domains;
            for (const V3GraphEdge& edge : vtx.inEdges()) {
                Vertex* const callerp = edge.fromp()->as<Vertex>();
                callerp->m_domains.insert(domains.begin(), domains.end());
                // A caller continues after the callee's zero delay, and other awaits
                callerp->m_zeroDelay |= vtx.as<Vertex>()->m_zeroDelay;
                callerp->m_waits.insert(vtx.as<Vertex>()->m_waits.begin(),
                                        vtx.as<Vertex>()->m_waits.end());
                callerp->m_wakeAny |= vtx.as<Vertex>()->m_wakeAny;
            }
        }
        // Propagate the domains down the graph
        for (V3GraphVertex& vtx : m_graph.vertices()) {
            const std::set<AstSenTree*>& domains = vtx.as<Vertex>()->m_domains;
            for (V3GraphEdge& edge : vtx.outEdges()) {
                Vertex* const calleep = edge.top()->as<Vertex>();
                calleep->m_domains.insert(domains.begin(), domains.end());
                calleep->m_zeroDelay |= vtx.as<Vertex>()->m_zeroDelay;
                calleep->m_waits.insert(vtx.as<Vertex>()->m_waits.begin(),
                                        vtx.as<Vertex>()->m_waits.end());
                calleep->m_wakeAny |= vtx.as<Vertex>()->m_wakeAny;
            }
        }

        // Mark variables written by suspendables, and compute their external domains
        for (V3GraphVertex& vtx : m_graph.vertices()) {
            const Vertex* const vtxp = vtx.as<Vertex>();
            for (AstVarScope* const vscp : vtxp->m_writes) {
                m_externalDomains[vscp].insert(vtxp->m_domains.begin(), vtxp->m_domains.end());
                vscp->varp()->setWrittenBySuspendable();
            }
            // Record the body for partitioning around the 'inact' region
            if (!v3Global.usesZeroDelay()) continue;
            SuspendableCode code;
            code.m_reads.insert(vtxp->m_reads.begin(), vtxp->m_reads.end());
            code.m_writes.insert(vtxp->m_writes.begin(), vtxp->m_writes.end());
            code.m_memberReads.insert(vtxp->m_memberReads.begin(), vtxp->m_memberReads.end());
            code.m_memberWrites.insert(vtxp->m_memberWrites.begin(), vtxp->m_memberWrites.end());
            for (AstSenTree* const senTreep : vtxp->m_waits) {
                senTreep->foreach(
                    [&](const AstVarRef* refp) { code.m_triggers.emplace(refp->varScopep()); });
            }
            code.m_zeroDelay = vtxp->m_zeroDelay;
            code.m_wakeAny = vtxp->m_wakeAny;
            m_suspendables.push_back(std::move(code));
        }

        if (v3Global.opt.stats()) {
            size_t nDomains = 0;
            std::set<const AstSenTree*> sentreeps;
            for (const auto& vscpDomains : m_externalDomains) {
                nDomains += vscpDomains.second.size();
                sentreeps.insert(vscpDomains.second.begin(), vscpDomains.second.end());
            }
            V3Stats::addStat("Scheduling, Timing, variables written by suspendables",
                             m_externalDomains.size());
            V3Stats::addStat("Scheduling, Timing, external sensitivities, total", nDomains);
            V3Stats::addStat("Scheduling, Timing, unique external sentrees", sentreeps.size());
        }
    }

    // Code resumed after a zero delay runs in the 'inact' region, which fires no trigger, so
    // logic reading what it writes would not see the write. Set a flag before each statement
    // that may write such a variable, or a writable argument of a coroutine, for the
    // 'inact' region to fire the triggers of the delay scheduler, see createEval. No await is
    // inside a statement before its write, so the flag is still set when the code suspends.
    void instrument() {
        std::vector<AstNodeStmt*> stmtps;
        std::unordered_set<const AstNodeStmt*> seen;
        for (const V3GraphVertex& vtx : m_graph.vertices()) {
            const Vertex* const vtxp = vtx.as<Vertex>();
            if (!vtxp->m_zeroDelay) continue;
            for (const auto& stmtVar : vtxp->m_writeStmts) {
                const AstVar* const varp = stmtVar.second;
                if (!m_readps.count(varp) && !(varp->isFuncLocal() && varp->isWritable())) {
                    continue;
                }
                if (seen.insert(stmtVar.first).second) stmtps.push_back(stmtVar.first);
            }
        }
        V3Stats::addStat("Scheduling, Timing, zero delay writes flagged", stmtps.size());
        if (stmtps.empty()) return;
        // Stores in concurrently run code all set it to 1, read only in the 'inact' region
        m_dirtyp = v3Global.rootp()->topScopep()->createTemp("__VzeroDelayDirty", 1);
        m_dirtyp->varp()->setIgnoreSchedWrite();
        for (AstNodeStmt* const stmtp : stmtps) {
            FileLine* const flp = stmtp->fileline();
            stmtp->addHereThisAsNext(new AstAssign{flp,
                                                   new AstVarRef{flp, m_dirtyp, VAccess::WRITE},
                                                   new AstConst{flp, AstConst::BitTrue{}}});
        }
    }

    // VISITORS
    void visit(AstActive* const nodep) override {
        VL_RESTORER(m_inComb);
        m_inComb = nodep->sentreep()->hasCombo() || nodep->sentreep()->hasHybrid();
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeStmt* const nodep) override {
        VL_RESTORER(m_stmtp);
        m_stmtp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeProcedure* const nodep) override {
        UASSERT_OBJ(!m_vtxp, nodep, "Should not nest");
        // If the process is suspendable, record its body
        if (nodep->isSuspendable()) {
            recordBody(nodep);
            return;
        }
        // A non-suspendable process is walked only to find its forks
        iterateChildrenConst(nodep);
    }
    void visit(AstCFunc* const nodep) override {
        UASSERT_OBJ(!m_vtxp, nodep, "Should not nest");
        // A coroutine is suspendable, so record its body
        if (nodep->isCoroutine()) {
            recordBody(nodep);
            return;
        }
        // Gather regular functions not yet recorded during the walk,
        // they will be analyzed at the end to minimize repeated traversals
        if (!nodep->user1p()) m_funcps.push_back(nodep);
    }
    void visit(AstFork* nodep) override {
        // Fork branches are always suspendable, so record their body
        Vertex* const vtxp = recordBody(nodep);
        // Add edge if started from suspendable code
        if (m_vtxp) addEdge(vtxp);
    }
    void visit(AstCAwait* nodep) override {
        UASSERT_OBJ(m_vtxp, nodep, "Await not in suspendable code");
        const AstCMethodHard* const methodp = VN_CAST(nodep->exprp(), CMethodHard);
        const bool isDelay = methodp && methodp->method() == VCMethod::SCHED_DELAY;
        // Record the domain
        if (AstSenTree* const senTreep = nodep->sentreep()) {
            m_vtxp->m_domains.insert(senTreep);
            if (!isDelay) m_vtxp->m_waits.insert(senTreep);
        }
        if (isDelay) {
            // A delay not known to be nonzero may be zero
            const AstConst* const constp = VN_CAST(methodp->pinsp(), Const);
            if (!constp || constp->isZero()) m_vtxp->m_zeroDelay = true;
        } else if (!nodep->sentreep() && !VN_IS(nodep->exprp(), NodeCCall)) {
            // Something else, e.g. a join, that anything may complete. A call is a coroutine,
            // recorded with its own awaits.
            m_vtxp->m_wakeAny = true;
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeCCall* const nodep) override {
        iterateChildrenConst(nodep);
        if (m_inComb) {  // Walk the functions combinational logic calls for their reads
            for (AstCFunc* const cfuncp : m_callTargetsp->getTargets(nodep)) {
                if (!cfuncp->isCoroutine() && m_combFuncps.insert(cfuncp).second) {
                    iterateChildrenConst(cfuncp);
                }
            }
        }
        if (!m_vtxp) return;  // Not in suspendable code
        // Add edges to all functions that may be called, including through virtual calls
        for (AstCFunc* const cfuncp : m_callTargetsp->getTargets(nodep)) {
            addEdge(recordBody(cfuncp));
        }
    }
    void visit(AstNodeVarRef* nodep) override {
        // A function's own variable is read by that function only
        if (nodep->access().isReadOrRW() && m_inComb && !nodep->varp()->isFuncLocal()) {
            m_readps.insert(nodep->varp());
        }
        if (!m_vtxp) return;  // Not in suspendable code, or outside processes/functions
        if (nodep->access().isReadOrRW()) m_vtxp->m_reads.insert(nodep->varScopep());
        if (nodep->access().isWriteOrRW() && !nodep->varp()->ignoreSchedWrite()) {
            m_vtxp->m_writes.insert(nodep->varScopep());
            // A writable argument of a function, unlike of a coroutine, which may wait before
            // returning, is written at the call, see instrument
            const AstVar* const varp = nodep->varp();
            const bool callArg = varp->isFuncLocal() && varp->isWritable() && !m_inProcess;
            if (m_stmtp && !callArg) m_vtxp->m_writeStmts.emplace_back(m_stmtp, varp);
        }
    }
    void visit(AstMemberRef* nodep) override {
        iterateChildrenConst(nodep);
        // A member of a class object, maybe written through another reference to the object
        if (nodep->access().isReadOrRW() && m_inComb) m_readps.insert(nodep->varp());
        if (m_vtxp && m_stmtp && nodep->access().isWriteOrRW()) {
            m_vtxp->m_writeStmts.emplace_back(m_stmtp, nodep->varp());
        }
        if (m_vtxp && nodep->access().isReadOrRW()) m_vtxp->m_memberReads.insert(nodep->varp());
        if (m_vtxp && nodep->access().isWriteOrRW()) {
            m_vtxp->m_memberWrites.insert(nodep->varp());
        }
    }
    void visit(AstConst*) override {}  // Accelerate
    void visit(AstVar*) override {}  // Accelerate
    void visit(AstVarScope*) override {}  // Accelerate
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

    // CONSTRUCTORS
    explicit ExternalDomainsVisitor(AstNetlist* nodep)
        : m_callTargetsp{V3CallTargets::build()} {
        // Record the bodies of suspendable processes, coroutines, and forks
        iterateConst(nodep);
        // Regular functions not called by any of the above are walked only to find their forks
        for (AstCFunc* const funcp : m_funcps) {
            if (!funcp->user1p()) iterateChildrenConst(funcp);
        }
        // Contract each strongly connected component into a single vertex
        contractSCCs();
        // Topological order, callers first
        m_graph.order();
        // Propagate the domains up and down the graph to compute external sensitivities
        computeExternalDomains();
        instrument();
    }

public:
    // Returns the external domains of variables written by suspendables, the flag set by
    // writes after a zero delay that logic reads, if any, and the bodies of suspendable code
    static std::tuple<std::map<const AstVarScope*, std::set<AstSenTree*>>, AstVarScope*,
                      std::vector<SuspendableCode>>
    apply(AstNetlist* nodep) {
        ExternalDomainsVisitor visitor{nodep};
        return std::make_tuple(std::move(visitor.m_externalDomains), visitor.m_dirtyp,
                               std::move(visitor.m_suspendables));
    }
};

TimingKit prepareTiming(AstNetlist* const netlistp) {
    if (!v3Global.usesTiming()) return {};
    std::pair<ProcessList, AstNodeStmt*> resumes = ResumeProcessBuilder::apply(netlistp);
    auto domainsDirty = ExternalDomainsVisitor::apply(netlistp);
    return {std::move(resumes.first), resumes.second, std::move(std::get<0>(domainsDirty)),
            std::get<1>(domainsDirty), std::move(std::get<2>(domainsDirty))};
}

}  // namespace V3Sched
