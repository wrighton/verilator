// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: NFA-based multi-cycle SVA assertion evaluation
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2005-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
// V3AssertNfa's Transformations:
//
//  - Lower the local variable assignments of match items into temps read
//    through $past.
//  - Convert multi-cycle SVA sequences/properties into NFA graphs.
//  - Attach inherited assertion clocks before moving sampled-value functions.
//  - Emit module-level state registers driven by AstAlways blocks.
//  - Replace converted assertions with combinational match/reject checks
//    so V3AssertPre sees no multi-cycle SExpr (unsupported ones fall through).
//
//  Members marked OWNED hold an AST tree this pass allocated and must delete;
//  they are not linked into the netlist.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3AssertNfa.h"

#include "V3Assert.h"
#include "V3Const.h"
#include "V3Graph.h"
#include "V3Stats.h"
#include "V3UniqueNames.h"

#include <unordered_set>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// NFA Graph Data Structures (V3Graph-derived per upstream convention)

namespace {

class SvaStateVertex;

// Per-vertex algorithm data, stored via V3GraphVertex::userp() during lowering
struct SvaVertexData final {
    AstVar* stateVarp = nullptr;  // NBA state register for this vertex
    AstVar* delayRingVarp = nullptr;  // Packed occupancy bits or per-slot match counts
    AstVar* delayRingHeadVarp
        = nullptr;  // Cached outgoing slot; isolates readers from in-place writes
    AstVar* delayRingIdxVarp = nullptr;  // Next slot written in delayRingVarp
    AstVar* delayRingLiveCountVarp = nullptr;  // Number of threads in delayRingVarp
    AstVar* delayRingWrappedVarp = nullptr;  // All slots written since the last clear
    AstVar* doneLVarp = nullptr;  // SAnd LHS done-latch
    AstVar* doneRVarp = nullptr;  // SAnd RHS done-latch
    AstNodeExpr* stateSigp = nullptr;  // Combinational state signal; OWNED during lowering
    AstNodeExpr* stateCountSigp = nullptr;  // Cover-sequence match count; OWNED during lowering
    AstNodeExpr* stateCountOverflowSigp = nullptr;  // Count overflow; OWNED during lowering
    bool delayRingCounts = false;  // Ring slots hold thread counts
    bool stateCounts = false;  // stateVarp holds a thread count, not a bit
    bool needsReg = false;  // True if vertex has incoming clocked edge
};

// NFA state vertex -- one per NFA position in the sequence evaluation
class SvaStateVertex final : public V3GraphVertex {
    VL_RTTI_IMPL(SvaStateVertex, V3GraphVertex)
public:
    // True if this is the sequence-match terminal vertex
    bool m_isMatch = false;
    // OWNED throughout-guard condition clones; IEEE 1800-2023 16.9.9
    std::vector<AstNodeExpr*> m_throughoutConds;
    // Nonzero for a ring-buffer vertex for ## delays.
    bool m_isFixedDelayRing = false;
    unsigned m_delayRingSize = 0;  // Number of ring slots. Range: max-min+1.
    AstNodeExpr* m_delayRingClearCondp = nullptr;  // local RHS for pure-boolean range
    AstNodeExpr* m_delayRingAdvanceCondp = nullptr;  // Advance only when this condition holds
    bool m_replayAbortReject = false;  // Compressed repetition needs per-thread abort replay
    // OWNED; enclosing-abort fire condition clearing state or suppressing guard rejection
    AstNodeExpr* m_abortClearp = nullptr;
    // OWNED; reject-abort fire condition rejecting all represented live threads
    AstNodeExpr* m_abortRejectp = nullptr;
    // Liveness terminal (IEEE weak semantics): reject must not fire from this source
    bool m_isUnbounded = false;
    // Implication antecedent vertex: a dropped throughout guard ends the attempt without
    // a verdict, as a non-matching antecedent is vacuously true (IEEE 1800-2023 16.12.7)
    bool m_isAntecedent = false;
    // Temporal sequence AND combiner; IEEE 1800-2023 16.9.5
    bool m_isAndCombiner = false;
    SvaStateVertex* m_andLhsTermp = nullptr;  // LHS sub-NFA terminal vertex
    SvaStateVertex* m_andRhsTermp = nullptr;  // RHS sub-NFA terminal vertex
    AstNodeExpr* m_andLhsCondp = nullptr;  // OWNED; LHS final condition (may be nullptr)
    AstNodeExpr* m_andRhsCondp = nullptr;  // OWNED; RHS final condition (may be nullptr)
    // Reject sink for SAnd rejectOnFail wiring; not a state-signal source
    bool m_isRejectSink = false;
    // Vertex of a strong s_always[m:n] attempt: if its state is still set at
    // end-of-simulation the universal-quantifier window never completed, which is
    // a liveness failure (IEEE 1800-2023 16.12.11 strong semantics).
    bool m_strongPending = false;

    // CONSTRUCTORS
    explicit SvaStateVertex(V3Graph* graphp)
        : V3GraphVertex{graphp} {}
    ~SvaStateVertex() override {
        for (AstNodeExpr* cp : m_throughoutConds) VL_DO_DANGLING(cp->deleteTree(), cp);
        if (m_delayRingClearCondp)
            VL_DO_DANGLING(m_delayRingClearCondp->deleteTree(), m_delayRingClearCondp);
        if (m_delayRingAdvanceCondp)
            VL_DO_DANGLING(m_delayRingAdvanceCondp->deleteTree(), m_delayRingAdvanceCondp);
        if (m_abortClearp) VL_DO_DANGLING(m_abortClearp->deleteTree(), m_abortClearp);
        if (m_abortRejectp) VL_DO_DANGLING(m_abortRejectp->deleteTree(), m_abortRejectp);
        if (m_andLhsCondp) VL_DO_DANGLING(m_andLhsCondp->deleteTree(), m_andLhsCondp);
        if (m_andRhsCondp) VL_DO_DANGLING(m_andRhsCondp->deleteTree(), m_andRhsCondp);
    }
    // METHODS
    // LCOV_EXCL_START -- Graphviz dump only
    string name() const override {
        string name = "s" + cvtToStr(color());
        if (m_delayRingSize) {
            name += "\\n";
            name += m_isFixedDelayRing ? "fixed chain " : "range chain ";
            name += cvtToStr(m_delayRingSize) + " slots";
        }
        return name;
    }
    string dotColor() const override {
        if (m_isMatch) return "red";
        if (m_delayRingSize) return "blue";
        if (m_isAndCombiner) return "purple";
        return "black";
    }
    // LCOV_EXCL_STOP
    // Access per-vertex algorithm data (valid only during lowering phase)
    SvaVertexData* datap() const { return static_cast<SvaVertexData*>(userp()); }
};

// NFA transition edge -- clocked (##1) or combinational link (##0)
class SvaTransEdge final : public V3GraphEdge {
    VL_RTTI_IMPL(SvaTransEdge, V3GraphEdge)
public:
    AstNodeExpr* m_condp;  // Transition condition; nullptr = unconditional; OWNED
    bool m_consumesCycle;  // true = clocked edge (##1), false = link (##0/boolean)
    // Reject when source is active and condp is false; set only on
    // outermost required-step Link
    bool m_rejectOnFail = false;
    // Optional dynamic condition vertex for m_rejectOnFail. Used when the
    // success condition is another NFA state rather than a static expression.
    SvaStateVertex* m_condVtxp = nullptr;
    bool m_abortReject = false;  // m_rejectOnFail edge rejecting a live thread on an abort

    // CONSTRUCTORS
    SvaTransEdge(V3Graph* graphp, V3GraphVertex* fromp, V3GraphVertex* top, AstNodeExpr* condp,
                 bool consumesCycle)
        : V3GraphEdge{graphp, fromp, top, /*weight=*/1}
        , m_condp{condp}
        , m_consumesCycle{consumesCycle} {}
    ~SvaTransEdge() override {
        if (m_condp) VL_DO_DANGLING(m_condp->deleteTree(), m_condp);
    }
    // METHODS
    // LCOV_EXCL_START -- Graphviz dump only
    string dotLabel() const override { return m_consumesCycle ? "##1" : "link"; }
    string dotStyle() const override { return m_consumesCycle ? "" : "dashed"; }
    // LCOV_EXCL_STOP
    // Typed accessors for NFA vertices
    SvaStateVertex* fromVtxp() const { return static_cast<SvaStateVertex*>(fromp()); }
    SvaStateVertex* toVtxp() const { return static_cast<SvaStateVertex*>(top()); }
};

// NFA graph container
class SvaGraph final {
public:
    V3Graph m_graph;  // Owns all vertices and edges
    SvaStateVertex* m_startVertexp = nullptr;  // Trigger/start vertex
    SvaStateVertex* m_matchVertexp = nullptr;  // Sequence-match terminal vertex
    std::vector<SvaStateVertex*> m_vacuousVertices;  // Vacuous success terminal per implication

    // Create a new state vertex
    SvaStateVertex* createStateVertex() { return new SvaStateVertex{&m_graph}; }
    // Create the match terminal vertex
    SvaStateVertex* createMatchVertex() {
        SvaStateVertex* const vtxp = createStateVertex();
        vtxp->m_isMatch = true;
        m_matchVertexp = vtxp;
        return vtxp;
    }
    // Add a clocked transition edge (##1)
    SvaTransEdge* addClockedEdge(SvaStateVertex* fromp, SvaStateVertex* top,
                                 AstNodeExpr* condp = nullptr) {
        return new SvaTransEdge{&m_graph, fromp, top, condp, /*consumesCycle=*/true};
    }
    // Add a combinational link (##0 / boolean condition)
    SvaTransEdge* addLink(SvaStateVertex* fromp, SvaStateVertex* top,
                          AstNodeExpr* condp = nullptr) {
        return new SvaTransEdge{&m_graph, fromp, top, condp, /*consumesCycle=*/false};
    }
    // Collect all edges into a flat vector for iteration.
    // Used by the lowering phase which needs global edge scans.
    std::vector<const SvaTransEdge*> allEdges() const {
        std::vector<const SvaTransEdge*> result;
        for (const V3GraphVertex& vtxr : m_graph.vertices()) {
            for (const V3GraphEdge& edger : vtxr.outEdges()) {
                result.push_back(static_cast<const SvaTransEdge*>(&edger));
            }
        }
        return result;
    }
};

//######################################################################
// Builder result: terminal vertex + optional final condition (match Link condition).
struct BuildResult final {
    SvaStateVertex* termVertexp;  // Primary terminal; contributes to both match and reject
    AstNodeExpr* finalCondp;  // nullptr = unconditional
    // Mid-window sources for range delays (pure boolean RHS): match-only (isUnbounded)
    std::vector<SvaStateVertex*> midSources;
    bool errorEmitted = false;  // Builder already emitted specific error; skip generic
    // For cover_sequence: when true, midSources already enumerate every
    // end-of-match, so wireMatchAndMidSources must NOT add the main
    // termVtxp -> matchVertex Link (would double-count via the merge vertex).
    bool termIsMidMerge = false;
    bool valid() const { return termVertexp != nullptr; }
    static BuildResult fail(bool errored = false) { return {nullptr, nullptr, {}, errored}; }
    static BuildResult failWithError() { return {nullptr, nullptr, {}, true}; }
};

// Parser-marked SAnd of overlapped implications: a property if/else/case.
static bool hasPropertyControlConjunction(const AstNodeExpr* nodep) {
    return nodep->exists([](const AstSAnd* andp) { return andp->propertyControl(); });
}

static AstConst* newTypedConstp(FileLine* const flp, const AstNodeDType* const dtypep,
                                const uint32_t value) {
    AstConst* const constp = new AstConst{flp, AstConst::DTyped{}, dtypep};
    constp->num().setLong(value);
    return constp;
}

static AstNodeExpr* sampled(AstNodeExpr* exprp) {
    return new AstSampled{exprp->fileline(), exprp, exprp->dtypep(), true};
}

static const char* assertPassOnQuery(bool vacuous) {
    static constexpr const char* queries[2]
        = {"ASSERT_CTL_PASS_ON_NONVACUOUS", "ASSERT_CTL_PASS_ON_VACUOUS"};
    return queries[vacuous];
}

static AstNodeExpr* assertOnCond(FileLine* flp, VAssertType type,
                                 VAssertDirectiveType directiveType) {
    if (!v3Global.opt.assertOn()) { return new AstConst{flp, AstConst::BitFalse{}}; }
    return new AstCExpr{flp, AstCExpr::Pure{},
                        V3AssertCommon::assertCtlGetCall("ASSERT_CTL_ON", type, directiveType), 1};
}

static AstNodeExpr* assertKillGet(FileLine* flp, VAssertType type,
                                  VAssertDirectiveType directiveType) {
    return new AstCExpr{flp, AstCExpr::Pure{},
                        V3AssertCommon::assertCtlGetCall("ASSERT_CTL_KILL", type, directiveType),
                        32};
}

static string assertActionControlPrefix(VAssertDirectiveType directiveType) {
    const int controlled = !!(static_cast<int>(directiveType)
                              & (static_cast<int>(VAssertDirectiveType::ASSERT)
                                 | static_cast<int>(VAssertDirectiveType::COVER)
                                 | static_cast<int>(VAssertDirectiveType::ASSUME)));
    const int checkRuntime = controlled & static_cast<int>(v3Global.opt.assertOn());
    return "("s + std::to_string(controlled ^ 1) + " || ("s + std::to_string(checkRuntime)
           + " && "s;
}

static AstNodeExpr* assertPassOnCond(FileLine* flp, VAssertType type,
                                     VAssertDirectiveType directiveType, bool vacuous) {
    return new AstCExpr{
        flp, AstCExpr::Pure{},
        assertActionControlPrefix(directiveType)
            + V3AssertCommon::assertCtlGetCall(assertPassOnQuery(vacuous), type, directiveType)
            + "))"s,
        1};
}

static AstNodeExpr* assertFailOnCond(FileLine* flp, VAssertType type,
                                     VAssertDirectiveType directiveType) {
    return new AstCExpr{
        flp, AstCExpr::Pure{},
        assertActionControlPrefix(directiveType)
            + V3AssertCommon::assertCtlGetCall("ASSERT_CTL_FAIL_ON", type, directiveType) + "))"s,
        1};
}

static AstIf* newPassOnIf(FileLine* flp, AstNodeExpr* firep, AstNodeStmt* bodyp, VAssertType type,
                          VAssertDirectiveType directiveType, bool vacuous) {
    AstNodeExpr* const condp
        = new AstLogAnd{flp, firep, assertPassOnCond(flp, type, directiveType, vacuous)};
    AstIf* const ifp = new AstIf{flp, condp, bodyp};
    ifp->isBoundsCheck(true);
    ifp->user1(true);
    return ifp;
}

static AstNodeStmt* newIfAssertFailOn(AstNodeStmt* bodyp, VAssertDirectiveType directiveType,
                                      VAssertType type) {
    FileLine* const flp = bodyp->fileline();
    AstNodeExpr* const condp = assertFailOnCond(flp, type, directiveType);
    AstIf* const ifp = new AstIf{flp, condp, bodyp};
    ifp->isBoundsCheck(true);
    ifp->user1(true);
    return ifp;
}

static AstAlways* newAssertAlways(FileLine* flp, VAlwaysKwd kwd, AstSenTree* sentreep,
                                  AstNodeStmt* bodyp) {
    AstAlways* const alwaysp = new AstAlways{flp, kwd, sentreep, bodyp};
    alwaysp->foreach([](AstNodeVarRef* nodep) {
        nodep->fileline()->modifyWarnOff(V3ErrorCode::SYNCASYNCNET, true);
    });
    return alwaysp;
}

//######################################################################
// NFA Builder

// True if a node has a multi-cycle sequence or property expression in it
static bool hasMultiCycleExpr(const AstNode* nodep) {
    return nodep->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); });
}

class SvaNfaBuilder final {
    SvaGraph& m_graph;  // NFA graph being built
    AstNodeModule* const m_modp;  // Module to receive hoisted sampled-prop temps
    V3UniqueNames& m_propTempNames;  // Module-shared temp-var name source
    std::vector<AstNodeExpr*> m_temporalGuardStack;  // Guards active across nested temporal states
    // Outer abort conditions, AND-ed as !cond into inner abort edges
    // (IEEE 1800-2023 16.12.14 outer-wraps-inner).
    std::vector<AstNodeExpr*> m_outerAbortStack;
    bool m_inUnboundedScope = false;  // Sticky: nodes created after inherit liveness
    bool m_inAndCombiner = false;  // Building an operand of buildAndCombiner
    bool m_markStrongPending = false;  // Mark new vertices as strong s_always in-window
    // A cover only records matches, so a pending obligation at $finish is not a failure
    bool m_noEosFailure = false;
    // Negated: a strong obligation pending at end-of-simulation makes the property hold
    // (IEEE 1800-2023 16.12.3)
    bool m_isNegated = false;
    // IEEE 1800-2023 16.14.3 cover sequence: each end-of-match fires the action,
    // not just the first. Builder builds parallel-branch (no first-match-wins)
    // topology when true. Default false preserves cover_property semantics.
    bool m_isCoverSeq = false;
    // Unsupported endpoint topology must reject, not ignore, or the wait hangs
    bool m_isSeqEvent = false;
    bool m_inSequencePrefix = false;  // Prefix composition does not preserve every endpoint
    bool m_wantBoolLeaf = false;  // Building a |-> / |=> or top-level body (see buildOrMerge)
    bool m_isDeclarative = false;  // Directive outside any procedure
    // Building an implication antecedent, which cannot fail, and every match of which counts
    bool m_inAntecedent = false;
    // Building the consequent of an antecedent with a zero-minimum repetition, whose empty
    // match is not filtered (see buildImplicationEdges)
    bool m_inEmptyMatchConsequent = false;
    bool m_trackVacuous = false;  // Record vacuous successes (they fail a negated assertion)
    // Building the outer operand of a variable-length 'within', which needs a vertex on every
    // tick of each thread, so no delay ring (see buildVarLenWithin)
    bool m_perTickVertices = false;

    struct RangeDelayRejectInfo final {
        SvaStateVertex* startp = nullptr;
        unsigned range = 0;
        int rhsLen = 0;
    };

    void warnEndpointUnsupported(FileLine* flp, const string& what) const {
        if (m_isSeqEvent) {
            flp->v3warn(E_UNSUPPORTED,
                        "Unsupported: sequence used as an event control with " << what);
        } else {
            flp->v3warn(COVERIGN, "Ignoring unsupported: cover sequence with " << what);
        }
    }

    AstNodeExpr* throughoutCond(AstNodeExpr* baseCondp, FileLine* flp) {
        if (m_temporalGuardStack.empty()) return baseCondp;
        // AND all active temporal guards (supports nesting)
        // Each must use $sampled values.
        AstNodeExpr* guardp = nullptr;
        for (AstNodeExpr* const condp : m_temporalGuardStack) {
            AstNodeExpr* const clonep = sampled(condp->cloneTreePure(false));
            if (!guardp) {
                guardp = clonep;
            } else {
                guardp = new AstLogAnd{flp, guardp, clonep};
            }
        }
        if (baseCondp) { guardp = new AstLogAnd{flp, baseCondp, guardp}; }
        return guardp;
    }

    static unsigned getConstUInt(AstNodeExpr* exprp) {
        AstNodeExpr* const constp = V3Const::constifyEdit(exprp->cloneTreePure(false));
        const AstConst* const cp = VN_CAST(constp, Const);
        const unsigned val = cp ? cp->toUInt() : 0;
        VL_DO_DANGLING(constp->deleteTree(), constp);
        return val;
    }

