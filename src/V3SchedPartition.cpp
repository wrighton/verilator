// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Scheduling - partitioning
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
// V3SchedPartition (and in particular V3Sched::partition) partitions all
// logic into two regions, the 'act' region contains all logic that might
// compute a clock via an update even that falls into the SystemVerilog Active
// scheduling region (that is: blocking and continuous assignments in
// particular). All other logic is assigned to the 'nba' region.
//
// To achieve this, we build a dependency graph of all logic in the design,
// and trace back from every AstSenItem through all logic that might (via an
// Active region update) feed into triggering that AstSenItem. Any such logic
// is then assigned to the 'act' region, and all other logic is assigned to
// the 'nba' region.
//
// For later practical purposes, AstAlwaysPre logic that would be assigned to
// the 'act' region is returned separately. Nevertheless, this logic is part of
// the 'act' region.
//
// For more details, please see the internals documentation.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3CallTargets.h"
#include "V3EmitV.h"
#include "V3Graph.h"
#include "V3Sched.h"
#include "V3Stats.h"

#include <array>
#include <memory>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

namespace {

class SchedSenVertex final : public V3GraphVertex {
    VL_RTTI_IMPL(SchedSenVertex, V3GraphVertex)
    const AstSenItem* const m_senItemp;  // Sensitivity item this vertex represents

public:
    SchedSenVertex(V3Graph* graphp, const AstSenItem* senItemp)
        : V3GraphVertex{graphp}
        , m_senItemp{senItemp} {}
    const AstSenItem* senItemp() const { return m_senItemp; }

    // LCOV_EXCL_START // Debug code
    string name() const override {
        std::ostringstream os;
        V3EmitV::verilogForTree(const_cast<AstSenItem*>(m_senItemp), os);
        return VString::quoteBackslash(os.str());
    }
    string dotShape() const override { return "doubleoctagon"; }
    string dotColor() const override { return "red"; }
    // LCOV_EXCL_STOP
};

class SchedLogicVertex final : public V3GraphVertex {
    VL_RTTI_IMPL(SchedLogicVertex, V3GraphVertex)
    const Process& m_process;  // The process this vertex represents

public:
    SchedLogicVertex(V3Graph* graphp, const Process& process)
        : V3GraphVertex{graphp}
        , m_process{process} {}
    const Process& process() const { return m_process; }
    AstNodeProcedure* procp() const { return m_process.m_procp; }

    // LCOV_EXCL_START // Debug code
    string name() const override VL_MT_STABLE {
        return procp()->typeName() + ("\n" + procp()->fileline()->ascii());
    };
    string dotShape() const override { return "rectangle"; }
    // LCOV_EXCL_STOP
};

class SchedVarVertex final : public V3GraphVertex {
    VL_RTTI_IMPL(SchedVarVertex, V3GraphVertex)
    const AstVarScope* const m_vscp;  // Variable scope this vertex represents

public:
    SchedVarVertex(V3Graph* graphp, AstVarScope* vscp)
        : V3GraphVertex{graphp}
        , m_vscp{vscp} {}

    AstVar* varp() const { return m_vscp->varp(); }
    const AstVarScope* vscp() const { return m_vscp; }

    // LCOV_EXCL_START // Debug code
    string name() const override VL_MT_STABLE { return m_vscp->name(); }
    string dotShape() const override {
        return m_vscp->scopep()->isTop() && m_vscp->varp()->isNonOutput() ? "invhouse" : "ellipse";
    }
    string dotColor() const override {
        return m_vscp->scopep()->isTop() && m_vscp->varp()->isNonOutput() ? "green" : "black";
    }
    // LCOV_EXCL_STOP
};

class SchedGraphBuilder final {
    // NODE STATE
    // AstVarScope::user1p() -> SchedVarVertex
    // AstSenItem::user1p() -> SchedSenVertex
    // AstVarScope::user2() -> bool: Read of this AstVarScope triggers this logic.
    //                         Used only for hybrid logic.
    const VNUser1InUse m_user1InUse;
    const VNUser2InUse m_user2InUse;

    // STATE
    V3Graph* const m_graphp = new V3Graph;  // The dataflow graph being built
    // The vertices associated with a unique AstSenItem
    std::unordered_map<VNRef<AstSenItem>, SchedSenVertex*> m_senVertices;
    // Predicate for whether a read of the given variable triggers this block
    std::function<bool(AstVarScope*)> m_readTriggersThisLogic;
    // The DPI export trigger variable, if any
    AstVarScope* const m_dpiExportTriggerp = v3Global.rootp()->dpiExportTriggerp();

