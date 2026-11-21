// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Multi-threaded MTask graph data hazard fixing
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
// The fine-grained graph from V3Order may contain data hazards which are not a problem for
// serial mode, but which would be a problem in parallel mode. There are two classes:
// unordered pairs of writes, and unordered write-read pairs. This transform adds edges here
// until no such unordered pair remains.
//
// ABOUT UNORDERED WRITE-WRITE PAIRS
//
//   The V3Order dependency graph treats these as unordered events:
//
//    a)  sig[15:8] = stuff;
//          ...
//    b)  sig[7:0]  = other_stuff;
//
//   They are writes to disjoint bits of the same signal. They can run in
//   either order, in serial mode, and the result will be the same.
//
//   The resulting C code for each of this isn't a pure write, it's actually an R-M-W
//   sequence:
//
//    a)  sig = (sig & 0xff)   | (0xff00 & (stuff << 8));
//          ...
//    b)  sig = (sig & 0xff00) | (0xff & other_stuff);
//
//   In serial mode, order doesn't matter as these run serially. In parallel mode,
//   they must be serialized to avoid a race.
//
//   This pass does not check if each write would involve an R-M-W, it just assumes that
//   it does. If this routine ever causes a drastic increase in critical path, it could be
//   optimized to make a better prediction (with all the risk that word implies!) about
//   whether a given write is likely to turn into an R-M-W.
//
// ABOUT UNORDERED WRITE-READ PAIRS
//
//   If we don't put unordered write-read pairs into some order at Verilation time, we risk
//   a runtime race.
//
//   These arise because the OrderGraph deliberately does not model every access. A read of
//   a variable that is in the reading block's own hybrid sensitivity list gets no edge, as
//   does a read ignored due to a force/release, or an access to a variable marked
//   'ignoreSchedWrite' and friends. For serial mode that is fine: whatever order the logic
//   ends up in, it runs one block at a time. In parallel mode two such blocks can run
//   concurrently, and if one of them writes what the other reads, that is an observable
//   data race.
//
// HOW TO FIX THEM
//
//   An arbitrary ordering is prescribed by adding edges between MTasks. The new edges
//   must not create a cycle, and should be added in a way that increases critical paths
//   as little as possible.
//
//   Every MTask is given a unique sequence number, in a topological order of the graph, so
//   that for every edge 'from -> to' we have seq(from) < seq(to). Adding a new edge that
//   runs in increasing sequence order therefore cannot create a cycle, and the property is
//   maintained by induction as more edges are added.
//
//   With that in hand, for each variable we take its accessors in sequence order, chain the
//   writers together, and bracket each reader between the writers either side of it.
//   Readers need no ordering with respect to one another.
//
//   The sequence numbers are assigned by a topological sort that emits the ready MTask with
//   the smallest forward critical path first. As the forward critical path of an MTask is at
//   least that of each of its predecessors, the smallest among the ready MTasks is also the
//   smallest among all not yet emitted ones, so MTasks come out in globally non-decreasing
//   forward critical path order. Chaining them in that order is what tends to grow the
//   critical path least: the longest path through a chain starts at the head of its first
//   MTask, so putting those with the shortest path to them first keeps that sum down.
//
//   The critical paths are also what makes finding the edges that are actually needed cheap.
//   An edge is only added between a pair that is not ordered already, and a pair can be
//   ruled ordered, or not, in constant time whenever their critical paths are inconsistent
//   with a path between them, which avoids searching the graph for most pairs.
//
//   SystemC variables are handled similarly, except that all SystemC variables are treated as
//   a single entity. Reasoning: writing a systemC var actually turns into a call to a var.write()
//   method, which under the hood is accessing some data structure that's shared by many SC vars.
//   It's not thread safe.
//
//   DPI calls are serialized similarly (they are assumed not thread safe), unless directed by
//   options.
//
//   An MTask that may control processes runs alone, ordered against every other MTask (see
//   ProcessControlVisitor). Each such MTask is a barrier in sequence order: every other MTask is
//   ordered after the last barrier before it and before the first barrier after it, which also
//   orders the barriers among themselves. An MTask needs an edge only if no predecessor, or
//   successor, between it and that barrier orders it already. A pass in sequence order, and one
//   in reverse, find these edges, which are then added updating the critical paths only once (see
//   OrderMTaskGraph::addEdges), all in time linear in the size of the graph.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3CallTargets.h"
#include "V3Control.h"
#include "V3Global.h"
#include "V3Graph.h"
#include "V3OrderGraph.h"
#include "V3OrderMTaskGraph.h"
#include "V3Stats.h"