    // Static fixed-length analysis: clock ticks from entry to terminal, or -1.
    // Used by SIntersect to verify IEEE 1800-2023 16.9.6 equal-length precondition.
    //
    // Supported:
    //  - Boolean leaf (default)              -> 0
    //  - AstSExpr with fixed cycle delay     -> pre + N + body
    //  - AstSExpr with range delay M==N      -> pre + N + body
    //  - AstSThroughout                      -> length of rhsp (the seq)
    // Unsupported (returns -1):
    //  - Range delays with M != N            -> variable
    //  - Unbounded waits ##[M:$]             -> infinite/variable
    //  - ConsRep / SGotoRep / SAnd / SOr     -> defer (rare in intersect)
    //  - SIntersect nested in SIntersect     -> defer
    static int fixedLength(AstNodeExpr* nodep) {
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            if (!delayp || !delayp->isCycleDelay()) return -1;
            unsigned delayCycles;
            if (delayp->isRangeDelay()) {
                if (delayp->isUnbounded()) return -1;  // LCOV_EXCL_LINE
                const unsigned minD = getConstUInt(delayp->lhsp());
                const unsigned maxD = getConstUInt(delayp->rhsp());
                if (minD != maxD) return -1;
                delayCycles = minD;
            } else {
                delayCycles = getConstUInt(delayp->lhsp());
            }
            int preLen = 0;
            if (AstNodeExpr* const prep = sexprp->preExprp()) {
                preLen = fixedLength(prep);
                if (preLen < 0) return -1;  // LCOV_EXCL_LINE
            }
            const int bodyLen = fixedLength(sexprp->exprp());
            if (bodyLen < 0) return -1;  // LCOV_EXCL_LINE
            return preLen + delayCycles + bodyLen;
        }
        if (AstSThroughout* const throughp = VN_CAST(nodep, SThroughout)) {
            return fixedLength(throughp->rhsp());
        }
        if (AstSOr* const orp = VN_CAST(nodep, SOr)) {
            // Alternatives must share one end cycle; buildSWithin relies on
            // this to pair the OR with an SIntersect.
            const int lhsLen = fixedLength(orp->lhsp());
            const int rhsLen = fixedLength(orp->rhsp());
            if (lhsLen < 0 || rhsLen < 0 || lhsLen != rhsLen) return -1;
            return lhsLen;
        }
        if (AstSWithin* const withinp = VN_CAST(nodep, SWithin)) {
            // `seq1 within seq2` ends at seq2's end cycle (IEEE 16.9.10).
            const int lhsLen = fixedLength(withinp->lhsp());
            const int rhsLen = fixedLength(withinp->rhsp());
            if (lhsLen < 0 || rhsLen < 0 || lhsLen > rhsLen) return -1;
            return rhsLen;
        }
        // LCOV_EXCL_START -- defensive: V3AssertPre rejects composite SVA ops
        // nested in an intersect arm before fixedLength runs (clock-context
        // resolution fails). Kept as a guard in case future parser relaxations
        // permit it.
        if (nodep->isMultiCycleSva()) return -1;
        // LCOV_EXCL_STOP
        // Plain boolean expression (no SVA constructs) -- 0 cycles.
        return 0;
    }

    // Contiguous match-length range [lo,hi] for an operand whose length varies
    // from AT MOST ONE ranged cycle delay; {-1,-1} otherwise. Drives the
    // variable-length `intersect` lowering (IEEE 1800-2023 16.9.6): more than
    // one ranged delay would make the per-length realization ambiguous, so it
    // is reported unsupported rather than mis-paired.
    static std::pair<int, int> lengthRange(AstNodeExpr* nodep) {
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            if (!delayp || !delayp->isCycleDelay()) return {-1, -1};
            std::pair<int, int> delayRange;
            if (delayp->isRangeDelay()) {
                if (delayp->isUnbounded()) return {-1, -1};
                const unsigned minD = getConstUInt(delayp->lhsp());
                const unsigned maxD = getConstUInt(delayp->rhsp());
                delayRange = {minD, maxD};
            } else {
                const unsigned d = getConstUInt(delayp->lhsp());
                delayRange = {d, d};
            }
            std::pair<int, int> preRange{0, 0};
            if (AstNodeExpr* const prep = sexprp->preExprp()) {
                preRange = lengthRange(prep);
                if (preRange.first < 0) return {-1, -1};
            }
            const std::pair<int, int> bodyRange = lengthRange(sexprp->exprp());
            if (bodyRange.first < 0) return {-1, -1};
            const int variableParts = (preRange.first != preRange.second)
                                      + (delayRange.first != delayRange.second)
                                      + (bodyRange.first != bodyRange.second);
            if (variableParts > 1) return {-1, -1};
            return {preRange.first + delayRange.first + bodyRange.first,
                    preRange.second + delayRange.second + bodyRange.second};
        }
        if (AstSThroughout* const throughp = VN_CAST(nodep, SThroughout)) {
            return lengthRange(throughp->rhsp());
        }
        if (nodep->isMultiCycleSva()) return {-1, -1};
        return {0, 0};  // plain boolean -- 0 cycles
    }

    // Clone `operand` with its sole variable ranged cycle delay pinned so the
    // total match length is exactly `len`. `lo` is the operand's minimum length
    // (lengthRange().first). A fixed operand has no such delay and is returned
    // as a plain clone (callers only request its single achievable length).
    static AstNodeExpr* realizeAtLength(AstNodeExpr* operandp, int len, int lo) {
        AstNodeExpr* const clonep = operandp->cloneTreePure(false);
        AstDelay* rangeDelayp = nullptr;
        clonep->foreach([&](AstDelay* dp) {
            if (!rangeDelayp && dp->isRangeDelay() && !dp->isUnbounded()
                && getConstUInt(dp->lhsp()) != getConstUInt(dp->rhsp())) {
                rangeDelayp = dp;
            }
        });
        if (rangeDelayp) {
            FileLine* const flp = rangeDelayp->fileline();
            const unsigned pinned = getConstUInt(rangeDelayp->lhsp()) + (len - lo);
            AstNodeExpr* const oldMinp = rangeDelayp->lhsp();
            oldMinp->replaceWith(new AstConst{flp, pinned});
            VL_DO_DANGLING(oldMinp->deleteTree(), oldMinp);
            // Drop the max bound so it lowers as a fixed `##d`, not `##[d:d]`.
            AstNode* const oldMaxp = rangeDelayp->rhsp()->unlinkFrBack();
            VL_DO_DANGLING(oldMaxp->deleteTree(), oldMaxp);
        }
        return clonep;
    }

    // Cuts AST size from O(N * sizeof(exprp)) to O(N) + O(sizeof(exprp)) by
    // sharing a single `VarRef` across N check edges. Hoist also matches the
    // IEEE 1800-2023 16.9.9 "single preponed-region snapshot" semantic for
    // any exprp -- even an impure one would now evaluate exactly once per
    // clock instead of N times. Orphan temps from failed builds are unused
    // MODULETEMPs and are removed by V3Dead.
    AstVar* tryHoistSampled(AstNodeExpr* exprp, FileLine* flp, unsigned cloneCount) {
        constexpr unsigned kHoistThreshold = 2;
        if (cloneCount < kHoistThreshold) return nullptr;
        AstVar* const tempVarp
            = new AstVar{flp, VVarType::MODULETEMP, m_propTempNames.get(exprp), exprp->dtypep()};
        m_modp->addStmtsp(tempVarp);
        AstAssign* const assignp = new AstAssign{flp, new AstVarRef{flp, tempVarp, VAccess::WRITE},
                                                 sampled(exprp->cloneTreePure(false))};
        m_modp->addStmtsp(newAssertAlways(flp, VAlwaysKwd::ALWAYS_COMB, nullptr, assignp));
        return tempVarp;
    }

    static AstNodeExpr* sampledRefOrClone(AstVar* hoistVarp, AstNodeExpr* exprp, FileLine* flp) {
        if (hoistVarp) return new AstVarRef{flp, hoistVarp, VAccess::READ};
        return sampled(exprp->cloneTreePure(false));
    }

    // Create vertex and inherit temporal guards from the current scope.
    SvaStateVertex* scopedCreateVertex() {
        SvaStateVertex* const vtxp = m_graph.createStateVertex();
        for (AstNodeExpr* const cp : m_temporalGuardStack) {
            vtxp->m_throughoutConds.push_back(cp->cloneTreePure(false));
        }
        if (m_inUnboundedScope) vtxp->m_isUnbounded = true;
        if (m_markStrongPending) vtxp->m_strongPending = true;
        return vtxp;
    }

    // AND current temporal guards into every edge/link.
    SvaTransEdge* guardedLink(SvaStateVertex* fromp, SvaStateVertex* top, AstNodeExpr* condp,
                              FileLine* flp) {
        return m_graph.addLink(fromp, top, throughoutCond(condp, flp));
    }
    SvaTransEdge* guardedLink(SvaStateVertex* fromp, SvaStateVertex* top, FileLine* flp) {
        return m_graph.addLink(fromp, top, throughoutCond(nullptr, flp));
    }
    SvaTransEdge* guardedEdge(SvaStateVertex* fromp, SvaStateVertex* top, AstNodeExpr* condp,
                              FileLine* flp) {
        return m_graph.addClockedEdge(fromp, top, throughoutCond(condp, flp));
    }
    SvaTransEdge* guardedEdge(SvaStateVertex* fromp, SvaStateVertex* top, FileLine* flp) {
        return m_graph.addClockedEdge(fromp, top, throughoutCond(nullptr, flp));
    }

    SvaStateVertex* addDelayChain(SvaStateVertex* startp, unsigned size, FileLine* flp,
                                  bool isFixed = true, AstNodeExpr* clearCondp = nullptr,
                                  AstNodeExpr* advanceCondp = nullptr) {
        if (isFixed && size == 0) return startp;
        UASSERT_OBJ(size > 0, startp, "Delay chain needs at least one slot");
        if (isFixed && size == 1 && !advanceCondp) {
            SvaStateVertex* const nextp = scopedCreateVertex();
            guardedEdge(startp, nextp, flp);
            return nextp;
        }
        if (isFixed && !advanceCondp && m_perTickVertices) {
            SvaStateVertex* vtxp = startp;
            for (unsigned i = 0; i < size; ++i) vtxp = addDelayChain(vtxp, 1, flp);
            return vtxp;
        }
        SvaStateVertex* const ringVtxp = scopedCreateVertex();
        ringVtxp->m_isFixedDelayRing = isFixed;
        ringVtxp->m_delayRingSize = size;
        if (clearCondp) {
            UASSERT_OBJ(!isFixed, startp, "Fixed delay cannot have a clear condition");
            ringVtxp->m_delayRingClearCondp = clearCondp->cloneTreePure(false);
        }
        ringVtxp->m_delayRingAdvanceCondp = advanceCondp;
        if (isFixed) {
            guardedEdge(startp, ringVtxp, flp);
        } else {
            guardedLink(startp, ringVtxp, flp);
        }
        return ringVtxp;
    }

    // Build NFA for an SExpr. finalCond = RHS (not yet added as a vertex).
    // isTopLevelStep: marks outermost required boolean check as rejectOnFail.
    // Apply a range delay `##[M:N]` to currentp. Returns true on success. On
    // failure, emits a diagnostic and returns false.
    bool applyRangeDelay(AstSExpr* sexprp, SvaStateVertex*& currentp,
                         std::vector<SvaStateVertex*>& midSources,
                         RangeDelayRejectInfo* rangeRejectInfop = nullptr) {
        FileLine* const flp = sexprp->fileline();
        AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
        AstNodeExpr* const rhsExprp = sexprp->exprp();
        const unsigned minDelay = getConstUInt(delayp->lhsp());
        if (delayp->isUnbounded()) {
            // `##[M:$]`: wait M cycles, then retain every matured attempt in a
            // one-slot ring while also exposing the first eligible tick.
            currentp = addDelayChain(currentp, minDelay, flp);
            SvaStateVertex* const waitRingp = addDelayChain(currentp, 1, flp, false);
            // The ring's live count is updated in NBA, so this link retains the previous
            // tick's live attempts alongside new arrivals for the next tick.
            guardedLink(waitRingp, waitRingp, flp);
            SvaStateVertex* const mergeVtxp = scopedCreateVertex();
            guardedLink(currentp, mergeVtxp, flp);
            guardedLink(waitRingp, mergeVtxp, flp);
            currentp = mergeVtxp;
            currentp->m_isUnbounded = true;  // Liveness, so no reject.
            m_inUnboundedScope = true;
            return true;
        }
        const unsigned maxDelay = getConstUInt(delayp->rhsp());
        if (minDelay == maxDelay) {
            currentp = addDelayChain(currentp, minDelay, flp);
            return true;
        }
        const unsigned range = maxDelay - minDelay;
        currentp = addDelayChain(currentp, minDelay, flp);
        const bool multiCycleRhs = rhsExprp->isMultiCycleSva();
        const AstNodeExpr* const preExprp = sexprp->preExprp();
        // Prefix and nested-sequence composition can lose endpoints or their multiplicity
        // required by cover sequence (IEEE 1800-2023 16.14.3), regardless of the range width.
        if (m_isCoverSeq
            && (multiCycleRhs || m_inSequencePrefix
                || (preExprp && preExprp->isMultiCycleSva()))) {
            warnEndpointUnsupported(flp, "this ranged cycle delay");
            return false;
        }
        if (m_inSequencePrefix) {
            flp->v3warn(E_UNSUPPORTED,
                        "Unsupported: Bounded ranged cycle delay in a sequence prefix");
            return false;
        }
        if (multiCycleRhs) {
            // Launch a candidate at every eligible tick. Candidate-local misses are not
            // assertion rejects while a later position can still match.
            if (rangeRejectInfop) {
                const int rhsLen = fixedLength(rhsExprp);
                if (rhsLen >= 0) *rangeRejectInfop = {currentp, range, rhsLen};
            }
            SvaStateVertex* const tailp = addDelayChain(currentp, range + 1U, flp, false);
            SvaStateVertex* const mergeVtxp = scopedCreateVertex();
            mergeVtxp->m_isUnbounded = true;
            guardedLink(currentp, mergeVtxp, flp);
            guardedLink(tailp, mergeVtxp, flp);
            currentp = mergeVtxp;
            m_inUnboundedScope = true;
        } else {
            // The first eligible tick is explicit. The ring retains attempts for the
            // remaining ticks and exposes the final tick for rejection. Only properties
            // clear on success, since a cover sequence and an antecedent use every endpoint.
            midSources.push_back(currentp);
            currentp = addDelayChain(currentp, range + 1U, flp, false,
                                     m_isCoverSeq || m_inAntecedent ? nullptr : rhsExprp);
        }
        return true;
    }

    void addFiniteRangeReject(const RangeDelayRejectInfo& info, const BuildResult& result,
                              FileLine* flp) {
        if (!info.startp) return;

        SvaStateVertex* const expiryVtxp
            = addDelayChain(info.startp, info.range + info.rhsLen, flp);
        SvaStateVertex* const expiryMatchp = scopedCreateVertex();
        std::vector<SvaStateVertex*> sources = result.midSources;
        sources.push_back(result.termVertexp);
        for (SvaStateVertex* const srcp : sources) {
            AstNodeExpr* const condp
                = result.finalCondp ? sampled(result.finalCondp->cloneTreePure(false)) : nullptr;
            SvaStateVertex* const successNowp = scopedCreateVertex();
            guardedLink(srcp, successNowp, condp, flp);
            // Retain a success through the latest deadline it can satisfy.
            SvaStateVertex* const historyp
                = addDelayChain(successNowp, info.range + 1U, flp, false);
            guardedLink(successNowp, expiryMatchp, flp);
            guardedLink(historyp, expiryMatchp, flp);
        }

        SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
        sinkVtxp->m_isRejectSink = true;
        SvaTransEdge* const rejectp = m_graph.addLink(expiryVtxp, sinkVtxp);
        rejectp->m_rejectOnFail = true;
        rejectp->m_condVtxp = expiryMatchp;
    }

    BuildResult buildSExpr(AstSExpr* sexprp, SvaStateVertex* entryVtxp,
                           bool isTopLevelStep = false) {
        AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
        if (!delayp || !delayp->isCycleDelay()) return BuildResult::fail();

        FileLine* const flp = sexprp->fileline();
        AstNodeExpr* const exprp = sexprp->exprp();

        // An empty match of a zero-minimum repetition next to the delay takes a cycle off the
        // delay: `s ##n empty` is `s ##(n-1) 1` and `empty ##n s` is `##(n-1) s`, and neither
        // matches for n == 0 (IEEE 1800-2023 16.9.2.1). A zero-minimum repetition lowered from
        // a vertex has its empty match there, and its first repetition on the next tick.
        AstSConsRep* const preZeroMinp = zeroMinRep(sexprp->preExprp());
        AstSConsRep* const zeroMinp = zeroMinRep(exprp);
        if ((preZeroMinp || zeroMinp) && (delayp->isRangeDelay() || (preZeroMinp && zeroMinp))) {
            sexprp->v3warn(E_UNSUPPORTED, "Unsupported: zero-minimum consecutive repetition next"
                                          " to a ranged cycle delay or another zero-minimum"
                                          " repetition (IEEE 1800-2023 16.9.2.1)");
            return BuildResult::failWithError();
        }

        // Handle LHS (preExpr)
        SvaStateVertex* currentp = entryVtxp;
        if (AstNodeExpr* const preExprp = sexprp->preExprp()) {
            // A goto repetition range ends at several occurrences. A later step failing after
            // one of them must not reject while another may still match, which the merged
            // threads cannot tell apart, so the later steps would never reject.
            if (isTopLevelStep && !m_noEosFailure && preExprp->exists([](const AstSGotoRep* repp) {
                    return repp->maxCountp()
                           && getConstUInt(repp->maxCountp()) != getConstUInt(repp->countp());
                })) {
                sexprp->v3warn(E_UNSUPPORTED, "Unsupported: goto repetition range followed by"
                                              " a later sequence element in a property"
                                              " (IEEE 1800-2023 16.9.2)");
                return BuildResult::failWithError();
            }
            // A nonconsecutive repetition has several matches. A later step failing after one of
            // them must not reject while another may still match, which the merged threads
            // cannot tell apart, so the later steps would never reject.
            if (!m_inAntecedent && !m_noEosFailure
                && preExprp->exists([](const AstSNonConsRep*) { return true; })) {
                sexprp->v3warn(E_UNSUPPORTED, "Unsupported: nonconsecutive repetition followed by"
                                              " a later sequence element outside an implication"
                                              " antecedent (IEEE 1800-2023 16.9.2)");
                return BuildResult::failWithError();
            }
            if (isTopLevelStep && !m_noEosFailure && preExprp->exists([](const AstSConsRep* repp) {
                    return repp->maxCountp() != nullptr;
                })) {
                return buildConsRepRangeTail(sexprp, entryVtxp);
            }
            VL_RESTORER(m_inSequencePrefix);
            m_inSequencePrefix = true;
            // The empty match is added after the delay, so the first repetition is not required
            const BuildResult pre = preZeroMinp ? buildConsRep(preZeroMinp, currentp, false, true)
                                                : buildExpr(preExprp, currentp, isTopLevelStep);
            if (!pre.valid()) return BuildResult::fail(pre.errorEmitted);  // LCOV_EXCL_LINE
            if (pre.finalCondp) {
                SvaStateVertex* const condVtxp = scopedCreateVertex();
                SvaTransEdge* const edgep = guardedLink(
                    pre.termVertexp, condVtxp, sampled(pre.finalCondp->cloneTreePure(false)), flp);
                if (isTopLevelStep && !pre.termVertexp->m_isUnbounded && !m_inUnboundedScope) {
                    // Do not mark liveness sources: first boolean check is deferred.
                    edgep->m_rejectOnFail = true;
                }
                freeUnlinkedCondp(pre.finalCondp);
                currentp = condVtxp;
            } else {
                currentp = pre.termVertexp;
            }
        }

        // Handle delay
        std::vector<SvaStateVertex*> rangeMidSources;
        RangeDelayRejectInfo rangeRejectInfo;
        const bool addRangeReject = isTopLevelStep && !m_inUnboundedScope;
        if (delayp->isRangeDelay()) {
            if (!applyRangeDelay(sexprp, currentp, rangeMidSources,
                                 addRangeReject ? &rangeRejectInfo : nullptr)) {
                return BuildResult::failWithError();
            }
        } else {
            const unsigned delayCycles = getConstUInt(delayp->lhsp());
            if (zeroMinp) {
                if (!delayCycles) return buildConsRep(zeroMinp, currentp, isTopLevelStep, true);
                // Lowered from the tick of its empty match, see above
                currentp = addDelayChain(currentp, delayCycles - 1, flp);
            } else {
                currentp = addDelayChain(currentp, delayCycles, flp);
                if (preZeroMinp && delayCycles) {
                    // Empty match of the left repetition, see above
                    SvaStateVertex* const mergeVtxp = scopedCreateVertex();
                    guardedLink(currentp, mergeVtxp, flp);
                    guardedLink(addDelayChain(entryVtxp, delayCycles - 1, flp), mergeVtxp, flp);
                    currentp = mergeVtxp;
                }
            }
        }

        // Multi-cycle RHS: recurse (only plain boolean is returned as finalCondp).
        if (exprp->isMultiCycleSva()) {
            const BuildResult result = buildExpr(exprp, currentp, isTopLevelStep);
            if (result.valid()) addFiniteRangeReject(rangeRejectInfo, result, flp);
            return result;
        }
        return {currentp, exprp, std::move(rangeMidSources)};
    }

    // Build a consecutive repetition range followed by a later step in a property
    BuildResult buildConsRepRangeTail(AstSExpr* sexprp, SvaStateVertex* entryVtxp) {
        // Each length is an alternative, and one failing the later step must not reject while
        // another may still match, which the merged threads of the plain lowering cannot tell
        // apart. With a boolean g, `f[*m:n] ##1 g` is `f[*m] ##1 ((f || g) throughout ##[0:n-m]
        // g)`: from the end of f[*m] each tick matches on g, continues while f holds, and fails
        // otherwise. Likewise `f[*m:n] ##0 g` is `f[*m-1] ##1 (f throughout ##[0:n-m] (f && g))`
        // (m >= 1).
        FileLine* const flp = sexprp->fileline();
        // A leading fixed delay just starts the range later: `##k f[*m:n] ##1 g`
        AstNodeExpr* preExprp = sexprp->preExprp();
        SvaStateVertex* startp = entryVtxp;
        if (const AstSExpr* const leadp = VN_CAST(preExprp, SExpr)) {
            const AstDelay* const leadDelayp = VN_AS(leadp->delayp(), Delay);
            if (!leadp->preExprp() && !leadDelayp->isRangeDelay()) {
                // Start from a plain vertex, as a delay ring end cannot carry the throughout
                startp = scopedCreateVertex();
                guardedLink(addDelayChain(entryVtxp, getConstUInt(leadDelayp->lhsp()), flp),
                            startp, flp);
                preExprp = leadp->exprp();
            }
        }
        AstSConsRep* const repp = VN_CAST(preExprp, SConsRep);
        const AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
        if (!repp || repp->exprp()->isMultiCycleSva() || delayp->isRangeDelay()
            || getConstUInt(delayp->lhsp()) > 1 || sexprp->exprp()->isMultiCycleSva()) {
            sexprp->v3warn(E_UNSUPPORTED, "Unsupported: consecutive repetition range followed by"
                                          " a later sequence element in a property, other than"
                                          " '##0' or '##1' and a boolean"
                                          " (IEEE 1800-2023 16.9.2)");
            return BuildResult::failWithError();
        }
        const bool fused = getConstUInt(delayp->lhsp()) == 0;
        AstNodeExpr* const fp = repp->exprp();
        AstNodeExpr* const gp = sexprp->exprp();
        // An empty match fused with g does not match (IEEE 1800-2023 16.9.2.1)
        const unsigned minN = std::max(getConstUInt(repp->countp()), fused ? 1U : 0U);
        const unsigned prefixN = fused ? minN - 1 : minN;
        AstNodeExpr* const guardp
            = fused ? fp->cloneTreePure(false)
                    : new AstLogOr{flp, fp->cloneTreePure(false), gp->cloneTreePure(false)};
        AstNodeExpr* const endp
            = fused ? new AstLogAnd{flp, fp->cloneTreePure(false), gp->cloneTreePure(false)}
                    : gp->cloneTreePure(false);
        guardp->dtypeSetBit();
        endp->dtypeSetBit();
        AstDelay* const rangep = new AstDelay{flp, new AstConst{flp, 0U}, /*isCycle=*/true};
        rangep->rhsp(new AstConst{flp, getConstUInt(repp->maxCountp()) - minN});
        AstNodeExpr* treep = new AstSThroughout{flp, guardp, new AstSExpr{flp, rangep, endp}};
        if (prefixN) {
            treep = new AstSExpr{
                flp, new AstSConsRep{flp, fp->cloneTreePure(false), new AstConst{flp, prefixN}},
                new AstDelay{flp, new AstConst{flp, 1U}, /*isCycle=*/true}, treep};
        }
        treep->dtypeSetBit();
        return buildFromLoweringTree(treep, startp, /*isTopLevelStep=*/true);
    }

    static AstSConsRep* zeroMinRep(AstNodeExpr* nodep) {
        AstSConsRep* const repp = VN_CAST(nodep, SConsRep);
        return repp && getConstUInt(repp->countp()) == 0 ? repp : nullptr;
    }

    // nonEmpty: Drop the empty match of a zero-minimum repetition
    BuildResult buildConsRep(AstSConsRep* repp, SvaStateVertex* entryVtxp,
                             bool isTopLevelStep = false, bool nonEmpty = false) {
        // With nonEmpty the first repetition is on the entry tick.
        FileLine* const flp = repp->fileline();
        AstNodeExpr* const exprp = repp->exprp();
        if (exprp->isMultiCycleSva() && !repp->maxCountp() && !repp->unbounded()) {
            // `s[*n]` is `s ##1 s ##1 ... ##1 s` (IEEE 1800-2023 16.9.2)
            const unsigned count = getConstUInt(repp->countp());
            UASSERT_OBJ(count >= 1, repp, "[*0] is removed by V3Width");
            AstNodeExpr* chainp = exprp->cloneTree(false);
            for (unsigned i = count; i > 1; --i) {
                AstDelay* const delayp
                    = new AstDelay{flp, new AstConst{flp, 1U}, /*isCycle=*/true};
                chainp = new AstSExpr{flp, chainp, delayp, exprp->cloneTree(false)};
                chainp->dtypeSetBit();
            }
            return buildFromLoweringTree(chainp, entryVtxp, isTopLevelStep);
        }
        // Other multi-cycle expr in ConsRep not yet supported; bail to avoid invalid AST.
        if (exprp->isMultiCycleSva()) {
            repp->v3warn(E_UNSUPPORTED, "Unsupported: multi-cycle sequence expression inside"
                                        " consecutive repetition (IEEE 1800-2023 16.9.2)");
            return BuildResult::failWithError();
        }
        const unsigned minN = std::max(getConstUInt(repp->countp()), nonEmpty ? 1U : 0U);

        // Sum sites across prefix + unbounded/range tail so one hoist covers
        // every check edge of this repetition.
        unsigned totalSites = minN;
        if (repp->unbounded()) {
            totalSites += 1;
        } else if (repp->maxCountp()) {
            totalSites += getConstUInt(repp->maxCountp()) - minN;
        }
        AstVar* const hoistVarp = tryHoistSampled(exprp, flp, totalSites);

        // Cover-sequence (IEEE 1800-2023 16.14.3): collect each end-of-match
        // position so they all fire the action, not just the merged terminal.
        std::vector<SvaStateVertex*> consMidSources;

        SvaStateVertex* currentp = entryVtxp;
        for (unsigned i = 0; i < minN; ++i) {
            // Keep the first repetition explicit, collapse all remaining checks into the ring.
            if (i == 1 && !m_perTickVertices) {
                currentp = addDelayChain(currentp, minN - 1, flp);
                currentp->m_delayRingClearCondp
                    = new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)};
                currentp->m_replayAbortReject = true;
                if (isTopLevelStep) {
                    currentp->m_throughoutConds.push_back(
                        sampledRefOrClone(hoistVarp, exprp, flp));
                }
                i = minN - 1;
            } else if (i) {
                // Per tick, so no ring; without m_perTickVertices i == 1 above already jumped
                // to the last repetition, so this is not reached
                currentp = addDelayChain(currentp, 1, flp);
            }
            // Every repetition in the minimum prefix is required.
            SvaStateVertex* const condVtxp = scopedCreateVertex();
            SvaTransEdge* const linkp
                = guardedLink(currentp, condVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
            // Only an outermost required step rejects the property. Its first check is explicit,
            // later required checks reject through the ring's throughout guard.
            if (isTopLevelStep && i == 0) linkp->m_rejectOnFail = true;
            currentp = condVtxp;
        }
        // After minN: currentp is the first valid end-of-match position for [*m:n].
        if (m_isCoverSeq && (repp->unbounded() || repp->maxCountp())) {
            consMidSources.push_back(currentp);
        }

        if (repp->unbounded()) {
            if (minN == 0) {
                SvaStateVertex* const waitVtxp = scopedCreateVertex();
                guardedEdge(currentp, waitVtxp, flp);
                SvaStateVertex* const checkVtxp = scopedCreateVertex();
                guardedLink(waitVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
                guardedEdge(checkVtxp, waitVtxp, flp);
                guardedLink(currentp, checkVtxp, flp);
                currentp = checkVtxp;
            } else {
                SvaStateVertex* const loopBackVtxp = scopedCreateVertex();
                guardedEdge(currentp, loopBackVtxp, flp);
                SvaStateVertex* const reCheckVtxp = scopedCreateVertex();
                guardedLink(loopBackVtxp, reCheckVtxp, sampledRefOrClone(hoistVarp, exprp, flp),
                            flp);
                guardedEdge(reCheckVtxp, loopBackVtxp, flp);
                guardedLink(reCheckVtxp, currentp, flp);
            }
            currentp->m_isUnbounded = true;
            m_inUnboundedScope = true;
        } else if (repp->maxCountp()) {
            const unsigned maxN = getConstUInt(repp->maxCountp());
            SvaStateVertex* const mergeVtxp = scopedCreateVertex();
            guardedLink(currentp, mergeVtxp, flp);
            unsigned tailMinN = minN;
            SvaStateVertex* tailStartp = currentp;
            // Build the first optional iteration explicitly. Feeding the empty endpoint
            // directly into a range ring would incorrectly keep that match alive. Without
            // rings, build every optional iteration so.
            while (tailMinN == 0 || (m_perTickVertices && tailMinN < maxN)) {
                SvaStateVertex* const nextVtxp = scopedCreateVertex();
                guardedEdge(tailStartp, nextVtxp, flp);
                SvaStateVertex* const checkVtxp = scopedCreateVertex();
                guardedLink(nextVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
                guardedLink(checkVtxp, mergeVtxp, flp);
                if (m_isCoverSeq) consMidSources.push_back(checkVtxp);
                tailStartp = checkVtxp;
                ++tailMinN;
            }
            if (maxN > tailMinN) {
                // Add tail-ring only if the tail is non-empty.
                SvaStateVertex* const nextVtxp
                    = addDelayChain(tailStartp, maxN - tailMinN + 1, flp, false);
                nextVtxp->m_delayRingClearCondp
                    = new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)};
                nextVtxp->m_replayAbortReject = true;
                SvaStateVertex* const checkVtxp = scopedCreateVertex();
                guardedLink(nextVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
                guardedLink(checkVtxp, mergeVtxp, flp);
                if (m_isCoverSeq) consMidSources.push_back(checkVtxp);
            }
            currentp = mergeVtxp;
        }
        // finalCond = nullptr (already checked via Links)
        BuildResult res;
        res.termVertexp = currentp;
        res.finalCondp = nullptr;
        res.midSources = std::move(consMidSources);
        // mergeVtxp is the OR of all the end-positions we already pushed to
        // midSources, so the main termVtxp -> matchVertex Link would duplicate.
        res.termIsMidMerge = m_isCoverSeq && !res.midSources.empty();
        return res;
    }

    // always[lo:hi] / s_always[lo:hi] (IEEE 1800-2023 16.12.11).
    BuildResult buildPropAlways(AstPropAlways* nodep, SvaStateVertex* entryVtxp,
                                bool isTopLevelStep = false) {
        FileLine* const flp = nodep->fileline();
        AstNodeExpr* const propp = nodep->propp();
        const unsigned lo = getConstUInt(nodep->loBoundp());
        if (VN_IS(nodep->hiBoundp(), Unbounded)) {
            // Weak always [lo:$]: unbounded upper bound (IEEE 1800-2023 16.12.11).
            // p must hold at every clock tick at least lo cycles after the attempt
            // start; those ticks are not required to exist, so there is no
            // end-of-trace obligation (weak). Each observed cycle is a safety
            // obligation, so a false p rejects immediately and ends the attempt.
            // A registered vertex holds the attempt while p holds. It must only
            // have clocked edges into it, so with lo == 0 the entry, which may be
            // reached by a link, checks the first tick itself.
            UASSERT_OBJ(!nodep->isStrong(), nodep, "Unbounded always must be weak (V3Width)");
            if (!isTopLevelStep) {
                // Only a top-level step rejects, so an enclosing operator would never see it fail
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: unbounded 'always' in complex property expression");
                return BuildResult::failWithError();
            }
            SvaStateVertex* const sinkp = m_graph.createStateVertex();
            sinkp->m_isRejectSink = true;
            const auto addCheck = [&](SvaStateVertex* fromp) {
                SvaTransEdge* const rejEdgep
                    = guardedLink(fromp, sinkp, sampled(propp->cloneTreePure(false)), flp);
                rejEdgep->m_rejectOnFail = true;
            };
            SvaStateVertex* const holdp = scopedCreateVertex();
            if (lo == 0) {
                addCheck(entryVtxp);
                guardedEdge(entryVtxp, holdp, sampled(propp->cloneTreePure(false)), flp);
            } else {
                guardedEdge(addDelayChain(entryVtxp, lo - 1, flp), holdp, flp);
            }
            guardedEdge(holdp, holdp, sampled(propp->cloneTreePure(false)), flp);
            addCheck(holdp);
            holdp->m_isUnbounded = true;
            return {holdp, nullptr, {}};
        }
        const unsigned hi = getConstUInt(nodep->hiBoundp());
        // Strong s_always[m:n]: mark every vertex of the attempt so an attempt
        // still before or in its window at end-of-simulation is reported as a liveness
        // failure (IEEE strong: the n+1 ticks must exist). An attempt that has
        // completed earlier in the trace has already cleared its state, so it is
        // not flagged; an attempt whose final tick coincides with $finish is still
        // flagged, matching the strong reference. Weak always[m:n] is not marked.
        VL_RESTORER(m_markStrongPending);
        m_markStrongPending = nodep->isStrong() && !m_noEosFailure && !m_isNegated;
        // Check the first in-window tick, then reuse a guarded fixed-delay ring
        // for the remaining ticks instead of creating one state per cycle.
        SvaStateVertex* currentp = addDelayChain(entryVtxp, lo, flp);
        SvaStateVertex* const checkp = scopedCreateVertex();
        SvaTransEdge* const linkp
            = guardedLink(currentp, checkp, sampled(propp->cloneTreePure(false)), flp);
        if (isTopLevelStep) linkp->m_rejectOnFail = true;
        currentp = checkp;
        m_temporalGuardStack.push_back(propp);
        currentp = addDelayChain(currentp, hi - lo, flp);
        m_temporalGuardStack.pop_back();
        return {currentp, propp, {}};
    }

    template <typename T_Rep>
    BuildResult buildGotoRep(T_Rep* repp, SvaStateVertex* entryVtxp) {
        FileLine* const flp = repp->fileline();
        AstNodeExpr* const exprp = repp->exprp();
        const unsigned minN = getConstUInt(repp->countp());
        if (minN == 0) return BuildResult::fail();
        const unsigned maxN = repp->maxCountp() ? getConstUInt(repp->maxCountp()) : minN;
        if (m_isCoverSeq) {
            // Several attempts may coalesce in the one-bit wait vertex before reaching the ring,
            // so a cover sequence action block could run too few times.
            warnEndpointUnsupported(flp, "a goto repetition");
            return BuildResult::failWithError();
        }

        AstVar* const hoistVarp = tryHoistSampled(exprp, flp, 2);

        // The first occurrence may be on the entry tick (IEEE 1800-2023 16.9.2). From the
        // entry and from the wait state, false takes a clocked edge to the wait state, while
        // true takes the zero-delay guardedLink on that tick.
        SvaStateVertex* const waitVtxp = scopedCreateVertex();
        SvaStateVertex* currentp = scopedCreateVertex();
        for (SvaStateVertex* const fromp : {entryVtxp, waitVtxp}) {
            guardedEdge(fromp, waitVtxp,
                        new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)}, flp);
            guardedLink(fromp, currentp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
        }

        if (minN > 1) {
            SvaStateVertex* const ringVtxp = addDelayChain(
                currentp, minN - 1, flp, true, nullptr, sampledRefOrClone(hoistVarp, exprp, flp));
            ringVtxp->m_replayAbortReject = true;
            SvaStateVertex* const checkVtxp = scopedCreateVertex();
            guardedLink(ringVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
            currentp = checkVtxp;
        }
        // Waiting for an occurrence never rejects. [->N] then has exactly one match, at the
        // Nth occurrence, so later steps are required and may reject
        if (maxN == minN) return {currentp, nullptr, {}};

        // [->M:N]: the range ring holds matches from M through N and advances
        // only on expr, preserving arbitrarily long gaps between occurrences.
        SvaStateVertex* const mergeVtxp = scopedCreateVertex();
        guardedLink(currentp, mergeVtxp, flp);  // accept at match_M
        SvaStateVertex* const ringVtxp
            = addDelayChain(currentp, maxN - minN + 1, flp, false, nullptr,
                            sampledRefOrClone(hoistVarp, exprp, flp));
        ringVtxp->m_replayAbortReject = true;
        SvaStateVertex* const checkVtxp = scopedCreateVertex();
        guardedLink(ringVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
        guardedLink(checkVtxp, mergeVtxp, flp);
        mergeVtxp->m_isUnbounded = true;  // [->M:N] still has unbounded waits between matches
        m_inUnboundedScope = true;
        return {mergeVtxp, nullptr, {}};
    }

    // Build a nonconsecutive repetition b[=M:N]
    BuildResult buildNonConsRep(AstSNonConsRep* repp, SvaStateVertex* entryVtxp) {
        FileLine* const flp = repp->fileline();
        if (m_isCoverSeq) {  // As for a goto repetition
            warnEndpointUnsupported(flp, "a nonconsecutive repetition");
            return BuildResult::failWithError();
        }
        const BuildResult gotoResult = buildGotoRep(repp, entryVtxp);
        UASSERT_OBJ(gotoResult.valid(), repp, "V3Width rejects a zero repetition count");
        // b[=M:N] is b[->M:N] ##1 !b[*0:$] (IEEE 1800-2023 16.9.2), so it also matches at each
        // later tick until b holds again. As it has several matches, later steps never reject.
        m_inUnboundedScope = true;
        SvaStateVertex* const endVtxp = scopedCreateVertex();
        guardedLink(gotoResult.termVertexp, endVtxp, flp);
        SvaStateVertex* const waitVtxp = scopedCreateVertex();
        guardedEdge(endVtxp, waitVtxp, flp);
        guardedLink(waitVtxp, endVtxp,
                    new AstLogNot{flp, sampled(repp->exprp()->cloneTreePure(false))}, flp);
        return {endVtxp, nullptr, {}};
    }

    // True if the sequence has a zero-minimum consecutive repetition, which may match empty
    static bool hasZeroMinRep(const AstNodeExpr* seqp) {
        return seqp->exists(
            [](const AstSConsRep* repp) { return getConstUInt(repp->countp()) == 0; });
    }

    // True if a leaf's condition has no implication or multi-cycle sequence in it
    // (a leaf can be e.g. 'not (x |-> y)')
    static bool isPlainBoolean(const AstNodeExpr* condp) {
        return !condp->exists(
            [](const AstNodeExpr* np) { return np->isMultiCycleSva() || VN_IS(np, Implication); });
    }
    // Build `b or p` at the end of an asserted property, with b boolean
    BuildResult buildBoolOrProp(AstNodeExpr* boolp, AstNodeExpr* propp, SvaStateVertex* entryVtxp,
                                FileLine* flp) {
        // It holds at once when b holds and otherwise exactly when p does (IEEE 1800-2023
        // 16.12.4). So p is evaluated only when b is false, with the rejections of a top-level
        // property.
        SvaStateVertex* const propEntryp = scopedCreateVertex();
        guardedLink(entryVtxp, propEntryp,
                    new AstLogNot{flp, sampled(boolp->cloneTreePure(false))}, flp);
        VL_RESTORER(m_wantBoolLeaf);
        m_wantBoolLeaf = true;
        const BuildResult prop = buildExpr(propp, propEntryp, /*isTopLevelStep=*/true);
        if (!prop.valid()) return prop;
        SvaStateVertex* const propTermp = prop.termVertexp;
        // A ranged end rejects through its ring at the match vertex, which p does not reach
        if (!prop.midSources.empty()) {
            flp->v3warn(E_UNSUPPORTED,
                        "Unsupported: property 'or' with an operand ending in a ranged delay");
            freeUnlinkedCondp(prop.finalCondp);
            return BuildResult::failWithError();
        }
        UASSERT_OBJ(!propTermp->m_delayRingSize || propTermp->m_isFixedDelayRing, propTermp,
                    "Ranged delay ring ends a property without mid-window sources");
        // Otherwise reach the merge vertex as p would reach the match vertex
        SvaStateVertex* const mergeVtxp = scopedCreateVertex();
        guardedLink(entryVtxp, mergeVtxp, sampled(boolp->cloneTreePure(false)), flp);
        if (!prop.finalCondp) {
            guardedLink(propTermp, mergeVtxp, flp);
            return {mergeVtxp, nullptr, {}};
        }
        guardedLink(propTermp, mergeVtxp, sampled(prop.finalCondp->cloneTreePure(false)), flp);
        if (!propTermp->m_isUnbounded) {
            SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
            sinkVtxp->m_isRejectSink = true;
            SvaTransEdge* const edgep = m_graph.addLink(
                propTermp, sinkVtxp, sampled(prop.finalCondp->cloneTreePure(false)));
            edgep->m_rejectOnFail = true;
        }
        freeUnlinkedCondp(prop.finalCondp);
        return {mergeVtxp, nullptr, {}};
    }

    // Build merge vertex for SOr / LogOr: both branches feed into one vertex.
    BuildResult buildOrMerge(AstNodeExpr* lhsp, AstNodeExpr* rhsp, SvaStateVertex* entryVtxp,
                             FileLine* flp, bool wantBoolLeaf) {
        // An attempt fails when every operand fails, which the merge vertex does not see
        const bool canFail = !m_noEosFailure && !m_inAntecedent;
        if (canFail && wantBoolLeaf) {
            if (isPlainBoolean(lhsp) && hasMultiCycleExpr(rhsp)) {
                return buildBoolOrProp(lhsp, rhsp, entryVtxp, flp);
            }
            if (isPlainBoolean(rhsp) && hasMultiCycleExpr(lhsp)) {
                return buildBoolOrProp(rhsp, lhsp, entryVtxp, flp);
            }
        }
        const BuildResult lhs = buildExpr(lhsp, entryVtxp);
        const BuildResult rhs = buildExpr(rhsp, entryVtxp);
        if (!lhs.valid() || !rhs.valid()) {  // LCOV_EXCL_START -- sub-build fail bail
            freeUnlinkedCondp(lhs.finalCondp);
            freeUnlinkedCondp(rhs.finalCondp);
            return BuildResult::fail(lhs.errorEmitted || rhs.errorEmitted);
        }  // LCOV_EXCL_STOP
        // IEEE 1800-2023 16.14.3: a cover sequence counts every end-of-match. A
        // sequence operand of 'or' can end more than once, but only its final
        // end reaches the merge vertex below, so reject sequence operands rather
        // than under-count. Plain boolean disjunction has one end per cycle and
        // is handled by the OR-fold.
        const bool booleanOnly = lhs.termVertexp == entryVtxp && lhs.finalCondp
                                 && rhs.termVertexp == entryVtxp && rhs.finalCondp;
        if (m_isCoverSeq && !booleanOnly) {
            warnEndpointUnsupported(flp, "a sequence operand of 'or'");
            freeUnlinkedCondp(lhs.finalCondp);
            freeUnlinkedCondp(rhs.finalCondp);
            return BuildResult::failWithError();
        }
        if (booleanOnly && (wantBoolLeaf || (canFail && !m_inEmptyMatchConsequent))) {
            if (isPlainBoolean(lhs.finalCondp) && isPlainBoolean(rhs.finalCondp)) {
                // A disjunction of two plain booleans must be able to reject: return it as a
                // boolean finalCondp. The merge vertex below drops the attempt silently when
                // both operands are false.
                AstNodeExpr* const orCondp
                    = new AstLogOr{flp, lhs.finalCondp->cloneTreePure(false),
                                   rhs.finalCondp->cloneTreePure(false)};
                freeUnlinkedCondp(lhs.finalCondp);
                freeUnlinkedCondp(rhs.finalCondp);
                return {entryVtxp, orCondp, {}};
            }
        }
        SvaStateVertex* const mergeVtxp = scopedCreateVertex();
        if (booleanOnly) {
            UASSERT_OBJ(lhs.finalCondp && rhs.finalCondp, lhsp,
                        "Single-cycle SOr operands must have finalCondp");
            guardedLink(entryVtxp, mergeVtxp,
                        new AstLogOr{flp, sampled(lhs.finalCondp->cloneTreePure(false)),
                                     sampled(rhs.finalCondp->cloneTreePure(false))},
                        flp);
        } else {
            for (const BuildResult* const opp : {&lhs, &rhs}) {
                // The first eligible tick of a range delay is a separate source
                std::vector<SvaStateVertex*> endps = opp->midSources;
                endps.push_back(opp->termVertexp);
                for (SvaStateVertex* const endp : endps) {
                    if (opp->finalCondp) {
                        guardedLink(endp, mergeVtxp,
                                    sampled(opp->finalCondp->cloneTreePure(false)), flp);
                    } else {
                        guardedLink(endp, mergeVtxp, flp);
                    }
                }
            }
        }
        freeUnlinkedCondp(lhs.finalCondp);
        freeUnlinkedCondp(rhs.finalCondp);
        return {mergeVtxp, nullptr, {}};
    }

    // Build `b and p` at the end of a property, with b boolean
    BuildResult buildBoolAndProp(AstNodeExpr* boolp, AstNodeExpr* propp, SvaStateVertex* entryVtxp,
                                 FileLine* flp) {
        // It fails at once when b fails and otherwise exactly when p does (IEEE 1800-2023
        // 16.12.5).
        SvaStateVertex* const propEntryp = scopedCreateVertex();
        SvaTransEdge* const edgep
            = guardedLink(entryVtxp, propEntryp, sampled(boolp->cloneTreePure(false)), flp);
        edgep->m_rejectOnFail = true;
        VL_RESTORER(m_wantBoolLeaf);
        m_wantBoolLeaf = true;
        return buildExpr(propp, propEntryp, /*isTopLevelStep=*/true);
    }

    // Build done-latch combiner for SAnd/SIntersect (IEEE 1800-2023 16.9.5).
    BuildResult buildAndCombiner(AstNodeExpr* lhsExprp, AstNodeExpr* rhsExprp,
                                 SvaStateVertex* entryVtxp, FileLine* flp) {
        // An 'and' in an operand is built by the combiner too: one lowered by newConjoinedAndp
        // would change which failures the combiner reports
        VL_RESTORER(m_inAndCombiner);
        m_inAndCombiner = true;
        // Snapshot-restore scope so LHS liveness does not leak into RHS.
        const bool savedScope = m_inUnboundedScope;
        const BuildResult lhs = buildExpr(lhsExprp, entryVtxp);
        const bool lhsScope = m_inUnboundedScope;
        m_inUnboundedScope = savedScope;
        const BuildResult rhs = buildExpr(rhsExprp, entryVtxp);
        const bool rhsScope = m_inUnboundedScope;
        m_inUnboundedScope = savedScope || lhsScope || rhsScope;
        if (!lhs.valid() || !rhs.valid()) {  // LCOV_EXCL_START -- sub-build fail bail
            freeUnlinkedCondp(lhs.finalCondp);
            freeUnlinkedCondp(rhs.finalCondp);
            return BuildResult::fail(lhs.errorEmitted || rhs.errorEmitted);
        }  // LCOV_EXCL_STOP

        // Single-cycle operands: use boolean AND (done-latch would fire across cycles).
        // If both operands stayed at entry, they must be boolean leaves which
        // buildExpr returns with finalCondp=nodep (non-null).
        if (lhs.termVertexp == entryVtxp && rhs.termVertexp == entryVtxp) {
            UASSERT_OBJ(lhs.finalCondp && rhs.finalCondp, lhsExprp,
                        "Single-cycle SAnd operands must have finalCondp");
            AstNodeExpr* const condp = new AstLogAnd{flp, lhs.finalCondp->cloneTreePure(false),
                                                     rhs.finalCondp->cloneTreePure(false)};
            freeUnlinkedCondp(lhs.finalCondp);
            freeUnlinkedCondp(rhs.finalCondp);
            return {entryVtxp, condp, {}};
        }
        // Range-delay mid-window sources in either sub-branch would need
        // to be folded into the latch's match-now signal, which the
        // current combiner does not support.
        if (!lhs.midSources.empty() || !rhs.midSources.empty()) {
            flp->v3warn(E_UNSUPPORTED,
                        "Unsupported: ranged cycle delay in an operand of property 'and'");
            freeUnlinkedCondp(lhs.finalCondp);
            freeUnlinkedCondp(rhs.finalCondp);
            return BuildResult::failWithError();
        }
        SvaStateVertex* const combVtxp = scopedCreateVertex();
        combVtxp->m_isAndCombiner = true;
        combVtxp->m_andLhsTermp = lhs.termVertexp;
        combVtxp->m_andRhsTermp = rhs.termVertexp;
        if (lhs.finalCondp) combVtxp->m_andLhsCondp = lhs.finalCondp->cloneTreePure(false);
        if (rhs.finalCondp) combVtxp->m_andRhsCondp = rhs.finalCondp->cloneTreePure(false);
        if (lhs.termVertexp->m_isUnbounded || rhs.termVertexp->m_isUnbounded) {
            combVtxp->m_isUnbounded = true;
        }
        // Wire terminal-boolean rejects to a dedicated sink so each side can fail
        // the AND independently. Skip for liveness or single-cycle operands
        // (single-cycle termVertexp == entryVtxp would fire every cycle).
        if (!combVtxp->m_isUnbounded) {
            bool needSink = false;
            const bool lhsMultiCycle = (lhs.termVertexp != entryVtxp);
            const bool rhsMultiCycle = (rhs.termVertexp != entryVtxp);
            if (lhs.finalCondp && lhsMultiCycle && !lhs.termVertexp->m_isUnbounded) {
                needSink = true;
            }
            if (rhs.finalCondp && rhsMultiCycle && !rhs.termVertexp->m_isUnbounded) {
                needSink = true;
            }
            if (needSink) {
                SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
                sinkVtxp->m_isRejectSink = true;
                if (lhs.finalCondp && lhsMultiCycle && !lhs.termVertexp->m_isUnbounded) {
                    SvaTransEdge* const ep = m_graph.addLink(
                        lhs.termVertexp, sinkVtxp, sampled(lhs.finalCondp->cloneTreePure(false)));
                    ep->m_rejectOnFail = true;
                }
                if (rhs.finalCondp && rhsMultiCycle && !rhs.termVertexp->m_isUnbounded) {
                    SvaTransEdge* const ep = m_graph.addLink(
                        rhs.termVertexp, sinkVtxp, sampled(rhs.finalCondp->cloneTreePure(false)));
                    ep->m_rejectOnFail = true;
                }
            }
        }
        freeUnlinkedCondp(lhs.finalCondp);
        freeUnlinkedCondp(rhs.finalCondp);
        return {combVtxp, nullptr, {}};
    }

    // Limits the vertices plus condition nodes a variable-length 'within' adds, which has a
    // vertex per tick of its operands and phase, where delay rings would have one per delay
    static constexpr uint64_t MAX_WITHIN_SIZE = 16384;

    // Whether boolean leafp requires boolean condp to be false: a conjunct of leafp is the
    // logical negation of condp, or condp of the conjunct
    static bool excludes(const AstNodeExpr* leafp, const AstNodeExpr* condp) {
        if (const AstLogAnd* const andp = VN_CAST(leafp, LogAnd)) {
            return excludes(andp->lhsp(), condp) || excludes(andp->rhsp(), condp);
        }
        return isNegationOf(leafp, condp) || isNegationOf(condp, leafp);
    }
    static bool isNegationOf(const AstNodeExpr* notp, const AstNodeExpr* exprp) {
        if (const AstLogNot* const lognotp = VN_CAST(notp, LogNot)) {
            return lognotp->lhsp()->sameTree(exprp);
        }
        const AstNot* const bitnotp = VN_CAST(notp, Not);
        return bitnotp && bitnotp->width() == 1 && bitnotp->lhsp()->sameTree(exprp);
    }

    // Whether nodep is booleans joined by fixed cycle delays
    static bool isBooleanChain(AstNodeExpr* nodep) {
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            return delayp && delayp->isCycleDelay() && !delayp->isRangeDelay()
                   && isUIntConst(delayp->lhsp())
                   && (!sexprp->preExprp() || isBooleanChain(sexprp->preExprp()))
                   && isBooleanChain(sexprp->exprp());
        }
        return isPlainBoolean(nodep);
    }
    // Ticks of the longest match of a sequence isBooleanChain accepts, with each
    // repetition at its maximum, or one more than its minimum if unbounded
    static uint64_t chainTicks(AstNodeExpr* nodep) {
        if (AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            const uint64_t minN = getConstUInt(repp->countp());
            if (repp->unbounded()) return minN + 1;
            return repp->maxCountp() ? getConstUInt(repp->maxCountp()) : minN;
        }
        AstSExpr* const sexprp = VN_CAST(nodep, SExpr);
        if (!sexprp) return 1;
        const uint64_t delay = getConstUInt(VN_AS(sexprp->delayp(), Delay)->lhsp());
        const uint64_t preTicks = sexprp->preExprp() ? chainTicks(sexprp->preExprp()) : 1;
        // A zero delay fuses the last tick of the prefix with the first of the rest
        return preTicks - 1 + delay + chainTicks(sexprp->exprp());
    }

    // Split a concatenation into its operands and the cycle delays between them
    static bool splitConcat(AstNodeExpr* nodep, std::vector<AstNodeExpr*>& operandps,
                            std::vector<AstDelay*>& delayps) {
        AstSExpr* const sexprp = VN_CAST(nodep, SExpr);
        if (!sexprp || !sexprp->preExprp()) {
            operandps.push_back(nodep);
            return true;
        }
        AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
        if (!delayp || !delayp->isCycleDelay() || delayp->isRangeDelay()
            || !isUIntConst(delayp->lhsp())) {
            return false;
        }
        if (!splitConcat(sexprp->preExprp(), operandps, delayps)) return false;
        delayps.push_back(delayp);
        return splitConcat(sexprp->exprp(), operandps, delayps);
    }

    // The consecutive repetition of an outer 'within' operand `P ##1 b[*m:n] ##1 Q` with
    // boolean b and boolean chains P and Q, or nullptr. Fills operandps/delayps, the operands
    // of the concatenation and the delays between them.
    static AstSConsRep* runRepetition(AstNodeExpr* outerp, std::vector<AstNodeExpr*>& operandps,
                                      std::vector<AstDelay*>& delayps, size_t& repIndex) {
        if (!splitConcat(outerp, operandps, delayps)) return nullptr;
        AstSConsRep* repp = nullptr;
        for (size_t i = 0; i < operandps.size(); ++i) {
            if (isBooleanChain(operandps[i])) continue;
            AstSConsRep* const runp = VN_CAST(operandps[i], SConsRep);
            if (repp || !runp || !isPlainBoolean(runp->exprp()) || !isUIntConst(runp->countp())
                || (runp->maxCountp() && !isUIntConst(runp->maxCountp()))) {
                return nullptr;
            }
            repp = runp;
            repIndex = i;
        }
        if (!repp || repIndex == 0 || repIndex + 1 == operandps.size()) return nullptr;
        if (getConstUInt(delayps[repIndex - 1]->lhsp()) != 1
            || getConstUInt(delayps[repIndex]->lhsp()) != 1) {
            return nullptr;
        }
        return repp;
    }

    // Whether boolean chain operandp checks a pure boolean requiring boolean condp to be false
    // on its last (else first) tick: its last (first) boolean, which is checked on that tick
    static bool edgeExcludes(AstNodeExpr* operandp, bool last, const AstNodeExpr* condp) {
        while (AstSExpr* const sexprp = VN_CAST(operandp, SExpr)) {
            // A leading delay leaves the first tick unchecked
            if (!last && !sexprp->preExprp()) return false;
            operandp = last ? sexprp->exprp() : sexprp->preExprp();
        }
        return operandp->isPure() && excludes(operandp, condp);
    }

    // Sampled checks of a fixed inner sequence at clock offset 'offset', or nullptr if none
    static AstNodeExpr* newInnerCheckp(const std::map<int, std::vector<AstNodeExpr*>>& checks,
                                       int offset, FileLine* flp) {
        const auto it = checks.find(offset);
        if (it == checks.end()) return nullptr;
        AstNodeExpr* condp = nullptr;
        for (AstNodeExpr* const leafp : it->second) {
            AstNodeExpr* const checkp = sampled(leafp->cloneTreePure(false));
            condp = condp ? new AstLogAnd{flp, condp, checkp} : checkp;
        }
        return condp;
    }

    // Whether constant expression exprp is a two-state value of at most 32 bits, as
    // getConstUInt reads it
    static bool isUIntConst(AstNodeExpr* exprp) {
        AstNodeExpr* const constp = V3Const::constifyEdit(exprp->cloneTreePure(false));
        const AstConst* const cp = VN_CAST(constp, Const);
        const bool fits = cp && !cp->num().isFourState() && cp->num().fitsInUInt();
        VL_DO_DANGLING(constp->deleteTree(), constp);
        return fits;
    }

    static BuildResult withinTooLarge(AstSWithin* nodep) {
        nodep->v3warn(E_UNSUPPORTED, "Unsupported: 'within' with a variable-length outer sequence"
                                     " needing more than "
                                         << MAX_WITHIN_SIZE << " states and conditions");
        return BuildResult::failWithError();
    }

    // New vertex of a later phase of a variable-length 'within', with the scope of outer vertex
    // fromp, which has no throughout guard (see buildVarLenWithin)
    SvaStateVertex* newPhaseVertex(const SvaStateVertex* fromp) {
        SvaStateVertex* const vtxp = m_graph.createStateVertex();
        vtxp->m_isUnbounded = fromp->m_isUnbounded;
        vtxp->m_strongPending = fromp->m_strongPending;
        return vtxp;
    }

    // Lower `seq1 within seq2` (IEEE 1800-2023 16.9.10) for seq2 = `P ##1 b[*m:n] ##1 Q`, where
    // the tick of P before the repetition and the tick of Q after it each require !b, and a
    // seq1 of booleans checking c_0 .. c_L at its clock offsets. The repetition is then the
    // maximal run of b after P, so each attempt of seq2 matches at most once, and as P requires
    // !b no two attempts end on one tick. So the per-tick result of the cover property whose
    // whole sequence this is reports each successful attempt once (IEEE 1800-2023 16.14.3),
    // however many placements of seq1 match. Returns an invalid result without an error if
    // seq1 and seq2 are not of that form.
    //
    // seq2 is built once, as phase 0, where seq1 has not started, with a vertex on each tick;
    // phases 1 .. L+1 copy it, where seq1 has checked that many offsets. Each thread of seq2
    // enters every tick at one arrival vertex: the entry, or a registered vertex, which a
    // clocked edge enters and no Link does. There a phase-q thread checks c_q and continues in
    // phase q+1 from the arrival's junction vertex, which has the arrival's outgoing edges; a
    // phase-0 thread also stays in phase 0, so seq1 can start on any later tick. seq2 matching
    // in phase L+1 is a match of seq1 within seq2.
    BuildResult buildVarLenWithin(AstSWithin* nodep, SvaStateVertex* entryVtxp) {
        FileLine* const flp = nodep->fileline();
        // Checked before fixedLength and flattenFixedSeq, as the bounds can be large
        std::vector<AstNodeExpr*> operandps;
        std::vector<AstDelay*> delayps;
        size_t repIndex = 0;
        AstSConsRep* const repp = isBooleanChain(nodep->lhsp())
                                      ? runRepetition(nodep->rhsp(), operandps, delayps, repIndex)
                                      : nullptr;
        if (!repp || !repp->exprp()->isPure()
            || !edgeExcludes(operandps[repIndex - 1], true, repp->exprp())
            || !edgeExcludes(operandps[repIndex + 1], false, repp->exprp())) {
            return BuildResult::fail();
        }
        // The conditions become module state shared by all attempts, and sampled temporaries
        // evaluated once per tick, so they may only be pure and read variables that live as
        // long as the module
        if (!nodep->isPure() || nodep->exists([](const AstNode* np) {
                // A class handle, through which a member would be read, or a call may read
                // other state
                if (np->dtypep() && VN_IS(np->dtypep()->skipRefp(), ClassRefDType)) return true;
                if (VN_IS(np, NodeFTaskRef) || VN_IS(np, CMethodHard)) return true;
                const AstNodeVarRef* const refp = VN_CAST(np, NodeVarRef);
                if (!refp) return false;
                const AstVar* const varp = refp->varp();
                return !varp || varp->isFuncLocal() || varp->lifetime().isAutomatic()
                       || varp->isClassMember();
            })) {
            return BuildResult::fail();
        }
        uint64_t outerTicks = 0;
        for (AstNodeExpr* const operandp : operandps) outerTicks += chainTicks(operandp);
        for (AstDelay* const delayp : delayps) outerTicks += getConstUInt(delayp->lhsp());
        const uint64_t innerTicks = chainTicks(nodep->lhsp());
        uint64_t concats = 0;
        nodep->rhsp()->foreach([&concats](const AstSExpr*) { ++concats; });
        const uint64_t innerNodes = nodep->lhsp()->nodeCount();
        const uint64_t outerNodes = nodep->rhsp()->nodeCount();
        // Each factor is checked first, so the products below cannot wrap
        for (const uint64_t factor : {innerTicks, outerTicks, concats, innerNodes, outerNodes}) {
            if (factor > MAX_WITHIN_SIZE) return withinTooLarge(nodep);
        }
        // Phase 0 has the entry, per tick at most a delay vertex and the two of a repetition
        // step, and per concatenation a check vertex and the merge of an empty repetition; each
        // vertex has at most three outgoing edges. Its conditions are sampled clones of the
        // booleans of seq2 and a condition per repetition step. Each of the innerTicks later
        // phases clones phase 0, adds at most a junction per vertex, and checks seq1's booleans
        // at one offset from each junction.
        const uint64_t phase0Vertices = 3 * outerTicks + 2 * concats + 2;
        const uint64_t phase0CondNodes = 2 * outerNodes + 2 * outerTicks;
        const uint64_t size = 4 * (2 * innerTicks + 1) * phase0Vertices
                              + (innerTicks + 1) * phase0CondNodes
                              + innerTicks * phase0Vertices * (2 * innerNodes + 1);
        if (size > MAX_WITHIN_SIZE) return withinTooLarge(nodep);
        std::map<int, std::vector<AstNodeExpr*>> innerChecks;
        flattenFixedSeq(nodep->lhsp(), 0, innerChecks);
        const int innerLen = fixedLength(nodep->lhsp());
        SvaStateVertex* const startp = scopedCreateVertex();
        guardedLink(entryVtxp, startp, flp);
        BuildResult outer;
        {
            // In a cover property each match of seq2 counts, as one without seq1 does not end
            // the attempt, and none rejects
            VL_RESTORER(m_perTickVertices);
            m_perTickVertices = true;
            outer = buildExpr(nodep->rhsp(), startp);
        }
        if (!outer.valid()) return outer;
        UASSERT_OBJ(outer.midSources.empty() && !outer.termIsMidMerge, nodep,
                    "Variable-length within outer sequence with mid-window sources");
        // Phase 0 vertices, in creation order
        std::vector<SvaStateVertex*> vtxps;
        std::unordered_map<const SvaStateVertex*, size_t> indexes;
        for (V3GraphVertex& vtxr : m_graph.m_graph.vertices()) {
            SvaStateVertex* const vtxp = static_cast<SvaStateVertex*>(&vtxr);
            if (vtxps.empty() && vtxp != startp) continue;
            // A vertex on each tick has no ring, throughout guard, combiner, reject sink or
            // enclosing abort yet
            UASSERT_OBJ(!vtxp->m_isMatch && !vtxp->m_delayRingSize && !vtxp->m_isFixedDelayRing
                            && !vtxp->m_delayRingClearCondp && !vtxp->m_delayRingAdvanceCondp
                            && !vtxp->m_replayAbortReject && !vtxp->m_abortClearp
                            && !vtxp->m_abortRejectp && !vtxp->m_isAndCombiner
                            && !vtxp->m_andLhsTermp && !vtxp->m_andRhsTermp && !vtxp->m_andLhsCondp
                            && !vtxp->m_andRhsCondp && !vtxp->m_isRejectSink
                            && vtxp->m_throughoutConds.empty(),
                        vtxp, "Variable-length within outer vertex not built per tick");
            indexes.emplace(vtxp, vtxps.size());
            vtxps.push_back(vtxp);
        }
        std::vector<bool> arrivals(vtxps.size());
        std::vector<const SvaTransEdge*> edgeps;
        for (size_t i = 0; i < vtxps.size(); ++i) {
            bool clocked = false;
            bool linked = false;
            for (const V3GraphEdge& edger : vtxps[i]->inEdges()) {
                (static_cast<const SvaTransEdge&>(edger).m_consumesCycle ? clocked : linked)
                    = true;
            }
            UASSERT_OBJ(!clocked || !linked, vtxps[i], "Registered vertex with an incoming Link");
            arrivals[i] = !i || clocked;
            for (const V3GraphEdge& edger : vtxps[i]->outEdges()) {
                const SvaTransEdge* const tedgep = static_cast<const SvaTransEdge*>(&edger);
                UASSERT_OBJ(indexes.count(tedgep->toVtxp()) && tedgep->toVtxp() != startp
                                && !tedgep->m_rejectOnFail && !tedgep->m_condVtxp
                                && !tedgep->m_abortReject,
                            vtxps[i], "Variable-length within outer edge not built per tick");
                edgeps.push_back(tedgep);
            }
        }
        // Copies by phase; the entry has none, and a junction only in phase 1
        const size_t lastPhase = static_cast<size_t>(innerLen) + 1;
        std::vector<std::vector<SvaStateVertex*>> copyps(lastPhase + 1);
        std::vector<std::vector<SvaStateVertex*>> junctionps(lastPhase + 1);
        for (size_t q = 1; q <= lastPhase; ++q) {
            copyps[q].resize(vtxps.size());
            junctionps[q].resize(vtxps.size());
            for (size_t i = 0; i < vtxps.size(); ++i) {
                if (i) copyps[q][i] = newPhaseVertex(vtxps[i]);
                if (arrivals[i] && (i || q == 1)) junctionps[q][i] = newPhaseVertex(vtxps[i]);
            }
        }
        for (const SvaTransEdge* const tedgep : edgeps) {
            const size_t from = indexes.at(tedgep->fromVtxp());
            const size_t to = indexes.at(tedgep->toVtxp());
            for (size_t q = 1; q <= lastPhase; ++q) {
                SvaStateVertex* const fromp
                    = arrivals[from] ? junctionps[q][from] : copyps[q][from];
                if (!fromp) continue;
                new SvaTransEdge{&m_graph.m_graph, fromp, copyps[q][to],
                                 tedgep->m_condp ? tedgep->m_condp->cloneTreePure(false) : nullptr,
                                 tedgep->m_consumesCycle};
            }
        }
        for (size_t i = 0; i < vtxps.size(); ++i) {
            if (!arrivals[i]) continue;
            m_graph.addLink(vtxps[i], junctionps[1][i], newInnerCheckp(innerChecks, 0, flp));
            if (!i) continue;
            for (size_t q = 1; q < lastPhase; ++q) {
                m_graph.addLink(copyps[q][i], junctionps[q + 1][i],
                                newInnerCheckp(innerChecks, static_cast<int>(q), flp));
            }
            m_graph.addLink(copyps[lastPhase][i], junctionps[lastPhase][i]);
        }
        const size_t term = indexes.at(outer.termVertexp);
        SvaStateVertex* const termp
            = arrivals[term] ? junctionps[lastPhase][term] : copyps[lastPhase][term];
        UASSERT_OBJ(termp, nodep, "Variable-length within outer sequence ends on its entry");
        // A thread can only be in a vertex reachable from the entry. Later phases have no copy of
        // the entry, so some of their vertices are not, and as their state would have no inputs,
        // remove them. Phase 0 is reachable, as it is built from the entry.
        std::unordered_set<const SvaStateVertex*> reachedps{startp};
        std::vector<const SvaStateVertex*> workps{startp};
        while (!workps.empty()) {
            const SvaStateVertex* const vtxp = workps.back();
            workps.pop_back();
            for (const V3GraphEdge& edger : vtxp->outEdges()) {
                const SvaStateVertex* const top = static_cast<const SvaTransEdge&>(edger).toVtxp();
                if (reachedps.emplace(top).second) workps.push_back(top);
            }
        }
        const bool termReached = reachedps.count(termp);
        for (size_t q = 1; q <= lastPhase; ++q) {
            for (std::vector<SvaStateVertex*>* const phasepsp : {&copyps[q], &junctionps[q]}) {
                for (SvaStateVertex*& vtxp : *phasepsp) {
                    if (vtxp && !reachedps.count(vtxp)) {
                        VL_DO_CLEAR(vtxp->unlinkDelete(&m_graph.m_graph), vtxp = nullptr);
                    }
                }
            }
        }
        // Ignoring conditions, a path reaches the last phase of the terminal exactly if seq2 has
        // a match of at least as many ticks as seq1, so otherwise seq1 is longer than every
        // match of seq2 (IEEE 1800-2023 16.9.10)
        if (!termReached) {
            for (size_t q = 1; q <= lastPhase; ++q) {
                for (SvaStateVertex* const vtxp : copyps[q]) {
                    if (vtxp) vtxp->unlinkDelete(&m_graph.m_graph);
                }
                for (SvaStateVertex* const vtxp : junctionps[q]) {
                    if (vtxp) vtxp->unlinkDelete(&m_graph.m_graph);
                }
            }
            for (size_t i = vtxps.size() - 1; i > 0; --i) {
                VL_DO_DANGLING(vtxps[i]->unlinkDelete(&m_graph.m_graph), vtxps[i]);
            }
            freeUnlinkedCondp(outer.finalCondp);
            return buildNeverMatchIntersect(
                nodep, startp, false, "the inner sequence is longer than the outer sequence");
        }
        return {termp, outer.finalCondp, {}};
    }

    // Lower `seq1 within seq2` (IEEE 1800-2023 16.9.10) as:
    //   (OR_{i in 0..slack} 1 ##i seq1 ##(slack-i) 1) intersect seq2
    // Both operands must have fixed length (no ranged cycle delays).
    // The OR lives inside a single SIntersect so one AndCombiner done-latch
    // serves all offsets; lifting it out would double-count matches where
    // multiple offsets accept on the same seq2 end cycle.
    BuildResult buildSWithin(AstSWithin* nodep, SvaStateVertex* entryVtxp,
                             bool isTopLevelStep = false) {
        const int innerLen = fixedLength(nodep->lhsp());
        const int outerLen = fixedLength(nodep->rhsp());
        if (innerLen < 0 || outerLen < 0) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: within with ranged cycle-delay operand");
            return BuildResult::failWithError();
        }
        if (innerLen > outerLen) {
            return buildNeverMatchIntersect(
                nodep, entryVtxp, isTopLevelStep,
                "the inner sequence is longer than the outer sequence");
        }
        FileLine* const flp = nodep->fileline();
        const int slack = outerLen - innerLen;
        AstNodeExpr* innerOrp = nullptr;
        for (int i = 0; i <= slack; ++i) {
            const int postPad = slack - i;
            AstNodeExpr* branchp = nodep->lhsp()->cloneTreePure(false);
            if (i > 0) {
                AstConst* const prePadp = new AstConst{flp, AstConst::BitTrue{}};
                AstDelay* const delayp
                    = new AstDelay{flp, new AstConst{flp, static_cast<uint32_t>(i)}, true};
                AstSExpr* const wrappedp = new AstSExpr{flp, prePadp, delayp, branchp};
                wrappedp->dtypeSetBit();
                branchp = wrappedp;
            }
            if (postPad > 0) {
                AstConst* const postTruep = new AstConst{flp, AstConst::BitTrue{}};
                AstDelay* const delayp
                    = new AstDelay{flp, new AstConst{flp, static_cast<uint32_t>(postPad)}, true};
                AstSExpr* const wrappedp = new AstSExpr{flp, branchp, delayp, postTruep};
                wrappedp->dtypeSetBit();
                branchp = wrappedp;
            }
            innerOrp = innerOrp ? static_cast<AstNodeExpr*>(new AstSOr{flp, innerOrp, branchp})
                                : branchp;
        }
        AstNodeExpr* const outerClonep = nodep->rhsp()->cloneTreePure(false);
        AstNodeExpr* const combinedp = new AstSIntersect{flp, innerOrp, outerClonep};
        BuildResult result = buildExpr(combinedp, entryVtxp, isTopLevelStep);
        VL_DO_DANGLING(combinedp->deleteTree(), combinedp);
        // When both operands are plain booleans, buildAndCombiner returns a
        // freshly-allocated AstAnd as finalCondp with no parent. Callers up
        // the chain clone-and-discard finalCondp, so leave it parent-less and
        // it leaks; anchor it in the graph now via an edge.
        if (result.valid() && result.finalCondp && !result.finalCondp->backp()) {
            SvaStateVertex* const wrapVtxp = scopedCreateVertex();
            guardedLink(result.termVertexp, wrapVtxp, sampled(result.finalCondp), flp);
            result = {wrapVtxp, nullptr, result.midSources};
        }
        return result;
    }

    // Collect the boolean leaf checks of a fixed-length sequence keyed by their
    // clock offset from the start. Returns false for anything other than nested
    // AstSExpr with fixed cycle delays over boolean leaves (e.g. throughout).
    static bool flattenFixedSeq(AstNodeExpr* nodep, int baseOffset,
                                std::map<int, std::vector<AstNodeExpr*>>& out) {
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            if (!delayp || !delayp->isCycleDelay() || delayp->isUnbounded()) return false;
            const unsigned delayCycles = getConstUInt(delayp->lhsp());
            if (delayp->isRangeDelay() && getConstUInt(delayp->rhsp()) != delayCycles)
                return false;
            int preLen = 0;
            if (AstNodeExpr* const prep = sexprp->preExprp()) {
                if (!flattenFixedSeq(prep, baseOffset, out)) return false;
                preLen = fixedLength(prep);
                if (preLen < 0) return false;
            }
            return flattenFixedSeq(sexprp->exprp(), baseOffset + preLen + delayCycles, out);
        }
        if (!isPlainBoolean(nodep)) return false;
        out[baseOffset].push_back(nodep);
        return true;
    }

    // Conjoin two fixed-length sequences starting together into one sequence, or null
    static AstNodeExpr* conjoinFixedSeqs(AstNodeExpr* lhsp, AstNodeExpr* rhsp, FileLine* flp) {
        // At each clock offset AND the boolean checks of both operands. The result ends with the
        // longer operand, which is exact for 'and' (IEEE 1800-2023 16.9.5), and for 'intersect'
        // of equal lengths (16.9.6). Null if an operand is not a fixed sequence of boolean leaves.
        std::map<int, std::vector<AstNodeExpr*>> checks;
        if (!flattenFixedSeq(lhsp, 0, checks) || !flattenFixedSeq(rhsp, 0, checks)) return nullptr;
        return newCheckSeqp(checks, flp);
    }
    // A sequence of the boolean checks at each clock offset, or null if none
    static AstNodeExpr* newCheckSeqp(const std::map<int, std::vector<AstNodeExpr*>>& checks,
                                     FileLine* const flp) {
        if (checks.empty()) return nullptr;
        AstNodeExpr* resultp = nullptr;
        int prevOffset = 0;
        for (const auto& offsetChecks : checks) {
            const int offset = offsetChecks.first;
            AstNodeExpr* condp = nullptr;
            for (AstNodeExpr* const leafp : offsetChecks.second) {
                AstNodeExpr* const clonep = leafp->cloneTreePure(false);
                if (!condp) {
                    condp = clonep;
                } else {
                    condp = new AstLogAnd{flp, condp, clonep};
                    condp->dtypeSetBit();
                }
            }
            if (!resultp) {
                if (offset > 0) {
                    AstDelay* const delayp = new AstDelay{
                        flp, new AstConst{flp, static_cast<uint32_t>(offset)}, /*isCycle=*/true};
                    resultp
                        = new AstSExpr{flp, new AstConst{flp, AstConst::BitTrue{}}, delayp, condp};
                    resultp->dtypeSetBit();
                } else {
                    resultp = condp;
                }
            } else {
                AstDelay* const delayp = new AstDelay{
                    flp, new AstConst{flp, static_cast<uint32_t>(offset - prevOffset)},
                    /*isCycle=*/true};
                resultp = new AstSExpr{flp, resultp, delayp, condp};
                resultp->dtypeSetBit();
            }
            prevOffset = offset;
        }
        return resultp;
    }

    // A boolean equal to a single-cycle operand of 'and', or null
    static AstNodeExpr* newSingleCycleBoolp(AstNodeExpr* const nodep) {
        if (isPlainBoolean(nodep)) return nodep->cloneTreePure(false);
        FileLine* const flp = nodep->fileline();
        AstNodeExpr* resultp = nullptr;
        if (const AstSThroughout* const throughp = VN_CAST(nodep, SThroughout)) {
            // Over a single tick both conditions hold at it, the left one being a boolean
            // (IEEE 1800-2023 16.9.9)
            AstNodeExpr* const rhsp = newSingleCycleBoolp(throughp->rhsp());
            if (!rhsp) return nullptr;
            resultp = new AstLogAnd{flp, throughp->lhsp()->cloneTreePure(false), rhsp};
        } else if (const AstImplication* const implp = VN_CAST(nodep, Implication)) {
            // Holds unless the antecedent holds and the consequent does not (16.12.7). Not an
            // OR, which a sequence prefix would build as a sequence 'or'.
            if (!implp->isOverlapped() || implp->isFollowedBy()) return nullptr;
            AstNodeExpr* const lhsp = newSingleCycleBoolp(implp->lhsp());
            AstNodeExpr* const rhsp = lhsp ? newSingleCycleBoolp(implp->rhsp()) : nullptr;
            if (!rhsp) {
                if (lhsp) VL_DO_DANGLING(lhsp->deleteTree(), lhsp);
                return nullptr;
            }
            AstNodeExpr* const notRhsp = new AstLogNot{flp, rhsp};
            notRhsp->dtypeSetBit();
            AstNodeExpr* const failp = new AstLogAnd{flp, lhsp, notRhsp};
            failp->dtypeSetBit();
            resultp = new AstLogNot{flp, failp};
        } else {
            return nullptr;
        }
        resultp->dtypeSetBit();
        return resultp;
    }
    // Checks of the operands of an 'and' of fixed-length sequences of boolean checks
    struct AndChecks final {
        std::map<int, std::vector<AstNodeExpr*>> checks;  // Boolean checks by clock offset
        std::vector<AstNodeExpr*> ownedps;  // Checks made here, to delete after use
        // An operand is a sequence, so the 'and' is never a vacuous success, which an
        // implication operand made a boolean cannot tell (IEEE 1800-2023 16.12.5, 16.14.8)
        bool nonvacuous = false;
    };
    // Add the checks of an operand of 'and', false if it is not such a fixed-length sequence
    static bool addAndChecks(AstNodeExpr* const nodep, AndChecks& andChecksr) {
        if (const AstSAnd* const andp = VN_CAST(nodep, SAnd)) {
            return !andp->propertyControl() && addAndChecks(andp->lhsp(), andChecksr)
                   && addAndChecks(andp->rhsp(), andChecksr);
        }
        if (AstNodeExpr* const boolp = newSingleCycleBoolp(nodep)) {
            andChecksr.ownedps.push_back(boolp);
            andChecksr.checks[0].push_back(boolp);
            andChecksr.nonvacuous |= !VN_IS(nodep, Implication);
            return true;
        }
        if (!flattenFixedSeq(nodep, 0, andChecksr.checks)) return false;
        andChecksr.nonvacuous = true;
        return true;
    }
    // A nonvacuous 'and' of fixed-length sequences of boolean checks as one sequence checking
    // both, or null
    static AstNodeExpr* newConjoinedAndp(AstSAnd* const andp) {
        // It matches at the later end of its operands (IEEE 1800-2023 16.9.5), and as a
        // property fails once per attempt, at its first failing check (16.12.5). A side effect
        // is left where the combiner evaluates it.
        if (andp->exists([](AstNodeExpr* np) { return !np->isPure(); })) return nullptr;
        AndChecks andChecks;
        AstNodeExpr* conjp = nullptr;
        if (addAndChecks(andp->lhsp(), andChecks) && addAndChecks(andp->rhsp(), andChecks)
            && andChecks.nonvacuous) {
            conjp = newCheckSeqp(andChecks.checks, andp->fileline());
        }
        for (AstNodeExpr* const ownedp : andChecks.ownedps) {
            VL_DO_DANGLING(ownedp->deleteTree(), ownedp);
        }
        return conjp;
    }

    // `seq` is a simple ranged sequence `start ##[m:n] end` (start/end boolean,
    // start may be absent). Used to collapse a both-variable intersect to one
    // ranged delay.
    struct SimpleRanged final {
        bool ok = false;
        AstNodeExpr* startp = nullptr;  // may be null (absent start)
        AstNodeExpr* endp = nullptr;
    };
    static SimpleRanged asSimpleRanged(AstNodeExpr* nodep) {
        AstSExpr* const sexprp = VN_CAST(nodep, SExpr);
        if (!sexprp) return {};
        AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
        if (!delayp || !delayp->isCycleDelay() || !delayp->isRangeDelay() || delayp->isUnbounded())
            return {};
        if (getConstUInt(delayp->lhsp()) == getConstUInt(delayp->rhsp())) return {};
        AstNodeExpr* const prep = sexprp->preExprp();
        if (prep && fixedLength(prep) != 0) return {};
        if (fixedLength(sexprp->exprp()) != 0) return {};
        return {true, prep, sexprp->exprp()};
    }

    // Build the NFA for a synthesized intersect lowering tree, then free it.
    // buildExpr returns the terminal condition (finalCondp) by reference into the
    // tree; detach a clone so the tree can be freed here. The graph already holds
    // clones/hoists of every edge condition, so nothing else dangles.
    BuildResult buildFromLoweringTree(AstNodeExpr* treep, SvaStateVertex* entryVtxp,
                                      bool isTopLevelStep) {
        BuildResult result = buildExpr(treep, entryVtxp, isTopLevelStep);
        // A final condition in the tree is deleted with it; a new one is already the result's
        if (result.valid() && result.finalCondp
            && (result.finalCondp == treep || result.finalCondp->backp())) {
            result.finalCondp = result.finalCondp->cloneTreePure(false);
        }
        VL_DO_DANGLING(treep->deleteTree(), treep);
        return result;
    }

    // Empty common-length intersection -- unequal fixed lengths, or disjoint
    // ranged lengths. IEEE 1800-2023 16.9.6 requires both operands to match
    // over a window of the same length, so with no common length the intersect
    // simply never matches. This is legal (matching nothing), not an error, so
    // lower to a constant false rather than rejecting legal code.
    BuildResult buildNeverMatchIntersect(AstNodeExpr* nodep, SvaStateVertex* entryVtxp,
                                         bool isTopLevelStep, const char* reason) {
        nodep->v3warn(NEVERMATCH, "Sequence can never match because " << reason << ".");
        AstNodeExpr* const falsep = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
        return buildFromLoweringTree(falsep, entryVtxp, isTopLevelStep);
    }

    // Lower `seq1 intersect seq2` when an operand's match length varies
    // (IEEE 1800-2023 16.9.6: both match over one window, equal start and end).
    // The common length range is [lo,hi] = intersection of the two operands'
    // achievable lengths. The equal-length combiner is avoided -- it mis-handles
    // operands with an internal boolean check -- by lowering to plain sequences:
    //  - lo == hi (one shared length, e.g. one fixed + one ranged operand):
    //    pin each operand to that length and conjoin them cycle-by-cycle into a
    //    single fixed sequence.
    //  - lo < hi with simple `bool ##[m:n] bool` operands: collapse to one
    //    ranged delay `(start1 & start2) ##[lo:hi] (end1 & end2)`. (An OR of
    //    per-length branches cannot reject correctly -- a single missed length
    //    would fail the whole intersect, cf. Lesson 48.)
    //  - otherwise unsupported (clean error, not the legacy fall-through crash).
    BuildResult buildVarLenIntersect(AstSIntersect* nodep, SvaStateVertex* entryVtxp,
                                     bool isTopLevelStep) {
        const std::pair<int, int> lhsRange = lengthRange(nodep->lhsp());
        const std::pair<int, int> rhsRange = lengthRange(nodep->rhsp());
        if (lhsRange.first < 0 || rhsRange.first < 0) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: intersect with this variable-length operand");
            return BuildResult::failWithError();
        }
        const int lo = std::max(lhsRange.first, rhsRange.first);
        const int hi = std::min(lhsRange.second, rhsRange.second);
        if (lo > hi) {
            // Disjoint length ranges share no common length -> never matches.
            return buildNeverMatchIntersect(nodep, entryVtxp, isTopLevelStep,
                                            "intersect operands have no common length");
        }
        FileLine* const flp = nodep->fileline();
        if (lo == hi) {
            AstNodeExpr* const lp = realizeAtLength(nodep->lhsp(), lo, lhsRange.first);
            AstNodeExpr* const rp = realizeAtLength(nodep->rhsp(), lo, rhsRange.first);
            AstNodeExpr* const conjp = conjoinFixedSeqs(lp, rp, flp);
            VL_DO_DANGLING(lp->deleteTree(), lp);
            VL_DO_DANGLING(rp->deleteTree(), rp);
            if (!conjp) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: intersect operand is not a plain boolean sequence");
                return BuildResult::failWithError();
            }
            return buildFromLoweringTree(conjp, entryVtxp, isTopLevelStep);
        }
        const SimpleRanged sl = asSimpleRanged(nodep->lhsp());
        const SimpleRanged sr = asSimpleRanged(nodep->rhsp());
        if (!sl.ok || !sr.ok) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: intersect of two sequences that each vary in length over a"
                          " range with internal structure");
            return BuildResult::failWithError();
        }
        const auto andBool = [&](AstNodeExpr* ap, AstNodeExpr* bp) -> AstNodeExpr* {
            AstNodeExpr* const aClonep
                = ap ? ap->cloneTreePure(false) : new AstConst{flp, AstConst::BitTrue{}};
            AstNodeExpr* const bClonep
                = bp ? bp->cloneTreePure(false) : new AstConst{flp, AstConst::BitTrue{}};
            AstLogAnd* const andp = new AstLogAnd{flp, aClonep, bClonep};
            andp->dtypeSetBit();
            return andp;
        };
        AstDelay* const delayp = new AstDelay{flp, new AstConst{flp, static_cast<uint32_t>(lo)},
                                              /*isCycle=*/true};
        delayp->rhsp(new AstConst{flp, static_cast<uint32_t>(hi)});
        AstSExpr* const reducedp
            = new AstSExpr{flp, andBool(sl.startp, sr.startp), delayp, andBool(sl.endp, sr.endp)};
        reducedp->dtypeSetBit();
        return buildFromLoweringTree(reducedp, entryVtxp, isTopLevelStep);
    }

    BuildResult buildThroughout(AstSThroughout* nodep, SvaStateVertex* entryVtxp,
                                bool isTopLevelStep = false) {
        // A delay ring also holds attempts that have not reached the start yet, which the
        // guard must neither clear nor reject, so start from a plain vertex after it
        if (entryVtxp->m_delayRingSize) {
            SvaStateVertex* const startp = scopedCreateVertex();
            guardedLink(entryVtxp, startp, nodep->fileline());
            entryVtxp = startp;
        }
        // Mark entryVtxp so "cond false at tick 0" is detected as throughout-drop.
        entryVtxp->m_throughoutConds.push_back(nodep->lhsp()->cloneTreePure(false));
        m_temporalGuardStack.push_back(nodep->lhsp());
        BuildResult result = buildExpr(nodep->rhsp(), entryVtxp, isTopLevelStep);
        m_temporalGuardStack.pop_back();
        if (AstNodeExpr* finalCondp = result.finalCondp) {
            // The guard must also hold on the tick of the final check
            if (finalCondp->backp()) finalCondp = finalCondp->cloneTreePure(false);
            result.finalCondp = new AstLogAnd{nodep->fileline(), finalCondp,
                                              sampled(nodep->lhsp()->cloneTreePure(false))};
        }
        return result;
    }

    // until / until_with per IEEE 1800-2023 16.12.12.
    // Topology: combinational wait vertex with self-feeding state register.
    //   entry  --link[T]--> waitC
    //   waitR  --link[T]--> waitC                          (back-loop)
    //   waitC  --edge[##1, sampled(p) && !sampled(q)]--> waitR  (continue)
    //   waitC  --link[REQUIRE, rejectOnFail]--> sink            (per-cycle fail)
    //   waitC  --link[T]--> match  (added by wireMatchAndMidSources;
    //                               accept condition rides via finalCondp)
    // waitC is m_isUnbounded so the terminal-match link contributes only to
    // terminalActive, not to rejectBase (which would otherwise spuriously fire
    // every cycle q is false). Per-cycle reject comes from the explicit
    // rejectOnFail link to the sink vertex.
    //
    // Non-overlapping (p until q):
    //   REQUIRE = sampled(p) || sampled(q)   accept = sampled(q)
    // Overlapping (p until_with q):
    //   REQUIRE = sampled(p)                 accept = sampled(p) && sampled(q)
    // Strong forms use the same checks and mark the registered wait state as
    // an end-of-simulation liveness obligation.
    BuildResult buildUntil(AstUntil* nodep, SvaStateVertex* entryVtxp, bool isTopLevelStep) {
        FileLine* const flp = nodep->fileline();
        if (!isTopLevelStep) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: '" << nodep->verilogKwd()
                                                          << "' in complex property expression");
            return BuildResult::failWithError();
        }
        AstNodeExpr* const lhsp = nodep->lhsp();
        AstNodeExpr* const rhsp = nodep->rhsp();
        const auto hasSeq = [](const AstNodeExpr* ep) {
            return ep->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); });
        };
        if (hasSeq(lhsp) || hasSeq(rhsp)) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: '" << nodep->verilogKwd()
                                                          << "' in complex property expression");
            return BuildResult::failWithError();
        }

        const bool ov = nodep->isOverlapping();
        AstNodeExpr* const lhsBitp = nodep->lhsp();
        AstNodeExpr* const rhsBitp = nodep->rhsp();
        // p hoist count: continue, require (ov: 1 use; nov: 1 use). At least 2 uses.
        AstVar* const pHoistp = tryHoistSampled(lhsBitp, flp, 2);
        // q hoist count: continue (1) + require nov (1) = 2; ov: continue only (1).
        AstVar* const qHoistp = ov ? nullptr : tryHoistSampled(rhsBitp, flp, 2);

        SvaStateVertex* const waitCp = scopedCreateVertex();
        SvaStateVertex* const waitRp = scopedCreateVertex();
        waitCp->m_isUnbounded = true;
        waitRp->m_strongPending = nodep->isStrong() && !m_noEosFailure && !m_isNegated;

        // Entry and back-loop Links carry no condition; throughout-folding still applies.
        guardedLink(entryVtxp, waitCp, flp);
        guardedLink(waitRp, waitCp, flp);

        // Continue clocked edge: p && !q advances to next-cycle wait.
        AstNodeExpr* const contCondp
            = new AstLogAnd{flp, sampledRefOrClone(pHoistp, lhsBitp, flp),
                            new AstLogNot{flp, sampledRefOrClone(qHoistp, rhsBitp, flp)}};
        guardedEdge(waitCp, waitRp, contCondp, flp);

        // Reject sink: fires when require-condition is false.
        SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
        sinkVtxp->m_isRejectSink = true;
        AstNodeExpr* requireCondp;
        if (ov) {
            requireCondp = sampledRefOrClone(pHoistp, lhsBitp, flp);
        } else {
            requireCondp = new AstLogOr{flp, sampledRefOrClone(pHoistp, lhsBitp, flp),
                                        sampledRefOrClone(qHoistp, rhsBitp, flp)};
        }
        SvaTransEdge* const rejEdgep = m_graph.addLink(waitCp, sinkVtxp, requireCondp);
        rejEdgep->m_rejectOnFail = true;

        // Accept condition rides via finalCondp; assembleResult $sampled-wraps it.
        AstNodeExpr* acceptCondp;
        if (ov) {
            acceptCondp
                = new AstLogAnd{flp, lhsBitp->cloneTreePure(false), rhsBitp->cloneTreePure(false)};
        } else {
            acceptCondp = rhsBitp->cloneTreePure(false);
        }
        return {waitCp, acceptCondp, {}};
    }

    // s_eventually p per IEEE 1800-2023 16.12.13, built as the equivalent `1 s_until p`
    BuildResult buildSEventually(AstSEventually* nodep, SvaStateVertex* entryVtxp,
                                 bool isTopLevelStep) {
        // s_eventually s_eventually p is s_eventually p
        AstNodeExpr* exprp = nodep->exprp();
        while (AstSEventually* const innerp = VN_CAST(exprp, SEventually)) exprp = innerp->exprp();
        if (exprp->exists([](const AstNodeExpr* np) {
                return VN_IS(np, Until) || VN_IS(np, AbortOn) || VN_IS(np, PropAlways)
                       || VN_IS(np, SEventually) || VN_IS(np, Implication);
            })) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: property operand of 's_eventually'");
            return BuildResult::failWithError();
        }
        // Leave a sequence operand to V3AssertPre, which reports it
        if (exprp->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); })) {
            return {entryVtxp, nodep, {}};
        }
        if (!isTopLevelStep) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: 's_eventually' in complex property expression");
            return BuildResult::failWithError();
        }
        // buildUntil only uses clones of the operands, so build from a temporary
        FileLine* const flp = nodep->fileline();
        AstUntil* const untilp
            = new AstUntil{flp, new AstConst{flp, AstConst::BitTrue{}},
                           exprp->cloneTreePure(false), /*strong=*/true, /*overlapping=*/false};
        untilp->dtypeSetBit();
        const BuildResult result = buildUntil(untilp, entryVtxp, isTopLevelStep);
        VL_DO_DANGLING(untilp->deleteTree(), untilp);
        return result;
    }

    // IEEE 1800-2023 16.12.14 property abort operators. Sync and async share
    // the same NFA encoding: AstSampled already gives matured values at every
    // maturing clocking event, and async firing "between clocks" is not
    // observable in a cycle-based model. VAbortKind selects accept vs reject
    // verdict (sync vs async only changes the user-visible spelling).

    // Build `condp && !outer_1 && !outer_2 ...` (unsampled).
    AstNodeExpr* abortFireExpr(AstNodeExpr* condp, FileLine* flp) {
        AstNodeExpr* resultp = condp->cloneTreePure(false);
        for (AstNodeExpr* const op : m_outerAbortStack)
            resultp = new AstLogAnd{flp, resultp, new AstLogNot{flp, op->cloneTreePure(false)}};
        return resultp;
    }

    // True when unguarded ring-wide rejection or a same-tick Link chain already accounts the
    // attempt: a required-step Link covers both outcomes; followed-by pairs both edges.
    static bool chainAccountsSource(const SvaStateVertex* srcp,
                                    const std::unordered_set<const V3GraphEdge*>& preEdges) {
        if (srcp->m_delayRingSize && srcp->m_throughoutConds.empty()) return true;
        for (const V3GraphEdge& edger : srcp->inEdges()) {
            if (preEdges.count(&edger)) continue;
            const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
            if (tedger.m_consumesCycle) continue;
            const auto* const fromp = static_cast<const SvaStateVertex*>(tedger.fromVtxp());
            if (fromp->m_abortRejectp) return true;
        }
        bool plainNonSink = false;
        bool markedSink = false;
        for (const V3GraphEdge& edger : srcp->outEdges()) {
            if (preEdges.count(&edger)) continue;
            const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
            if (tedger.m_consumesCycle) continue;
            const bool sink = static_cast<const SvaStateVertex*>(tedger.toVtxp())->m_isRejectSink;
            if (tedger.m_rejectOnFail) {
                if (!sink) return true;
                markedSink = true;
            } else if (!sink) {
                if (srcp->m_abortRejectp) return true;
                plainNonSink = true;
            }
        }
        return plainNonSink && markedSink;
    }

    // Reject edge: fires when the source is live and the abort samples true.
    void addAbortRejectEdge(SvaStateVertex* srcp, SvaStateVertex* sinkp, AstNodeExpr* condp,
                            FileLine* flp) {
        AstNodeExpr* const notFirep = new AstLogNot{flp, sampled(abortFireExpr(condp, flp))};
        SvaTransEdge* const edgep = m_graph.addLink(srcp, sinkp, notFirep);
        edgep->m_rejectOnFail = true;
        edgep->m_abortReject = true;
    }

    // On the fire tick: kill body threads; accept kinds also forgive step misses.
    void gateBodyEdgesOnAbort(const std::unordered_set<const V3GraphEdge*>& preEdges,
                              AstNodeExpr* condp, VAbortKind kind, FileLine* flp) {
        for (V3GraphVertex& vtxr : m_graph.m_graph.vertices()) {
            for (V3GraphEdge& edger : vtxr.outEdges()) {
                if (preEdges.count(&edger)) continue;
                SvaTransEdge* const tedgep = static_cast<SvaTransEdge*>(&edger);
                if (tedgep->m_rejectOnFail) {
                    if (!kind.isAccept()) continue;
                    AstNodeExpr* const firep = sampled(abortFireExpr(condp, flp));
                    tedgep->m_condp
                        = tedgep->m_condp ? new AstLogOr{flp, tedgep->m_condp, firep} : firep;
                } else if (tedgep->m_consumesCycle) {
                    AstNodeExpr* const notFirep
                        = new AstLogNot{flp, sampled(abortFireExpr(condp, flp))};
                    tedgep->m_condp = tedgep->m_condp
                                          ? new AstLogAnd{flp, tedgep->m_condp, notFirep}
                                          : notFirep;
                }
            }
        }
    }

    BuildResult buildAbortOn(AstNodeExpr* condp, AstNodeExpr* bodyp, SvaStateVertex* entryVtxp,
                             VAbortKind kind, FileLine* flp, bool isTopLevelStep) {
        // Snapshot pre-body vertices/edges so post-build diff yields the body's sub-NFA.
        std::unordered_set<const V3GraphVertex*> preExisting;
        std::unordered_set<const V3GraphEdge*> preEdges;
        for (V3GraphVertex& vtxr : m_graph.m_graph.vertices()) {
            preExisting.insert(&vtxr);
            for (V3GraphEdge& edger : vtxr.outEdges()) preEdges.insert(&edger);
        }

        m_outerAbortStack.push_back(condp);
        const BuildResult bodyResult = buildExpr(bodyp, entryVtxp, isTopLevelStep);
        m_outerAbortStack.pop_back();
        if (!bodyResult.valid()) return bodyResult;

        gateBodyEdgesOnAbort(preEdges, condp, kind, flp);

        // Live-thread sources for the abort edge: entry + new body vertices,
        // minus reject sinks (they carry reject fuel, not live-thread fuel).
        std::vector<SvaStateVertex*> abortSources;
        abortSources.push_back(entryVtxp);
        for (V3GraphVertex& vtxr : m_graph.m_graph.vertices()) {
            if (preExisting.count(&vtxr)) continue;
            auto* const sp = static_cast<SvaStateVertex*>(&vtxr);
            if (sp->m_delayRingSize || !sp->m_throughoutConds.empty()) {
                AstNodeExpr* const firep = abortFireExpr(condp, flp);
                sp->m_abortClearp
                    = sp->m_abortClearp ? new AstLogOr{flp, sp->m_abortClearp, firep} : firep;
            }
            if (!kind.isAccept()
                && ((sp->m_delayRingSize && sp->m_throughoutConds.empty())
                    || sp->m_replayAbortReject)) {
                AstNodeExpr* const firep = abortFireExpr(condp, flp);
                sp->m_abortRejectp
                    = sp->m_abortRejectp ? new AstLogOr{flp, sp->m_abortRejectp, firep} : firep;
            }
            if (sp->m_isRejectSink) continue;
            abortSources.push_back(sp);
        }

        auto sampledAbortFire = [&]() -> AstNodeExpr* {
            AstNodeExpr* const exprp = abortFireExpr(condp, flp);
            return sampled(exprp);
        };

        if (kind.isAccept()) {
            // Match-only sink fed by $sampled(abort-fire) from every live source;
            // registered as midSource so it never contributes a reject.
            SvaStateVertex* const acceptSinkp = scopedCreateVertex();
            for (SvaStateVertex* const srcp : abortSources)
                guardedLink(srcp, acceptSinkp, sampledAbortFire(), flp);
            std::vector<SvaStateVertex*> midSources = bodyResult.midSources;
            midSources.push_back(acceptSinkp);
            AstNodeExpr* finalCondp = bodyResult.finalCondp;
            if (finalCondp) {
                if (finalCondp->backp()) finalCondp = finalCondp->cloneTreePure(false);
                finalCondp = new AstLogOr{flp, finalCondp, abortFireExpr(condp, flp)};
            }
            return {bodyResult.termVertexp, finalCondp, std::move(midSources)};
        }

        // rejectOnFail treats m_condp as the success condition and fires on
        // !condp, so the edge carries !sampledAbortFire().
        SvaStateVertex* const rejectSinkp = m_graph.createStateVertex();
        rejectSinkp->m_isRejectSink = true;
        for (SvaStateVertex* const srcp : abortSources)
            if (!chainAccountsSource(srcp, preEdges))
                addAbortRejectEdge(srcp, rejectSinkp, condp, flp);
        AstNodeExpr* finalCondp = bodyResult.finalCondp;
        if (finalCondp) {
            if (finalCondp->backp()) finalCondp = finalCondp->cloneTreePure(false);
            finalCondp
                = new AstLogAnd{flp, finalCondp, new AstLogNot{flp, abortFireExpr(condp, flp)}};
        }
        return {bodyResult.termVertexp, finalCondp, bodyResult.midSources};
    }