    SchedVarVertex* getVarVertex(AstVarScope* vscp) const {
        if (!vscp->user1p()) {
            SchedVarVertex* const vtxp = new SchedVarVertex{m_graphp, vscp};
            // If this variable can be written via a DPI export, add a source edge from the
            // DPI export trigger vertex. This ensures calls to DPI exports that might write a
            // clock end up in the 'act' region.
            if (vscp->varp()->isWrittenByDpi()) {
                new V3GraphEdge{m_graphp, getVarVertex(m_dpiExportTriggerp), vtxp, 1};
            }
            vscp->user1p(vtxp);
        }
        return vscp->user1u().to<SchedVarVertex*>();
    }

    SchedSenVertex* getSenVertex(AstSenItem* senItemp) {
        if (!senItemp->user1p()) {
            // There is a unique SchedSenVertex for each globally unique AstSenItem. Multiple
            // AstSenTree might use the same AstSenItem (e.g.: posedge clk1 or rst, posedge clk2 or
            // rst), so we use a hash map to get the unique SchedSenVertex. (Note: This creates
            // separate vertices for ET_CHANGED and ET_HYBRID over the same expression, but that is
            // OK for now).
            const auto pair = m_senVertices.emplace(*senItemp, nullptr);
            // If it does not exist, create it
            if (pair.second) {
                // Create the vertex
                SchedSenVertex* const vtxp = new SchedSenVertex{m_graphp, senItemp};

                // Connect up the variable references
                if (senItemp->sensp()) {
                    senItemp->sensp()->foreach([&](AstVarRef* refp) {
                        new V3GraphEdge{m_graphp, getVarVertex(refp->varScopep()), vtxp, 1};
                    });
                }

                // Store back to hash map so we can find it next time
                pair.first->second = vtxp;
            }

            // Cache sensitivity vertex
            senItemp->user1p(pair.first->second);
        }
        return senItemp->user1u().to<SchedSenVertex*>();
    }

    void visitLogic(const Process& process) {
        AstNodeProcedure* const nodep = process.m_procp;
        AstSenTree* const senTreep = process.m_senTreep;

        SchedLogicVertex* const logicVtxp = new SchedLogicVertex{m_graphp, process};

        // Clocked or hybrid logic has explicit sensitivity, so add edge from sensitivity vertex
        if (!senTreep->hasCombo()) {
            senTreep->foreach([this, nodep, logicVtxp](AstSenItem* senItemp) {
                UASSERT_OBJ(senItemp->isClocked() || senItemp->isHybrid(), nodep,
                            "Non-clocked SenItem under clocked SenTree");
                V3GraphVertex* const eventVtxp = getSenVertex(senItemp);
                new V3GraphEdge{m_graphp, eventVtxp, logicVtxp, 10};
            });
        }

        // Add edges based on references
        V3Sched::util::VarScopeSet forceReadEdgeIgnores;
        V3Sched::util::collectForceReadEdgeIgnores(nodep, forceReadEdgeIgnores);
        nodep->foreach([this, logicVtxp, &forceReadEdgeIgnores](const AstVarRef* vrefp) {
            AstVarScope* const vscp = vrefp->varScopep();
            if (vrefp->access().isReadOrRW() && m_readTriggersThisLogic(vscp)
                && !forceReadEdgeIgnores.count(vscp)) {
                new V3GraphEdge{m_graphp, getVarVertex(vscp), logicVtxp, 10};
            }
            if (vrefp->access().isWriteOrRW() && !vrefp->varp()->ignoreSchedWrite()) {
                new V3GraphEdge{m_graphp, logicVtxp, getVarVertex(vscp), 10};
            }
        });

        // If the logic calls a 'context' DPI import, it might fire the DPI Export trigger
        if (m_dpiExportTriggerp) {
            nodep->foreach([this, logicVtxp](const AstCCall* callp) {
                if (!callp->funcp()->dpiImportWrapper()) return;
                if (!callp->funcp()->dpiContext()) return;
                new V3GraphEdge{m_graphp, logicVtxp, getVarVertex(m_dpiExportTriggerp), 10};
            });
        }
    }

