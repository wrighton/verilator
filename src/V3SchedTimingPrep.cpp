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
// strongly connected components.
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

#include <unordered_map>

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

//============================================================================
// Creates the processes resuming the timing schedulers

class ResumeProcessBuilder final {
    // NODE STATE
    //  AstSenTree::user1()  -> bool.  Set true if the sentree has been visited.
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
        // Put it in a process
        AstAlways* const procp
            = new AstAlways{flp, VAlwaysKwd::ALWAYS, nullptr, resumep->makeStmt()};
        m_procList.add({m_scopeTopp, sentreep, procp, {}});
    }

    // CONSTRUCTORS
    explicit ResumeProcessBuilder(AstNetlist* netlistp)
        : m_scopeTopp{netlistp->topScopep()->scopep()} {
        netlistp->foreach([&](AstCAwait* awaitp) {
            AstSenTree* const sentreep = awaitp->sentreep();
            if (sentreep && !sentreep->user1SetOnce()) createResumeProcess(awaitp);
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
        std::set<AstSenTree*> m_waits;  // Sentrees waited on, other than for delays
        std::set<AstVarScope*> m_writes;  // Variables written
        std::set<AstVarScope*> m_reads;  // Variables read
        std::set<const AstVar*> m_memberReads;  // Class members read
        std::set<const AstVar*> m_memberWrites;  // Class members written
        bool m_zeroDelay = false;  // Has a delay that may be zero
        bool m_wakeAny = false;  // Awaits something other than a delay or a sentree
        bool m_sideEffect = false;  // Has an output or DPI effect
        bool m_contextDpi = false;  // Calls a context DPI import
        bool m_foreign = false;  // Runs user C code or a DPI import
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
    bool m_inSchedAwait = false;  // Under the await of a scheduler's method
    const AstNodeExpr* m_loopCondp = nullptr;  // Condition of the current loop test
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
            m_vtxp = vtxp;
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
            keepp->m_reads.insert(mergep->m_reads.begin(), mergep->m_reads.end());
            keepp->m_memberReads.insert(mergep->m_memberReads.begin(),
                                        mergep->m_memberReads.end());
            keepp->m_memberWrites.insert(mergep->m_memberWrites.begin(),
                                         mergep->m_memberWrites.end());
            keepp->m_waits.insert(mergep->m_waits.begin(), mergep->m_waits.end());
            keepp->m_zeroDelay |= mergep->m_zeroDelay;
            keepp->m_wakeAny |= mergep->m_wakeAny;
            keepp->m_sideEffect |= mergep->m_sideEffect;
            keepp->m_contextDpi |= mergep->m_contextDpi;
            keepp->m_foreign |= mergep->m_foreign;
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
            const Vertex* const vtxp = vtx.as<Vertex>();
            for (const V3GraphEdge& edge : vtx.inEdges()) {
                Vertex* const callerp = edge.fromp()->as<Vertex>();
                callerp->m_domains.insert(vtxp->m_domains.begin(), vtxp->m_domains.end());
                // A caller continues after the callee's delays and awaits
                callerp->m_waits.insert(vtxp->m_waits.begin(), vtxp->m_waits.end());
                callerp->m_zeroDelay |= vtxp->m_zeroDelay;
                callerp->m_wakeAny |= vtxp->m_wakeAny;
            }
        }
        // Propagate the domains down the graph
        for (V3GraphVertex& vtx : m_graph.vertices()) {
            const Vertex* const vtxp = vtx.as<Vertex>();
            for (V3GraphEdge& edge : vtx.outEdges()) {
                Vertex* const calleep = edge.top()->as<Vertex>();
                calleep->m_domains.insert(vtxp->m_domains.begin(), vtxp->m_domains.end());
                // A callee may be called after the caller's delays and awaits
                calleep->m_waits.insert(vtxp->m_waits.begin(), vtxp->m_waits.end());
                calleep->m_zeroDelay |= vtxp->m_zeroDelay;
                calleep->m_wakeAny |= vtxp->m_wakeAny;
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
            code.m_sideEffect = vtxp->m_sideEffect;
            code.m_contextDpi = vtxp->m_contextDpi;
            code.m_foreign = vtxp->m_foreign;
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

    // Record that suspendable code accesses runtime state
    void noteEffect(AstNode* nodep) {
        if (!m_vtxp || !util::accessesRuntimeState(nodep)) return;
        // C code made for scheduling: the arguments of a scheduler's method describing the
        // process, and the test for $finish of a loop, which $finish is ordered against anyway
        if ((VN_IS(nodep, CExpr) || VN_IS(nodep, CStmt))
            && (m_inSchedAwait || nodep == m_loopCondp)) {
            return;
        }
        m_vtxp->m_sideEffect = true;
        if (VN_IS(nodep, CExprUser) || VN_IS(nodep, CStmtUser)) m_vtxp->m_foreign = true;
    }

    // VISITORS
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
            // Only a constant non-zero delay is known not to resume in 'inact'
            const AstConst* const constp = VN_CAST(methodp->pinsp(), Const);
            if (!constp || constp->isZero()) m_vtxp->m_zeroDelay = true;
        } else if (!nodep->sentreep() && !VN_IS(nodep->exprp(), NodeCCall)) {
            // A call is a coroutine, recorded with its own awaits
            m_vtxp->m_wakeAny = true;
        }
        VL_RESTORER(m_inSchedAwait);
        if (methodp) m_inSchedAwait = true;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeCCall* const nodep) override {
        iterateChildrenConst(nodep);
        if (!m_vtxp) return;  // Not in suspendable code
        // Add edges to all functions that may be called, including through virtual calls
        for (AstCFunc* const cfuncp : m_callTargetsp->getTargets(nodep)) {
            if (cfuncp->dpiImportWrapper()) {
                m_vtxp->m_sideEffect = true;
                m_vtxp->m_foreign = true;
                if (cfuncp->dpiContext()) m_vtxp->m_contextDpi = true;
            }
            addEdge(recordBody(cfuncp));
        }
    }
    void visit(AstNodeVarRef* nodep) override {
        if (!m_vtxp) return;  // Not in suspendable code, or outside processes/functions
        if (nodep->access().isWriteOrRW() && !nodep->varp()->ignoreSchedWrite()) {
            m_vtxp->m_writes.insert(nodep->varScopep());
        }
        if (nodep->access().isReadOrRW()) m_vtxp->m_reads.insert(nodep->varScopep());
    }
    void visit(AstMemberRef* nodep) override {
        iterateChildrenConst(nodep);
        if (!m_vtxp) return;  // Not in suspendable code
        // A member of a class object, maybe accessed through another reference to the object
        if (nodep->access().isReadOrRW()) m_vtxp->m_memberReads.insert(nodep->varp());
        if (nodep->access().isWriteOrRW()) m_vtxp->m_memberWrites.insert(nodep->varp());
    }
    void visit(AstConst*) override {}  // Accelerate
    void visit(AstVar*) override {}  // Accelerate
    void visit(AstVarScope*) override {}  // Accelerate
    void visit(AstLoopTest* nodep) override {
        VL_RESTORER(m_loopCondp);
        m_loopCondp = nodep->condp();
        iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override {
        noteEffect(nodep);
        iterateChildrenConst(nodep);
    }

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
    }

public:
    // Returns the external domains of variables written by suspendables, and the bodies of
    // suspendable code
    static std::pair<std::map<const AstVarScope*, std::set<AstSenTree*>>,
                     std::vector<SuspendableCode>>
    apply(AstNetlist* nodep) {
        ExternalDomainsVisitor visitor{nodep};
        return {std::move(visitor.m_externalDomains), std::move(visitor.m_suspendables)};
    }
};

TimingKit prepareTiming(AstNetlist* const netlistp) {
    if (!v3Global.usesTiming()) return {};
    std::pair<ProcessList, AstNodeStmt*> resumes = ResumeProcessBuilder::apply(netlistp);
    std::pair<std::map<const AstVarScope*, std::set<AstSenTree*>>, std::vector<SuspendableCode>>
        domains = ExternalDomainsVisitor::apply(netlistp);
    return {std::move(resumes.first), resumes.second, std::move(domains.first),
            std::move(domains.second)};
}

}  // namespace V3Sched