public:
    // Free a dropped sub-result condition that is not linked into the AST
    // (abort folds synthesize unparented finalCondp trees).
    static void freeUnlinkedCondp(AstNodeExpr* condp) {
        if (condp && !condp->backp()) VL_DO_DANGLING(condp->deleteTree(), condp);
    }

    SvaNfaBuilder(SvaGraph& graph, AstNodeModule* modp, V3UniqueNames& propTempNames,
                  bool isCoverSeq = false, bool isSeqEvent = false, bool noEosFailure = false,
                  bool isNegated = false, bool trackVacuous = false, bool isDeclarative = false)
        : m_graph{graph}
        , m_modp{modp}
        , m_propTempNames{propTempNames}
        , m_noEosFailure{noEosFailure}
        , m_isNegated{isNegated}
        , m_isCoverSeq{isCoverSeq}
        , m_isSeqEvent{isSeqEvent}
        , m_isDeclarative{isDeclarative}
        , m_trackVacuous{trackVacuous} {}

    // Reset scope between antecedent and consequent: liveness must not leak.
    // m_outerAbortStack survives: an abort wrapping the implication covers the
    // consequent too (IEEE 1800-2023 16.12.14).
    void resetScope() {
        m_inUnboundedScope = false;
        m_temporalGuardStack.clear();
    }

    BuildResult buildExpr(AstNodeExpr* nodep, SvaStateVertex* entryVtxp,
                          bool isTopLevelStep = false) {
        VL_RESTORER(m_wantBoolLeaf);
        const bool wantBoolLeaf = m_wantBoolLeaf;
        m_wantBoolLeaf = false;
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            return buildSExpr(sexprp, entryVtxp, isTopLevelStep);
        }
        if (AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            return buildConsRep(repp, entryVtxp, isTopLevelStep);
        }
        if (AstPropAlways* const alwaysp = VN_CAST(nodep, PropAlways)) {
            return buildPropAlways(alwaysp, entryVtxp, isTopLevelStep);
        }
        if (AstSGotoRep* const repp = VN_CAST(nodep, SGotoRep)) {
            return buildGotoRep(repp, entryVtxp);
        }
        if (AstSNonConsRep* const repp = VN_CAST(nodep, SNonConsRep)) {
            return buildNonConsRep(repp, entryVtxp);
        }
        if (AstSThroughout* const throughoutp = VN_CAST(nodep, SThroughout)) {
            return buildThroughout(throughoutp, entryVtxp, isTopLevelStep);
        }
        if (AstSOr* const orp = VN_CAST(nodep, SOr)) {
            return buildOrMerge(orp->lhsp(), orp->rhsp(), entryVtxp, orp->fileline(),
                                wantBoolLeaf);
        }
        if (AstLogOr* const orp = VN_CAST(nodep, LogOr)) {
            return buildOrMerge(orp->lhsp(), orp->rhsp(), entryVtxp, orp->fileline(),
                                wantBoolLeaf);
        }
        if (AstSAnd* const andp = VN_CAST(nodep, SAnd)) {
            // Both operands start together (IEEE 1800-2023 16.9.5): with fixed lengths the
            // 'and' holds exactly when every check of both operands holds
            if (!andp->propertyControl()) {
                AstNodeExpr* conjp = m_inAndCombiner ? nullptr : newConjoinedAndp(andp);
                if (!conjp) conjp = conjoinFixedSeqs(andp->lhsp(), andp->rhsp(), andp->fileline());
                if (conjp) return buildFromLoweringTree(conjp, entryVtxp, isTopLevelStep);
                if (wantBoolLeaf) {
                    if (isPlainBoolean(andp->lhsp())) {
                        return buildBoolAndProp(andp->lhsp(), andp->rhsp(), entryVtxp,
                                                andp->fileline());
                    }
                    if (isPlainBoolean(andp->rhsp())) {
                        return buildBoolAndProp(andp->rhsp(), andp->lhsp(), entryVtxp,
                                                andp->fileline());
                    }
                }
            }
            return buildAndCombiner(andp->lhsp(), andp->rhsp(), entryVtxp, andp->fileline());
        }
        if (AstSIntersect* const intp = VN_CAST(nodep, SIntersect)) {
            // IEEE 1800-2023 16.9.6: both operands match over one window with
            // equal start and end (equal length). Lower to a single sequence
            // that conjoins both operands' per-cycle checks -- correct under
            // concurrent attempts, where the done-latch combiner conflates the
            // two operands' start times and over-accepts. The combiner remains
            // only as a fallback for operands that do not flatten.
            const int lhsLen = fixedLength(intp->lhsp());
            const int rhsLen = fixedLength(intp->rhsp());
            if (lhsLen >= 0 && rhsLen >= 0) {
                if (lhsLen != rhsLen) {
                    // Unequal fixed lengths share no common length -> never matches.
                    return buildNeverMatchIntersect(intp, entryVtxp, isTopLevelStep,
                                                    "intersect operands have no common length");
                }
                if (AstNodeExpr* const conjp
                    = conjoinFixedSeqs(intp->lhsp(), intp->rhsp(), intp->fileline())) {
                    return buildFromLoweringTree(conjp, entryVtxp, isTopLevelStep);
                }
                return buildAndCombiner(intp->lhsp(), intp->rhsp(), entryVtxp, intp->fileline());
            }
            return buildVarLenIntersect(intp, entryVtxp, isTopLevelStep);
        }
        if (AstSWithin* const withinp = VN_CAST(nodep, SWithin)) {
            return buildSWithin(withinp, entryVtxp, isTopLevelStep);
        }
        if (AstAbortOn* const ap = VN_CAST(nodep, AbortOn)) {
            return buildAbortOn(ap->condp(), ap->propp(), entryVtxp, ap->kind(), ap->fileline(),
                                isTopLevelStep);
        }
        if (AstImplication* const implp = VN_CAST(nodep, Implication)) {
            // A vacuous success is a success of the whole property only when nothing follows
            // the implication
            const bool trackVacuous = m_trackVacuous && !implp->isFollowedBy();
            if (trackVacuous && !wantBoolLeaf) {
                implp->v3warn(E_UNSUPPORTED, "Unsupported: implication inside another property "
                                             "operator in a negated property");
                return BuildResult::failWithError();
            }
            return buildImplicationEdges(implp->lhsp(), implp->rhsp(), entryVtxp,
                                         implp->isOverlapped(), implp->isFollowedBy(),
                                         implp->lhsp(), implp->fileline(), trackVacuous);
        }
        if (AstUntil* const untilp = VN_CAST(nodep, Until)) {
            return buildUntil(untilp, entryVtxp, isTopLevelStep);
        }
        if (AstSEventually* const evp = VN_CAST(nodep, SEventually)) {
            return buildSEventually(evp, entryVtxp, isTopLevelStep);
        }
        // A 'not' of a multi-cycle operand is no boolean leaf; at the top it is unwrapped
        if (VN_IS(nodep, LogNot) && hasMultiCycleExpr(nodep)) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: 'not' of a multi-cycle operand inside "
                                         "another property operator");
            return BuildResult::failWithError();
        }
        // Boolean leaf (including LogAnd): return as finalCond
        return {entryVtxp, nodep, {}};
    }

    // An antecedent that does not match leaves the implication vacuously true
    BuildResult buildAntecedent(AstNodeExpr* antExprp, SvaStateVertex* entryVtxp) {
        VL_RESTORER(m_inAntecedent);
        m_inAntecedent = true;
        return buildExpr(antExprp, entryVtxp);
    }

    // Wire an implication / followed-by from `entryVtxp`: builds the antecedent,
    // emits the match-link (and for followed-by the reject-sink edge), inserts a
    // delay vertex for non-overlapped forms, and builds the body. Used both for
    // nested AstImplication in pexpr position and for the top-level assertion
    // antecedent -- `errorNodep` anchors the "unsupported sequence antecedent"
    // error, which differs between the two call sites.
    BuildResult buildImplicationEdges(AstNodeExpr* antExprp, AstNodeExpr* bodyExprp,
                                      SvaStateVertex* entryVtxp, bool isOverlapped,
                                      bool isFollowedBy, AstNode* errorNodep, FileLine* flp,
                                      bool trackVacuous = false) {
        // Vertices are appended, so those after the current tail belong to the antecedent
        V3GraphVertex::List& vertices = m_graph.m_graph.vertices();
        const V3GraphVertex* const lastPrep = vertices.backp();
        // entryVtxp can be shared with other operands, so is not marked; instead the
        // guards the antecedent adds to it are removed again below
        std::vector<AstNodeExpr*>& entryConds = entryVtxp->m_throughoutConds;
        const size_t entryCondsNum = entryConds.size();
        const BuildResult antResult = buildAntecedent(antExprp, entryVtxp);
        if (!antResult.valid()) return antResult;
        for (auto it = vertices.rbegin(); &*it != lastPrep; ++it)
            static_cast<SvaStateVertex*>(&*it)->m_isAntecedent = true;

        // Followed-by requires pure-boolean antecedent for non-vacuous-fail at
        // the attempt-start cycle. IEEE 1800-2023 16.12.9 permits a multi-cycle
        // sequence LHS, so this is an implementation gap rather than illegal SV.
        if (isFollowedBy && antResult.termVertexp != entryVtxp) {
            errorNodep->v3warn(E_UNSUPPORTED,
                               "Unsupported: sequence expression as antecedent of followed-by"
                               " (#-# / #=#) (IEEE 1800-2023 16.12.9)");
            return BuildResult::failWithError();
        }
        UASSERT_OBJ(!isFollowedBy || antResult.finalCondp, errorNodep,
                    "followed-by antecedent terminal at entry must carry finalCondp");

        // The implication succeeds vacuously when its antecedent has no match
        // (IEEE 1800-2023 16.12.7); this is detected for a boolean antecedent
        if (trackVacuous) {
            if (antExprp->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); })) {
                errorNodep->v3warn(E_UNSUPPORTED, "Unsupported: sequence antecedent of an "
                                                  "implication in a negated property");
                freeUnlinkedCondp(antResult.finalCondp);
                return BuildResult::failWithError();
            }
            // Vacuous successes of different implications can belong to different attempts
            SvaStateVertex* const vacuousVtxp = m_graph.createStateVertex();
            m_graph.m_vacuousVertices.push_back(vacuousVtxp);
            m_graph.addLink(entryVtxp, vacuousVtxp,
                            new AstLogNot{flp, sampled(antExprp->cloneTreePure(false))});
        }

        // Use raw createStateVertex() so trigVtxp starts without liveness --
        // reaching the antecedent terminal is a definitive event.
        SvaStateVertex* const trigVtxp = m_graph.createStateVertex();
        AstNodeExpr* antMatchp = nullptr;
        if (antResult.finalCondp) {
            antMatchp = sampled(antResult.finalCondp->cloneTreePure(false));
            // The first eligible tick of a range delay is a separate source; as at the
            // terminal, a throughout guard dropped on that tick prevents the match
            for (SvaStateVertex* const midp : antResult.midSources) {
                AstNodeExpr* midMatchp = antMatchp->cloneTreePure(false);
                for (AstNodeExpr* const condp : midp->m_throughoutConds) {
                    midMatchp
                        = new AstLogAnd{flp, midMatchp, sampled(condp->cloneTreePure(false))};
                }
                m_graph.addLink(midp, trigVtxp, midMatchp);
            }
            // finalCondp is cloned into the Sampled nodes; if the original is
            // not parented anywhere in the AST anymore it must be freed here
            // or ASan flags it as a leak (e.g. t_sequence_bool_ops).
            if (!antResult.finalCondp->backp()) {
                VL_DO_DANGLING(antResult.finalCondp->deleteTree(), antResult.finalCondp);
            }
        }
        // Antecedent vertices do not reject on a dropped throughout guard, so a guard
        // dropped on the last tick must instead prevent the match
        const std::vector<AstNodeExpr*>& termConds = antResult.termVertexp->m_throughoutConds;
        for (size_t i = antResult.termVertexp == entryVtxp ? entryCondsNum : 0;
             i < termConds.size(); ++i) {
            AstNodeExpr* const sp = sampled(termConds[i]->cloneTreePure(false));
            antMatchp = antMatchp ? new AstLogAnd{flp, antMatchp, sp} : sp;
        }
        for (size_t i = entryCondsNum; i < entryConds.size(); ++i) {
            VL_DO_DANGLING(entryConds[i]->deleteTree(), entryConds[i]);
        }
        entryConds.resize(entryCondsNum);
        // Followed-by non-vacuous fail: rejectOnFail fires when the attempt
        // is live (termVtx reachable) and sampled(antecedent) is false.
        if (isFollowedBy) {
            SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
            sinkVtxp->m_isRejectSink = true;
            m_graph.addLink(antResult.termVertexp, sinkVtxp, antMatchp->cloneTreePure(false))
                ->m_rejectOnFail
                = true;
        }
        m_graph.addLink(antResult.termVertexp, trigVtxp, antMatchp);
        resetScope();

        SvaStateVertex* bodyEntryp = trigVtxp;
        if (!isOverlapped) {
            SvaStateVertex* const delayVtxp = m_graph.createStateVertex();
            m_graph.addClockedEdge(trigVtxp, delayVtxp);
            bodyEntryp = delayVtxp;
        }
        // An empty antecedent match must not start the consequent, but a zero-minimum
        // repetition's empty match is not handled here; keep the merge vertex for those
        VL_RESTORER(m_wantBoolLeaf);
        VL_RESTORER(m_inEmptyMatchConsequent);
        m_inEmptyMatchConsequent = hasZeroMinRep(antExprp);
        m_wantBoolLeaf = !isFollowedBy && !m_inEmptyMatchConsequent;
        return buildExpr(bodyExprp, bodyEntryp, /*isTopLevelStep=*/true);
    }

    BuildResult build(AstNodeExpr* exprp) {
        m_graph.m_startVertexp = scopedCreateVertex();
        VL_RESTORER(m_wantBoolLeaf);
        m_wantBoolLeaf = true;
        // A variable-length 'within' is supported as the whole sequence of a declarative cover
        // property, where each attempt is reported once, see buildVarLenWithin
        AstSWithin* const withinp = VN_CAST(exprp, SWithin);
        if (withinp && m_noEosFailure && m_isDeclarative && !m_isCoverSeq && !m_isSeqEvent
            && !m_isNegated) {
            const BuildResult result = buildVarLenWithin(withinp, m_graph.m_startVertexp);
            if (result.valid() || result.errorEmitted) return result;
        }
        return buildExpr(exprp, m_graph.m_startVertexp, /*isTopLevelStep=*/true);
    }
};