    SchedGraphBuilder(const ProcessList& clockedLogic, const ProcessList& combinationalLogic,
                      const ProcessList& hybridLogic) {
        // Build the data flow graph
        const auto iter = [this](const ProcessList& procList) {
            for (const Process& process : procList) {
                AstNodeProcedure* const procp = process.m_procp;
                AstSenTree* const senTreep = process.m_senTreep;
                UASSERT_OBJ(senTreep->hasClocked() || senTreep->hasCombo()
                                || senTreep->hasHybrid(),
                            senTreep, "Unhandled");
                UASSERT_OBJ(!VN_IS(procp, Initial), procp, "Should not need ordering");
                UASSERT_OBJ(!VN_IS(procp, InitialStatic), procp, "Should not need ordering");
                UASSERT_OBJ(!VN_IS(procp, Final), procp, "Should not need ordering");
                // Pre and Post logic are handled separately
                if (VN_IS(procp, AlwaysPre) || VN_IS(procp, AlwaysPost)) {
                    UASSERT_OBJ(senTreep->hasClocked(), procp, "Should be clocked");
                    continue;
                }
                // Mark explicit sensitivities as not triggering this logic
                if (senTreep->hasHybrid()) {
                    AstNode::user2ClearTree();
                    senTreep->foreach([](const AstVarRef* refp) {  //
                        refp->varScopep()->user2(true);
                    });
                }
                visitLogic(process);
            }
        };
        // Clocked logic is never triggered by reads
        m_readTriggersThisLogic = [](AstVarScope*) { return false; };
        iter(clockedLogic);
        // Combinational logic is always triggered by reads
        m_readTriggersThisLogic = [](AstVarScope*) { return true; };
        iter(combinationalLogic);
        // Hybrid logic is triggered by all reads, except for reads of the explicit sensitivities
        m_readTriggersThisLogic = [](AstVarScope* vscp) { return !vscp->user2(); };
        iter(hybridLogic);
    }

public:
    // Build the dataflow graph for partitioning
    static std::unique_ptr<V3Graph> build(const ProcessList& clockedLogic,
                                          const ProcessList& combinationalLogic,
                                          const ProcessList& hybridLogic) {
        const SchedGraphBuilder visitor{clockedLogic, combinationalLogic, hybridLogic};
        return std::unique_ptr<V3Graph>{visitor.m_graphp};
    }
};

// With a #0 delay, the 'inact' region runs suspendable code between the 'act' and 'nba'
// sections. Inactive region events run only once the Active region is empty (IEEE 1800-2023
// 4.4.2.3, 4.5), so a clocked process triggered in the time step must have run before them.
// Running it in 'nba' instead is unobservable only if it does not interact with what can run
// after a #0 delay in the time step: suspendable code with a delay that may be zero, and code
// woken by what that writes, including combinational logic and re-triggered processes.
// Computes the logic that must run in 'act' for this, and the variables it reads, whose
// combinational drivers must then run in 'act' as well.
class ZeroDelayPinning final {
public:
    // Why logic is pinned, the first that applies
    enum Reason : uint8_t {
        TRIGGERED,
        SIDE_EFFECT,
        READS,
        WRITES_READ,
        WRITES,
        MEMBER,
        _ENUM_END
    };

private:
    // TYPES
    // What a body of code accesses. A class or interface member accessed through a reference
    // (including a virtual interface) may be that member of any object, or of any instance a
    // reference can be made to.
    struct Body final {
        std::unordered_set<const AstVarScope*> m_reads;  // Variables read
        std::unordered_set<const AstVarScope*> m_writes;  // Variables written
        std::unordered_set<const AstVar*> m_memberReads;  // Members read through a reference
        std::unordered_set<const AstVar*> m_memberWrites;  // Members written through one
        std::unordered_set<const AstVarScope*> m_triggers;  // Variables triggering it
        SchedLogicVertex* m_logicp = nullptr;  // The logic, if not suspendable code
        bool m_sideEffect = false;  // Accesses runtime state shared with other processes
        bool m_endsTimeStep = false;  // May end the time step: $finish, $stop or $fatal
        bool m_contextDpi = false;  // Calls a context DPI import, which may call DPI exports
        bool m_foreign = false;  // Runs user C code or a DPI import, which may access via VPI
        bool m_after = false;  // Runs after a #0
    };