#include <algorithm>
#include <memory>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// DpiImportCallVisitor

// Scan node, indicate whether it contains a call to a DPI imported routine.
class DpiImportCallVisitor final : public VNVisitorConst {
    bool m_hasDpiHazard = false;  // Found a DPI import call.
    bool m_tracingCall = false;  // Iterating into a CCall to a CFunc
    std::unordered_set<const AstCFunc*> m_visitedps;  // Functions already visited
    // METHODS
    void visit(AstCFunc* nodep) override {
        if (!m_tracingCall) return;
        m_tracingCall = false;
        if (nodep->dpiImportWrapper()) {
            if (nodep->dpiPure() ? !v3Global.opt.threadsDpiPure()
                                 : !v3Global.opt.threadsDpiUnpure()) {
                // If hierarchical DPI wrapper cost is not found or is of a 0 cost,
                // we have a normal DPI which induces DPI hazard by default.
                const bool dpiHazard = V3Control::getProfileData(nodep->cname()) == 0;
                m_hasDpiHazard |= dpiHazard;
                UINFO(9, "DPI wrapper '" << nodep->cname() << "' has dpi hazard = " << dpiHazard);
            }
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeCCall* nodep) override {
        iterateChildrenConst(nodep);
        // Enter the function and trace it, once, as functions can be recursive
        if (!m_visitedps.emplace(nodep->funcp()).second) return;
        m_tracingCall = true;
        iterateConst(nodep->funcp());
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

    // CONSTRUCTORS
    explicit DpiImportCallVisitor(AstNode* nodep) { iterateConst(nodep); }

public:
    static bool hasDpiHazard(AstNode* nodep) { return DpiImportCallVisitor{nodep}.m_hasDpiHazard; }
};

//######################################################################
// ProcessControlVisitor

// Find the logic that may control processes through a called function. Killing a process can
// end a fork..join and resume the waiting process right away, and starting one runs it until it
// first waits, in a timing scheduler. Either way the logic then makes accesses that are not its
// own, which ordering it by its own accesses does not account for. Conservatively, a function may
// control processes if it uses a process reference, as std::process methods such as kill() and
// status() do, or a timing scheduler, or calls a function that may, through a virtual call any
// it may dispatch to (see V3CallTargets). Logic using these itself is ordered by its accesses as
// usual. A 'disable fork' does not count by itself: it only kills descendants of the process of
// the logic, which other logic can only reach through a process reference, so that logic runs
// alone. A context DPI import counts as calling every DPI export, as its C code may call any
// (IEEE 1800-2023 35.5.3). Process control in user $c code is not seen.
class ProcessControlVisitor final : public VNVisitorConst {
    // TYPES
    // Vertex of the call graph: a function, with edges to what its calls may call, which is a
    // function, or, for a virtual call, a dispatch vertex with edges to all it may dispatch to.
    // A context DPI import has an edge to one more dispatch vertex, with edges to all DPI
    // exports.
    class Vertex final : public V3GraphVertex {
        VL_RTTI_IMPL(Vertex, V3GraphVertex)
    public:
        bool m_control = false;  // May control processes
        explicit Vertex(V3Graph* graphp)
            : V3GraphVertex{graphp} {}
    };

    // STATE
    const std::unique_ptr<V3CallTargets> m_callTargetsp = V3CallTargets::build();
    V3Graph m_graph;  // The call graph
    std::unordered_map<const AstCFunc*, Vertex*> m_funcVtxps;  // Function -> Its vertex
    std::unordered_map<const AstCFunc*, Vertex*> m_dispatchVtxps;  // Function -> Dispatch vertex
    // Dispatch vertex of the calls of context DPI imports to DPI exports
    Vertex* const m_dpiExportsVtxp = new Vertex{&m_graph};
    Vertex* m_funcVtxp = nullptr;  // Vertex of the function being visited
    bool m_logicControl = false;  // The logic checked by mayControl may control processes

    // METHODS
    Vertex* funcVtxp(const AstCFunc* funcp) {
        Vertex*& vtxpr = m_funcVtxps[funcp];
        if (!vtxpr) vtxpr = new Vertex{&m_graph};
        return vtxpr;
    }
    // The vertex of what 'callp' may call
    Vertex* calleeVtxp(const AstNodeCCall* callp) {
        const std::vector<AstCFunc*>& targetps = m_callTargetsp->getTargets(callp);
        if (targetps.size() == 1) return funcVtxp(targetps.front());
        // Only a virtual call has several, the same for all calls of the function
        Vertex*& vtxpr = m_dispatchVtxps[callp->funcp()];
        if (vtxpr) return vtxpr;
        vtxpr = new Vertex{&m_graph};
        for (const AstCFunc* const targetp : targetps) {
            Vertex* const targetVtxp = funcVtxp(targetp);
            new V3GraphEdge{&m_graph, vtxpr, targetVtxp, 1};
            // Needed when made after propagation in the constructor
            vtxpr->m_control |= targetVtxp->m_control;
        }
        return vtxpr;
    }

    // VISITORS
    void visit(AstCFunc* nodep) override {
        VL_RESTORER(m_funcVtxp);
        m_funcVtxp = funcVtxp(nodep);
        if (nodep->dpiImportWrapper() && nodep->dpiContext()) {
            new V3GraphEdge{&m_graph, m_funcVtxp, m_dpiExportsVtxp, 1};
        }
        if (nodep->dpiExportImpl()) new V3GraphEdge{&m_graph, m_dpiExportsVtxp, m_funcVtxp, 1};
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (!m_funcVtxp) return;
        const AstBasicDType* const basicp = nodep->varp()->dtypep()->skipRefp()->basicp();
        if (!basicp) return;
        if (basicp->isProcessRef() || basicp->isDelayScheduler() || basicp->isTriggerScheduler()
            || basicp->isDynamicTriggerScheduler()) {
            m_funcVtxp->m_control = true;
        }
    }
    void visit(AstNodeCCall* nodep) override {
        iterateChildrenConst(nodep);
        Vertex* const calleep = calleeVtxp(nodep);
        if (!m_funcVtxp) {
            m_logicControl |= calleep->m_control;
        } else {
            new V3GraphEdge{&m_graph, m_funcVtxp, calleep, 1};
        }
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit ProcessControlVisitor(AstNetlist* netlistp) {
        iterateConst(netlistp);
        // The callers of a function that may control processes may too
        std::vector<Vertex*> workList;
        for (V3GraphVertex& vtx : m_graph.vertices()) {
            Vertex* const vtxp = vtx.as<Vertex>();
            if (vtxp->m_control) workList.push_back(vtxp);
        }
        while (!workList.empty()) {
            const Vertex* const vtxp = workList.back();
            workList.pop_back();
            for (const V3GraphEdge& edge : vtxp->inEdges()) {
                Vertex* const callerp = edge.fromp()->as<Vertex>();
                if (callerp->m_control) continue;
                callerp->m_control = true;
                workList.push_back(callerp);
            }
        }
    }

    // METHODS
    // Whether logic may control processes, through a function it calls
    bool mayControl(AstNode* logicp) {
        m_logicControl = false;
        iterateConst(logicp);
        return m_logicControl;
    }
};

//######################################################################
// FixDataHazards

class FixDataHazards final {
    // TYPES

    // Access to one variable, with the MTask performing it
    struct Access final {
        const AstVarScope* m_vscp;  // The variable accessed, its index is in 'user1'
        LogicMTask* m_mtaskp;  // The accessing MTask
        VAccess m_access;  // The kind of access
    };

    // NODE STATE
    //  AstVarScope::user1    -> int: Variable index for stable sorting
    const VNUser1InUse m_user1InUse;

    // MEMBERS
    OrderMTaskGraph& m_mTaskGraph;  // The Mtask graph
    std::vector<LogicMTask*> m_scratch;  // Scratch MTask list, reused to avoid reallocation

    // METHODS

    // Assign each MTask a unique sequence number, held in 'user()', such that for every edge
    // 'from -> to' we have seq(from) < seq(to). See the note at top of file on why this matters.
    // This is a topological sort using Kahn's algorithm with MTasks enumerated in a globally
    // non-decreasing critical path order.
    void assignSequenceNumbers() {
        struct MTaskCmp final {
            bool operator()(const LogicMTask* ap, const LogicMTask* bp) const {
                // Order by critical path
                const uint64_t aCp = ap->cpExclusive<GraphWay::FORWARD>();
                const uint64_t bCp = bp->cpExclusive<GraphWay::FORWARD>();
                if (aCp != bCp) return aCp < bCp;
                // Break ties by stable id
                return *ap < *bp;
            }
        };
        // Set of ready vertices. Initialized to the entry MTask.
        std::set<LogicMTask*, MTaskCmp> ready{m_mTaskGraph.entryp()};
        // 'user' also used to count remaining dependencies of each MTask. Initialize it.
        for (V3GraphVertex& vtx : m_mTaskGraph.vertices()) {
            vtx.user(static_cast<uint32_t>(vtx.inEdges().size()));
        }
        // Next sequence number to assign to each MTask.
        uint32_t seq = 0;
        // Process ready vertices in critical path order.
        while (!ready.empty()) {
            // Pick up and detach the ready MTask with the smallest critical path.
            const auto it = ready.begin();
            LogicMTask* const mtaskp = *it;
            ready.erase(it);
            // Assign the next sequence number to the MTask
            mtaskp->user(++seq);
            // Decrement edge count of successors and add to ready set if no dependencies left
            for (V3GraphEdge& edge : mtaskp->outEdges()) {
                LogicMTask* const top = static_cast<LogicMTask*>(edge.top());
                const uint32_t nDeps = top->user() - 1;
                top->user(nDeps);
                if (!nDeps) ready.insert(top);
            }
        }
        UASSERT(seq == m_mTaskGraph.vertices().size(), "MTask graph is cyclic");
    }

    // Gather every variable access, resolved to the MTask performing it.
    std::vector<Access> gatherAccesses() {
        std::vector<Access> accesses;
        int nVars = 0;
        for (V3GraphVertex& vtx : m_mTaskGraph.vertices()) {
            LogicMTask& mtask = static_cast<LogicMTask&>(vtx);
            for (const OrderMoveVertex& mVtx : mtask.vertexList()) {
                const OrderLogicVertex* const lVtxp = mVtx.logicp();
                if (!lVtxp) continue;
                for (const OrderLogicVertex::VarAccess& acc : lVtxp->varAccesses()) {
                    AstVarScope* const vscp = acc.m_vscp;
                    if (!vscp->user1()) vscp->user1(++nVars);
                    accesses.push_back({vscp, &mtask, acc.m_access});
                }
            }
        }
        return accesses;
    }

    // Add an edge ordering 'fromp' before 'top', unless they are already ordered
    void addEdgeIfNeeded(LogicMTask* fromp, LogicMTask* top) {
        // Nothing to order within a single MTask
        if (fromp == top) return;
        UASSERT_OBJ(fromp->user() < top->user(), fromp,
                    "Edge must run in increasing sequence order");
        // Already directly ordered. This is an O(1) set lookup, and catches the common case of
        // a dependency the OrderGraph already provided.
        if (fromp->hasEdgeTo(top)) return;
        // Otherwise check if already ordered
        if (m_mTaskGraph.pathExists(fromp, top, nullptr)) return;
        // Unordered. Add an edge between them.
        m_mTaskGraph.addEdge(fromp, top);
    }

    // Add the edges required to make the accesses of one variable race free. 'beginp'/'endp'
    // delimit the accesses of a single variable, in sequence number order.
    void serializeVariable(const Access* beginp, const Access* endp) {
        // Nothing to order if at most one MTask accesses this variable. Each MTask appears at
        // most once in the range, see the assertion below, so this is just the range size.
        if (endp - beginp < 2) return;

        std::vector<LogicMTask*>& pendingReaders = m_scratch;
        pendingReaders.clear();
        LogicMTask* prevWriterp = nullptr;
        for (const Access* accp = beginp; accp != endp; ++accp) {
            // The accesses of a variable by the same MTask were combined into one, so an MTask
            // cannot appear twice here.
            UASSERT_OBJ(accp == beginp || accp[-1].m_mtaskp != accp->m_mtaskp, accp->m_mtaskp,
                        "Multiple accesses of a variable in an MTask");
            LogicMTask* const mtaskp = accp->m_mtaskp;
            if (accp->m_access.isWriteOrRW()) {
                // Reads since the previous write must complete before this write
                for (LogicMTask* const readerp : pendingReaders) addEdgeIfNeeded(readerp, mtaskp);
                // Consecutive writes must be ordered. If a read came between them, the edges to
                // and from that read imply it already.
                if (prevWriterp && pendingReaders.empty()) addEdgeIfNeeded(prevWriterp, mtaskp);
                pendingReaders.clear();
                prevWriterp = mtaskp;
            } else {
                // This read must happen after the preceding write
                if (prevWriterp) addEdgeIfNeeded(prevWriterp, mtaskp);
                pendingReaders.push_back(mtaskp);
            }
        }
    }

    // Serialize the given MTasks, in sequence number order
    void serializeMTasks(std::vector<LogicMTask*>& mtaskps) {
        std::sort(mtaskps.begin(), mtaskps.end(), [](const LogicMTask* ap, const LogicMTask* bp) {
            return ap->user() < bp->user();
        });
        mtaskps.erase(std::unique(mtaskps.begin(), mtaskps.end()), mtaskps.end());
        for (size_t i = 1; i < mtaskps.size(); ++i) addEdgeIfNeeded(mtaskps[i - 1], mtaskps[i]);
    }

    // Make each MTask in 'barrierps' run alone (see the note at the top of the file)
    void runAlone(const std::vector<LogicMTask*>& barrierps) {
        // The MTasks by sequence number, which are 1 to the number of MTasks
        std::vector<LogicMTask*> seqps(m_mTaskGraph.vertices().size() + 1, nullptr);
        for (V3GraphVertex& vtx : m_mTaskGraph.vertices()) {
            LogicMTask* const mtaskp = static_cast<LogicMTask*>(&vtx);
            seqps[mtaskp->user()] = mtaskp;
        }
        std::vector<bool> isBarrier(seqps.size(), false);
        for (const LogicMTask* const barrierp : barrierps) isBarrier[barrierp->user()] = true;
        std::vector<std::pair<LogicMTask*, LogicMTask*>> edges;  // The edges to add
        // Order each MTask after the last barrier before it. This pass already ordered those in
        // between after it, so an edge is needed only if no predecessor is one of them.
        LogicMTask* barrierp = nullptr;
        for (size_t seq = 1; seq < seqps.size(); ++seq) {
            LogicMTask* const mtaskp = seqps[seq];
            if (barrierp) {
                bool ordered = false;
                for (const V3GraphEdge& edge : mtaskp->inEdges()) {
                    if (edge.fromp()->user() >= barrierp->user()) {
                        ordered = true;
                        break;
                    }
                }
                if (!ordered) edges.emplace_back(barrierp, mtaskp);
            }
            if (isBarrier[seq]) barrierp = mtaskp;
        }
        // Likewise order each MTask other than a barrier before the first barrier after it
        barrierp = nullptr;
        for (size_t seq = seqps.size() - 1; seq > 0; --seq) {
            LogicMTask* const mtaskp = seqps[seq];
            if (isBarrier[seq]) {
                barrierp = mtaskp;
                continue;
            }
            if (!barrierp) continue;
            bool ordered = false;
            for (const V3GraphEdge& edge : mtaskp->outEdges()) {
                if (edge.top()->user() <= barrierp->user()) {
                    ordered = true;
                    break;
                }
            }
            if (!ordered) edges.emplace_back(mtaskp, barrierp);
        }
        V3Stats::addStatSum("Scheduling, process control ordering edges", edges.size());
        m_mTaskGraph.addEdges(edges);
    }

    bool hasDpiHazard(LogicMTask* mtaskp) {
        for (const OrderMoveVertex& mVtx : mtaskp->vertexList()) {
            OrderLogicVertex* const lvtxp = mVtx.logicp();
            if (!lvtxp) continue;
            // NOTE: We don't handle the variables DPI exports access, only their process control
            // (see ProcessControlVisitor). If testbench code calls a DPI-exported function
            // at any time during eval() we may have a data hazard. (Likewise in non-threaded mode
            // if an export messes with an ordered variable we're broken.)

            // Find all calls to DPI-imported functions, we can put those into a serial order at
            // least. That should solve the most likely DPI-related data hazards.
            if (DpiImportCallVisitor::hasDpiHazard(lvtxp->nodep())) return true;
        }
        return false;
    }

    // CONSTRUCTOR
    explicit FixDataHazards(OrderMTaskGraph& mTaskGraph)
        : m_mTaskGraph{mTaskGraph} {
        // Give the MTasks a total order consistent with their dependencies
        assignSequenceNumbers();

        // Gather variable accesses made by each MTask
        std::vector<Access> accesses = gatherAccesses();
        // Sort by variable (to group by variable), then by sequence number of the accessing MTask
        std::sort(accesses.begin(), accesses.end(), [](const Access& a, const Access& b) {
            if (a.m_vscp != b.m_vscp) return a.m_vscp->user1() < b.m_vscp->user1();
            return a.m_mtaskp->user() < b.m_mtaskp->user();
        });
        // An MTask holding several logic blocks can access a variable more than once. Combine
        // these into one access, as each OrderLogicVertex does for its own accesses.
        if (accesses.size() > 1) {
            size_t last = 0;  // Index of the last combined access
            for (size_t i = 1; i < accesses.size(); ++i) {
                Access& lastAcc = accesses[last];
                const Access& acc = accesses[i];
                if (acc.m_vscp == lastAcc.m_vscp && acc.m_mtaskp == lastAcc.m_mtaskp) {
                    if (acc.m_access != lastAcc.m_access) lastAcc.m_access = VAccess::READWRITE;
                } else {
                    accesses[++last] = acc;
                }
            }
            accesses.resize(last + 1);
        }

        // Serialize the accesses of each variable
        for (size_t i = 0; i < accesses.size();) {
            size_t end = i + 1;
            while (end < accesses.size() && accesses[end].m_vscp == accesses[i].m_vscp) ++end;
            serializeVariable(accesses.data() + i, accesses.data() + end);
            i = end;
        }

        // Serialize all writes to SystemC vars. Note the reads of an individual SC var are already
        // ordered against its writes by the per variable pass above, it is only the writes between
        // different SC vars that need this extra serialization. Only top level ports are SC vars,
        // so this should not hurt performance too much.
        {
            m_scratch.clear();
            for (const Access& access : accesses) {
                if (!access.m_access.isWriteOrRW()) continue;
                if (!access.m_vscp->varp()->isSc()) continue;
                m_scratch.push_back(access.m_mtaskp);
            }
            serializeMTasks(m_scratch);
        }

        // Make MTasks that may control processes run alone. Processes are only controlled with
        // timing, as the std::process methods are otherwise empty.
        if (v3Global.opt.timing().isSetTrue()) {
            ProcessControlVisitor processControl{v3Global.rootp()};
            m_scratch.clear();
            for (V3GraphVertex& vtx : m_mTaskGraph.vertices()) {
                LogicMTask& mtask = static_cast<LogicMTask&>(vtx);
                for (const OrderMoveVertex& mVtx : mtask.vertexList()) {
                    const OrderLogicVertex* const lvtxp = mVtx.logicp();
                    if (lvtxp && processControl.mayControl(lvtxp->nodep())) {
                        m_scratch.push_back(&mtask);
                        break;
                    }
                }
            }
            V3Stats::addStatSum("Scheduling, MTasks with process control", m_scratch.size());
            if (!m_scratch.empty()) runAlone(m_scratch);
        }

        // Serialize DPI calls unless user gave '--threads-dpi none'.
        if (!v3Global.opt.threadsDpiPure() || !v3Global.opt.threadsDpiUnpure()) {
            m_scratch.clear();
            for (V3GraphVertex& vtx : m_mTaskGraph.vertices()) {
                LogicMTask& mtask = static_cast<LogicMTask&>(vtx);
                if (hasDpiHazard(&mtask)) m_scratch.push_back(&mtask);
            }
            serializeMTasks(m_scratch);
        }
    }

public:
    static void apply(OrderMTaskGraph& mTaskGraph) { FixDataHazards{mTaskGraph}; }
};

void OrderMTaskGraph::fixDataHazards(OrderMTaskGraph& mtaskGraph) {
    FixDataHazards::apply(mtaskGraph);
    // The critical paths are maintained as the graph is mutated, check them
    mtaskGraph.validate();
}