// A cover sequence directive counts its matches; a sequence event control does not
static bool countsMatches(const AstNodeCoverOrAssert* assertp) {
    const AstCover* const coverp = VN_CAST(assertp, Cover);
    return coverp && coverp->isCoverSeq() && !coverp->isSeqEvent();
}

//######################################################################
// NFA Lowering (converts NFA graph to synthesizable AstAlways blocks)

class SvaNfaLowering final {
    AstNodeModule* const m_modp;  // Module to add state vars and always blocks to
    AstNodeDType* const m_u32DTypep;  // Shared unsigned counter dtype
    V3UniqueNames m_names{"__Vnfa"};  // Unique names for generated variables
    V3UniqueNames& m_actionNames;  // Automatics of cloned actions
    size_t m_statDelayRingEdgeVisits = 0;  // Delay-ring incoming edges visited
    size_t m_statLinkEdgeVisits = 0;  // Incoming edges visited while resolving Links

    // Per-lowering shared context (passed to phase sub-functions)
    // Per-vertex lowering state is stored in SvaVertexData and accessed via
    // V3GraphVertex::userp() (see SvaStateVertex::datap()).
    struct LowerCtx final {
        FileLine* flp;  // Source location for generated AST
        AstSenTree* senTreep;  // Clock sensitivity tree
        AstNodeExpr* disableExprp;  // disable iff expression (may be nullptr)
        AstNodeExpr* matchCondp;  // Final boolean match condition (may be nullptr)
        VAssertType assertType;  // Assertion type for control tasks
        VAssertDirectiveType directiveType;  // Directive type for control tasks
        AstVar* killVarp;  // Last observed kill generation
        SvaGraph& graph;  // NFA graph
        bool exactCounts;  // Count threads exactly, each being one attempt
        const AstAbortOn* exactAbortp;  // With exactCounts, top-level synchronous abort, if any
    };