    // STATE
    const std::unique_ptr<V3CallTargets> m_callTargetsp;  // To get the functions a call may call
    std::vector<Body> m_bodies;  // Logic, then suspendable code
    std::unordered_set<const AstVarScope*> m_written;  // Written after a #0
    std::unordered_set<const AstVarScope*> m_read;  // Read after a #0
    std::unordered_set<const AstVar*> m_memberWritten;  // Members written through a reference
    std::unordered_set<const AstVar*> m_memberRead;  // Members read through a reference
    // Variables of what is written or read after a #0 that a reference can reach
    std::unordered_set<const AstVar*> m_writtenVars;
    std::unordered_set<const AstVar*> m_readVars;
    std::vector<const AstVarScope*> m_pendingWrites;  // Written, readers not yet woken
    std::vector<const AstVar*> m_pendingMembers;  // Members written, readers not yet woken
    std::vector<const AstVarScope*> m_dpiWritten;  // Variables a DPI export may write
    bool m_afterSideEffect = false;  // Code after a #0 has an output or DPI effect
    bool m_afterContextDpi = false;  // Code after a #0 calls a context DPI import
    bool m_anyMember = false;  // Whether any body accesses a member through a reference
    bool m_afterForeign = false;  // Code after a #0 runs user C code or a DPI import
    bool m_afterPublic = false;  // Code after a #0 accesses a variable public to VPI
    // Interface instances, and interfaces of all instances, a reference may be made to
    bool m_referencesFound = false;
    std::unordered_set<const AstCell*> m_referencedCells;
    std::unordered_set<const AstNodeModule*> m_referencedIfaces;
    std::vector<V3GraphVertex*> m_seeds;  // Pinned logic, and the variables it reads
    std::array<size_t, _ENUM_END> m_nPinned{};  // Number of pinned logic vertices, by reason
    size_t m_nVisits = 0;  // Number of bodies visited for being woken, for complexity