    // Build a match-now expression: stateSig[i] && $sampled(condp)
    static AstNodeExpr* buildMatchNow(FileLine* flp, AstNodeExpr* stateExprp, AstNodeExpr* condp) {
        AstNodeExpr* const statep = stateExprp->cloneTreePure(false);
        if (!condp) return statep;
        return new AstLogAnd{flp, statep, sampled(condp->cloneTreePure(false))};
    }
    static AstNodeExpr* andCond(FileLine* flp, AstNodeExpr* exprp, AstNodeExpr* condp) {
        if (!condp) return exprp;
        return new AstLogAnd{flp, exprp, condp->cloneTreePure(false)};
    }
    // bp is always non-null; only ap can be null (serving as accumulator).
    static AstNodeExpr* orExprs(FileLine* flp, AstNodeExpr* ap, AstNodeExpr* bp) {
        if (!ap) return bp;
        return new AstLogOr{flp, ap, bp};
    }
    // Balanced OR of the terms in [beginIt, endIt), or nullptr if none.
    static AstNodeExpr* newOrTree(FileLine* flp, std::vector<AstNodeExpr*>::const_iterator beginIt,
                                  std::vector<AstNodeExpr*>::const_iterator endIt) {
        // A term per NFA step: a left-deep chain would make V3Const quadratic
        if (beginIt == endIt) return nullptr;
        if (endIt - beginIt == 1) return *beginIt;
        const auto midIt = beginIt + (endIt - beginIt) / 2;
        return new AstLogOr{flp, newOrTree(flp, beginIt, midIt), newOrTree(flp, midIt, endIt)};
    }
    static AstNodeExpr* addCountp(FileLine* const flp, AstNodeExpr* const totalCountp,
                                  AstNodeExpr* const contributionp,
                                  AstNodeExpr* const enablep = nullptr) {
        // contribution = enable ? contribution : 0;
        AstNodeExpr* const enabledContributionp
            = enablep ? new AstCond{flp, enablep, contributionp,
                                    newTypedConstp(flp, contributionp->dtypep(), 0)}
                      : contributionp;
        if (!totalCountp) return enabledContributionp;
        return new AstAdd{flp, totalCountp, enabledContributionp};
    }
    static AstNodeExpr* gateCheckedCountp(FileLine* const flp, AstNodeExpr* const countp,
                                          AstNodeExpr*& overflowp, AstNodeExpr* const enablep) {
        if (overflowp) {
            overflowp = new AstLogAnd{flp, enablep->cloneTreePure(false), overflowp};
        }
        return addCountp(flp, nullptr, countp, enablep);
    }
    static AstNodeExpr* addCheckedCountp(FileLine* const flp, AstNodeExpr* const totalCountp,
                                         AstNodeExpr* const contributionp, AstNodeExpr*& overflowp,
                                         AstNodeExpr* const contributionOverflowp = nullptr) {
        if (contributionOverflowp) { overflowp = orExprs(flp, overflowp, contributionOverflowp); }
        if (!totalCountp) return contributionp;
        AstNodeExpr* const oldTotalp = totalCountp->cloneTreePure(false);
        AstNodeExpr* const resultp = new AstAdd{flp, totalCountp, contributionp};
        overflowp
            = orExprs(flp, overflowp, new AstLt{flp, resultp->cloneTreePure(false), oldTotalp});
        return resultp;
    }
    AstIf* newCountOverflowWarning(FileLine* const flp, AstNodeExpr* const condp) const {
        AstDisplay* const dispp = new AstDisplay{
            flp, VDisplayType::DT_WARNING,
            "Cover sequence match count overflowed 32-bit storage; results may be incorrect.",
            nullptr, nullptr};
        dispp->fmtp()->timeunit(m_modp->timeunit());
        AstIf* const ifp = new AstIf{flp, condp, dispp};
        ifp->branchPred(VBranchPred::BP_UNLIKELY);
        return ifp;
    }
    static AstNodeExpr* killActive(LowerCtx& c) {
        return new AstNeq{c.flp, new AstVarRef{c.flp, c.killVarp, VAccess::READ},
                          assertKillGet(c.flp, c.assertType, c.directiveType)};
    }
    static AstNodeExpr* notKillActive(LowerCtx& c) { return new AstLogNot{c.flp, killActive(c)}; }
    static AstNodeExpr* gateNotKill(LowerCtx& c, AstNodeExpr* exprp) {
        if (!exprp) return nullptr;
        return new AstLogAnd{c.flp, exprp, notKillActive(c)};
    }
    static AstNodeExpr* nextRingIndex(FileLine* flp, AstNodeExpr* idxExprp, uint32_t size) {
        const auto u32Const = [flp](uint32_t value) {
            return new AstConst{flp, AstConst::WidthedValue{}, 32, value};
        };
        UASSERT_OBJ(size > 0, idxExprp, "Ring size must be positive");
        if (size == 1) {
            VL_DO_DANGLING(idxExprp->deleteTree(), idxExprp);
            return u32Const(0);
        }
        // idx == size - 1 ? 0 : idx + 1
        AstAdd* const addp = new AstAdd{flp, idxExprp->cloneTreePure(false), u32Const(1)};
        addp->dtypeFrom(idxExprp);
        AstCond* const condp
            = new AstCond{flp, new AstEq{flp, idxExprp, u32Const(size - 1)}, u32Const(0), addp};
        condp->dtypeFrom(idxExprp);
        return condp;
    }
    static AstNodeExpr* delayRingSlot(FileLine* flp, SvaStateVertex* vtxp, AstNodeExpr* idxExprp,
                                      VAccess access = VAccess::READ) {
        // ring[idx]
        AstVar* const ringp = vtxp->datap()->delayRingVarp;
        AstVarRef* const refp = new AstVarRef{flp, ringp, access};
        if (vtxp->datap()->delayRingCounts) return new AstArraySel{flp, refp, idxExprp};
        return new AstSel{flp, refp, idxExprp, 1};
    }
    static AstNodeExpr* delayRingHeadCount(FileLine* flp, SvaStateVertex* vtxp) {
        AstNodeExpr* const headp
            = new AstVarRef{flp, vtxp->datap()->delayRingHeadVarp, VAccess::READ};
        if (vtxp->datap()->delayRingCounts) return headp;
        return new AstExtend{flp, headp, vtxp->datap()->delayRingLiveCountVarp->dtypep()->width()};
    }
    static AstNodeExpr* delayRingAtLastIndex(FileLine* const flp, AstVar* const idxp,
                                             const uint32_t size) {
        return new AstEq{flp, new AstVarRef{flp, idxp, VAccess::READ},
                         new AstConst{flp, AstConst::WidthedValue{}, 32, size - 1}};
    }
    static AstNodeExpr* delayRingOutputCount(FileLine* const flp, SvaStateVertex* const vtxp) {
        AstVar* const idxp = vtxp->datap()->delayRingIdxVarp;
        const uint32_t size = vtxp->m_delayRingSize;
        AstNodeExpr* outgoingValidp
            = new AstVarRef{flp, vtxp->datap()->delayRingWrappedVarp, VAccess::READ};
        if (!vtxp->m_isFixedDelayRing) {
            outgoingValidp
                = new AstLogOr{flp, outgoingValidp, delayRingAtLastIndex(flp, idxp, size)};
        }
        AstVar* const liveCountVarp = vtxp->datap()->delayRingLiveCountVarp;
        return new AstCond{flp, outgoingValidp, delayRingHeadCount(flp, vtxp),
                           newTypedConstp(flp, liveCountVarp->dtypep(), 0)};
    }
    static AstNodeExpr* delayRingHasLiveThreadsp(FileLine* const flp,
                                                 AstVar* const liveCountVarp) {
        // active = live_count != 0;
        return new AstNeq{flp, new AstVarRef{flp, liveCountVarp, VAccess::READ},
                          newTypedConstp(flp, liveCountVarp->dtypep(), 0)};
    }

    // Phase 3 output signals
    struct SignalSet final {
        AstNodeExpr* terminalActivep = nullptr;  // OR of all successful terminal matches
        AstNodeExpr* matchCountp = nullptr;  // NFA paths completing the sequence this tick
        AstNodeExpr* matchCountOverflowp = nullptr;  // Match count overflow this tick
        AstNodeExpr* rejectBasep = nullptr;  // Reject when a terminal match fails
        AstNodeExpr* requiredStepRejectp = nullptr;  // Per-source reject from rejectOnFail Links
        AstNodeExpr* throughoutRejectp = nullptr;  // Reject when a throughout guard drops
        AstNodeExpr* threadFailCountp = nullptr;  // Number of threads rejected on this tick
        AstNodeExpr* vacuousp = nullptr;  // Vacuous success this tick, if tracked
        AstNodeExpr* successCountp = nullptr;  // Matches and vacuous successes on this tick
    };

    // Disable condition also aborts attempts between clock events. A constant disable
    // never rises, and $sampled is unsupported in a sensitivity list.
    static bool isAsyncDisable(const AstNodeExpr* const disableExprp) {
        return disableExprp && !VN_IS(disableExprp, Const)
               && !disableExprp->exists([](const AstSampled*) { return true; });
    }

    // Emit the clocked update block of registers that hold pending attempts. The clearp
    // statements reset the same registers: a disable rising between clock events also
    // aborts pending attempts (IEEE 1800-2023 16.12), so clearp runs on that rising edge
    // in a separate block. It must clear unconditionally, as the disable may already be
    // false again when it runs, and the update block must not run on that edge, as it
    // would advance the attempts as if the clock had ticked. Blocks that hold no attempt
    // state, such as the $assertkill acknowledge in emitKillAckNba, do not go through here.
    // Callers pass a null clearp when the disable cannot rise between clock events.
    void addStateAlways(LowerCtx& c, AstNodeStmt* bodyp, AstNodeStmt* clearp) {
        m_modp->addStmtsp(
            newAssertAlways(c.flp, VAlwaysKwd::ALWAYS, c.senTreep->cloneTree(false), bodyp));
        if (!clearp) return;
        m_modp->addStmtsp(newAssertAlways(
            c.flp, VAlwaysKwd::ALWAYS,
            new AstSenTree{c.flp, new AstSenItem{c.flp, VEdgeType::ET_POSEDGE,
                                                 c.disableExprp->cloneTreePure(false)}},
            clearp));
    }

    // Boolean edge contribution to a state register or packed ring: src && cond && !disable
    static AstNodeExpr* gatedEdgeSigp(LowerCtx& c, const SvaTransEdge& tedger) {
        const SvaStateVertex* const fromVtxp = tedger.fromVtxp();
        UASSERT_OBJ(fromVtxp->datap()->stateSigp, fromVtxp, "Edge source missing stateSig");
        AstNodeExpr* const srcSigp
            = andCond(c.flp, fromVtxp->datap()->stateSigp->cloneTreePure(false), tedger.m_condp);
        if (!c.disableExprp) return srcSigp;
        return new AstLogAnd{c.flp, srcSigp,
                             new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)}};
    }

    // Phase 2/2b/2c: Emit NBA register updates and in-place delay-ring writes.
    // Phase 2: State register NBA always block. Each clocked-edge target
    // latches the OR of its incoming contributions.
    void emitStateRegisterNba(LowerCtx& c) {
        const bool asyncDisable = isAsyncDisable(c.disableExprp);
        AstNodeStmt* bodyp = nullptr;
        AstNodeStmt* clearp = nullptr;
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            if (!vtxp->datap()->stateVarp) continue;

            const bool counts = vtxp->datap()->stateCounts;
            AstNodeExpr* nextStatep = nullptr;
            for (const V3GraphEdge& edger : vtxp->inEdges()) {
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                if (!tedger.m_consumesCycle) continue;
                if (counts) {
                    // next_count += src_cond && !disable ? source_count : 0;
                    AstNodeExpr* enablep
                        = tedger.m_condp ? tedger.m_condp->cloneTreePure(false) : nullptr;
                    if (c.disableExprp) {
                        AstNodeExpr* const notDisp
                            = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                        enablep = enablep ? new AstLogAnd{c.flp, enablep, notDisp} : notDisp;
                    }
                    nextStatep = addCountp(
                        c.flp, nextStatep,
                        tedger.fromVtxp()->datap()->stateCountSigp->cloneTreePure(false), enablep);
                } else {
                    nextStatep = orExprs(c.flp, nextStatep, gatedEdgeSigp(c, tedger));
                }
            }

            UASSERT_OBJ(nextStatep, vtxp,
                        "Registered vertex has no clocked incoming contribution");
            nextStatep = counts ? addCountp(c.flp, nullptr, nextStatep, notKillActive(c))
                                : gateNotKill(c, nextStatep);

            AstAssignDly* const assignp = new AstAssignDly{
                c.flp, new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::WRITE}, nextStatep};
            bodyp = AstNode::addNextNull(bodyp, assignp);
            if (asyncDisable) {
                AstNodeExpr* const zerop = counts ? newTypedConstp(c.flp, m_u32DTypep, 0)
                                                  : new AstConst{c.flp, AstConst::BitFalse{}};
                clearp = AstNode::addNextNull(
                    clearp,
                    new AstAssignDly{
                        c.flp, new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::WRITE},
                        zerop});
            }
        }
        if (bodyp) addStateAlways(c, bodyp, clearp);
    }

    // Phase 2b: In-place ring storage and registered ring metadata.
    // countMatches: of a cover sequence, whose counts overflowing are reported
    void emitDelayRingUpdates(LowerCtx& c, const bool countMatches) {
        const bool asyncDisable = isAsyncDisable(c.disableExprp);
        for (V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            SvaStateVertex* const vtxp = static_cast<SvaStateVertex*>(&vtxr);
            if (!vtxp->datap()->delayRingVarp) continue;
            AstVar* const idxp = vtxp->datap()->delayRingIdxVarp;
            AstVar* const liveCountVarp = vtxp->datap()->delayRingLiveCountVarp;
            AstVar* const wrappedp = vtxp->datap()->delayRingWrappedVarp;
            const uint32_t size = static_cast<uint32_t>(vtxp->m_delayRingSize);
            const bool storesCounts = vtxp->datap()->delayRingCounts;

            // Packed rings store whether any thread arrives, count rings store how many.
            AstNodeExpr* incomingp = nullptr;
            AstNodeExpr* incomingOverflowp = nullptr;
            for (const V3GraphEdge& edger : vtxp->inEdges()) {
                ++m_statDelayRingEdgeVisits;
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                UASSERT_OBJ(tedger.m_consumesCycle == vtxp->m_isFixedDelayRing, vtxp,
                            "Delay-ring incoming edge kind mismatch");
                if (!storesCounts) {
                    incomingp = orExprs(c.flp, incomingp, gatedEdgeSigp(c, tedger));
                    continue;
                }
                const SvaStateVertex* const fromVtxp = tedger.fromVtxp();
                UASSERT_OBJ(fromVtxp->datap()->stateCountSigp, fromVtxp,
                            "Delay-ring incoming source missing stateCountSig");
                // IEEE 1800-2023 16.14.1/16.14.3: assertion alternatives belong to one
                // evaluation; only a cover sequence counts each end-of-match, and an
                // assertion with one thread per evaluation counts its threads.
                AstNodeExpr* contribp = fromVtxp->datap()->stateCountSigp->cloneTreePure(false);
                AstNodeExpr* contribOverflowp
                    = fromVtxp->datap()->stateCountOverflowSigp
                          ? fromVtxp->datap()->stateCountOverflowSigp->cloneTreePure(false)
                          : nullptr;
                if (tedger.m_condp) {
                    contribp = gateCheckedCountp(c.flp, contribp, contribOverflowp,
                                                 tedger.m_condp->cloneTreePure(false));
                }
                if (c.disableExprp) {
                    contribp = gateCheckedCountp(
                        c.flp, contribp, contribOverflowp,
                        new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)});
                }
                incomingp = addCheckedCountp(c.flp, incomingp, contribp, incomingOverflowp,
                                             contribOverflowp);
            }
            UASSERT_OBJ(incomingp, vtxp, "Delay ring has no incoming edge");
            AstNodeExpr* const incomingCountp
                = storesCounts ? incomingp->cloneTreePure(false)
                               : new AstExtend{c.flp, incomingp->cloneTreePure(false),
                                               m_u32DTypep->width()};
            // Only this block accesses the storage. Other processes read the cached head, so
            // the ring can be updated in place without an NBA shadow copy.
            AstAssign* const writeIncomingp = new AstAssign{
                c.flp,
                delayRingSlot(c.flp, vtxp, new AstVarRef{c.flp, idxp, VAccess::READ},
                              VAccess::WRITE),
                incomingp};
            AstNodeStmt* updateBodyp = writeIncomingp;
            // live_count <= live_count - outgoing_count + incoming_count;
            AstNodeExpr* const outgoingp = delayRingOutputCount(c.flp, vtxp);
            AstNodeExpr* const afterOutgoingp
                = new AstSub{c.flp, new AstVarRef{c.flp, liveCountVarp, VAccess::READ}, outgoingp};
            AstNodeExpr* const oldAfterOutgoingp = afterOutgoingp->cloneTreePure(false);
            AstAdd* const nextLiveCountp = new AstAdd{c.flp, afterOutgoingp, incomingCountp};
            if (storesCounts && countMatches) {
                AstNodeExpr* const liveOverflowp
                    = new AstLt{c.flp, nextLiveCountp->cloneTreePure(false), oldAfterOutgoingp};
                AstNodeExpr* const overflowp = orExprs(c.flp, incomingOverflowp, liveOverflowp);
                updateBodyp = newCountOverflowWarning(c.flp, overflowp);
                updateBodyp->addNext(writeIncomingp);
            } else {
                VL_DO_DANGLING(oldAfterOutgoingp->deleteTree(), oldAfterOutgoingp);
            }
            // Cache the outgoing slot for the next index after the write. Reading after
            // writing also handles one-slot rings and two-slot range rings without alias cases.
            AstNodeExpr* nextHeadIdxp
                = nextRingIndex(c.flp, new AstVarRef{c.flp, idxp, VAccess::READ}, size);
            if (!vtxp->m_isFixedDelayRing) {
                nextHeadIdxp = nextRingIndex(c.flp, nextHeadIdxp, size);
            }
            updateBodyp->addNext(new AstAssignDly{
                c.flp, new AstVarRef{c.flp, vtxp->datap()->delayRingHeadVarp, VAccess::WRITE},
                delayRingSlot(c.flp, vtxp, nextHeadIdxp)});
            updateBodyp->addNext(new AstAssignDly{
                c.flp, new AstVarRef{c.flp, liveCountVarp, VAccess::WRITE}, nextLiveCountp});
            // wrapped <= wrapped || idx == size - 1;
            updateBodyp->addNext(
                new AstAssignDly{c.flp, new AstVarRef{c.flp, wrappedp, VAccess::WRITE},
                                 new AstLogOr{c.flp, new AstVarRef{c.flp, wrappedp, VAccess::READ},
                                              delayRingAtLastIndex(c.flp, idxp, size)}});
            // idx <= next_idx;
            updateBodyp->addNext(new AstAssignDly{
                c.flp, new AstVarRef{c.flp, idxp, VAccess::WRITE},
                nextRingIndex(c.flp, new AstVarRef{c.flp, idxp, VAccess::READ}, size)});
            if (vtxp->m_delayRingAdvanceCondp) {
                updateBodyp = new AstIf{
                    c.flp, sampled(vtxp->m_delayRingAdvanceCondp->cloneTreePure(false)),
                    updateBodyp};
            }

            AstNodeExpr* clearCondp = killActive(c);
            if (vtxp->m_delayRingClearCondp) {
                clearCondp = orExprs(c.flp, clearCondp,
                                     sampled(vtxp->m_delayRingClearCondp->cloneTreePure(false)));
            }
            if (vtxp->m_abortClearp) {
                clearCondp = orExprs(c.flp, clearCondp,
                                     sampled(vtxp->m_abortClearp->cloneTreePure(false)));
            }
            if (c.disableExprp) {
                clearCondp = orExprs(c.flp, clearCondp, c.disableExprp->cloneTreePure(false));
            }
            AstNodeExpr* guardp = nullptr;
            for (AstNodeExpr* const cp : vtxp->m_throughoutConds) {
                AstNodeExpr* const sampledp = sampled(cp->cloneTreePure(false));
                guardp = guardp ? static_cast<AstNodeExpr*>(new AstLogAnd{c.flp, guardp, sampledp})
                                : sampledp;
            }
            if (guardp) clearCondp = orExprs(c.flp, clearCondp, new AstLogNot{c.flp, guardp});
            // Logically clear the ring without touching its wide storage.
            AstAssignDly* const clearCountp
                = new AstAssignDly{c.flp, new AstVarRef{c.flp, liveCountVarp, VAccess::WRITE},
                                   newTypedConstp(c.flp, liveCountVarp->dtypep(), 0)};
            clearCountp->addNext(new AstAssignDly{c.flp,
                                                  new AstVarRef{c.flp, wrappedp, VAccess::WRITE},
                                                  new AstConst{c.flp, AstConst::BitFalse{}}});
            clearCountp->addNext(new AstAssignDly{c.flp,
                                                  new AstVarRef{c.flp, idxp, VAccess::WRITE},
                                                  newTypedConstp(c.flp, idxp->dtypep(), 0)});
            updateBodyp = new AstIf{c.flp, clearCondp, clearCountp, updateBodyp};

            addStateAlways(c, updateBodyp, asyncDisable ? clearCountp->cloneTree(true) : nullptr);
        }
    }

    // Phase 2c: SAnd combiner done-latch always block.
    // NBA semantics ensure doneL/doneR read pre-update values (IEEE 16.9.5).
    void emitAndCombinerDoneLatchNba(LowerCtx& c) {
        const bool asyncDisable = isAsyncDisable(c.disableExprp);
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            const SvaStateVertex* const avp = static_cast<const SvaStateVertex*>(&vtxr);
            if (!avp->datap()->doneLVarp) continue;
            // doneLVars is non-null only for AndCombiner vertices, which always
            // have both m_andLhsTermp and m_andRhsTermp set at build time.
            UASSERT_OBJ(avp->m_andLhsTermp && avp->m_andRhsTermp, avp,
                        "AndCombiner vertex missing LHS/RHS terminal");
            const SvaStateVertex* const lhsTermp = avp->m_andLhsTermp;
            const SvaStateVertex* const rhsTermp = avp->m_andRhsTermp;
            AstAssignDly* const clearLp = new AstAssignDly{
                c.flp, new AstVarRef{c.flp, avp->datap()->doneLVarp, VAccess::WRITE},
                new AstConst{c.flp, AstConst::BitFalse{}}};
            AstAssignDly* const clearRp = new AstAssignDly{
                c.flp, new AstVarRef{c.flp, avp->datap()->doneRVarp, VAccess::WRITE},
                new AstConst{c.flp, AstConst::BitFalse{}}};
            clearLp->addNext(clearRp);

            AstNodeExpr* const matchLNowp
                = buildMatchNow(c.flp, lhsTermp->datap()->stateSigp, avp->m_andLhsCondp);
            AstNodeExpr* const matchRNowp
                = buildMatchNow(c.flp, rhsTermp->datap()->stateSigp, avp->m_andRhsCondp);
            AstNodeExpr* gateLp = matchLNowp;
            AstNodeExpr* gateRp = matchRNowp;
            if (c.disableExprp) {
                AstNodeExpr* const notDisLp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                gateLp = new AstLogAnd{c.flp, gateLp, notDisLp};
                AstNodeExpr* const notDisRp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                gateRp = new AstLogAnd{c.flp, gateRp, notDisRp};
            }
            AstAssignDly* const setLp = new AstAssignDly{
                c.flp, new AstVarRef{c.flp, avp->datap()->doneLVarp, VAccess::WRITE},
                new AstConst{c.flp, AstConst::BitTrue{}}};
            AstIf* const setLIfp = new AstIf{c.flp, gateLp, setLp, nullptr};
            AstAssignDly* const setRp = new AstAssignDly{
                c.flp, new AstVarRef{c.flp, avp->datap()->doneRVarp, VAccess::WRITE},
                new AstConst{c.flp, AstConst::BitTrue{}}};
            AstIf* const setRIfp = new AstIf{c.flp, gateRp, setRp, nullptr};
            setLIfp->addNext(setRIfp);

            AstNodeExpr* clearCondp = new AstLogOr{c.flp, killActive(c),
                                                   avp->datap()->stateSigp->cloneTreePure(false)};
            if (c.disableExprp) {
                clearCondp = orExprs(c.flp, clearCondp, c.disableExprp->cloneTreePure(false));
            }
            AstIf* const topp = new AstIf{c.flp, clearCondp, clearLp, setLIfp};
            addStateAlways(c, topp, asyncDisable ? clearLp->cloneTree(true) : nullptr);
        }
    }

    void emitKillAckNba(LowerCtx& c) {
        AstAssignDly* const ackp
            = new AstAssignDly{c.flp, new AstVarRef{c.flp, c.killVarp, VAccess::WRITE},
                               assertKillGet(c.flp, c.assertType, c.directiveType)};
        m_modp->addStmtsp(
            newAssertAlways(c.flp, VAlwaysKwd::ALWAYS, c.senTreep->cloneTree(false), ackp));
    }

    // Add the threads of a terminal Link that reach their final check this tick
    static void addTerminalCount(LowerCtx& c, AstNodeExpr*& totalCountp, const SvaTransEdge& tedge,
                                 AstNodeExpr* const countp) {
        // Threads another check of the vertex rejects are counted by that check instead.
        UASSERT_OBJ(!tedge.m_condp, tedge.fromVtxp(),
                    "Conditional terminal Link only comes from a mid-window source");
        AstNodeExpr* enablep = newRequiredStepsHoldp(c, tedge.fromVtxp());
        if (AstNodeExpr* const rejectCondp = newThroughoutRejectCondp(c, tedge.fromVtxp())) {
            AstNodeExpr* const notRejectp = new AstLogNot{c.flp, rejectCondp};
            enablep = enablep ? new AstLogAnd{c.flp, enablep, notRejectp} : notRejectp;
        }
        totalCountp = addCountp(c.flp, totalCountp, countp, enablep);
    }

    // Phase 3/3a/3b: Compute terminal match/reject signals, required-step reject,
    // throughout-drop reject; clean up intermediate state signals.
    // Phase 3: terminalActive and rejectBase from Links to matchVertex.
    // Builder only adds Links (non-clocked) to matchVertex via addLink in
    // wireMatchAndMidSources. For cover sequence, also count each end-of-match
    // so the action can be replayed without unrolling endpoints.
    void computeTerminalMatchAndReject(LowerCtx& c, SignalSet& sigs, const bool needMatchCount,
                                       AstNodeExpr** const terminalCountpp) {
        // If terminalCountpp is set, also count the threads whose final check decides this tick.
        for (const SvaTransEdge* const tedgep : c.graph.allEdges()) {
            if (tedgep->toVtxp() != c.graph.m_matchVertexp) continue;
            SvaStateVertex* const fromVtxp = tedgep->fromVtxp();
            UASSERT_OBJ(fromVtxp->datap()->stateSigp, fromVtxp,
                        "Terminal-link source missing stateSig");

            AstNodeExpr* srcSigp = fromVtxp->datap()->stateSigp->cloneTreePure(false);
            srcSigp = andCond(c.flp, srcSigp, tedgep->m_condp);
            if (needMatchCount) {
                UASSERT_OBJ(fromVtxp->datap()->stateCountSigp, fromVtxp,
                            "Terminal-link source missing stateCountSig");
                AstNodeExpr* contributionp
                    = fromVtxp->datap()->stateCountSigp->cloneTreePure(false);
                AstNodeExpr* contributionOverflowp
                    = fromVtxp->datap()->stateCountOverflowSigp
                          ? fromVtxp->datap()->stateCountOverflowSigp->cloneTreePure(false)
                          : nullptr;
                if (tedgep->m_condp) {
                    contributionp = gateCheckedCountp(c.flp, contributionp, contributionOverflowp,
                                                      tedgep->m_condp->cloneTreePure(false));
                }
                sigs.matchCountp
                    = addCheckedCountp(c.flp, sigs.matchCountp, contributionp,
                                       sigs.matchCountOverflowp, contributionOverflowp);
            }

            if (fromVtxp->m_delayRingSize && !fromVtxp->m_isFixedDelayRing) {
                sigs.terminalActivep
                    = orExprs(c.flp, sigs.terminalActivep, srcSigp->cloneTreePure(false));
                // reject |= (wrapped || idx == size - 1) && head && final_condition;
                // Only a range creates such a ring, and a range has several threads
                UASSERT_OBJ(!c.exactCounts, fromVtxp, "Range ring with exact counts");
                AstNodeExpr* expireContribp = delayRingOutputCount(c.flp, fromVtxp);
                if (terminalCountpp) {
                    addTerminalCount(c, *terminalCountpp, *tedgep,
                                     expireContribp->cloneTreePure(false));
                }
                expireContribp = andCond(c.flp, expireContribp, tedgep->m_condp);
                sigs.rejectBasep = orExprs(c.flp, sigs.rejectBasep, expireContribp);
                VL_DO_DANGLING(srcSigp->deleteTree(), srcSigp);
            } else if (fromVtxp->m_isUnbounded || fromVtxp->m_isAndCombiner) {
                sigs.terminalActivep = orExprs(c.flp, sigs.terminalActivep, srcSigp);
            } else {
                if (terminalCountpp) {
                    // With exact counts, each thread of the source
                    AstNodeExpr* const countp
                        = c.exactCounts ? fromVtxp->datap()->stateCountSigp->cloneTreePure(false)
                                        : new AstExtend{c.flp, srcSigp->cloneTreePure(false),
                                                        m_u32DTypep->width()};
                    addTerminalCount(c, *terminalCountpp, *tedgep, countp);
                }
                sigs.terminalActivep
                    = orExprs(c.flp, sigs.terminalActivep, srcSigp->cloneTreePure(false));
                sigs.rejectBasep = orExprs(c.flp, sigs.rejectBasep, srcSigp);
            }
        }
        // wireMatchAndMidSources always adds a Link from result.termVertexp
        // to m_matchVertexp, so the loop above always sets terminalActivep.
        UASSERT_OBJ(sigs.terminalActivep, c.graph.m_matchVertexp,
                    "No terminal edge to match vertex");
    }

    AstNodeExpr* newThroughoutThreadFailCountp(LowerCtx& c, AstVar* const delayRingLiveCountVarp,
                                               AstNodeExpr* const stateExprp,
                                               AstNodeExpr* const enablep) {
        AstNodeExpr* const activeThreadCountp
            = delayRingLiveCountVarp
                  ? static_cast<AstNodeExpr*>(
                        new AstVarRef{c.flp, delayRingLiveCountVarp, VAccess::READ})
                  : new AstExtend{c.flp, stateExprp->cloneTreePure(false), m_u32DTypep->width()};
        return addCountp(c.flp, nullptr, activeThreadCountp, enablep);
    }

    // Condition under which a rejectOnFail Link keeps its source threads
    static AstNodeExpr* newRequiredStepCondp(LowerCtx& c, const SvaTransEdge& tedge) {
        if (!tedge.m_condVtxp) return tedge.m_condp->cloneTreePure(false);
        UASSERT_OBJ(tedge.m_condVtxp->datap()->stateSigp, tedge.m_condVtxp,
                    "rejectOnFail condVtxp missing stateSig");
        AstNodeExpr* const condp = tedge.m_condVtxp->datap()->stateSigp->cloneTreePure(false);
        if (!tedge.m_condp) return condp;
        return new AstLogOr{c.flp, condp, tedge.m_condp->cloneTreePure(false)};
    }
    // Condition under which every rejectOnFail Link leaving a vertex keeps its threads
    static AstNodeExpr* newRequiredStepsHoldp(LowerCtx& c, const SvaStateVertex* const vtxp) {
        // Or nullptr if there is none.
        // A thread such a Link rejects is counted by that Link, so the other checks of the vertex
        // count only the threads kept here.
        AstNodeExpr* holdp = nullptr;
        for (const V3GraphEdge& edger : vtxp->outEdges()) {
            const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
            if (!tedger.m_rejectOnFail) continue;
            AstNodeExpr* const condp = newRequiredStepCondp(c, tedger);
            holdp = holdp ? new AstLogAnd{c.flp, holdp, condp} : condp;
        }
        return holdp;
    }
    // Condition rejecting a vertex's threads on a throughout drop or abort, or nullptr
    static AstNodeExpr* newThroughoutRejectCondp(LowerCtx& c, const SvaStateVertex* const vtxp) {
        // An antecedent's throughout guard only ends its match attempt, so does not reject
        const bool guardRejects = !vtxp->m_throughoutConds.empty() && !vtxp->m_isAntecedent;
        if (!guardRejects && !vtxp->m_abortRejectp) return nullptr;
        AstNodeExpr* guardp = nullptr;
        if (guardRejects) {
            for (AstNodeExpr* const cp : vtxp->m_throughoutConds) {
                AstNodeExpr* const sp = sampled(cp->cloneTreePure(false));
                guardp = guardp ? static_cast<AstNodeExpr*>(new AstLogAnd{c.flp, guardp, sp})
                                : sp;
            }
        }
        if (vtxp->m_abortRejectp) {
            AstNodeExpr* const notAbortp
                = new AstLogNot{c.flp, sampled(vtxp->m_abortRejectp->cloneTreePure(false))};
            guardp = guardp ? static_cast<AstNodeExpr*>(new AstLogAnd{c.flp, guardp, notAbortp})
                            : notAbortp;
        }
        AstNodeExpr* rejectCondp = new AstLogNot{c.flp, guardp};
        if (vtxp->m_abortClearp) {
            // Any abort clears the ring. Accept aborts suppress a simultaneous guard failure;
            // reject aborts are restored below so they still force rejection.
            AstNodeExpr* const notAbortClearp
                = new AstLogNot{c.flp, sampled(vtxp->m_abortClearp->cloneTreePure(false))};
            rejectCondp = new AstLogAnd{c.flp, rejectCondp, notAbortClearp};
            if (vtxp->m_abortRejectp) {
                rejectCondp = new AstLogOr{c.flp, rejectCondp,
                                           sampled(vtxp->m_abortRejectp->cloneTreePure(false))};
            }
        }
        return rejectCondp;
    }

    // Phase 3b: Throughout-drop and ring-wide abort rejection.
    void computeThroughoutReject(LowerCtx& c, SignalSet& sigs, const bool needThreadFailCount,
                                 const std::vector<int>& offsets,
                                 std::map<int, AstNodeExpr*>& failps) {
        std::vector<AstNodeExpr*> rejectps;  // Terms of throughoutRejectp
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            const bool guardRejects = !vtxp->m_throughoutConds.empty() && !vtxp->m_isAntecedent;
            if (!guardRejects && !vtxp->m_abortRejectp) continue;
            if (vtxp->m_isAndCombiner) continue;
            AstNodeExpr* stateExprp = nullptr;
            if (vtxp->datap()->stateVarp) {
                stateExprp = new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::READ};
            } else if (vtxp->datap()->delayRingVarp && vtxp->m_isFixedDelayRing) {
                stateExprp
                    = delayRingHasLiveThreadsp(c.flp, vtxp->datap()->delayRingLiveCountVarp);
            } else {
                UASSERT_OBJ(vtxp->datap()->stateSigp, vtxp,
                            "Throughout-conds vertex missing state representation");
                stateExprp = vtxp->datap()->stateSigp->cloneTreePure(false);
            }
            AstNodeExpr* const rejectCondp = newThroughoutRejectCondp(c, vtxp);
            if (needThreadFailCount && !vtxp->datap()->delayRingLiveCountVarp) {
                AstNodeExpr*& keyFailp = failps[failKey(offsets, vtxp)];
                keyFailp = orExprs(c.flp, keyFailp,
                                   new AstLogAnd{c.flp, stateExprp->cloneTreePure(false),
                                                 rejectCondp->cloneTreePure(false)});
            } else if (needThreadFailCount) {
                AstNodeExpr* countCondp = rejectCondp->cloneTreePure(false);
                if (AstNodeExpr* const holdp = newRequiredStepsHoldp(c, vtxp)) {
                    countCondp = new AstLogAnd{c.flp, countCondp, holdp};
                }
                AstNodeExpr* const contributionp = newThroughoutThreadFailCountp(
                    c, vtxp->datap()->delayRingLiveCountVarp, stateExprp, countCondp);
                sigs.threadFailCountp = addCountp(c.flp, sigs.threadFailCountp, contributionp);
                if (vtxp->m_abortRejectp && vtxp->m_delayRingAdvanceCondp) {
                    // An advancing ring thread also occupies its same-tick match vertex in the
                    // unrolled NFA, so abort rejection must replay both fail actions.
                    AstNodeExpr* const abortAndAdvancep = new AstLogAnd{
                        c.flp, sampled(vtxp->m_abortRejectp->cloneTreePure(false)),
                        sampled(vtxp->m_delayRingAdvanceCondp->cloneTreePure(false))};
                    AstNodeExpr* const matchContributionp = newThroughoutThreadFailCountp(
                        c, vtxp->datap()->delayRingLiveCountVarp, stateExprp, abortAndAdvancep);
                    sigs.threadFailCountp
                        = addCountp(c.flp, sigs.threadFailCountp, matchContributionp);
                }
            }
            rejectps.push_back(new AstLogAnd{c.flp, stateExprp, rejectCondp});
        }
        sigs.throughoutRejectp = newOrTree(c.flp, rejectps.cbegin(), rejectps.cend());
    }

    // Fail count with a top-level synchronous abort (IEEE 1800-2023 16.12.14). Each thread
    // live at the start of the tick, in a state register, a delay ring, or the attempt
    // starting now, is one evaluation attempt, which the abort fails or passes.
    AstNodeExpr* newExactAbortFailCountp(LowerCtx& c, AstNodeExpr* const otherFailCountp) {
        AstNodeExpr* const firep = sampled(c.exactAbortp->condp()->cloneTreePure(false));
        if (c.exactAbortp->kind().isAccept()) {
            return new AstCond{c.flp, firep, newTypedConstp(c.flp, m_u32DTypep, 0),
                               otherFailCountp};
        }
        // Each thread is counted where it starts the tick: zero-delay links only move it
        AstNodeExpr* liveCountp = nullptr;
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            if (vtxp == c.graph.m_startVertexp || vtxp->datap()->stateVarp) {
                liveCountp = addCountp(c.flp, liveCountp,
                                       vtxp->datap()->stateCountSigp->cloneTreePure(false));
            } else if (vtxp->datap()->delayRingLiveCountVarp) {
                liveCountp = addCountp(
                    c.flp, liveCountp,
                    new AstVarRef{c.flp, vtxp->datap()->delayRingLiveCountVarp, VAccess::READ});
            }
        }
        if (c.disableExprp) {
            liveCountp = addCountp(c.flp, nullptr, liveCountp,
                                   new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)});
        }
        return new AstCond{c.flp, firep, liveCountp, otherFailCountp};
    }

    // Clock ticks from the attempt start to each vertex by color, or negative if not fixed
    static std::vector<int> vertexOffsets(const SvaGraph& graph) {
        // A thread in a vertex of a fixed offset started that many ticks ago, so the threads of
        // all vertices with one offset belong to one attempt.
        constexpr int UNSET = -2;  // Not reached from the start vertex (yet)
        constexpr int VARIABLE = -1;  // Reached at different offsets
        std::vector<int> offsets(graph.m_graph.vertices().size(), UNSET);
        offsets[graph.m_startVertexp->color()] = 0;
        std::vector<const SvaStateVertex*> work{graph.m_startVertexp};
        // An AND combiner has no in-edges, so the walk cannot tell its offset
        for (const V3GraphVertex& vtxr : graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            if (!vtxp->m_isAndCombiner) continue;
            offsets[vtxp->color()] = VARIABLE;
            work.push_back(vtxp);
        }
        while (!work.empty()) {
            const SvaStateVertex* const fromp = work.back();
            work.pop_back();
            const int fromOffset = offsets[fromp->color()];
            for (const V3GraphEdge& edger : fromp->outEdges()) {
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                const SvaStateVertex* const top = tedger.toVtxp();
                int toOffset = VARIABLE;
                if (fromOffset >= 0 && !top->m_delayRingSize) {
                    toOffset = fromOffset + tedger.m_consumesCycle;
                } else if (fromOffset >= 0 && top->m_isFixedDelayRing
                           && !top->m_delayRingAdvanceCondp) {
                    toOffset = fromOffset + static_cast<int>(top->m_delayRingSize);
                }
                int& offset = offsets[top->color()];
                if (offset == VARIABLE || offset == toOffset) continue;
                offset = offset == UNSET ? toOffset : VARIABLE;
                work.push_back(top);
            }
        }
        return offsets;
    }
    // Key of the rejections of a vertex's threads, counted once per tick, see computeSignals
    static int failKey(const std::vector<int>& offsets, const SvaStateVertex* vtxp) {
        const int offset = offsets[vtxp->color()];
        return offset >= 0 ? offset : -1 - vtxp->color();
    }

    // Number of attempts completing this tick, or nullptr if threads cannot tell
    AstNodeExpr* newAttemptMatchCountp(LowerCtx& c) {
        // On a tick, all threads of one offset from the attempt start belong to one attempt.
        // So when all terminal vertices have one fixed offset, their threads are one attempt.
        // A range ring fed from that offset holds attempts at larger offsets, one per slot.
        // The final condition clearing the ring also clears its incoming attempts, so its
        // attempts complete together, and no attempt completes twice.
        const std::vector<int> offsets = vertexOffsets(c.graph);
        std::set<int> attemptOffsets;
        const SvaStateVertex* ringp = nullptr;
        std::vector<const SvaTransEdge*> fixedEdgeps;
        for (const SvaTransEdge* const tedgep : c.graph.allEdges()) {
            if (tedgep->toVtxp() != c.graph.m_matchVertexp) continue;
            const SvaStateVertex* const fromVtxp = tedgep->fromVtxp();
            // The ring must clear exactly when the final condition holds, which an enclosing
            // operator such as throughout can extend, so compare the two conditions
            if (fromVtxp->m_delayRingClearCondp
                && fromVtxp->m_delayRingClearCondp->sameTree(c.matchCondp)) {
                UASSERT_OBJ(!ringp, fromVtxp, "Second range ring linked to the match");
                UASSERT_OBJ(!tedgep->m_condp, fromVtxp, "Range ring Link has a condition");
                ringp = fromVtxp;
                for (const V3GraphEdge& edger : ringp->inEdges())
                    attemptOffsets.insert(offsets[edger.fromp()->color()]);
            } else {
                attemptOffsets.insert(offsets[fromVtxp->color()]);
                fixedEdgeps.push_back(tedgep);
            }
        }
        if (attemptOffsets.size() != 1 || *attemptOffsets.begin() < 0) return nullptr;
        // The first tick of a range is a terminal vertex of its own
        UASSERT_OBJ(!fixedEdgeps.empty(), c.graph.m_matchVertexp,
                    "Range ring without its first tick");
        AstNodeExpr* fixedMatchp = nullptr;
        for (const SvaTransEdge* const tedgep : fixedEdgeps)
            fixedMatchp = orExprs(
                c.flp, fixedMatchp,
                andCond(c.flp, tedgep->fromVtxp()->datap()->stateSigp->cloneTreePure(false),
                        tedgep->m_condp));
        AstNodeExpr* const countp = new AstExtend{c.flp, fixedMatchp, m_u32DTypep->width()};
        if (!ringp) return countp;
        return addCountp(c.flp, countp, ringp->datap()->stateCountSigp->cloneTreePure(false));
    }

    SignalSet computeSignals(LowerCtx& c, const bool needThreadFailCount,
                             const bool needRejectCount, const bool needSuccessCount,
                             const bool needMatchCount, const bool countAttempts) {
        SignalSet sigs;

        // Exact counts always count failures, from zero
        if (c.exactCounts) sigs.threadFailCountp = newTypedConstp(c.flp, m_u32DTypep, 0);
        // Each terminal thread fails when the final condition is false.
        AstNodeExpr* terminalCountp = nullptr;
        const bool needTerminalCount = needRejectCount && c.matchCondp;
        computeTerminalMatchAndReject(c, sigs, needMatchCount,
                                      needTerminalCount ? &terminalCountp : nullptr);
        if (terminalCountp) {
            // thread_fail_count += final_condition ? 0 : terminal_count;
            sigs.threadFailCountp
                = addCountp(c.flp, sigs.threadFailCountp, terminalCountp,
                            new AstLogNot{c.flp, sampled(c.matchCondp->cloneTreePure(false))});
        }
        // A cover property replays its pass action for each attempt completing
        if (countAttempts) sigs.matchCountp = newAttemptMatchCountp(c);

        // Phase 3a: required-step rejection.
        // Builder only sets m_rejectOnFail on non-clocked Links with m_condp
        // or m_condVtxp, and the source always has a resolved stateSig.
        // A thread or an attempt failing several checks on one tick, such as its next step and
        // a throughout guard, or both operands of an 'and', fails once. So count the rejections
        // of sources with one fixed offset once, and of other sources once per vertex.
        const std::vector<int> offsets
            = needThreadFailCount || needRejectCount ? vertexOffsets(c.graph) : std::vector<int>{};
        std::map<int, AstNodeExpr*> failps;  // By failKey
        std::vector<AstNodeExpr*> rejectps;  // Terms of requiredStepRejectp
        for (const SvaTransEdge* const tedgep : c.graph.allEdges()) {
            if (!tedgep->m_rejectOnFail) continue;
            const SvaStateVertex* const fromVtxp = tedgep->fromVtxp();
            UASSERT_OBJ(fromVtxp->datap()->stateSigp && (tedgep->m_condp || tedgep->m_condVtxp),
                        fromVtxp,
                        "rejectOnFail Link must have condp/condVtxp and source stateSig");
            AstNodeExpr* const srcSigp = fromVtxp->datap()->stateSigp->cloneTreePure(false);
            AstNodeExpr* const notCondp = new AstLogNot{c.flp, newRequiredStepCondp(c, *tedgep)};
            AstNodeExpr* const rawFailp = new AstLogAnd{c.flp, srcSigp, notCondp};
            if (c.exactCounts) {
                // thread_fail_count += fail ? source_count : 0;
                if (!tedgep->m_abortReject) {
                    sigs.threadFailCountp
                        = addCountp(c.flp, sigs.threadFailCountp,
                                    fromVtxp->datap()->stateCountSigp->cloneTreePure(false),
                                    notCondp->cloneTreePure(false));
                }
            } else if (needThreadFailCount) {
                AstNodeExpr*& keyFailp = failps[failKey(offsets, fromVtxp)];
                keyFailp = orExprs(c.flp, keyFailp, rawFailp->cloneTreePure(false));
            }
            rejectps.push_back(gateNotKill(c, rawFailp));
        }
        sigs.requiredStepRejectp = newOrTree(c.flp, rejectps.cbegin(), rejectps.cend());

        computeThroughoutReject(c, sigs, needRejectCount, offsets, failps);
        for (const auto& it : failps) {
            sigs.threadFailCountp
                = addCountp(c.flp, sigs.threadFailCountp,
                            new AstExtend{c.flp, it.second, m_u32DTypep->width()});
        }
        if (c.exactAbortp)
            sigs.threadFailCountp = newExactAbortFailCountp(c, sigs.threadFailCountp);
        if (sigs.threadFailCountp) {
            sigs.threadFailCountp
                = addCountp(c.flp, nullptr, sigs.threadFailCountp, notKillActive(c));
        }
        if (sigs.matchCountp) {
            if (c.matchCondp) {
                sigs.matchCountp
                    = gateCheckedCountp(c.flp, sigs.matchCountp, sigs.matchCountOverflowp,
                                        sampled(c.matchCondp->cloneTreePure(false)));
            }
            sigs.matchCountp = gateCheckedCountp(c.flp, sigs.matchCountp, sigs.matchCountOverflowp,
                                                 notKillActive(c));
        }
        sigs.terminalActivep = gateNotKill(c, sigs.terminalActivep);
        AstNodeExpr* vacuousCountp = nullptr;  // Vacuous successes this tick, before gating
        for (const SvaStateVertex* const vtxp : c.graph.m_vacuousVertices) {
            AstNodeExpr* const sigp = vtxp->datap()->stateSigp;
            sigs.vacuousp = orExprs(c.flp, sigs.vacuousp, sigp->cloneTreePure(false));
            if (needSuccessCount) {
                vacuousCountp = addCountp(
                    c.flp, vacuousCountp,
                    new AstExtend{c.flp, sigp->cloneTreePure(false), m_u32DTypep->width()});
            }
        }
        sigs.vacuousp = gateNotKill(c, sigs.vacuousp);
        sigs.rejectBasep = gateNotKill(c, sigs.rejectBasep);
        sigs.throughoutRejectp = gateNotKill(c, sigs.throughoutRejectp);

        // Clean up intermediate state signals. These are orphan subtrees
        // (never linked into the enclosing AST); deleteTree() is immediate
        // which is what we want since stateSigp lifetime ends with this scope.
        for (V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            SvaStateVertex* const vtxp = static_cast<SvaStateVertex*>(&vtxr);
            AstNodeExpr*& sigp = vtxp->datap()->stateSigp;
            if (sigp) VL_DO_DANGLING(sigp->deleteTree(), sigp);
            AstNodeExpr*& countp = vtxp->datap()->stateCountSigp;
            if (countp) VL_DO_DANGLING(countp->deleteTree(), countp);
            AstNodeExpr*& overflowp = vtxp->datap()->stateCountOverflowSigp;
            if (overflowp) VL_DO_DANGLING(overflowp->deleteTree(), overflowp);
        }
        // Disable iff gating (IEEE 1800-2023 16.12) on the current level value.
        if (c.disableExprp) {
            // terminalActivep is always set, so gate it unconditionally.
            AstNodeExpr* const notTermp
                = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
            sigs.terminalActivep = new AstLogAnd{c.flp, sigs.terminalActivep, notTermp};
            if (sigs.vacuousp) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.vacuousp = new AstLogAnd{c.flp, sigs.vacuousp, notDisp};
            }
            if (sigs.rejectBasep) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.rejectBasep = new AstLogAnd{c.flp, sigs.rejectBasep, notDisp};
            }
            if (sigs.throughoutRejectp) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.throughoutRejectp = new AstLogAnd{c.flp, sigs.throughoutRejectp, notDisp};
            }
            if (sigs.requiredStepRejectp) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.requiredStepRejectp = new AstLogAnd{c.flp, sigs.requiredStepRejectp, notDisp};
            }
            if (sigs.matchCountp) {
                sigs.matchCountp = gateCheckedCountp(
                    c.flp, sigs.matchCountp, sigs.matchCountOverflowp,
                    new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)});
            }
            if (sigs.threadFailCountp) {
                sigs.threadFailCountp
                    = addCountp(c.flp, nullptr, sigs.threadFailCountp,
                                new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)});
            }
        }

        // A match and vacuous successes of different attempts can coincide; the NFA state
        // aggregates attempts, so the match and each implication count at most once per tick
        if (vacuousCountp) {
            AstNodeExpr* matchp = sigs.terminalActivep->cloneTreePure(false);
            if (c.matchCondp) {
                matchp = new AstLogAnd{c.flp, matchp, sampled(c.matchCondp->cloneTreePure(false))};
            }
            sigs.successCountp
                = addCountp(c.flp, new AstExtend{c.flp, matchp, m_u32DTypep->width()},
                            vacuousCountp, sigs.vacuousp->cloneTreePure(false));
        }

        if (sigs.matchCountOverflowp) {
            m_modp->addStmtsp(
                newAssertAlways(c.flp, VAlwaysKwd::ALWAYS, c.senTreep->cloneTree(false),
                                newCountOverflowWarning(c.flp, sigs.matchCountOverflowp)));
            sigs.matchCountOverflowp = nullptr;
        }

        return sigs;
    }

    // Progress of resolveLinkState on one vertex
    enum class LinkVisit : uint8_t { UNVISITED, IN_PROGRESS, RESOLVED };

    // Build the state signal of a link-only or SAnd combiner vertex once, after every
    // vertex it reads. Start, register and delay-ring vertices are seeded beforehand, and
    // match and reject sinks get no state signal here, so the recursion stops at them.
    void resolveLinkState(LowerCtx& c, SvaStateVertex* const vtxp, std::vector<LinkVisit>& visits,
                          const bool countMatches) {
        LinkVisit& visit = visits[vtxp->color()];
        if (visit == LinkVisit::RESOLVED) return;
        UASSERT_OBJ(visit == LinkVisit::UNVISITED, vtxp,
                    "NFA loop through Links without a register or delay ring");
        visit = LinkVisit::IN_PROGRESS;
        if (vtxp->m_isAndCombiner) {
            SvaStateVertex* const lhsTermp = vtxp->m_andLhsTermp;
            SvaStateVertex* const rhsTermp = vtxp->m_andRhsTermp;
            // AndCombiner vertices always have both terminal pointers set.
            UASSERT_OBJ(lhsTermp && rhsTermp, vtxp, "AndCombiner vertex missing LHS/RHS terminal");
            resolveLinkState(c, lhsTermp, visits, countMatches);
            resolveLinkState(c, rhsTermp, visits, countMatches);
            UASSERT_OBJ(lhsTermp->datap()->stateSigp && rhsTermp->datap()->stateSigp, vtxp,
                        "AndCombiner operand terminal has no state signal");
            AstNodeExpr* const matchLp
                = buildMatchNow(c.flp, lhsTermp->datap()->stateSigp, vtxp->m_andLhsCondp);
            AstNodeExpr* const matchRp
                = buildMatchNow(c.flp, rhsTermp->datap()->stateSigp, vtxp->m_andRhsCondp);
            AstNodeExpr* const doneLOrp = new AstLogOr{
                c.flp, new AstVarRef{c.flp, vtxp->datap()->doneLVarp, VAccess::READ}, matchLp};
            AstNodeExpr* const doneROrp = new AstLogOr{
                c.flp, new AstVarRef{c.flp, vtxp->datap()->doneRVarp, VAccess::READ}, matchRp};
            // Both operands matched since the attempt started. The done latches are cleared
            // once this holds, so they are never both set and one operand matches now.
            vtxp->datap()->stateSigp = new AstLogAnd{c.flp, doneLOrp, doneROrp};
            vtxp->datap()->stateCountSigp = new AstExtend{
                c.flp, vtxp->datap()->stateSigp->cloneTreePure(false), m_u32DTypep->width()};
        } else if (vtxp != c.graph.m_startVertexp && !vtxp->datap()->stateVarp
                   && !vtxp->datap()->delayRingVarp && !vtxp->m_isMatch && !vtxp->m_isRejectSink) {
            // OR of the active sources of the incoming Links, each gated by its Link
            // condition, together with the summed thread count
            AstNodeExpr* nextStatep = nullptr;
            AstNodeExpr* nextStateCountp = nullptr;
            AstNodeExpr* nextStateCountOverflowp = nullptr;
            for (const V3GraphEdge& er : vtxp->inEdges()) {
                ++m_statLinkEdgeVisits;
                const SvaTransEdge& te = static_cast<const SvaTransEdge&>(er);
                SvaStateVertex* const fromVtxp = te.fromVtxp();
                resolveLinkState(c, fromVtxp, visits, countMatches);
                UASSERT_OBJ(fromVtxp->datap()->stateSigp && fromVtxp->datap()->stateCountSigp,
                            fromVtxp, "Link source missing state signal");
                AstNodeExpr* const contributionp = andCond(
                    c.flp, fromVtxp->datap()->stateSigp->cloneTreePure(false), te.m_condp);
                nextStatep = orExprs(c.flp, nextStatep, contributionp);
                AstNodeExpr* countContributionp
                    = fromVtxp->datap()->stateCountSigp->cloneTreePure(false);
                AstNodeExpr* countContributionOverflowp
                    = countMatches && fromVtxp->datap()->stateCountOverflowSigp
                          ? fromVtxp->datap()->stateCountOverflowSigp->cloneTreePure(false)
                          : nullptr;
                if (te.m_condp) {
                    AstNodeExpr* const enablep = te.m_condp->cloneTreePure(false);
                    countContributionp = gateCheckedCountp(c.flp, countContributionp,
                                                           countContributionOverflowp, enablep);
                }
                nextStateCountp
                    = countMatches
                          ? addCheckedCountp(c.flp, nextStateCountp, countContributionp,
                                             nextStateCountOverflowp, countContributionOverflowp)
                          : addCountp(c.flp, nextStateCountp, countContributionp);
            }
            vtxp->datap()->stateSigp = nextStatep;
            vtxp->datap()->stateCountSigp = nextStateCountp;
            vtxp->datap()->stateCountOverflowSigp = nextStateCountOverflowp;
        }
        visit = LinkVisit::RESOLVED;
    }

    // Phase 1: Resolve combinational Links in dependency order.
    void resolveLinks(LowerCtx& c, AstNodeExpr* triggerExprp, const bool countMatches) {
        // datap() was freshly allocated in lower() -- all state signals start null.
        c.graph.m_startVertexp->datap()->stateSigp = triggerExprp->cloneTreePure(false);
        c.graph.m_startVertexp->datap()->stateCountSigp
            = new AstExtend{c.flp, triggerExprp->cloneTreePure(false), m_u32DTypep->width()};
        for (V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            SvaStateVertex* const vtxp = static_cast<SvaStateVertex*>(&vtxr);
            if (vtxp->datap()->stateVarp && vtxp->datap()->stateCounts) {
                vtxp->datap()->stateCountSigp
                    = new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::READ};
                vtxp->datap()->stateSigp
                    = new AstNeq{c.flp, vtxp->datap()->stateCountSigp->cloneTreePure(false),
                                 newTypedConstp(c.flp, m_u32DTypep, 0)};
            } else if (vtxp->datap()->stateVarp) {
                vtxp->datap()->stateSigp
                    = new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::READ};
                vtxp->datap()->stateCountSigp = new AstExtend{
                    c.flp, new AstVarRef{c.flp, vtxp->datap()->stateVarp, VAccess::READ},
                    m_u32DTypep->width()};
            } else if (vtxp->datap()->delayRingVarp) {
                if (vtxp->m_isFixedDelayRing) {
                    // state_count = wrapped ? head : 0; state = state_count != 0;
                    AstNodeExpr* const countp = delayRingOutputCount(c.flp, vtxp);
                    vtxp->datap()->stateSigp = new AstNeq{c.flp, countp->cloneTreePure(false),
                                                          newTypedConstp(c.flp, m_u32DTypep, 0)};
                    vtxp->datap()->stateCountSigp = countp;
                } else {
                    vtxp->datap()->stateSigp
                        = delayRingHasLiveThreadsp(c.flp, vtxp->datap()->delayRingLiveCountVarp);
                    vtxp->datap()->stateCountSigp = new AstVarRef{
                        c.flp, vtxp->datap()->delayRingLiveCountVarp, VAccess::READ};
                }
            }
        }
        // Indexed by the vertex colors numbered in lower()
        std::vector<LinkVisit> visits(c.graph.m_graph.vertices().size(), LinkVisit::UNVISITED);
        for (V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            resolveLinkState(c, static_cast<SvaStateVertex*>(&vtxr), visits, countMatches);
        }
    }