    // METHODS
    // Accesses of the given code, including the functions it calls
    void collect(AstNode* nodep, Body& body, std::unordered_set<const AstCFunc*>& visited) {
        nodep->foreach([&](AstNode* np) {
            if (const AstNodeVarRef* const refp = VN_CAST(np, NodeVarRef)) {
                if (refp->access().isReadOrRW()) body.m_reads.emplace(refp->varScopep());
                if (refp->access().isWriteOrRW() && !refp->varp()->ignoreSchedWrite()) {
                    body.m_writes.emplace(refp->varScopep());
                }
            } else if (const AstMemberRef* const memberp = VN_CAST(np, MemberRef)) {
                if (memberp->access().isReadOrRW()) body.m_memberReads.emplace(memberp->varp());
                if (memberp->access().isWriteOrRW()) {
                    body.m_memberWrites.emplace(memberp->varp());
                }
            } else if (const AstNodeCCall* const callp = VN_CAST(np, NodeCCall)) {
                // Including the overriding functions a virtual call may run
                for (AstCFunc* const funcp : m_callTargetsp->getTargets(callp)) {
                    if (funcp->dpiImportWrapper()) {
                        body.m_sideEffect = true;
                        body.m_foreign = true;
                        if (funcp->dpiContext()) body.m_contextDpi = true;
                    }
                    if (visited.emplace(funcp).second) collect(funcp, body, visited);
                }
            } else if (util::accessesRuntimeState(np)) {
                body.m_sideEffect = true;
                if (VN_IS(np, Finish) || VN_IS(np, Stop)) body.m_endsTimeStep = true;
                if (VN_IS(np, CExprUser) || VN_IS(np, CStmtUser)) body.m_foreign = true;
            }
        });
    }
    // Find the interface instances a reference may be made to: those whose handle is read
    void findReferences() {
        m_referencesFound = true;
        v3Global.rootp()->foreach([&](const AstNodeExpr* exprp) {
            if (!exprp->dtypep()) return;
            const AstNodeDType* dtypep = exprp->dtypep()->skipRefp();
            bool array = false;
            while (const AstNodeArrayDType* const adtypep = VN_CAST(dtypep, NodeArrayDType)) {
                dtypep = adtypep->subDTypep()->skipRefp();
                array = true;
            }
            const AstIfaceRefDType* const idtypep = VN_CAST(dtypep, IfaceRefDType);
            if (!idtypep || idtypep->isVirtual()) return;
            const AstNodeVarRef* const refp = VN_CAST(exprp, NodeVarRef);
            if (refp && !refp->access().isReadOrRW()) return;
            if (refp && !array && idtypep->cellp()) {
                m_referencedCells.emplace(idtypep->cellp());
            } else {
                // Any instance of the interface
                m_referencedIfaces.emplace(idtypep->ifaceViaCellp());
            }
        });
    }
    // Whether an access through a reference may access the variable: a class member, or a
    // member of an interface instance a reference may be made to
    bool reachable(const AstVarScope* vscp) {
        const AstScope* const scopep = vscp->scopep();
        if (!VN_IS(scopep->modp(), Iface)) return true;
        if (!m_referencesFound) findReferences();
        return m_referencedIfaces.count(scopep->modp())
               || m_referencedCells.count(scopep->aboveCellp());
    }
    static bool isPublic(const AstVarScope* vscp) {
        return vscp->varp()->isSigUserRdPublic() || vscp->varp()->isSigUserRWPublic();
    }
    template <typename T>
    static bool intersects(const std::unordered_set<T>& as, const std::unordered_set<T>& bs) {
        for (const T& item : as) {
            if (bs.count(item)) return true;
        }
        return false;
    }
    // Whether any of the variables may be accessed as one of the members
    bool reachableIntersects(const std::unordered_set<const AstVarScope*>& vscps,
                             const std::unordered_set<const AstVar*>& varps) {
        if (varps.empty()) return false;
        for (const AstVarScope* const vscp : vscps) {
            if (varps.count(vscp->varp()) && reachable(vscp)) return true;
        }
        return false;
    }
    void addWritten(const AstVarScope* vscp) {
        if (!m_written.emplace(vscp).second) return;
        if (m_anyMember && reachable(vscp)) m_writtenVars.emplace(vscp->varp());
        m_pendingWrites.push_back(vscp);
    }
    // Record that the body runs after a #0, so what it writes wakes others
    void markAfter(size_t index) {
        Body& body = m_bodies[index];
        if (body.m_after) return;
        body.m_after = true;
        m_read.insert(body.m_reads.begin(), body.m_reads.end());
        if (m_anyMember) {
            for (const AstVarScope* const vscp : body.m_reads) {
                if (reachable(vscp)) m_readVars.emplace(vscp->varp());
            }
        }
        m_memberRead.insert(body.m_memberReads.begin(), body.m_memberReads.end());
        m_readVars.insert(body.m_memberReads.begin(), body.m_memberReads.end());
        for (const AstVarScope* const vscp : body.m_writes) addWritten(vscp);
        for (const AstVar* const varp : body.m_memberWrites) {
            m_writtenVars.emplace(varp);
            if (m_memberWritten.emplace(varp).second) m_pendingMembers.push_back(varp);
        }
        if (body.m_sideEffect) m_afterSideEffect = true;
        if (!m_afterPublic) {
            for (const AstVarScope* const vscp : body.m_reads) {
                if (isPublic(vscp)) m_afterPublic = true;
            }
            for (const AstVarScope* const vscp : body.m_writes) {
                if (isPublic(vscp)) m_afterPublic = true;
            }
        }
        if (body.m_foreign && !m_afterForeign) {
            // Through VPI it may access any public variable
            m_afterForeign = true;
            for (const Body& other : m_bodies) {
                for (const std::unordered_set<const AstVarScope*>* const vscpsp :
                     {&other.m_reads, &other.m_writes}) {
                    for (const AstVarScope* const vscp : *vscpsp) {
                        if (!isPublic(vscp)) continue;
                        m_afterPublic = true;
                        m_read.emplace(vscp);
                        if (m_anyMember && reachable(vscp)) m_readVars.emplace(vscp->varp());
                        if (vscp->varp()->isSigUserRWPublic()) addWritten(vscp);
                    }
                }
            }
        }
        if (body.m_contextDpi && !m_afterContextDpi) {
            // A DPI export it calls may write these
            m_afterContextDpi = true;
            for (const AstVarScope* const vscp : m_dpiWritten) addWritten(vscp);
        }
    }
    // Why the logic must run in 'act', if it must
    bool pinReason(const Body& body, Reason& reason) {
        if (body.m_after) {
            reason = TRIGGERED;
        } else if (body.m_endsTimeStep || body.m_contextDpi
                   || (body.m_sideEffect && m_afterSideEffect)
                   || (body.m_foreign && m_afterPublic)) {
            // Accessing runtime state other than variables is only ordered against code after a
            // #0 that accesses such state too, except for ending the time step, calling DPI
            // exports that may access anything, and accessing variables public to VPI that code
            // after a #0 accesses
            reason = SIDE_EFFECT;
        } else if (intersects(body.m_reads, m_written)) {
            reason = READS;
        } else if (intersects(body.m_writes, m_read)) {
            reason = WRITES_READ;
        } else if (intersects(body.m_writes, m_written)) {
            reason = WRITES;
        } else if (m_anyMember
                   && (intersects(body.m_memberReads, m_writtenVars)
                       || intersects(body.m_memberWrites, m_readVars)
                       || intersects(body.m_memberWrites, m_writtenVars)
                       || reachableIntersects(body.m_reads, m_memberWritten)
                       || reachableIntersects(body.m_writes, m_memberRead)
                       || reachableIntersects(body.m_writes, m_memberWritten))) {
            reason = MEMBER;
        } else {
            return false;
        }
        return true;
    }

public:
    // CONSTRUCTORS
    ZeroDelayPinning(V3Graph& graph, const std::vector<SuspendableCode>& suspendables)
        : m_callTargetsp{V3CallTargets::build()} {
        std::unordered_map<const AstVarScope*, V3GraphVertex*> varVtxps;
        for (V3GraphVertex& vtx : graph.vertices()) {
            if (SchedVarVertex* const vvtxp = vtx.cast<SchedVarVertex>()) {
                varVtxps.emplace(vvtxp->vscp(), vvtxp);
            } else if (SchedLogicVertex* const lvtxp = vtx.cast<SchedLogicVertex>()) {
                m_bodies.emplace_back();
                Body& body = m_bodies.back();
                body.m_logicp = lvtxp;
                std::unordered_set<const AstCFunc*> visited;
                collect(lvtxp->procp(), body, visited);
                AstSenTree* const senTreep = lvtxp->process().m_senTreep;
                if (senTreep->hasClocked()) {
                    senTreep->foreach([&](const AstVarRef* refp) {
                        body.m_triggers.emplace(refp->varScopep());
                    });
                } else {
                    // Combinational logic is evaluated whenever what it reads changes
                    body.m_triggers = body.m_reads;
                }
            }
        }
        const size_t nLogic = m_bodies.size();
        for (const SuspendableCode& code : suspendables) {
            m_bodies.emplace_back();
            Body& body = m_bodies.back();
            body.m_reads = code.m_reads;
            body.m_writes = code.m_writes;
            body.m_memberReads = code.m_memberReads;
            body.m_memberWrites = code.m_memberWrites;
            body.m_triggers = code.m_triggers;
            body.m_sideEffect = code.m_sideEffect;
            body.m_contextDpi = code.m_contextDpi;
            body.m_foreign = code.m_foreign;
        }
        // The variables a DPI export may write, of those any logic accesses
        std::unordered_set<const AstVarScope*> dpiWritten;
        for (const Body& body : m_bodies) {
            if (!body.m_memberReads.empty() || !body.m_memberWrites.empty()) m_anyMember = true;
            for (const std::unordered_set<const AstVarScope*>* const vscpsp :
                 {&body.m_reads, &body.m_writes}) {
                for (const AstVarScope* const vscp : *vscpsp) {
                    if (vscp->varp()->isWrittenByDpi() && dpiWritten.emplace(vscp).second) {
                        m_dpiWritten.push_back(vscp);
                    }
                }
            }
        }
        // The bodies each variable triggers, by variable scope, and by variable for members
        std::unordered_map<const AstVarScope*, std::vector<size_t>> triggered;
        std::unordered_map<const AstVar*, std::vector<size_t>> triggeredByVar;
        for (size_t i = 0; i < m_bodies.size(); ++i) {
            for (const AstVarScope* const vscp : m_bodies[i].m_triggers) {
                triggered[vscp].push_back(i);
                if (m_anyMember && reachable(vscp)) triggeredByVar[vscp->varp()].push_back(i);
            }
        }
        // What runs after a #0, as a work list over what it writes, so each body is visited
        // once for each variable triggering it. A body awaiting something other than
        // variables, e.g. a join, may be woken by such code.
        for (size_t i = 0; i < suspendables.size(); ++i) {
            const SuspendableCode& code = suspendables[i];
            if (code.m_zeroDelay || code.m_wakeAny) markAfter(nLogic + i);
        }
        while (!m_pendingWrites.empty() || !m_pendingMembers.empty()) {
            const std::vector<size_t>* indicesp = nullptr;
            if (!m_pendingWrites.empty()) {
                const auto it = triggered.find(m_pendingWrites.back());
                m_pendingWrites.pop_back();
                if (it != triggered.end()) indicesp = &it->second;
            } else {
                const auto it = triggeredByVar.find(m_pendingMembers.back());
                m_pendingMembers.pop_back();
                if (it != triggeredByVar.end()) indicesp = &it->second;
            }
            if (!indicesp) continue;
            for (const size_t i : *indicesp) {
                ++m_nVisits;
                markAfter(i);
            }
        }
        // Pinned is what would otherwise observe, be observed or be overwritten in the wrong
        // order
        for (size_t i = 0; i < nLogic; ++i) {
            const Body& body = m_bodies[i];
            Reason reason;
            if (!pinReason(body, reason)) continue;
            UINFO(4, "Pinned to 'act' for #0, reason " << static_cast<int>(reason) << ": "
                                                       << body.m_logicp->procp());
            ++m_nPinned[reason];
            m_seeds.push_back(body.m_logicp);
            for (const AstVarScope* const vscp : body.m_reads) {
                const auto it = varVtxps.find(vscp);
                if (it != varVtxps.end()) m_seeds.push_back(it->second);
            }
        }
    }
    const std::vector<V3GraphVertex*>& seeds() const { return m_seeds; }
    size_t nPinned() const {
        size_t n = 0;
        for (const size_t count : m_nPinned) n += count;
        return n;
    }
    size_t nPinned(Reason reason) const { return m_nPinned[reason]; }
    size_t nVisits() const { return m_nVisits; }
};

void traceActiveRegion(std::vector<V3GraphVertex*>& queue, const bool markClocks) {
    // Depth first traversal
    while (!queue.empty()) {
        // Pop next work item
        V3GraphVertex& vtx = *queue.back();
        queue.pop_back();
        // If not first encounter, move on
        if (vtx.color() != 0) continue;

        // Mark vertex as being in active region
        vtx.color(1);

        // Enqueue all parent vertices that feed this vertex.
        for (V3GraphEdge& edge : vtx.inEdges()) queue.push_back(edge.fromp());

        // Mark top level ports that drive a sensitivity list
        if (SchedVarVertex* const vvtxp = vtx.cast<SchedVarVertex>()) {
            AstVar* const varp = vvtxp->varp();
            if (markClocks && varp->isPrimaryIO()) varp->setPrimaryClock();
        }

        // If this is a logic vertex, also enqueue all variable vertices that are driven from this
        // logic. This will ensure that if a variable is set in the active region, then all
        // settings of that variable will be in the active region.
        if (vtx.is<SchedLogicVertex>()) {
            for (V3GraphEdge& edge : vtx.outEdges()) {
                UASSERT(edge.top()->is<SchedVarVertex>(), "Should be var vertex");
                queue.push_back(edge.top());
            }
        }
    }
}

size_t countActiveLogic(const V3Graph& graph) {
    size_t count = 0;
    for (const V3GraphVertex& vtx : graph.vertices()) {
        if (vtx.is<SchedLogicVertex>() && vtx.color()) ++count;
    }
    return count;
}

// Returns the number of logic vertices pinned for #0 delays that triggers alone would not move
// to 'act', and the number of others that the seeds moved to 'act'
std::pair<size_t, size_t> colorActiveRegion(V3Graph& graph,
                                            const std::vector<V3GraphVertex*>& seeds) {
    // Work queue for depth first traversal
    std::vector<V3GraphVertex*> queue{};

    // Trace from all SchedSenVertex, first from those other than of the updates V3Force makes, so
    // only the ports driving those others are clocks
    for (const bool forceUpdate : {false, true}) {
        for (V3GraphVertex& vtx : graph.vertices()) {
            if (const SchedSenVertex* const senVtxp = vtx.cast<SchedSenVertex>()) {
                if (senVtxp->senItemp()->forceUpdate() == forceUpdate) queue.push_back(&vtx);
            }
        }
        traceActiveRegion(queue, !forceUpdate);
    }
    if (seeds.empty()) return {0, 0};
    // Then from the logic pinned for #0 delays, which drives no clock
    const size_t nBefore = countActiveLogic(graph);
    size_t nSeeds = 0;
    for (V3GraphVertex* const vtxp : seeds) {
        if (vtxp->is<SchedLogicVertex>() && !vtxp->color()) ++nSeeds;
    }
    queue = seeds;
    traceActiveRegion(queue, false);
    return {nSeeds, countActiveLogic(graph) - nBefore - nSeeds};
}

}  // namespace