public:
    // Combine terminal/reject signals into final output expression.
    static AstNodeExpr* assembleResult(AstNodeCoverOrAssert* const assertp, const bool negated,
                                       AstNodeExpr* const matchCondp, const SignalSet& sigs,
                                       AstNodeExpr** const outMatchpp) {
        FileLine* const flp = assertp->fileline();
        const bool isCover = VN_IS(assertp, Cover);
        AstNodeExpr* const terminalActivep = sigs.terminalActivep;
        AstNodeExpr* const rejectBasep = sigs.rejectBasep;
        AstNodeExpr* const throughoutRejectp = sigs.throughoutRejectp;
        AstNodeExpr* const requiredStepRejectp = sigs.requiredStepRejectp;
        // Property negation (IEEE 1800-2023 16.12.1 `not`): invert match/reject.
        if (negated) {
            if (isCover) {
                if (terminalActivep)
                    VL_DO_DANGLING(terminalActivep->deleteTree(), terminalActivep);
                AstNodeExpr* negRejectp = nullptr;
                if (matchCondp && rejectBasep) {
                    AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
                    AstNodeExpr* const notCondp = new AstLogNot{flp, sampledCondp};
                    negRejectp = new AstLogAnd{flp, rejectBasep, notCondp};
                } else if (rejectBasep) {
                    VL_DO_DANGLING(rejectBasep->deleteTree(), rejectBasep);
                }
                if (throughoutRejectp) negRejectp = orExprs(flp, negRejectp, throughoutRejectp);
                if (requiredStepRejectp)
                    negRejectp = orExprs(flp, negRejectp, requiredStepRejectp);
                return negRejectp ? negRejectp : new AstConst{flp, AstConst::BitFalse{}};
            }
            // Negated assert/assume: output = !match, where a vacuous success is a match.
            AstNodeExpr* matchp = terminalActivep;
            if (matchCondp) {
                AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
                matchp = new AstLogAnd{flp, matchp, sampledCondp};
            }
            if (sigs.vacuousp) matchp = new AstLogOr{flp, matchp, sigs.vacuousp};
            if (outMatchpp) {
                AstNodeExpr* notPMatchp = nullptr;
                if (matchCondp && rejectBasep) {
                    AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
                    notPMatchp = new AstLogAnd{flp, rejectBasep->cloneTreePure(false),
                                               new AstLogNot{flp, sampledCondp}};
                } else if (rejectBasep) {
                    notPMatchp = rejectBasep->cloneTreePure(false);
                }
                if (throughoutRejectp)
                    notPMatchp = orExprs(flp, notPMatchp, throughoutRejectp->cloneTreePure(false));
                if (requiredStepRejectp)
                    notPMatchp
                        = orExprs(flp, notPMatchp, requiredStepRejectp->cloneTreePure(false));
                *outMatchpp = notPMatchp;
            }
            if (throughoutRejectp)
                VL_DO_DANGLING(throughoutRejectp->deleteTree(), throughoutRejectp);
            if (rejectBasep) VL_DO_DANGLING(rejectBasep->deleteTree(), rejectBasep);
            if (requiredStepRejectp)
                VL_DO_DANGLING(requiredStepRejectp->deleteTree(), requiredStepRejectp);
            AstNodeExpr* const resultExprp = new AstLogNot{flp, matchp};
            return resultExprp;
        }
        if (isCover) {
            if (throughoutRejectp)
                VL_DO_DANGLING(throughoutRejectp->deleteTree(), throughoutRejectp);
            if (rejectBasep) VL_DO_DANGLING(rejectBasep->deleteTree(), rejectBasep);
            if (requiredStepRejectp)
                VL_DO_DANGLING(requiredStepRejectp->deleteTree(), requiredStepRejectp);
            if (matchCondp) {
                AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
                return new AstLogAnd{flp, terminalActivep, sampledCondp};
            }
            return terminalActivep;
        }
        // Assert/assume: output = !reject
        AstNodeExpr* rejectp = nullptr;
        if (matchCondp && rejectBasep) {
            AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
            rejectp = new AstLogAnd{flp, rejectBasep, new AstLogNot{flp, sampledCondp}};
        } else if (rejectBasep) {
            VL_DO_DANGLING(rejectBasep->deleteTree(), rejectBasep);
        }
        if (outMatchpp) {
            AstNodeExpr* matchExprp = terminalActivep->cloneTreePure(false);
            if (matchCondp) {
                AstNodeExpr* const sp = sampled(matchCondp->cloneTreePure(false));
                matchExprp = new AstLogAnd{flp, matchExprp, sp};
            }
            *outMatchpp = matchExprp;
        }
        if (terminalActivep) VL_DO_DANGLING(terminalActivep->deleteTree(), terminalActivep);
        if (throughoutRejectp) rejectp = orExprs(flp, rejectp, throughoutRejectp);
        if (requiredStepRejectp) rejectp = orExprs(flp, rejectp, requiredStepRejectp);
        if (!rejectp) return new AstConst{flp, AstConst::BitTrue{}};
        AstNodeExpr* const resultExprp = new AstLogNot{flp, rejectp};
        return resultExprp;
    }

    SvaNfaLowering(AstNodeModule* modp, V3UniqueNames& actionNames)
        : m_modp{modp}
        , m_u32DTypep{modp->findBasicDType(VBasicDTypeKwd::UINT32)}
        , m_actionNames{actionNames} {}
    ~SvaNfaLowering() {
        V3Stats::addStatSum("Assertions, NFA delay ring edge visits", m_statDelayRingEdgeVisits);
        V3Stats::addStatSum("Assertions, NFA link edge visits", m_statLinkEdgeVisits);
    }

    // Return the statements run by an assertion failing at end of simulation
    AstNodeStmt* newFinalFailp(AstNodeCoverOrAssert* assertp) {
        FileLine* const flp = assertp->fileline();
        // The fail action replaces the default error (IEEE 1800-2023 16.14.1), unless it has a
        // timing control, which could not resume in a final block (IEEE 1800-2023 9.2.3)
        AstNodeStmt* const failsp = VN_AS(assertp, Assert)->failsp();
        const bool hasTimingControl = failsp && failsp->existsAndNext([](const AstNode* np) {
            return np->isTimingControl();
        });
        AstNodeStmt* stmtsp;
        if (failsp && !hasTimingControl) {
            stmtsp = V3AssertCommon::cloneAction(failsp, m_actionNames);
            // An NBA, legal in an action block, executes as a blocking assignment in a final
            // block, so FINALDLY does not apply
            stmtsp->foreachAndNext([](AstAssignDly* const dlyp) {
                FileLine* const newfl = new FileLine{dlyp->fileline()};
                newfl->warnOff(V3ErrorCode::FINALDLY, true);
                dlyp->fileline(newfl);
            });
        } else {
            // V3Assert turns the DT_ERROR display into the standard "Assertion failed in %m"
            AstDisplay* const dispp
                = new AstDisplay{flp, VDisplayType::DT_ERROR, "", nullptr, nullptr};
            dispp->fmtp()->timeunit(m_modp->timeunit());
            stmtsp = dispp;
            if (v3Global.opt.stopFail()) stmtsp->addNext(new AstStop{flp, false});
        }
        // Like a failure during simulation, subject to $assertcontrol FailOff
        return newIfAssertFailOn(stmtsp, assertp->directive(), assertp->userType());
    }

    // Lower NFA graph to synthesizable AstAlways blocks and raw result signals.
    // Links are combinational; Edges are registered (NBA).
    SignalSet lower(AstNodeCoverOrAssert* const assertp, SvaGraph& graph,
                    AstSenTree* const senTreep, AstNodeExpr* const matchCondp,
                    AstNodeExpr* const disableExprp, const bool needThreadFailCount,
                    const bool needRejectCount, const bool needSuccessCount,
                    const bool exactCounts, const AstAbortOn* const exactAbortp,
                    const bool countAttempts) {
        FileLine* const flp = assertp->fileline();
        AstCover* const coverp = VN_CAST(assertp, Cover);
        const bool isSeqEvent = coverp && coverp->isSeqEvent();
        const VAssertType assertType
            = isSeqEvent ? VAssertType{VAssertType::INTERNAL} : assertp->userType();
        const VAssertDirectiveType directiveType
            = isSeqEvent ? VAssertDirectiveType{VAssertDirectiveType::INTERNAL}
                         : assertp->directive();
        const std::string baseName = m_names.get("");

        // Number vertices with sequential colors for array indexing.
        int N = 0;
        for (V3GraphVertex& vtxr : graph.m_graph.vertices()) { vtxr.color(N++); }
        std::vector<SvaStateVertex*> vtx(N, nullptr);
        for (V3GraphVertex& vtxr : graph.m_graph.vertices()) {
            vtx[vtxr.color()] = static_cast<SvaStateVertex*>(&vtxr);
        }

        // Allocate per-vertex lowering data (stored via V3GraphVertex::userp()).
        std::vector<SvaVertexData> vertexData(N);
        for (int i = 0; i < N; ++i) vtx[i]->userp(&vertexData[i]);

        // Identify registered vertices (targets of clocked edges).
        for (int i = 0; i < N; ++i) {
            for (const V3GraphEdge& edger : vtx[i]->outEdges()) {
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                const int toIdx = tedger.toVtxp()->color();
                if (tedger.m_consumesCycle && tedger.toVtxp() != graph.m_matchVertexp
                    && !tedger.toVtxp()->m_isRejectSink) {
                    vtx[toIdx]->datap()->needsReg = true;
                }
            }
        }

        // A packed range ring can emit several live endpoints without needing per-slot counts.
        // Widen only a ring whose input can already carry multiplicity.
        std::vector<bool> ringNeedsMultiplicity(N);
        const bool countMatches = countsMatches(assertp);
        if (countMatches) {
            std::vector<bool> stateMayHaveMultiplicity(N);
            std::vector<int> multiplicityWork;
            for (int i = 0; i < N; ++i) {
                const bool multipleInputs = vtx[i]->inEdges().size() > 1;
                const bool isRing = vtx[i]->m_delayRingSize;
                ringNeedsMultiplicity[i] = isRing && multipleInputs;
                const bool startsMultiplicity = isRing
                                                    ? !vtx[i]->m_isFixedDelayRing
                                                    : multipleInputs && !vtx[i]->datap()->needsReg;
                if (startsMultiplicity) {
                    stateMayHaveMultiplicity[i] = true;
                    multiplicityWork.push_back(i);
                }
            }
            for (size_t wi = 0; wi < multiplicityWork.size(); ++wi) {
                for (const V3GraphEdge& edger : vtx[multiplicityWork[wi]]->outEdges()) {
                    const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                    const int ti = tedger.toVtxp()->color();
                    const bool isRing = vtx[ti]->m_delayRingSize;
                    if (isRing) ringNeedsMultiplicity[ti] = true;
                    // Match and reject sinks have no outgoing edges, so they stop naturally.
                    const bool stopsMultiplicity = !isRing && vtx[ti]->datap()->needsReg;
                    if (stateMayHaveMultiplicity[ti] || stopsMultiplicity) { continue; }
                    stateMayHaveMultiplicity[ti] = true;
                    multiplicityWork.push_back(ti);
                }
            }
        }

        const bool asyncDisable = isAsyncDisable(disableExprp);
        // Registers cleared on a rising disable are also written by their clocked block.
        FileLine* const regFlp = asyncDisable ? new FileLine{flp} : flp;
        if (asyncDisable) regFlp->warnOff(V3ErrorCode::MULTIDRIVEN, true);

        AstVar* const killVarp
            = new AstVar{flp, VVarType::MODULETEMP, baseName + "__kill", m_u32DTypep};
        killVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        m_modp->addStmtsp(killVarp);
        for (int i = 0; i < N; ++i) {
            if (vtx[i]->m_isAndCombiner) {
                const std::string base = baseName + "__a" + std::to_string(i);
                AstVar* const lp = new AstVar{regFlp, VVarType::MODULETEMP, base + "_doneL",
                                              m_modp->findBitDType()};
                lp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(lp);
                vtx[i]->datap()->doneLVarp = lp;
                AstVar* const rp = new AstVar{regFlp, VVarType::MODULETEMP, base + "_doneR",
                                              m_modp->findBitDType()};
                rp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(rp);
                vtx[i]->datap()->doneRVarp = rp;
                continue;
            }
            if (vtx[i]->m_delayRingSize) {
                const std::string base = baseName + "__d" + std::to_string(i);
                const bool storesCounts
                    = (countMatches && ringNeedsMultiplicity[i]) || exactCounts;
                AstNodeDType* ringDTypep = nullptr;
                if (storesCounts) {
                    // int unsigned ring [size];
                    ringDTypep = new AstUnpackArrayDType{
                        flp, m_u32DTypep,
                        new AstRange{flp, static_cast<int>(vtx[i]->m_delayRingSize - 1), 0}};
                    v3Global.rootp()->typeTablep()->addTypesp(ringDTypep);
                } else {
                    // bit [size-1:0] ring;
                    ringDTypep = m_modp->findBitDType(vtx[i]->m_delayRingSize,
                                                      vtx[i]->m_delayRingSize, VSigning::UNSIGNED);
                }
                AstVar* const ringp
                    = new AstVar{flp, VVarType::MODULETEMP, base + "_ring", ringDTypep};
                ringp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(ringp);
                vtx[i]->datap()->delayRingVarp = ringp;
                vtx[i]->datap()->delayRingCounts = storesCounts;
                AstVar* const headp
                    = new AstVar{flp, VVarType::MODULETEMP, base + "_head",
                                 storesCounts ? m_u32DTypep : m_modp->findBitDType()};
                headp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(headp);
                vtx[i]->datap()->delayRingHeadVarp = headp;
                // int unsigned idx;
                AstVar* const idxp
                    = new AstVar{regFlp, VVarType::MODULETEMP, base + "_idx", m_u32DTypep};
                idxp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(idxp);
                vtx[i]->datap()->delayRingIdxVarp = idxp;
                // int unsigned live_count;
                AstVar* const liveCountVarp
                    = new AstVar{regFlp, VVarType::MODULETEMP, base + "_liveCount", m_u32DTypep};
                liveCountVarp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(liveCountVarp);
                vtx[i]->datap()->delayRingLiveCountVarp = liveCountVarp;
                AstVar* const wrappedp = new AstVar{regFlp, VVarType::MODULETEMP,
                                                    base + "_wrapped", m_modp->findBitDType()};
                wrappedp->lifetime(VLifetime::STATIC_EXPLICIT);
                m_modp->addStmtsp(wrappedp);
                vtx[i]->datap()->delayRingWrappedVarp = wrappedp;
                continue;
            }
            if (!vtx[i]->datap()->needsReg) continue;
            if (vtx[i] == graph.m_startVertexp || vtx[i]->m_isMatch) continue;
            const std::string varName = baseName + "__s" + std::to_string(i);
            AstVar* const varp = new AstVar{regFlp, VVarType::MODULETEMP, varName,
                                            exactCounts ? m_u32DTypep : m_modp->findBitDType()};
            vtx[i]->datap()->stateCounts = exactCounts;
            varp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(varp);
            vtx[i]->datap()->stateVarp = varp;
        }

        // Build lowering context for phase sub-functions.
        LowerCtx c{flp,           senTreep, disableExprp, matchCondp,  assertType,
                   directiveType, killVarp, graph,        exactCounts, exactAbortp};

        // Phase 1: Resolve combinational Links.
        AstNodeExpr* const triggerExprp
            = isSeqEvent ? new AstConst{flp, AstConst::BitTrue{}}
                         : assertOnCond(flp, assertp->userType(), assertp->directive());
        resolveLinks(c, triggerExprp, countMatches);
        VL_DO_DANGLING(triggerExprp->deleteTree(), triggerExprp);

        // Phase 2/2b/2c: Emit NBA register updates and in-place delay-ring writes.
        emitStateRegisterNba(c);
        emitDelayRingUpdates(c, countMatches);
        emitAndCombinerDoneLatchNba(c);
        emitKillAckNba(c);

        // Phase 3/3a/3b: Compute terminal match/reject signals (cleans up stateSig).
        const SignalSet sigs = computeSignals(c, needThreadFailCount, needRejectCount,
                                              needSuccessCount, countMatches, countAttempts);

        // Strong s_always[m:n] end-of-simulation liveness: if any state of an attempt
        // is still set at $finish, the universal-quantifier window never completed
        // (IEEE 1800-2023 16.12.11 strong semantics). Fire the assertion failure
        // from a final block.
        // pending = |{strong state registers, strong delay live counts != 0};
        AstNodeExpr* pendingp = nullptr;
        for (int i = 0; i < N; ++i) {
            if (!vtx[i]->m_strongPending) continue;
            AstNodeExpr* pendingExprp = nullptr;
            if (vtx[i]->datap()->stateVarp) {
                pendingExprp = new AstVarRef{flp, vtx[i]->datap()->stateVarp, VAccess::READ};
            } else if (vtx[i]->m_delayRingSize) {
                pendingExprp
                    = delayRingHasLiveThreadsp(flp, vtx[i]->datap()->delayRingLiveCountVarp);
            } else {
                continue;
            }
            if (!pendingp) {
                pendingp = pendingExprp;
            } else {
                pendingp = new AstLogOr{flp, pendingp, pendingExprp};
            }
        }
        if (pendingp) {
            AstCExpr* const assertOnp
                = new AstCExpr{flp, AstCExpr::Pure{}, "vlSymsp->_vm_contextp__->assertOn()", 1};
            AstNodeExpr* const condp = new AstLogAnd{flp, assertOnp, pendingp};
            m_modp->addStmtsp(new AstFinal{flp, new AstIf{flp, condp, newFinalFailp(assertp)}});
        }

        // Clear userp on every vertex before vertexData is destroyed.
        for (int i = 0; i < N; ++i) vtx[i]->userp(nullptr);
        return sigs;
    }
};