LogicRegions partition(LogicClasses& logicClasses,
                       const std::vector<SuspendableCode>& suspendables) {
    UINFO(2, __FUNCTION__ << ":");

    // All of these classes are moved to the result
    ProcessList clockedLogic = std::move(logicClasses.m_clocked);
    const ProcessList combinationalLogic = std::move(logicClasses.m_comb);
    const ProcessList hybridLogic = std::move(logicClasses.m_hybrid);

    // Build the graph
    const std::unique_ptr<V3Graph> graphp
        = SchedGraphBuilder::build(clockedLogic, combinationalLogic, hybridLogic);
    if (dumpGraphLevel() >= 6) graphp->dumpDotFilePrefixed("sched");

    // Partition into Active and NBA regions, with the logic pinned for #0 delays in 'act'
    std::vector<V3GraphVertex*> seeds;
    if (v3Global.usesZeroDelay()) {
        const ZeroDelayPinning pinning{*graphp, suspendables};
        seeds = pinning.seeds();
        if (v3Global.opt.stats()) {
            V3Stats::addStat("Scheduling, zero delay, logic pinned to 'act'", pinning.nPinned());
            const std::array<std::pair<ZeroDelayPinning::Reason, const char*>,
                             ZeroDelayPinning::_ENUM_END>
                reasons{{{ZeroDelayPinning::TRIGGERED, "triggered after #0"},
                         {ZeroDelayPinning::SIDE_EFFECT, "side effect"},
                         {ZeroDelayPinning::READS, "reads written after #0"},
                         {ZeroDelayPinning::WRITES_READ, "writes read after #0"},
                         {ZeroDelayPinning::WRITES, "writes written after #0"},
                         {ZeroDelayPinning::MEMBER, "member access"}}};
            for (const std::pair<ZeroDelayPinning::Reason, const char*>& reason : reasons) {
                V3Stats::addStat(std::string{"Scheduling, zero delay, logic pinned, "}
                                     + reason.second,
                                 pinning.nPinned(reason.first));
            }
            V3Stats::addStat("Scheduling, zero delay, woken body visits", pinning.nVisits());
        }
    }
    const std::pair<size_t, size_t> moved = colorActiveRegion(*(graphp.get()), seeds);
    // Whether logic that could go to 'nba' went to 'act' for #0
    const bool movedToAct = moved.first || moved.second;
    if (v3Global.opt.stats() && v3Global.usesZeroDelay()) {
        V3Stats::addStat("Scheduling, zero delay, logic moved for pinned logic reads",
                         moved.second);
    }
    if (dumpGraphLevel() >= 6) graphp->dumpDotFilePrefixed("sched-partitioned", true);

    LogicRegions result;
    result.m_obs = std::move(logicClasses.m_observed);
    result.m_react = std::move(logicClasses.m_reactive);

    for (V3GraphVertex& vtx : graphp->vertices()) {
        if (const auto lvtxp = vtx.cast<SchedLogicVertex>()) {
            // Move to 'act'/'nba' based on coloring
            ProcessList& procList = lvtxp->color() ? result.m_act : result.m_nba;
            procList.add(lvtxp->process());
        }
    }
    // Only 'nba' logic runs in parallel, so say why it lost its parallelism. Informational,
    // as the design is correct as it is.
    if (movedToAct && v3Global.opt.mtasks()) {
        if (FileLine* const flp = v3Global.zeroDelayFlp()) {
            flp->v3info("Supporting static #0 delays moves logic out of the 'nba' region,"
                        " where '--threads' can run it in parallel, into the single-threaded"
                        " 'act' region.\n"
                        << flp->warnMore()  //
                        << "... If no #0 delay is executed at runtime,\n"
                        << flp->warnMore()  //
                        << "... use '--no-sched-zero-delay' for improved performance.\n"
                        << flp->warnMore()  //
                        << "... If a real #0 is expected at runtime,\n"
                        << flp->warnMore()  //
                        << "... use '--sched-zero-delay' to suppress this message.");
        }
    }

    // Partition the Pre logic
    {
        const VNUser1InUse user1InUse;  // AstVarScope::user1() -> bool: read in Active region
        const VNUser2InUse user2InUse;  // AstVarScope::user2() -> bool: written in Active region

        const auto markVars = [](AstNode* nodep) {
            nodep->foreach([](const AstNodeVarRef* vrefp) {
                AstVarScope* const vscp = vrefp->varScopep();
                if (vrefp->access().isReadOrRW()) vscp->user1(true);
                if (vrefp->access().isWriteOrRW() && !vrefp->varp()->ignoreSchedWrite())
                    vscp->user2(true);
            });
        };

        for (const Process& process : result.m_act) {
            markVars(process.m_senTreep);
            markVars(process.m_procp);
        }

        // AstAlwaysPre and AstAlwaysPost only appear in clocked logic
        for (Process& process : clockedLogic) {
            AstNodeProcedure* const nodep = process.m_procp;
            if (AstAlwaysPre* const logicp = VN_CAST(nodep, AlwaysPre)) {
                bool toActiveRegion = false;
                logicp->foreach([&](const AstNodeVarRef* vrefp) {
                    AstVarScope* const vscp = vrefp->varScopep();
                    if (vrefp->access().isReadOnly()) {
                        // Variable only read in Pre, and is written in active region
                        if (vscp->user2()) toActiveRegion = true;
                    } else {
                        // Variable written in Pre, and referenced in active region
                        if (vscp->user1() || vscp->user2()) toActiveRegion = true;
                    }
                });
                ProcessList& procList = toActiveRegion ? result.m_pre : result.m_nba;
                procList.add(std::move(process));
            } else if (VN_IS(nodep, AlwaysPost)) {
                result.m_nba.add(std::move(process));
            }
        }
    }

    return result;
}

}  // namespace V3Sched