//######################################################################
// Subtree sizes

// Number the nodes of a property in walk order, the operands of each parallel operator in order,
// and count the nodes of each subtree, so the smaller operand of a parallel operator can be walked
// first
class AssertNfaSizeVisitor final : public VNVisitorConst {
public:
    struct Size final {
        size_t ordinal;  // Number of the node in walk order
        size_t count;  // Nodes in its subtree
    };

private:
    std::unordered_map<const AstNode*, Size>& m_sizes;  // Of each node
    size_t& m_countr;  // Nodes numbered so far
    void setSize(const AstNode* const nodep, const size_t ordinal) {
        const bool inserted = m_sizes.emplace(nodep, Size{ordinal, m_countr - ordinal}).second;
        UASSERT_OBJ(inserted, nodep, "Node numbered twice");
    }
    // A match item is walked with its subsequence before its statements, the order in which an
    // unassigned read in an assigned value is reported
    void visit(AstExprStmt* nodep) override {
        const size_t ordinal = m_countr++;
        iterateAndNextConstNull(nodep->resultp());
        iterateAndNextConstNull(nodep->stmtsp());
        setSize(nodep, ordinal);
    }
    void visit(AstNode* nodep) override {
        const size_t ordinal = m_countr++;
        iterateChildrenConst(nodep);
        setSize(nodep, ordinal);
    }

public:
    AssertNfaSizeVisitor(AstNode* const nodep, std::unordered_map<const AstNode*, Size>& sizes,
                         size_t& countr)
        : m_sizes{sizes}
        , m_countr{countr} {
        iterateConst(nodep);
    }
};

//######################################################################
// Match item lowering

// Lower the local variable assignments of match items (IEEE 1800-2023 16.10) before NFA
// construction, as the NFA keeps no per-attempt storage. The property is walked forward in
// time, keeping the latest value assigned to each local variable and the cycle it was assigned
// in. Assignments of one match item take effect in list order at the end of its subsequence, so
// a reassignment applies from there on. Each value read is computed every cycle into a module
// temp, its own reads lowered the same way, and a read becomes $past of the temp delayed to the
// cycle of the read; the assignment is removed. A value is so evaluated every cycle, so an
// impure value is reported as unsupported. A random function call in a value is drawn by $past
// of its own call, with a history of its own, so the temp has an input changing every cycle, and
// each assignment draws its own value.
// A value is only tracked along a single thread of fixed cycle delays, so its read is a
// constant number of cycles after its assignment. Each operand of a composite sequence
// operator is walked as a thread of its own, in an operand walk of its own: an operand of 'and',
// 'intersect' or 'or' starts with the variables assigned before the operator, and the
// variables flowing out of the operator follow IEEE 1800-2023 16.10. A thread is summarized by
// its effect on each variable it assigns: the variable's state at its end, met with the state
// at its entry for a variable flowing out of only one operand of 'or'. The summary of an
// operand of a sequential operator is concatenated to the summary of its thread before it; the
// smaller operand of a parallel operator is walked first, its changes undone after it, and its
// summary merged into the other's, a variable only the other assigns being met with its
// incoming state after 'or' by a single epoch. A concatenation iterates the summary with fewer
// effects, and a parallel merge the summary of the operand with fewer nodes. Either way a
// summary receiving an effect holds all effects of the one it came from, and covers at least
// twice the nodes or holds at least twice the effects, so an effect moves a logarithmic number
// of times. A read of a value live at a range delay or at a composite operator, and a read of a
// variable an operand of a composite operator assigned, are reported as unsupported; a read with
// no assignment before it on its thread is an error. Only the instance copies of declared local
// variables are tracked, so an assignment to any other variable, e.g. a temporary made by
// V3Width, stays in place.
class AssertNfaMatchItemVisitor final : public VNVisitor {
    // TYPES
    struct Value final {
        AstNodeExpr* exprp;  // Assigned value, its reads already lowered
        AstVar* tempp;  // Temp computing the value every cycle, made at the first read
        uint32_t cycle;  // Cycle of the walk it was assigned in
        bool inAntecedent;  // Assigned in the antecedent of an implication
        size_t ordinal;  // Number of its assignment in walk order
    };
    struct Untimed final {
        AstNode* nodep;  // Range delay or composite operator the value was live at
        const char* whatp;  // What nodep is
        bool fromAntecedent;  // A value assigned in the antecedent was live at nodep
    };
    // The state of a variable at a point of a thread whose value is not tracked
    struct State final {
        enum Kind : uint8_t {
            UNASSIGNED,  // Not assigned, or blocked
            UNTIMED,  // Its value was live at an untimed node in operand walk 'operand'
            UNTRACKED  // Assigned in an operand of a composite operator
        };
        Kind kind;
        uint32_t operand;  // If UNTIMED, the operand walk its value became untimed in
        Untimed untimed;  // If UNTIMED, the untimed node
    };
    // The effect of a subtree on a variable: its state at the end of the subtree is 'value', met
    // with its state at the entry of the subtree if 'meetIn' (IEEE 1800-2023 16.10 'or')
    struct Effect final {
        bool meetIn;  // 'value' is met with the incoming state
        State value;  // State at the end, or met with the incoming state
        State in;  // State at the entry of the subtree
        uint64_t epoch;  // When set; it is 'meetIn' if before its summary's 'meetInEpoch'
    };
    // The effects of a subtree on the variables it assigns
    struct Summary final {
        std::unordered_map<const AstVar*, Effect> effects;  // Of each variable it assigns
        uint64_t meetInEpoch = 0;  // Effects set before are met with the incoming state
    };
    // The summary holding a variable's effect, before a change undone after its operand
    struct Change final {
        const AstVar* varp;  // Variable changed
        Summary* summaryp;  // Summary holding its effect before, nullptr if none
    };
    // A temp computing a value every cycle
    struct Temp final {
        AstVar* varp;  // The temp, named after the walk
        AstNodeExpr* exprp;  // Value it computes
        AstAlways* alwaysp;  // Block computing it
    };

    // STATE
    AstNodeModule* const m_modp;  // Module to receive the value temps
    V3UniqueNames& m_tempNames;  // Value temp names
    std::unordered_map<const AstVar*, Value> m_values;  // Live value of each assigned variable
    // Summary holding each variable's effect at this point, if any: its state not in m_values.
    // An effect is looked up by its variable in the summary, which is never deleted during the
    // walk, so neither this nor a saved change ever refers to a deleted summary.
    std::unordered_map<const AstVar*, Summary*> m_summaryps;
    std::vector<Change> m_changes;  // Changes of m_summaryps to undo after their operands
    std::unique_ptr<Summary> m_summaryp{new Summary};  // Summary of the thread walked
    std::vector<std::unique_ptr<Summary>> m_mergedSummaryps;  // Merged into another, now empty
    uint64_t m_epoch = 0;  // Last effect epoch
    std::vector<bool> m_operandWalking{true};  // Whether each operand walk is still walking
    std::unordered_map<const AstNode*, AssertNfaSizeVisitor::Size> m_sizes;  // Of each node
    // Value temps, by the walk order of their assignments, added to the module after the walk,
    // as the operands of a parallel operator may be walked out of order
    std::map<size_t, Temp> m_temps;
    std::map<size_t, AstNodeExpr*> m_valueps;  // Removed values, by walk order
    std::vector<AstAlways*> m_alwaysps;  // Blocks computing the value temps
    // Match items left without statements, replaced by their subsequence after the walk, as
    // a replacement during the walk would be iterated again
    std::vector<AstExprStmt*> m_emptyItemps;
    std::vector<AstRand*>* m_randpsp = nullptr;  // Random function calls of the value walked
    uint32_t m_cycle = 0;  // Current cycle of the walk, only ever increasing
    uint32_t m_operand = 0;  // Operand walk walking: an operand of a composite operator
    uint32_t m_undoDepth = 0;  // Number of operands walked whose changes are undone
    bool m_operandStart = false;  // Next node visited is an operand of a composite operator
    bool m_inConsequent = false;  // In the consequent of an implication
    bool m_inOperand = false;  // In an operand of a non-sequential operator
    bool m_failed = false;  // An error was found
    const AstNode* m_unsupportedp = nullptr;  // First unsupported construct found, reported after
    std::string m_unsupportedMsg;  // Its message
    size_t m_statValues = 0;  // Values lowered
    size_t m_statReads = 0;  // Reads of values lowered
    size_t m_statTemps = 0;  // Value temps made
    size_t m_statWork = 0;  // Nodes visited and references inspected
    size_t m_statFlow = 0;  // Nodes numbered, and effects looked up, set, merged and undone

    // METHODS
    // The live values reach a node from which their cycle is unknown; a later read is reported
    void untimeValues(AstNode* const nodep, const char* const whatp) {
        bool fromAntecedent = false;
        for (const auto& itr : m_values) fromAntecedent |= itr.second.inAntecedent;
        for (const auto& itr : m_values) {
            setState(itr.first,
                     State{State::UNTIMED, m_operand, Untimed{nodep, whatp, fromAntecedent}});
        }
        m_values.clear();
    }
    // The state of a variable, with an untimed value of an operand walk ended untracked
    State normalized(const State& stater) const {
        if (stater.kind != State::UNTIMED || m_operandWalking[stater.operand]) return stater;
        return State{State::UNTRACKED, 0, Untimed{}};
    }
    // The state of a variable assigned on either of two threads (IEEE 1800-2023 16.10 'or')
    static State meet(const State& ar, const State& br) {
        if (ar.kind == State::UNASSIGNED) return ar;
        if (br.kind == State::UNASSIGNED) return br;
        return State{State::UNTRACKED, 0, Untimed{}};
    }
    // An effect as set, or met with the incoming state if set before its summary's meetInEpoch
    static Effect effectOf(const Summary& summaryr, const Effect& effectr) {
        Effect effect = effectr;
        effect.meetIn |= effect.epoch < summaryr.meetInEpoch;
        if (effect.value.kind == State::UNASSIGNED) effect.meetIn = false;
        return effect;
    }
    // The state of a variable at this point, its value not in m_values
    State stateOf(const AstVar* const varp) {
        ++m_statFlow;
        const auto it = m_summaryps.find(varp);
        if (it == m_summaryps.end()) return State{State::UNASSIGNED, 0, Untimed{}};
        const Summary& summaryr = *it->second;
        const auto effectIt = summaryr.effects.find(varp);
        UASSERT_OBJ(effectIt != summaryr.effects.end(), varp,
                    "Summary not holding the variable's effect");
        const Effect effect = effectOf(summaryr, effectIt->second);
        return effect.meetIn ? meet(effect.value, effect.in) : effect.value;
    }
    // Hold a variable's effect in a summary, saving the change to undo if needed
    void setSummary(const AstVar* const varp, Summary* const summaryp) {
        ++m_statFlow;
        Summary*& summarypr = m_summaryps[varp];
        if (summarypr == summaryp) return;
        if (m_undoDepth) m_changes.push_back(Change{varp, summarypr});
        summarypr = summaryp;
    }
    // Undo the changes saved since the mark
    void undoChanges(const size_t mark) {
        for (size_t i = m_changes.size(); i > mark; --i) {
            ++m_statFlow;
            const Change& changer = m_changes[i - 1];
            if (changer.summaryp) {
                m_summaryps[changer.varp] = changer.summaryp;
            } else {
                m_summaryps.erase(changer.varp);
            }
        }
        // The first change of each variable restored a summary from before the mark, still
        // holding its effect
        for (size_t i = mark; i < m_changes.size(); ++i) {
            const Change& changer = m_changes[i];
            const auto it = m_summaryps.find(changer.varp);
            UASSERT_OBJ(it == m_summaryps.end() || it->second->effects.count(changer.varp),
                        changer.varp, "Restored summary not holding the variable's effect");
        }
        m_changes.resize(mark);
    }
    // Keep a summary merged into another, its effects freed, so it is not deleted while a change
    // may refer to it
    void retire(std::unique_ptr<Summary>& summaryp) {
        std::unordered_map<const AstVar*, Effect>{}.swap(summaryp->effects);
        m_mergedSummaryps.push_back(std::move(summaryp));
    }
    // Set the state of a variable at this point of the thread walked
    void setState(const AstVar* const varp, const State& stater) {
        ++m_statFlow;
        const auto pair = m_summaryp->effects.emplace(varp, Effect{false, stater, {}, ++m_epoch});
        if (!pair.second) {
            pair.first->second = Effect{false, stater, pair.first->second.in, m_epoch};
            return;
        }
        // Inserted, so the current summary did not hold varp, and stateOf reads its prior owner
        pair.first->second.in = stateOf(varp);
        setSummary(varp, m_summaryp.get());
    }
    // Make an effect held by a summary a new one
    void renewEffect(Summary& summaryr, const AstVar* const varp, Effect& effectr) {
        ++m_statFlow;
        effectr.epoch = ++m_epoch;
        if (effectr.value.kind == State::UNASSIGNED) effectr.meetIn = false;
        setSummary(varp, &summaryr);
    }
    // The effect of 'first' then 'then'
    Effect compose(const Effect& first, const Effect& then) const {
        if (!then.meetIn) return Effect{false, then.value, first.in, 0};
        return Effect{first.meetIn, meet(then.value, first.value), first.in, 0};
    }
    // Concatenate the summary of a subtree to the summary 'firstr' of the subtree before it,
    // iterating the smaller one. Keys in both are composed, the others are relative to the
    // entry of the concatenation already.
    void concatenate(std::unique_ptr<Summary>& firstr, std::unique_ptr<Summary>& thenr) {
        if (firstr->effects.size() >= thenr->effects.size()) {
            for (const auto& itr : thenr->effects) {
                ++m_statFlow;
                const Effect then = effectOf(*thenr, itr.second);
                const auto pair = firstr->effects.emplace(itr.first, then);
                if (!pair.second) {
                    pair.first->second = compose(effectOf(*firstr, pair.first->second), then);
                }
                renewEffect(*firstr, itr.first, pair.first->second);
            }
        } else {
            for (const auto& itr : firstr->effects) {
                ++m_statFlow;
                const Effect first = effectOf(*firstr, itr.second);
                const auto pair = thenr->effects.emplace(itr.first, first);
                if (!pair.second) {
                    pair.first->second = compose(first, effectOf(*thenr, pair.first->second));
                }
                renewEffect(*thenr, itr.first, pair.first->second);
            }
            firstr.swap(thenr);
        }
        retire(thenr);
    }
    const AssertNfaSizeVisitor::Size& sizeOf(const AstNode* const nodep) const {
        const auto it = m_sizes.find(nodep);
        UASSERT_OBJ(it != m_sizes.end(), nodep, "Node not numbered before the walk");
        return it->second;
    }
    // Note an unsupported construct, stopping the walk. Only the first in walk order is
    // reported, after the walk, as the operands of a parallel operator may be walked out of order.
    void unsupported(const AstNode* const nodep, const std::string& msg) {
        UASSERT_OBJ(!m_unsupportedp, nodep, "Unsupported construct after the walk stopped");
        m_failed = true;
        m_unsupportedp = nodep;
        m_unsupportedMsg = msg;
    }
    void unsupportedUntimed(const Untimed& untimedr) {
        if (m_inConsequent && untimedr.fromAntecedent) {
            unsupported(untimedr.nodep, "Unsupported: property local variable used across "s
                                            + untimedr.whatp
                                            + " in consequent (IEEE 1800-2023 16.10)");
        } else {
            unsupported(untimedr.nodep, "Unsupported: local variable used across "s
                                            + untimedr.whatp
                                            + " in sequence (IEEE 1800-2023 16.10)");
        }
    }
    // A read of a variable assigned in an operand of a composite sequence operator
    void unsupportedUntrackedRead(AstNode* const nodep) {
        unsupported(nodep, "Unsupported: local variable referenced after an operand"
                           " of a composite sequence operator assigned it"
                           " (IEEE 1800-2023 16.10).");
    }
    // The local variable assigned by a match item statement, if any
    static const AstVarRef* assignedLocalp(const AstNode* const itemp) {
        const AstAssign* const assignp = VN_CAST(itemp, Assign);
        const AstVarRef* const lhsp = assignp ? VN_CAST(assignp->lhsp(), VarRef) : nullptr;
        return lhsp && lhsp->varp()->isAssertLocal() ? lhsp : nullptr;
    }
    // Walk an operand of a composite operator as a thread of its own, from the state before it,
    // returning its summary. If 'undo', the variables' states are as before it after it.
    std::unique_ptr<Summary> iterateOperand(AstNode* const nodep, const bool undo) {
        UASSERT_OBJ(!nodep->nextp(), nodep, "Operand of a composite operator is not a list");
        UASSERT_OBJ(m_values.empty(), nodep, "Values not untimed before a composite operator");
        VL_RESTORER(m_inOperand);
        VL_RESTORER(m_operandStart);
        VL_RESTORER(m_operand);
        VL_RESTORER(m_undoDepth);
        std::unique_ptr<Summary> summaryp{new Summary};
        m_summaryp.swap(summaryp);  // Now the outer thread's summary
        m_inOperand = false;
        m_operandStart = false;
        m_operand = m_operandWalking.size();
        m_operandWalking.push_back(true);
        const size_t mark = m_changes.size();
        if (undo) ++m_undoDepth;
        iterateAndNextNull(nodep);
        // A value assigned in the operand is not tracked after it
        if (!m_failed) {
            for (const auto& itr : m_values) {
                setState(itr.first, State{State::UNTRACKED, 0, Untimed{}});
            }
        }
        m_values.clear();
        if (undo) undoChanges(mark);
        // A value untimed in the operand is no longer untimed after it, as the operand assigned it
        m_operandWalking[m_operand] = false;
        m_summaryp.swap(summaryp);
        return summaryp;
    }
    // Walk an operand starting from the state before it
    void iterateSequentialOperand(AstNode* const nodep) {
        std::unique_ptr<Summary> summaryp = iterateOperand(nodep, false);
        concatenate(m_summaryp, summaryp);
    }
    // A sequence that is not a single thread of fixed cycle delays: a composite operator, or a
    // sequence in an operand of a non-sequential operator, walked as a single operand
    void visitComposite(AstNodeExpr* const nodep) {
        if (m_failed) return;
        untimeValues(nodep, "composite sequence operator");
        if (m_inOperand) {
            iterateSequentialOperand(nodep);
            return;
        }
        const bool isOr = VN_IS(nodep, SOr);
        if (!isOr && !VN_IS(nodep, SAnd) && !VN_IS(nodep, SIntersect)) {
            // Sequential operands: each starts from the previous
            VL_RESTORER(m_operandStart);
            m_operandStart = true;
            iterateChildren(nodep);
            return;
        }
        const AstNodeBiop* const biopp = VN_AS(nodep, NodeBiop);
        AstNode* firstp = biopp->lhsp();
        AstNode* lastp = biopp->rhsp();
        // The smaller operand is walked first, its changes undone, its summary merged into the
        // other
        const bool swapped = sizeOf(firstp).count > sizeOf(lastp).count;
        if (swapped) std::swap(firstp, lastp);
        // Both operands start from before the operator
        std::unique_ptr<Summary> firstSummaryp = iterateOperand(firstp, true);
        if (m_failed && swapped) {
            // Report the left operand's unsupported construct, if any, as if walked first
            const AstNode* const rightp = m_unsupportedp;
            const std::string rightMsg = m_unsupportedMsg;
            m_failed = false;
            m_unsupportedp = nullptr;
            std::unique_ptr<Summary> summaryp = iterateOperand(lastp, true);
            retire(summaryp);
            if (!m_unsupportedp) {
                m_unsupportedp = rightp;
                m_unsupportedMsg = rightMsg;
            }
            m_failed = true;
        }
        if (m_failed) {
            retire(firstSummaryp);
            return;
        }
        std::unique_ptr<Summary> lastSummaryp = iterateOperand(lastp, false);
        if (m_failed) {
            retire(firstSummaryp);
            retire(lastSummaryp);
            return;
        }
        // A variable flows out of 'or' as met from both operands. It is blocked by 'and' or
        // 'intersect' if both assign it, else flows out of the operand assigning it.
        std::vector<std::pair<const AstVar*, Effect>> effects;
        effects.reserve(firstSummaryp->effects.size());
        for (const auto& itr : firstSummaryp->effects) {
            ++m_statFlow;
            const Effect first = effectOf(*firstSummaryp, itr.second);
            const auto lastIt = lastSummaryp->effects.find(itr.first);
            if (!isOr) {
                effects.emplace_back(
                    itr.first,
                    lastIt == lastSummaryp->effects.end()
                        ? first
                        : Effect{false, State{State::UNASSIGNED, 0, Untimed{}}, first.in, 0});
            } else if (lastIt == lastSummaryp->effects.end()) {
                // An operand not assigning a variable leaves its incoming state
                effects.emplace_back(itr.first, Effect{true, first.value, first.in, 0});
            } else {
                const Effect last = effectOf(*lastSummaryp, lastIt->second);
                effects.emplace_back(itr.first,
                                     Effect{first.meetIn || last.meetIn,
                                            meet(first.value, last.value), first.in, 0});
            }
        }
        // A variable only the other operand assigns is met with its incoming state
        if (isOr) lastSummaryp->meetInEpoch = ++m_epoch;
        for (const auto& itr : effects) {
            Effect& effectr = lastSummaryp->effects[itr.first];
            effectr = itr.second;
            renewEffect(*lastSummaryp, itr.first, effectr);
        }
        retire(firstSummaryp);
        concatenate(m_summaryp, lastSummaryp);
    }
    // Remove the local variable assignments of a match item, after its subsequence
    void lowerItems(AstExprStmt* const nodep) {
        AstNode* nextp;
        for (AstNode* itemp = nodep->stmtsp(); itemp; itemp = nextp) {
            nextp = itemp->nextp();
            const AstVarRef* const lhsp = assignedLocalp(itemp);
            if (!lhsp) {
                const AstNodeVarRef* writep = nullptr;
                itemp->exists([&](const AstNodeVarRef* refp) {
                    ++m_statWork;
                    if (refp->access().isWriteOrRW() && refp->varp()->isAssertLocal()) {
                        writep = refp;
                    }
                    return writep != nullptr;
                });
                if (writep) {
                    unsupported(writep, "Unsupported: match item assigning part of a"
                                        " local variable (IEEE 1800-2023 16.10).");
                    return;
                }
                // E.g. a subroutine call (IEEE 1800-2023 16.11) stays, reading values in order
                iterateChildren(itemp);
                if (m_failed) return;
                continue;
            }
            AstAssign* const assignp = VN_AS(itemp, Assign);
            std::vector<AstRand*> randps;
            VL_RESTORER(m_randpsp);
            m_randpsp = &randps;
            iterateAndNextNull(assignp->rhsp());
            if (m_failed) return;
            AstNodeExpr* const valuep = assignp->rhsp();
            VIsCached::clearCacheTree();  // Reads lowered above change its purity
            if (!valuep->isPure()) {
                unsupported(valuep, "Unsupported: match item assigning an impure value"
                                    " to a local variable.");
                return;
            }
            drawRandoms(randps);
            const size_t ordinal = sizeOf(assignp).ordinal;
            m_values[lhsp->varp()]
                = Value{assignp->rhsp(), nullptr, m_cycle, !m_inConsequent, ordinal};
            const bool inserted = m_valueps.emplace(ordinal, assignp->rhsp()).second;
            UASSERT_OBJ(inserted, assignp, "Assignment lowered twice");
            ++m_statValues;
            assignp->unlinkFrBack();
            pushDeletep(assignp);
        }
    }
    // Replace each random function call in the value walked with $past of the call, drawn
    // every cycle into a history of its own
    static void drawRandoms(const std::vector<AstRand*>& randps) {
        for (AstRand* const randp : randps) {
            FileLine* const flp = randp->fileline();
            VNRelinker relinkHandle;
            randp->unlinkFrBack(&relinkHandle);
            // Not property timing, so the history starts with a draw of its own
            AstPast* const pastp = new AstPast{
                flp, randp, new AstConst{flp, AstConst::WidthedValue{}, 32, 1}, nullptr, false};
            pastp->ownHistory(true);
            pastp->dtypeFrom(randp);
            relinkHandle.relink(pastp);
        }
    }
    // The temp computing a value every cycle
    AstVar* valueTempp(Value& valuer) {
        if (valuer.tempp) return valuer.tempp;
        AstNodeExpr* const exprp = valuer.exprp;
        FileLine* const flp = exprp->fileline();
        // Named after the walk
        valuer.tempp = new AstVar{flp, VVarType::MODULETEMP, "", exprp->dtypep()};
        AstAssign* const assignp = new AstAssign{
            flp, new AstVarRef{flp, valuer.tempp, VAccess::WRITE}, sampled(exprp->unlinkFrBack())};
        const bool inserted
            = m_temps
                  .emplace(valuer.ordinal,
                           Temp{valuer.tempp, exprp,
                                newAssertAlways(flp, VAlwaysKwd::ALWAYS_COMB, nullptr, assignp)})
                  .second;
        UASSERT_OBJ(inserted, exprp, "Value temp made twice");
        ++m_statTemps;
        return valuer.tempp;
    }

    // VISITORS
    void visit(AstSExpr* nodep) override {
        ++m_statWork;
        if (m_operandStart) {
            iterateSequentialOperand(nodep);
            return;
        }
        if (m_inOperand) {
            visitComposite(nodep);
            return;
        }
        iterateAndNextNull(nodep->preExprp());
        if (m_failed) return;
        // IEEE 1800-2023 16.9.2: the cycle delay of a sequence is folded to a constant before
        // this pass, a range delay `##[m:n]` aside
        const AstDelay* const delayp = VN_AS(nodep->delayp(), Delay);
        const AstConst* const cyclesp = VN_CAST(delayp->lhsp(), Const);
        UASSERT_OBJ(delayp->isCycleDelay() && cyclesp, nodep,
                    "SVA cycle delay must have a constant lhsp");
        if (delayp->isRangeDelay()) {
            untimeValues(nodep, "non-constant cycle delay");
        } else {
            m_cycle += cyclesp->toUInt();
        }
        iterateAndNextNull(nodep->exprp());
    }
    void visit(AstExprStmt* nodep) override {
        ++m_statWork;
        if (m_operandStart) {
            iterateSequentialOperand(nodep);
            return;
        }
        if (m_inOperand) {
            visitComposite(nodep);
            return;
        }
        iterateAndNextNull(nodep->resultp());
        if (m_failed) return;
        lowerItems(nodep);
        if (!nodep->stmtsp()) m_emptyItemps.push_back(nodep);
    }
    void visit(AstVarRef* nodep) override {
        ++m_statWork;
        if (m_operandStart) {
            iterateSequentialOperand(nodep);
            return;
        }
        if (m_failed || !nodep->access().isReadOnly()) return;
        const auto it = m_values.find(nodep->varp());
        if (it == m_values.end()) {
            const State state = normalized(stateOf(nodep->varp()));
            if (state.kind == State::UNTIMED) {
                unsupportedUntimed(state.untimed);
            } else if (state.kind == State::UNTRACKED) {
                unsupportedUntrackedRead(nodep);
            }  // Else reported after the walk
            return;
        }
        Value& valuer = it->second;
        FileLine* const flp = nodep->fileline();
        AstNodeExpr* newp = new AstVarRef{flp, valueTempp(valuer), VAccess::READ};
        if (const uint32_t ticks = m_cycle - valuer.cycle) {
            AstPast* const pastp
                = new AstPast{flp, newp, new AstConst{flp, AstConst::WidthedValue{}, 32, ticks},
                              nullptr, /* propertyTiming */ true};
            pastp->dtypeFrom(newp);
            newp = pastp;
        }
        ++m_statReads;
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstRand* nodep) override {
        if (m_randpsp) m_randpsp->push_back(nodep);
        visit(static_cast<AstNodeExpr*>(nodep));
    }
    void visit(AstNodeExpr* nodep) override {
        ++m_statWork;
        if (m_operandStart) {
            iterateSequentialOperand(nodep);
            return;
        }
        if (nodep->isMultiCycleSva()) {
            visitComposite(nodep);
            return;
        }
        // The operands of a non-sequential operator, e.g. a nested overlapped implication, are
        // walked in order, each sequence in them a thread of its own
        VL_RESTORER(m_inOperand);
        m_inOperand = true;
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override {
        ++m_statWork;
        iterateChildren(nodep);
    }

    // A read left in the property or in a removed value, with no assignment before it
    bool unassignedRead(const AstVarRef* const refp) {
        ++m_statWork;
        if (!refp->access().isReadOnly() || !refp->varp()->isAssertLocal()) return false;
        refp->v3error("Local variable " << AstNode::prettyNameQ(refp->varp()->origName())
                                        << " referenced before it is assigned"
                                           " (IEEE 1800-2023 16.10).");
        m_failed = true;
        return true;
    }

    // CONSTRUCTORS
    AssertNfaMatchItemVisitor(AstNodeModule* const modp, V3UniqueNames& tempNames,
                              AstNodeExpr* const antecedentp, const bool isOverlapped,
                              AstNodeExpr* const bodyp, AstNode* const propp)
        : m_modp{modp}
        , m_tempNames{tempNames} {
        size_t ordinal = 0;
        if (antecedentp) { AssertNfaSizeVisitor{antecedentp, m_sizes, ordinal}; }
        { AssertNfaSizeVisitor{bodyp, m_sizes, ordinal}; }
        m_statFlow += m_sizes.size();
        if (antecedentp) {
            iterateAndNextNull(antecedentp);
            if (!isOverlapped) ++m_cycle;
            m_inConsequent = true;
        }
        if (!m_failed) iterateAndNextNull(bodyp);
        if (m_unsupportedp) m_unsupportedp->v3warn(E_UNSUPPORTED, m_unsupportedMsg);
        for (const auto& itr : m_temps) {
            const Temp& tempr = itr.second;
            const std::string name = m_tempNames.get(tempr.exprp);
            tempr.varp->name(name);
            tempr.varp->origName(name);
            m_modp->addStmtsp(tempr.varp);
            m_alwaysps.push_back(tempr.alwaysp);
            m_modp->addStmtsp(tempr.alwaysp);
        }
        const auto unassignedReadFunc
            = [this](const AstVarRef* refp) { return unassignedRead(refp); };
        if (!m_failed) propp->exists(unassignedReadFunc);
        for (const auto& itr : m_valueps) {
            const AstNodeExpr* const valuep = itr.second;
            if (m_failed) break;
            valuep->exists(unassignedReadFunc);
        }
        for (AstExprStmt* const stmtp : m_emptyItemps) {
            stmtp->replaceWith(stmtp->resultp()->unlinkFrBack());
            VL_DO_DANGLING(pushDeletep(stmtp), stmtp);
        }
        // Lowering changes the purity of ancestors
        VIsCached::clearCacheTree();
    }

public:
    // Lower the match items of an implication, or of a property without one if antecedentp is
    // nullptr. Append the blocks computing value temps to alwaysps, unless an error was
    // reported, then return true.
    static bool lowerFailed(AstNodeModule* const modp, V3UniqueNames& tempNames,
                            AstNodeExpr* const antecedentp, const bool isOverlapped,
                            AstNodeExpr* const bodyp, AstNode* const propp,
                            std::vector<AstAlways*>& alwaysps) {
        AssertNfaMatchItemVisitor visitor{modp,         tempNames, antecedentp,
                                          isOverlapped, bodyp,     propp};
        if (visitor.m_failed) {
            for (AstAlways* const alwaysp : visitor.m_alwaysps) {
                visitor.pushDeletep(alwaysp->unlinkFrBack());
            }
            return true;
        }
        V3Stats::addStatSum("Assertions, local variable values", visitor.m_statValues);
        V3Stats::addStatSum("Assertions, local variable reads", visitor.m_statReads);
        V3Stats::addStatSum("Assertions, local variable value temps", visitor.m_statTemps);
        V3Stats::addStatSum("Assertions, local variable lowering work", visitor.m_statWork);
        V3Stats::addStatSum("Assertions, local variable flow entries", visitor.m_statFlow);
        alwaysps = visitor.m_alwaysps;
        return false;
    }
};

}  // namespace

//######################################################################
// Top-level visitor

class AssertNfaVisitor final : public VNVisitor {
    // True if exprStmtp is a match item
    static bool isMatchItem(const AstExprStmt* exprStmtp) {
        // V3Width also creates an ExprStmt assigning a temporary, e.g. for 'inside' with an
        // impure left-hand side
        const AstVarRef* const lhsRefp
            = VN_CAST(VN_AS(exprStmtp->stmtsp(), Assign)->lhsp(), VarRef);
        return !lhsRefp || lhsRefp->varp()->varType() != VVarType::XTEMP;
    }
    // True if nodep contains a match item
    static bool hasMatchItem(const AstNode* nodep) {
        return nodep->exists([](const AstExprStmt* exprStmtp) { return isMatchItem(exprStmtp); });
    }
    // STATE
    AstNodeModule* m_modp = nullptr;  // Current module being processed
    AstClocking* m_defaultClockingp = nullptr;  // Default clocking
    AstDefaultDisable* m_defaultDisablep = nullptr;  // Default disable iff
    SvaNfaLowering* m_loweringp = nullptr;  // NFA-to-hardware lowering engine
    AstSenTree* m_sampledValueClockp = nullptr;  // Inherited clock during scoped attachment
    AstAlways* m_alwaysp = nullptr;  // Enclosing always, for a procedural assertion
    AstSenItem* m_alwaysClockp = nullptr;  // Clock inferred from m_alwaysp
    V3UniqueNames m_propTempNames{"__VnfaSampled"};  // Hoisted $sampled(propp) temps
    V3UniqueNames m_localValueNames{"__VnfaLocalValue"};  // Local variable value temps
    V3UniqueNames m_failCountNames{"__VnfaRemainingFailCount"};  // Fail replay counter names
    V3UniqueNames m_actionNames{"__VnfaAction"};  // Automatics of cloned actions

    template <typename T_Node>
    void visitSampledValue(T_Node* const nodep) {
        if (m_sampledValueClockp && !nodep->sentreep()) {
            nodep->sentreep(m_sampledValueClockp->cloneTree(true));
        }
        iterateChildren(nodep);
    }

    // Wire match vertex and mid-window sources for a successful NFA build.
    static void wireMatchAndMidSources(SvaGraph& graph, const BuildResult& result, FileLine* flp) {
        graph.createMatchVertex();
        // Skip the main term Link when midSources already cover every
        // end-of-match (cover_sequence path); otherwise the per-mid extraction
        // double-counts via the merge vertex.
        if (!result.termIsMidMerge) { graph.addLink(result.termVertexp, graph.m_matchVertexp); }
        for (SvaStateVertex* srcVtxp : result.midSources) {
            AstNodeExpr* condp = nullptr;
            for (AstNodeExpr* const tcp : srcVtxp->m_throughoutConds) {
                AstNodeExpr* const tcClonep = tcp->cloneTreePure(false);
                condp = condp ? new AstLogAnd{flp, condp, tcClonep} : tcClonep;
            }
            graph.addLink(srcVtxp, graph.m_matchVertexp, condp);
            srcVtxp->m_isUnbounded = true;
        }
    }

    // Report a goto or nonconsecutive repetition in nodep with a sequence operand, true if any
    static bool reportSequenceRepOperand(const AstNode* nodep) {
        // Their operand is an expression (IEEE 1800-2023 16.9.2). Checked after sequence instances
        // are inlined, as an instance or an untyped formal argument may hide a sequence.
        return nodep->exists([](const AstNodeExpr* repp) {
            const AstNodeExpr* operandp = nullptr;
            const char* kindp = nullptr;
            if (const AstSGotoRep* const gotop = VN_CAST(repp, SGotoRep)) {
                operandp = gotop->exprp();
                kindp = "Goto";
            } else if (const AstSNonConsRep* const nonConsp = VN_CAST(repp, SNonConsRep)) {
                operandp = nonConsp->exprp();
                kindp = "Nonconsecutive";
            }
            if (!operandp || !hasMultiCycleExpr(operandp)) return false;
            repp->v3error(kindp << " repetition operand must be a boolean expression,"
                                   " but is a sequence (IEEE 1800-2023 16.9.2)");
            return true;
        });
    }

    static VPropStrength effectiveAssertPropStrength(const AstPropSpec* const propSpecp) {
        if (propSpecp->propStrength() != VPropStrength::DEFAULT) return propSpecp->propStrength();
        return propSpecp->fileline()->language() <= V3LangCode::L1800_2005 ? VPropStrength::STRONG
                                                                           : VPropStrength::WEAK;
    }

    // Bare `assert property (p until q)` with boolean operands stays on
    // V3AssertPre's AstLoop lowering, which preserves per-attempt action-block
    // firings that this NFA's single-bit aggregated state cannot. Strong bare
    // forms are also lowered there. NFA still owns sequence operands and any
    // embedding inside a multi-cycle context (implication consequent, or/and
    // operands, etc.).
    static bool isBareTopLevelUntil(AstNode* propp) {
        AstNode* p = propp;
        if (AstPropSpec* const specp = VN_CAST(p, PropSpec)) p = specp->propp();
        while (AstLogNot* const notp = VN_CAST(p, LogNot)) p = notp->lhsp();
        AstUntil* const untilp = VN_CAST(p, Until);
        if (!untilp) return false;
        const auto hasSeq = [](const AstNodeExpr* ep) {
            return ep->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); });
        };
        if (hasSeq(untilp->lhsp()) || hasSeq(untilp->rhsp())) return false;
        return true;
    }

    struct PropertyParts final {
        AstNodeExpr* triggerExprp = nullptr;
        AstNodeExpr* seqExprp = nullptr;
        bool isOverlapped = true;
        bool hasImplication = false;
        bool isFollowedBy = false;  // True for #-# / #=# (non-vacuous-fail on antecedent miss)
    };

    static PropertyParts decomposeProperty(AstNode* propp) {
        PropertyParts parts;
        if (AstPropSpec* const specp = VN_CAST(propp, PropSpec)) { propp = specp->propp(); }
        if (AstImplication* const implp = VN_CAST(propp, Implication)) {
            parts.hasImplication = true;
            parts.isOverlapped = implp->isOverlapped();
            parts.isFollowedBy = implp->isFollowedBy();
            parts.triggerExprp = implp->lhsp();
            parts.seqExprp = implp->rhsp();
        } else if (AstNodeExpr* const exprp = VN_CAST(propp, NodeExpr)) {
            parts.triggerExprp = nullptr;
            parts.seqExprp = exprp;
        }
        return parts;
    }

    static bool canSplitImplicationPassActions(const PropertyParts& parts) {
        UASSERT(parts.hasImplication,
                "Implication pass action split requested without implication");
        UASSERT(parts.triggerExprp, "Implication pass action split requested without trigger");
        // Direct vacuous/nonvacuous classification uses the antecedent value in the current
        // assertion attempt. Leave delayed antecedents on the existing NFA pass path.
        return !hasMultiCycleExpr(parts.triggerExprp);
    }

    void splitImplicationPassActions(AstAssert* assertp, const PropertyParts& parts,
                                     AstNodeExpr* nonvacuousMatchp) {
        FileLine* const flp = assertp->fileline();

        AstNodeStmt* const passsp = assertp->passsp()->unlinkFrBackWithNext();
        AstNodeStmt* splitsp = nullptr;

        if (!parts.isFollowedBy) {
            AstNodeExpr* const vacuousp
                = new AstLogNot{flp, sampled(parts.triggerExprp->cloneTreePure(false))};
            AstNodeStmt* const vacuousBodyp = V3AssertCommon::cloneAction(passsp, m_actionNames);
            splitsp = newPassOnIf(flp, vacuousp, vacuousBodyp, assertp->userType(),
                                  assertp->directive(), /*vacuous=*/true);
        }

        AstIf* const nonvacuousp
            = newPassOnIf(flp, nonvacuousMatchp, passsp, assertp->userType(), assertp->directive(),
                          /*vacuous=*/false);
        splitsp = AstNode::addNextNull<AstNodeStmt>(splitsp, nonvacuousp);
        // Another attempt failing on the same tick runs the fail action instead
        assertp->prependFailsp(V3AssertCommon::cloneAction(splitsp, m_actionNames));
        assertp->addPasssp(splitsp);
    }

    // On a PropSpec-wrapped assertion whose NFA build failed with a semantic
    // error (errorEmitted), replace the body with a BitFalse const so later
    // passes see a well-formed AST. Returns true if replaced.
    void replaceBodyOnBuildError(FileLine* flp, AstPropSpec* propSpecp, bool errorEmitted) {
        if (!errorEmitted) return;
        AstNode* const innerPropp = propSpecp->propp();
        innerPropp->replaceWith(new AstConst{flp, AstConst::BitFalse{}});
        VL_DO_DANGLING(pushDeletep(innerPropp), innerPropp);
    }

    // True if two clocking events have the same event expressions
    static bool sameClock(const AstSenItem* ap, const AstSenItem* bp) {
        for (; ap && bp; ap = VN_CAST(ap->nextp(), SenItem), bp = VN_CAST(bp->nextp(), SenItem)) {
            if (!ap->sameTree(bp)) return false;
        }
        return !ap && !bp;
    }
    // Replace a clocked sequence with its sequence
    void unwrapClockedSeq(AstSClocked* clockedp) {
        clockedp->replaceWith(clockedp->exprp()->unlinkFrBack());
        VL_DO_DANGLING(pushDeletep(clockedp), clockedp);
    }
    // Hoist a leading clocking event (IEEE 1800-2023 16.7):
    bool hoistClockedSeq(AstPropSpec* specp) {
        while (AstSClocked* const clockedp = VN_CAST(specp->propp(), SClocked)) {
            if (specp->sensesp()) {
                // The same clock as the property's does not make it multiclocked
                // (IEEE 1800-2023 16.13.2)
                if (sameClock(specp->sensesp(), clockedp->sensesp())) {
                    unwrapClockedSeq(clockedp);
                    continue;
                }
                clockedp->v3warn(E_UNSUPPORTED, "Unsupported: multiclocked sequence or property");
                replaceBodyOnBuildError(specp->fileline(), specp, true);
                return true;
            }
            for (const AstSenItem* sp = clockedp->sensesp(); sp;
                 sp = VN_CAST(sp->nextp(), SenItem)) {
                if (!sp->edgeType().anEdge()) {
                    clockedp->v3warn(E_UNSUPPORTED,
                                     "Unsupported: non-edge clocking event on a sequence; "
                                     "use an edge such as @(posedge clk)");
                    replaceBodyOnBuildError(specp->fileline(), specp, true);
                    return true;
                }
            }
            specp->addSensesp(clockedp->sensesp()->unlinkFrBackWithNext());
            unwrapClockedSeq(clockedp);
        }
        // A clocking event elsewhere in the sequence is supported if it is the property's clock,
        // or else the default clocking's (IEEE 1800-2023 16.13.2)
        const AstSenItem* const clockp = specp->sensesp() ? specp->sensesp()
                                         : m_defaultClockingp
                                             ? m_defaultClockingp->sentreep()->sensesp()
                                             : nullptr;
        std::vector<AstSClocked*> nestedps;
        specp->propp()->foreach([&](AstSClocked* p) { nestedps.push_back(p); });
        for (AstSClocked* const nestedp : nestedps) {
            if (!sameClock(clockp, nestedp->sensesp())) {
                nestedp->v3warn(E_UNSUPPORTED,
                                "Unsupported: clocking event inside sequence expression");
                replaceBodyOnBuildError(specp->fileline(), specp, true);
                return true;
            }
        }
        for (AstSClocked* const nestedp : nestedps) unwrapClockedSeq(nestedp);
        return false;
    }

    // Build the NFA graph for a property body, handling both the antecedent
    // |-> consequent and simple sequence cases. Returns the consequent/body
    // BuildResult (invalid on parse/build failure).
    BuildResult buildAssertionGraph(SvaNfaBuilder& builder, SvaGraph& graph, AstNodeExpr* seqBodyp,
                                    const PropertyParts& parts, FileLine* flp) {
        if (!parts.hasImplication) return builder.build(seqBodyp);

        graph.m_startVertexp = graph.createStateVertex();
        return builder.buildImplicationEdges(parts.triggerExprp, seqBodyp, graph.m_startVertexp,
                                             parts.isOverlapped, parts.isFollowedBy,
                                             parts.triggerExprp, flp);
    }

    // Run stmtp once per count above one on each tick; the assertion runs it the first time
    void addActionReplay(AstSenTree* const senTreep, AstNodeExpr* const countp,
                         AstNodeStmt* const stmtp) {
        FileLine* const flp = stmtp->fileline();
        AstVar* const remainingCountVarp
            = new AstVar{flp, VVarType::MODULETEMP, m_failCountNames.get(""),
                         m_modp->findBasicDType(VBasicDTypeKwd::UINT32)};
        remainingCountVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        m_modp->addStmtsp(remainingCountVarp);
        AstNodeStmt* const replayStmtsp
            = new AstAssign{flp, new AstVarRef{flp, remainingCountVarp, VAccess::WRITE}, countp};
        AstLoop* const replayLoopp = new AstLoop{flp};
        replayLoopp->addStmtsp(
            new AstLoopTest{flp, replayLoopp,
                            new AstGt{flp, new AstVarRef{flp, remainingCountVarp, VAccess::READ},
                                      newTypedConstp(flp, remainingCountVarp->dtypep(), 1)}});
        replayLoopp->addStmtsp(stmtp);
        AstSub* const decrementedCountp
            = new AstSub{flp, new AstVarRef{flp, remainingCountVarp, VAccess::READ},
                         newTypedConstp(flp, remainingCountVarp->dtypep(), 1)};
        replayLoopp->addStmtsp(new AstAssign{
            flp, new AstVarRef{flp, remainingCountVarp, VAccess::WRITE}, decrementedCountp});
        replayStmtsp->addNext(replayLoopp);
        m_modp->addStmtsp(
            newAssertAlways(flp, VAlwaysKwd::ALWAYS, senTreep->cloneTree(false), replayStmtsp));
    }

    // Install pass-action gating and replay simultaneous failures and passes.
    void attachActionHandlers(AstAssert* const assertp, AstNodeExpr* matchExprp,
                              AstSenTree* const senTreep, AstNodeExpr* const failCountp,
                              AstNodeExpr* const passCountp) {
        // IEEE 1800-2023 16.14.1 requires one action-block evaluation per failed or passed
        // thread. AstAssert handles the first, so replay the rest, before the fail action
        // below gets the pass action prefix.
        if (failCountp) {
            addActionReplay(
                senTreep, failCountp,
                newIfAssertFailOn(V3AssertCommon::cloneAction(assertp->failsp(), m_actionNames),
                                  assertp->directive(), assertp->userType()));
        }
        if (passCountp) {
            FileLine* const flp = assertp->fileline();
            addActionReplay(
                senTreep, passCountp,
                newPassOnIf(flp, new AstConst{flp, AstConst::BitTrue{}},
                            V3AssertCommon::cloneAction(assertp->passsp(), m_actionNames),
                            assertp->userType(), assertp->directive(), /*vacuous=*/false));
        }
        // Gate pass handler on match to prevent vacuous-pass firings.
        if (matchExprp) {
            // needMatch implies passsp() was non-null when evaluated above;
            // lowering does not mutate the assert's pass-action between the
            // two reads, so passsp() is still non-null here.
            AstNodeStmt* passsp = assertp->passsp();
            UASSERT_OBJ(passsp, assertp, "needMatch set but passsp is null");
            passsp->unlinkFrBackWithNext();
            FileLine* const flp = assertp->fileline();
            AstIf* const ifp = new AstIf{flp, matchExprp, passsp, nullptr};
            assertp->addPasssp(ifp);
            // Fail-handler prefix for overlapping instances (IEEE 16.12):
            // fires when reject=1 && match=1 in the same cycle.
            assertp->prependFailsp(V3AssertCommon::cloneAction(ifp, m_actionNames));
        }
    }

    static bool splitsImplicationPasssp(const AstNodeCoverOrAssert* assertp,
                                        const PropertyParts& parts) {
        const AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        return assertAssertp && assertAssertp->passsp() && parts.hasImplication
               && canSplitImplicationPassActions(parts);
    }

    // Takes ownership of outputp, and of matchp, matchCountp, failCountp and passCountp if
    // non-null
    void finishDirective(AstNodeCoverOrAssert* assertp, const PropertyParts& parts,
                         AstSenTree* senTreep, AstNodeExpr* outputp, AstNodeExpr* matchp,
                         AstNodeExpr* matchCountp, AstNodeExpr* failCountp,
                         AstNodeExpr* passCountp) {
        AstNodeExpr* outputExprp = outputp;
        FileLine* const flp = assertp->fileline();
        AstPropSpec* const propp = VN_AS(assertp->propp(), PropSpec);
        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        if (countsMatches(assertp)) {
            UASSERT_OBJ(matchCountp, assertp, "Cover sequence missing match count");
            VL_DO_DANGLING(outputExprp->deleteTree(), outputExprp);
            propp->matchCountp(matchCountp);
            outputExprp = new AstNeq{flp, matchCountp->cloneTreePure(false),
                                     newTypedConstp(flp, matchCountp->dtypep(), 0)};
        } else if (matchCountp) {
            propp->matchCountp(matchCountp);
        }

        const bool splitImplicationPasssp = splitsImplicationPasssp(assertp, parts);
        if (assertAssertp) {
            attachActionHandlers(assertAssertp, splitImplicationPasssp ? nullptr : matchp,
                                 senTreep, failCountp, passCountp);
        }
        // After the replays, which clone the fail action without the pass action prefix
        if (splitImplicationPasssp) splitImplicationPassActions(assertAssertp, parts, matchp);

        AstNode* const innerPropp = propp->propp();
        innerPropp->replaceWith(outputExprp);
        VL_DO_DANGLING(pushDeletep(innerPropp), innerPropp);
    }

    // Outcome counts for a property if/case are wrong in an outcome-multiplying
    // context. Returns that context, or nullptr when the shape is supported.
    static const char* unsupportedPropertyControl(const AstNodeCoverOrAssert* assertp,
                                                  const AstNodeExpr* seqBodyp, bool negated) {
        if (!hasPropertyControlConjunction(seqBodyp)) return nullptr;
        if (negated) return "negation";
        if (VN_IS(assertp, Cover)) return "cover";
        if (VN_AS(assertp, Assert)->passsp()) return "a pass action";
        return nullptr;
    }

    // Reject unsupported shapes.
    // Returns the PropSpec to lower, or nullptr when fully handled here.
    AstPropSpec* prepareAssertionProp(AstNodeCoverOrAssert* assertp) {
        if (reportSequenceRepOperand(assertp->propp())) {
            VL_DO_DANGLING(pushDeletep(assertp->unlinkFrBack()), assertp);
            return nullptr;
        }
        if (AstPropSpec* const specp = VN_CAST(assertp->propp(), PropSpec)) {
            // Leave a chain of property instances to V3AssertPre: the NFA lowering
            // reports one fail for attempts failing in the same cycle, e.g. after a goto
            // repetition antecedent, but each attempt fails (IEEE 1800-2023 16.14.1).
            if (specp->fromInstanceChain()) {
                // V3AssertPre keeps no per-attempt storage for a local variable
                const AstVarRef* localp = nullptr;
                specp->exists([&](const AstVarRef* refp) {
                    if (refp->varp()->isAssertLocal()) localp = refp;
                    return localp != nullptr;
                });
                if (localp) {
                    localp->v3warn(E_UNSUPPORTED, "Unsupported: local variable in a chain of"
                                                  " property instances (IEEE 1800-2023 16.10).");
                    replaceBodyOnBuildError(specp->fileline(), specp, /*errorEmitted=*/true);
                }
                return nullptr;
            }
            if (hoistClockedSeq(specp)) return nullptr;
        }

        AstPropSpec* const propp = VN_AS(assertp->propp(), PropSpec);
        // A strong sequence inside the property is the sequence if it matches on its first tick,
        // or in a cover, where strength makes no difference; else unsupported as for a strong
        // property below
        std::vector<AstSStrength*> strongps;
        propp->foreach([&](AstSStrength* strongp) { strongps.push_back(strongp); });
        for (AstSStrength* const strongp : strongps) {
            if (!VN_IS(assertp, Cover) && hasMultiCycleExpr(strongp->exprp())) {
                strongp->v3warn(E_UNSUPPORTED,
                                "Unsupported: strong sequence in " + assertp->verilogKwd() + ".");
                replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
                return nullptr;
            }
            strongp->replaceWith(strongp->exprp()->unlinkFrBack());
            VL_DO_DANGLING(pushDeletep(strongp), strongp);
        }
        if (!VN_IS(assertp, Cover)
            && effectiveAssertPropStrength(propp) == VPropStrength::STRONG) {
            propp->v3warn(E_UNSUPPORTED,
                          "Unsupported: strong property in " + assertp->verilogKwd() + ".");
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return nullptr;
        }

        if (!hasMultiCycleExpr(propp)) return nullptr;
        if (isBareTopLevelUntil(propp)) return nullptr;
        // An 'iff' is a Boolean equivalence (AstLogEq), which cannot hold a multi-cycle operand.
        // A followed-by operand is reported more specifically by V3AssertPre.
        const AstLogEq* iffp = nullptr;
        propp->foreach([&](const AstLogEq* eqp) {
            const bool multiCycle = eqp->exists([eqp](const AstNodeExpr* np) {
                if (!np->isMultiCycleSva()) return false;
                for (const AstNode* abovep = np; abovep != eqp; abovep = abovep->aboveLoopp()) {
                    const AstImplication* const implp = VN_CAST(abovep, Implication);
                    if (implp && implp->isFollowedBy()) return false;
                }
                return true;
            });
            if (multiCycle) iffp = eqp;
        });
        if (iffp) {
            iffp->v3warn(E_UNSUPPORTED, "Unsupported: property 'iff' with a multi-cycle operand"
                                        " (IEEE 1800-2023 16.12.8)");
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return nullptr;
        }
        // Match items in a repetition update the attempt's local variables at each iteration,
        // the value flowing into the next one (IEEE 1800-2023 16.10), which is not modeled.
        // Checked before the match items are lowered, which would report it less precisely.
        const AstNodeExpr* itemRepp = nullptr;
        propp->exists([&](const AstNodeExpr* repp) {
            if (!VN_IS(repp, SConsRep) && !VN_IS(repp, SGotoRep) && !VN_IS(repp, SNonConsRep)) {
                return false;
            }
            if (!hasMatchItem(repp)) return false;
            itemRepp = repp;
            return true;
        });
        if (itemRepp) {
            itemRepp->v3warn(E_UNSUPPORTED, "Unsupported: sequence match item in repetition"
                                            " (IEEE 1800-2023 16.10)");
            VL_DO_DANGLING(pushDeletep(assertp->unlinkFrBack()), assertp);
            return nullptr;
        }
        return propp;
    }

    // True if a statement in an always procedure is under a condition or loop
    static bool isUnderProceduralCondition(const AstNode* nodep) {
        for (const AstNode* abovep = nodep->aboveLoopp(); !VN_IS(abovep, Always);
             abovep = abovep->aboveLoopp()) {
            if (!VN_IS(abovep, Begin)) return true;
        }
        return false;
    }
    // A future value function of a multi-cycle property that V3Assert cannot lower, or nullptr
    static const AstNode* unloweredFuturep(const AstPropSpec* propp, const PropertyParts& parts) {
        // V3Assert evaluates the property one global clock tick late, delaying the other values
        // of its final condition (IEEE 1800-2023 16.9.4), so future values are supported only in
        // a boolean consequent, which stays in the final condition
        const AstNode* futurep = nullptr;
        const auto findFuture = [&futurep](const AstNode* nodep) {
            if (!nodep) return;
            nodep->exists([&futurep](const AstNode* np) {
                if (!VN_IS(np, Future) && !VN_IS(np, Rising) && !VN_IS(np, Falling)
                    && !VN_IS(np, Steady))
                    return false;
                futurep = np;
                return true;
            });
        };
        if (!parts.hasImplication || hasMultiCycleExpr(parts.seqExprp)) {
            findFuture(propp);
        } else {
            findFuture(parts.triggerExprp);
            findFuture(propp->disablep());
        }
        return futurep;
    }

    // True if an evaluation attempt of a property has at most one thread at a time
    static bool oneThreadPerAttempt(const AstNodeExpr* nodep, bool top) {
        // Only a top-level synchronous abort keeps each live thread one whole attempt
        if (const AstAbortOn* const abortp = VN_CAST(nodep, AbortOn)) {
            const VAbortKind kind = abortp->kind();
            return top
                   && (kind.m_e == VAbortKind::SYNC_ACCEPT_ON
                       || kind.m_e == VAbortKind::SYNC_REJECT_ON)
                   && oneThreadPerAttempt(abortp->propp(), false);
        }
        if (const AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            return !VN_AS(sexprp->delayp(), Delay)->isRangeDelay()
                   && (!sexprp->preExprp() || oneThreadPerAttempt(sexprp->preExprp(), false))
                   && oneThreadPerAttempt(sexprp->exprp(), false);
        }
        // A goto repetition repeats a boolean (IEEE 1800-2023 16.9.2); a consecutive repetition
        // of a multi-cycle sequence is reported as unsupported
        if (const AstSGotoRep* const repp = VN_CAST(nodep, SGotoRep)) return !repp->maxCountp();
        if (const AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            return !repp->maxCountp() && !repp->unbounded();
        }
        // A boolean
        return !nodep->exists([](const AstNodeExpr* exprp) { return exprp->isMultiCycleSva(); });
    }

    void processAssertion(AstNodeCoverOrAssert* assertp) {
        if (assertp->immediate()) return;

        AstPropSpec* const propp = prepareAssertionProp(assertp);
        if (!propp) return;

        PropertyParts parts = decomposeProperty(propp);
        UASSERT_OBJ(parts.seqExprp, propp, "Property body must be an expression");

        // Unwrap `not` (IEEE 1800-2023 16.12.1); odd count -> negated semantics.
        AstNodeExpr* seqBodyp = parts.seqExprp;
        bool negated = false;
        while (AstLogNot* const notp = VN_CAST(seqBodyp, LogNot)) {
            negated = !negated;
            seqBodyp = notp->lhsp();
        }

        // A negated unbounded always passes when its operand fails, which the NFA cannot
        // express as it has no pending state for the always
        const AstNode* negAlwaysp = nullptr;
        propp->exists([&](const AstLogNot* notp) {
            return notp->exists([&](const AstPropAlways* alwaysp) {
                if (VN_IS(alwaysp->hiBoundp(), Unbounded)) negAlwaysp = alwaysp;
                return negAlwaysp != nullptr;
            });
        });
        if (negAlwaysp) {
            negAlwaysp->v3warn(E_UNSUPPORTED,
                               "Unsupported: unbounded 'always' in a negated property");
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return;
        }

        const char* const propertyControlp
            = unsupportedPropertyControl(assertp, seqBodyp, negated);

        if (const AstNode* const futurep = unloweredFuturep(propp, parts)) {
            futurep->v3warn(E_UNSUPPORTED, "Unsupported: future sampled value function in a"
                                           " multi-cycle property, other than in a boolean"
                                           " implication consequent");
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return;
        }

        std::vector<AstAlways*> localValueps;  // Blocks computing local variable values
        if (AssertNfaMatchItemVisitor::lowerFailed(
                m_modp, m_localValueNames, parts.hasImplication ? parts.triggerExprp : nullptr,
                parts.isOverlapped, seqBodyp, propp->propp(), localValueps)) {
            AstPropSpec* const psp = VN_CAST(assertp->propp(), PropSpec);
            UASSERT_OBJ(psp, assertp, "Concurrent assertion must have PropSpec");
            replaceBodyOnBuildError(assertp->fileline(), psp, /*errorEmitted=*/true);
            return;
        }
        // Lowering replaced each match item with its subsequence
        parts = decomposeProperty(propp);
        seqBodyp = parts.seqExprp;
        while (AstLogNot* const notp = VN_CAST(seqBodyp, LogNot)) seqBodyp = notp->lhsp();

        AstCover* const coverp = VN_CAST(assertp, Cover);
        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        const bool isCoverSeq = coverp && coverp->isCoverSeq();
        // A sequence event control is not an assertion directive; no default
        // disable iff, no assertion control
        const bool isSeqEvent = coverp && coverp->isSeqEvent();
        const bool countMatches = countsMatches(assertp);
        // Inherit module defaults (IEEE 14.12, 16.15) when assertion has none. A clock inferred
        // from the always procedure takes precedence over default clocking (IEEE 1800-2023 16.16).
        if (!propp->sensesp() && m_defaultClockingp && !m_alwaysClockp) {
            propp->addSensesp(m_defaultClockingp->sentreep()->sensesp()->cloneTree(true));
        }
        if (!propp->disablep() && m_defaultDisablep && !isSeqEvent) {
            propp->disablep(m_defaultDisablep->condp()->cloneTreePure(true));
        }
        AstSenItem* sensesp = propp->sensesp();
        if (!sensesp && m_alwaysp && !isSeqEvent) {
            // The NFA starts an attempt on every clock, not only when the procedure reaches the
            // assertion, and the assertion reports each time the procedure runs
            if (isUnderProceduralCondition(assertp)) {
                assertp->v3warn(E_UNSUPPORTED,
                                "Unsupported: multi-cycle procedural concurrent assertion"
                                " under a condition or loop (IEEE 1800-2023 16.14.6)");
                replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
                return;
            }
            if (m_alwaysp->sentreep() && m_alwaysp->sentreep()->sensesp()->nextp()) {
                assertp->v3warn(E_UNSUPPORTED,
                                "Unsupported: multi-cycle procedural concurrent assertion in an"
                                " always procedure with several events (IEEE 1800-2023 16.14.6)");
                replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
                return;
            }
            sensesp = m_alwaysClockp;
            if (!sensesp) {
                assertp->v3error("Concurrent assertion has no clock (IEEE 1800-2023 16.16)\n"
                                 << assertp->warnMore()
                                 << "... Suggest provide a clocking event, a default clocking,"
                                    " or a clocked always procedure (IEEE 1800-2023 16.14.6)");
                replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
                return;
            }
        }
        if (!sensesp) {
            // V3AssertPre reports the missing clock (IEEE 1800-2023 16.16), but cannot lower the
            // multi-cycle body
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return;
        }
        AstSenTree* senTreep = new AstSenTree{propp->fileline(), sensesp->cloneTree(true)};
        AstNodeExpr* const disableExprp = propp->disablep();

        // NFA lowering clones repeated operands and may hoist them into an
        // always_comb block. Resolve implicit sampled-value clocks first, while
        // the enclosing assertion clock is still available.
        {
            VL_RESTORER(m_sampledValueClockp);
            m_sampledValueClockp = senTreep;
            iterate(propp->propp());
            for (AstAlways* const alwaysp : localValueps) iterate(alwaysp);
            // The final block clones the action block, so resolve its clocks while in scope
            if (assertAssertp) iterateAndNextNull(assertAssertp->failsp());
        }
        // V3AssertPre runs the action block once per failing attempt of a nonconsecutive
        // repetition, not at each failing match, but does not support it with a cycle delay.
        // Left after the module defaults are inherited, which V3AssertPre relies on.
        if (propp->exists([](const AstSNonConsRep*) { return true; })
            && !propp->exists([](const AstSExpr*) { return true; })) {
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
            return;
        }

        FileLine* const flp = assertp->fileline();

        SvaGraph graph;
        // A vacuous success fails a negated assertion (IEEE 1800-2023 16.12.3), so a cover,
        // counting passes, needs none; a negated property if/case is reported below instead
        const bool trackVacuous = negated && !coverp && !propertyControlp;
        // A concurrent assertion item is the only statement of its own process, inside the
        // implied block of its label if it has one
        const AstNode* processp = assertp->aboveLoopp();
        const AstBegin* const labelp = VN_CAST(processp, Begin);
        if (labelp && labelp->implied()) processp = labelp->aboveLoopp();
        const AstAlways* const alwaysp = VN_CAST(processp, Always);
        const bool isDeclarative = alwaysp && alwaysp->keyword() == VAlwaysKwd::ASSERT_COVER;
        SvaNfaBuilder builder{graph,      m_modp,       m_propTempNames,
                              isCoverSeq, isSeqEvent,   coverp != nullptr,
                              negated,    trackVacuous, isDeclarative};

        const BuildResult result = buildAssertionGraph(builder, graph, seqBodyp, parts, flp);
        if (result.valid()) wireMatchAndMidSources(graph, result, flp);
        if (!result.valid()) {
            // Fall through to V3AssertPre for unsupported constructs; only
            // replace the body on real semantic errors. Any hoisted temps
            // from this attempt become orphan MODULETEMPs; V3Dead removes
            // them along with the dead always_comb driver.
            replaceBodyOnBuildError(flp, propp, result.errorEmitted);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
            return;
        }
        // After the build, so a construct the builder rejects reports itself.
        if (propertyControlp) {
            seqBodyp->v3warn(E_UNSUPPORTED,
                             "Unsupported: temporal property if/case with " << propertyControlp);
            replaceBodyOnBuildError(flp, propp, /*errorEmitted=*/true);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
            return;
        }
        if (countMatches && !v3Global.opt.coverageUser()) {
            SvaNfaBuilder::freeUnlinkedCondp(result.finalCondp);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
            AstNode* const innerPropp = propp->propp();
            innerPropp->replaceWith(new AstConst{flp, AstConst::BitFalse{}});
            VL_DO_DANGLING(pushDeletep(innerPropp), innerPropp);
            return;
        }

        const bool splitImplicationPasssp = splitsImplicationPasssp(assertp, parts);
        const bool needMatch = assertAssertp && assertAssertp->passsp()
                               && (!parts.hasImplication || splitImplicationPasssp);

        // The rejected threads of a negated property's operand are passes of the property
        const bool replayFails = assertAssertp && assertAssertp->failsp() && !negated;
        const bool replayPasses
            = assertAssertp && assertAssertp->passsp() && !parts.hasImplication && negated;
        const bool replayThreads = replayFails || replayPasses;
        // Counting threads counts the failed attempts when each attempt has one thread
        const bool exactCounts
            = replayFails && !parts.hasImplication && oneThreadPerAttempt(seqBodyp, true);
        // A match and a vacuous success of its operand on one tick both fail a negated property
        const bool replaySuccesses = assertAssertp && assertAssertp->failsp() && negated;
        const auto signals
            = m_loweringp->lower(assertp, graph, senTreep, result.finalCondp, disableExprp,
                                 replayThreads, replayThreads, replaySuccesses, exactCounts,
                                 exactCounts ? VN_CAST(seqBodyp, AbortOn) : nullptr,
                                 coverp && !isCoverSeq && !negated && v3Global.opt.coverageUser());
        AstNodeExpr* matchExprp = nullptr;
        AstNodeExpr* const outputExprp = m_loweringp->assembleResult(
            assertp, negated, result.finalCondp, signals, needMatch ? &matchExprp : nullptr);
        if (result.finalCondp && !result.finalCondp->backp()) pushDeletep(result.finalCondp);
        finishDirective(assertp, parts, senTreep, outputExprp, matchExprp, signals.matchCountp,
                        replayFails ? signals.threadFailCountp : signals.successCountp,
                        replayPasses ? signals.threadFailCountp : nullptr);
        VL_DO_DANGLING(pushDeletep(senTreep), senTreep);

        UINFO(4, "NFA converted assertion at " << flp << endl);

        if (dumpGraphLevel() >= 6) graph.m_graph.dumpDotFilePrefixed("assert-nfa");
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_loweringp);
        VL_RESTORER(m_defaultClockingp);
        VL_RESTORER(m_defaultDisablep);
        VL_RESTORER_COPY(m_localValueNames);
        m_modp = nodep;
        m_localValueNames.reset();
        // A class nested in a module is in the scope of the module's default clocking
        if (!VN_IS(nodep, Class)) {
            m_defaultClockingp = V3AssertCommon::moduleDefaultClockingp(nodep);
        }
        m_defaultDisablep = nodep->defaultDisablep();
        SvaNfaLowering lowering{nodep, m_actionNames};
        m_loweringp = &lowering;
        iterateChildren(nodep);
    }
    void visit(AstAlways* nodep) override {
        VL_RESTORER(m_alwaysp);
        VL_RESTORER(m_alwaysClockp);
        m_alwaysp = nodep;
        m_alwaysClockp = V3AssertCommon::inferredClock(nodep);
        iterateChildren(nodep);
    }
    void visit(AstClocking* nodep) override {
        if (nodep->isDefault() && !m_defaultClockingp) m_defaultClockingp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        m_defaultDisablep = nodep->defaultDisablep();
        iterateChildren(nodep);
    }
    void visit(AstDefaultDisable* nodep) override {}
    void visit(AstFell* nodep) override { visitSampledValue(nodep); }
    void visit(AstPast* nodep) override { visitSampledValue(nodep); }
    void visit(AstRose* nodep) override { visitSampledValue(nodep); }
    void visit(AstStable* nodep) override { visitSampledValue(nodep); }
    void visit(AstAssert* nodep) override { processAssertion(nodep); }
    void visit(AstCover* nodep) override { processAssertion(nodep); }
    void visit(AstRestrict* nodep) override {
        // Restrict property is ignored by simulators (IEEE 1800-2023 16.12.2).
        // Remove here so temporal SExpr don't leak to V3AssertPre.
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }
    void visit(AstAssertIntrinsic* nodep) override {}
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit AssertNfaVisitor(AstNetlist* nodep) { iterate(nodep); }
};

//######################################################################
// Top entry point

void V3AssertNfa::assertNfaAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":" << endl);
    { AssertNfaVisitor{nodep}; }
    V3Global::dumpCheckGlobalTree("assertnfa", 0, dumpTreeEitherLevel() >= 3);
}
