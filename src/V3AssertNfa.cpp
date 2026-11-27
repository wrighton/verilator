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
    // Both operand matches of one attempt end on the same tick, so no done-latch is needed
    bool m_andAligned = false;
    // Reject sink for SAnd rejectOnFail wiring; not a state-signal source
    bool m_isRejectSink = false;
    // In-window vertex of a strong s_always[m:n]: if its state is still set at
    // end-of-simulation the universal-quantifier window never completed, which is
    // a liveness failure (IEEE 1800-2023 16.12.11 strong semantics).
    bool m_strongPending = false;
    // Ring introduced for the checked portion of a bounded strong s_always window.
    bool m_strongAlwaysRing = false;

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
    // With m_rejectOnFail, rejects as the antecedent of a followed-by does not match
    bool m_followedByAntecedent = false;
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
    ifp->isAssertPassGate(true);
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

class SvaNfaBuilder final {
    SvaGraph& m_graph;  // NFA graph being built
    AstNodeModule* const m_modp;  // Module to receive hoisted sampled-prop temps
    V3UniqueNames& m_propTempNames;  // Module-shared temp-var name source
    std::vector<AstNodeExpr*> m_temporalGuardStack;  // Guards active across nested temporal states
    // Outer abort conditions, AND-ed as !cond into inner abort edges
    // (IEEE 1800-2023 16.12.14 outer-wraps-inner).
    std::vector<AstNodeExpr*> m_outerAbortStack;
    bool m_inUnboundedScope = false;  // Sticky: nodes created after inherit liveness
    // Sticky: a miss of one candidate rejects the attempt, after a ranged delay that does not
    // reject once all its candidates miss, a goto repetition, or a repetition without a maximum.
    // This may count an attempt more than once, but never misses its failure.
    bool m_candidateMissRejects = false;
    // Sticky: after an unbounded cycle delay, whose later candidates can still match
    bool m_afterUnboundedDelay = false;
    // A range of counts followed by a later element keeps the earlier lowering, whose merged
    // threads cannot tell the counts apart, and its failures are counted per tick
    bool m_rangeFallback = false;
    bool m_inRangeCandidate = false;  // Building the operand after a ranged cycle delay
    bool m_markStrongPending = false;  // Mark new vertices as strong s_always in-window
    // A cover only records matches, so a pending obligation at $finish is not a failure
    bool m_noEosFailure = false;
    // IEEE 1800-2023 16.14.3 cover sequence: each end-of-match fires the action,
    // not just the first. Builder builds parallel-branch (no first-match-wins)
    // topology when true. Default false preserves cover_property semantics.
    bool m_isCoverSeq = false;
    // Unsupported endpoint topology must reject, not ignore, or the wait hangs
    bool m_isSeqEvent = false;
    bool m_inSequencePrefix = false;  // Prefix composition does not preserve every endpoint
    bool m_wantBoolLeaf = false;  // Building a |-> / |=> or top-level body (see buildOrMerge)
    bool m_trackVacuous = false;  // Record vacuous successes (they fail a negated assertion)
    bool m_atPropEnd = false;  // Building the consequent of a followed-by ending the property
    bool m_hasAndLatch = false;  // An 'and' combines its operands' matches (buildAndCombiner)
    bool m_inAntecedent = false;  // Building an implication antecedent, where nothing fails
    // Building the consequent of an antecedent with an empty match, which keeps merge vertices
    bool m_inEmptyMatchConsequent = false;
    // Building an operand of an 'or' that keeps its merge vertex, whose own 'or's keep theirs
    bool m_inMergeFallback = false;

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
    //  - AstSConsRep [*N], N > 0             -> N * (length of exprp + 1) - 1
    //  - always [M:N] of a boolean           -> N (an operand of a property 'or')
    // Unsupported (returns -1):
    //  - Range delays with M != N            -> variable
    //  - Unbounded waits ##[M:$]             -> infinite/variable
    //  - Ranged or zero ConsRep / SGotoRep / SAnd -> defer (rare in intersect)
    //  - SIntersect nested in SIntersect     -> defer
    //  - Property operands such as implications
    static int fixedLength(AstNodeExpr* nodep) {
        if (const AstPropAlways* const alwaysp = VN_CAST(nodep, PropAlways)) {
            if (VN_IS(alwaysp->hiBoundp(), Unbounded) || !isPlainBoolean(alwaysp->propp())) {
                return -1;
            }
            return static_cast<int>(getConstUInt(alwaysp->hiBoundp()));
        }
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
        if (const AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            // IEEE 1800-2023 16.9.2: N back-to-back iterations of exprp; -1 if N is 0 or the
            // length of exprp varies
            // cppcheck-suppress knownConditionTrueFalse
            if (repp->unbounded() || repp->maxCountp()) return -1;
            const int count = static_cast<int>(getConstUInt(repp->countp()));
            return count * (fixedLength(repp->exprp()) + 1) - 1;
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
        // Plain boolean expression (no SVA constructs) -- 0 cycles.
        return isPlainBoolean(nodep) ? 0 : -1;
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
            m_afterUnboundedDelay = true;
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
                // Not for a consecutive repetition, whose candidates reject on their own
                // misses, see m_candidateMissRejects
                const int rhsLen = rhsExprp->exists([](const AstSConsRep*) { return true; })
                                       ? -1
                                       : fixedLength(rhsExprp);
                if (rhsLen >= 0) {
                    *rangeRejectInfop = {currentp, range, rhsLen};
                } else {
                    m_candidateMissRejects = true;
                }
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
            // clear on success, since cover sequence counts every endpoint.
            midSources.push_back(currentp);
            currentp = addDelayChain(currentp, range + 1U, flp, false,
                                     m_isCoverSeq ? nullptr : rhsExprp);
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
        AstSConsRep* preZeroMinp = zeroMinRep(sexprp->preExprp());
        AstSConsRep* zeroMinp = zeroMinRep(exprp);
        if ((preZeroMinp || zeroMinp) && (delayp->isRangeDelay() || (preZeroMinp && zeroMinp))) {
            // Next to a ranged delay, or on both sides of one delay, keep the earlier lowering,
            // whose empty match is a cycle late
            preZeroMinp = nullptr;
            zeroMinp = nullptr;
            m_rangeFallback = true;
        }

        // Handle LHS (preExpr)
        SvaStateVertex* currentp = entryVtxp;
        if (AstNodeExpr* const preExprp = sexprp->preExprp()) {
            // A goto repetition range ends at several occurrences, which the merged threads
            // cannot tell apart, so a later step keeps the earlier lowering
            if (isTopLevelStep && !m_noEosFailure && isGotoRangeTail(sexprp)) {
                m_rangeFallback = true;
            }
            if (isTopLevelStep && !m_noEosFailure && preExprp->exists([](const AstSConsRep* repp) {
                    return repp->maxCountp() != nullptr;
                })) {
                // Inside the candidates of a ranged delay the alternatives of each would fail
                // the attempt on their own, while the earlier lowering merges the candidates
                if (rangeTailRep(sexprp) && !m_inRangeCandidate) {
                    return buildConsRepRangeTail(sexprp, entryVtxp);
                }
                m_rangeFallback = true;
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
            VL_RESTORER(m_inRangeCandidate);
            if (delayp->isRangeDelay()) m_inRangeCandidate = true;
            const BuildResult result = buildExpr(exprp, currentp, isTopLevelStep);
            if (result.valid()) addFiniteRangeReject(rangeRejectInfo, result, flp);
            return result;
        }
        return {currentp, exprp, std::move(rangeMidSources)};
    }

    // The repetition of a consecutive repetition range of a boolean followed by `##0 g` or
    // `##1 g`, g a boolean, in sexprp, also after a leading fixed delay, which
    // buildConsRepRangeTail lowers, or nullptr. Another form keeps the earlier lowering, whose
    // merged end points reject when one count fails the later element.
    static AstSConsRep* rangeTailRep(AstSExpr* sexprp) {
        AstNodeExpr* preExprp = sexprp->preExprp();
        if (const AstSExpr* const leadp = VN_CAST(preExprp, SExpr)) {
            const AstDelay* const leadDelayp = VN_AS(leadp->delayp(), Delay);
            if (!leadp->preExprp() && !leadDelayp->isRangeDelay()) preExprp = leadp->exprp();
        }
        AstSConsRep* const repp = VN_CAST(preExprp, SConsRep);
        const AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
        if (!repp || !repp->maxCountp() || repp->exprp()->isMultiCycleSva()
            || delayp->isRangeDelay() || getConstUInt(delayp->lhsp()) > 1
            || sexprp->exprp()->isMultiCycleSva()) {
            return nullptr;
        }
        return repp;
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
        SvaStateVertex* startp = entryVtxp;
        if (const AstSExpr* const leadp = VN_CAST(sexprp->preExprp(), SExpr)) {
            const AstDelay* const leadDelayp = VN_AS(leadp->delayp(), Delay);
            if (!leadp->preExprp() && !leadDelayp->isRangeDelay()) {
                // Start from a plain vertex, as a delay ring end cannot carry the throughout
                startp = scopedCreateVertex();
                guardedLink(addDelayChain(entryVtxp, getConstUInt(leadDelayp->lhsp()), flp),
                            startp, flp);
            }
        }
        AstSConsRep* const repp = rangeTailRep(sexprp);
        UASSERT_OBJ(repp, sexprp, "Repetition range tail of another form");
        const AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
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
        // Multi-cycle expr in ConsRep not yet supported; bail to avoid invalid AST.
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

        // Only an outermost required step rejects the property. After an unbounded cycle delay
        // a miss is local to one candidate, as a later one can still match.
        const bool rejectsOnMiss
            = isTopLevelStep
              && (!m_inUnboundedScope || (m_candidateMissRejects && !m_afterUnboundedDelay));
        SvaStateVertex* currentp = entryVtxp;
        for (unsigned i = 0; i < minN; ++i) {
            // Keep the first repetition explicit, collapse all remaining checks into the ring.
            if (i == 1) {
                currentp = addDelayChain(currentp, minN - 1, flp);
                currentp->m_delayRingClearCondp
                    = new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)};
                currentp->m_replayAbortReject = true;
                if (rejectsOnMiss) {
                    currentp->m_throughoutConds.push_back(
                        sampledRefOrClone(hoistVarp, exprp, flp));
                }
                i = minN - 1;
            }
            // Every repetition in the minimum prefix is required.
            SvaStateVertex* const condVtxp = scopedCreateVertex();
            SvaTransEdge* const linkp
                = guardedLink(currentp, condVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
            // The first check rejects explicitly, later required checks reject through the
            // ring's throughout guard.
            if (rejectsOnMiss && i == 0) linkp->m_rejectOnFail = true;
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
            m_candidateMissRejects = true;
        } else if (repp->maxCountp()) {
            const unsigned maxN = getConstUInt(repp->maxCountp());
            SvaStateVertex* const mergeVtxp = scopedCreateVertex();
            guardedLink(currentp, mergeVtxp, flp);
            unsigned tailMinN = minN;
            SvaStateVertex* tailStartp = currentp;
            if (minN == 0) {
                // Build the first optional iteration explicitly. Feeding the empty endpoint
                // directly into a range ring would incorrectly keep that match alive.
                SvaStateVertex* const nextVtxp = scopedCreateVertex();
                guardedEdge(currentp, nextVtxp, flp);
                SvaStateVertex* const checkVtxp = scopedCreateVertex();
                guardedLink(nextVtxp, checkVtxp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
                guardedLink(checkVtxp, mergeVtxp, flp);
                if (m_isCoverSeq) consMidSources.push_back(checkVtxp);
                tailStartp = checkVtxp;
                tailMinN = 1;
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
            // end-of-trace obligation (weak). The self-loop keeps the attempt live
            // every cycle; each observed cycle is a safety obligation, so a false p
            // rejects immediately.
            UASSERT_OBJ(!nodep->isStrong(), nodep, "Unbounded always must be weak (V3Width)");
            SvaStateVertex* const livep = addDelayChain(entryVtxp, lo, flp);
            livep->m_isUnbounded = true;
            guardedEdge(livep, livep, flp);  // stay active every subsequent cycle
            SvaStateVertex* const sinkp = m_graph.createStateVertex();
            sinkp->m_isRejectSink = true;
            SvaTransEdge* const rejEdgep
                = guardedLink(livep, sinkp, sampled(propp->cloneTreePure(false)), flp);
            if (isTopLevelStep) rejEdgep->m_rejectOnFail = true;
            return {livep, nullptr, {}};
        }
        const unsigned hi = getConstUInt(nodep->hiBoundp());
        // Strong s_always[m:n]: mark every in-window registered vertex so an
        // attempt still mid-window at end-of-simulation is reported as a liveness
        // failure (IEEE strong: the n+1 ticks must exist). An attempt that has
        // completed earlier in the trace has already cleared its state, so it is
        // not flagged; an attempt whose final tick coincides with $finish is still
        // flagged, matching the strong reference. Weak always[m:n] is not marked.
        VL_RESTORER(m_markStrongPending);
        m_markStrongPending = nodep->isStrong() && !m_noEosFailure;
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
        if (nodep->isStrong() && currentp->m_delayRingSize) currentp->m_strongAlwaysRing = true;
        m_temporalGuardStack.pop_back();
        return {currentp, propp, {}};
    }

    BuildResult buildGotoRep(AstSGotoRep* repp, SvaStateVertex* entryVtxp) {
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
        if (m_rangeFallback) {
            // The earlier lowering, which looks for the first occurrence from the next tick
            guardedEdge(entryVtxp, waitVtxp, flp);
            guardedEdge(waitVtxp, waitVtxp,
                        new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)}, flp);
            guardedLink(waitVtxp, currentp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
        } else {
            for (SvaStateVertex* const fromp : {entryVtxp, waitVtxp}) {
                guardedEdge(fromp, waitVtxp,
                            new AstLogNot{flp, sampledRefOrClone(hoistVarp, exprp, flp)}, flp);
                guardedLink(fromp, currentp, sampledRefOrClone(hoistVarp, exprp, flp), flp);
            }
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
        if (maxN == minN) {
            if (m_rangeFallback) {
                // The earlier lowering, see m_rangeFallback
                currentp->m_isUnbounded = true;
                m_inUnboundedScope = true;
                m_candidateMissRejects = true;
            }
            return {currentp, nullptr, {}};
        }

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
        m_candidateMissRejects = true;
        return {mergeVtxp, nullptr, {}};
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

    // Collect the operands of nested sequence 'or's
    static void collectOrOperands(AstNodeExpr* nodep, std::vector<AstNodeExpr*>& out) {
        if (AstSOr* const orp = VN_CAST(nodep, SOr)) {
            collectOrOperands(orp->lhsp(), out);
            collectOrOperands(orp->rhsp(), out);
        } else {
            out.push_back(nodep);
        }
    }
    // Operand of a sequence 'or' of fixed-length sequences of boolean leaves
    struct FixedOrOperand final {
        std::map<int, std::vector<AstNodeExpr*>> checks;  // Leaf checks by clock offset
        int length = 0;  // Offset of its last clock tick
    };
    static constexpr size_t MAX_FIXED_OR_OPERANDS = 4;  // Limits the 2^n operand sets tracked
    static constexpr size_t MAX_FIXED_OR_TRANSITIONS = 1024;  // Limits their transitions
    // Sampled checks of an operand at clock offset 'offset', true if it has none there
    static AstNodeExpr* newOperandCondp(const FixedOrOperand& op, int offset, FileLine* flp) {
        const auto it = op.checks.find(offset);
        if (it == op.checks.end()) return new AstConst{flp, AstConst::BitTrue{}};
        AstNodeExpr* condp = nullptr;
        for (AstNodeExpr* const leafp : it->second) {
            AstNodeExpr* const clonep = sampled(newLeafCondp(leafp));
            condp = condp ? new AstLogAnd{flp, condp, clonep} : clonep;
        }
        return condp;
    }
    // Whether any operand in 'mask' holds at clock offset 'offset'
    static AstNodeExpr* newAnyHoldsp(const std::vector<FixedOrOperand>& ops, unsigned mask,
                                     int offset, FileLine* flp) {
        AstNodeExpr* condp = nullptr;
        for (size_t i = 0; i < ops.size(); ++i) {
            if (!(mask & (1U << i))) continue;
            AstNodeExpr* const opp = newOperandCondp(ops[i], offset, flp);
            condp = condp ? new AstLogOr{flp, condp, opp} : opp;
        }
        return condp;
    }
    // Whether every operand in 'mask' holds at clock offset 'offset', or fails if not 'holds'
    static AstNodeExpr* newAllHoldp(const std::vector<FixedOrOperand>& ops, unsigned mask,
                                    int offset, bool holds, FileLine* flp) {
        AstNodeExpr* condp = nullptr;
        for (size_t i = 0; i < ops.size(); ++i) {
            if (!(mask & (1U << i))) continue;
            AstNodeExpr* opp = newOperandCondp(ops[i], offset, flp);
            if (!holds) opp = new AstLogNot{flp, opp};
            condp = condp ? new AstLogAnd{flp, condp, opp} : opp;
        }
        return condp;
    }
    // Build `s1 or s2 ...` at the end of an asserted property, with fixed-length sequences of
    // boolean leaves as operands, or return an invalid result for other operands
    // The transitions between the sets of operands still matching that buildFixedSeqOrProp
    // makes for an attempt
    static size_t fixedOrTransitions(const std::vector<FixedOrOperand>& ops,
                                     const std::set<int>& offsets) {
        size_t transitions = 0;
        std::set<unsigned> live{(1U << ops.size()) - 1};
        for (auto it = offsets.begin(); !live.empty(); ++it) {
            unsigned checkedMask = 0;
            for (size_t i = 0; i < ops.size(); ++i) {
                if (ops[i].checks.count(*it)) checkedMask |= 1U << i;
            }
            std::set<unsigned> next;
            for (const unsigned mask : live) {
                unsigned endedMask = 0;
                for (size_t i = 0; i < ops.size(); ++i) {
                    if ((mask & (1U << i)) && ops[i].length == *it) endedMask |= 1U << i;
                }
                const unsigned contMask = mask & ~endedMask;
                const unsigned uncheckedMask = contMask & ~checkedMask;
                for (unsigned checkedSub = contMask & checkedMask;;
                     checkedSub = (checkedSub - 1) & contMask & checkedMask) {
                    if (const unsigned sub = checkedSub | uncheckedMask) {
                        ++transitions;
                        next.insert(sub);
                    }
                    if (!checkedSub) break;
                }
            }
            live = std::move(next);
        }
        return transitions;
    }
    BuildResult buildFixedSeqOrProp(AstNodeExpr* lhsp, AstNodeExpr* rhsp,
                                    SvaStateVertex* entryVtxp, FileLine* flp) {
        // It holds when any operand matches, and fails once all have failed (IEEE 1800-2023
        // 16.9.7, 16.12.2). The operands of an attempt start together and have fixed lengths, so
        // at each clock offset track the set of operands of the attempt still matching. Offsets
        // with no check and no end leave the set unchanged, so a delay ring skips them.
        std::vector<AstNodeExpr*> opps;
        collectOrOperands(lhsp, opps);
        collectOrOperands(rhsp, opps);
        if (opps.size() > MAX_FIXED_OR_OPERANDS) return BuildResult::fail();
        std::vector<FixedOrOperand> ops(opps.size());
        std::set<int> offsets{0};  // Offsets of the start, and where an operand checks or ends
        // A strong always also fails at the end of simulation before its last tick (IEEE
        // 1800-2023 16.12.11)
        unsigned strongMask = 0;
        for (size_t i = 0; i < opps.size(); ++i) {
            const AstPropAlways* const alwaysp = VN_CAST(opps[i], PropAlways);
            // cppcheck-suppress knownConditionTrueFalse
            if (alwaysp && alwaysp->isStrong() && !m_noEosFailure) strongMask |= 1U << i;
            if (!flattenFixedSeq(opps[i], 0, ops[i].checks)) return BuildResult::fail();
            for (const auto& offsetChecks : ops[i].checks) offsets.insert(offsetChecks.first);
            // The offset of the last check, also of an implication of one tick
            ops[i].length = ops[i].checks.empty() ? 0 : ops[i].checks.rbegin()->first;
            offsets.insert(ops[i].length);
        }
        // More transitions keep the merge vertex, as an 'or' that is not of fixed-length operands
        if (fixedOrTransitions(ops, offsets) > MAX_FIXED_OR_TRANSITIONS)
            return BuildResult::fail();
        SvaStateVertex* const matchVtxp = scopedCreateVertex();
        SvaStateVertex* const sinkVtxp = m_graph.createStateVertex();
        sinkVtxp->m_isRejectSink = true;
        // The operand sets an attempt can move to number up to 3^n per checked offset, so their
        // transitions are bounded
        size_t transitions = 0;
        // Vertices of the current offset, by the set of operands still matching
        std::map<unsigned, SvaStateVertex*> livep;
        livep[(1U << ops.size()) - 1] = entryVtxp;
        for (auto it = offsets.begin(); !livep.empty(); ++it) {
            const int offset = *it;
            unsigned checkedMask = 0;
            for (size_t i = 0; i < ops.size(); ++i) {
                if (ops[i].checks.count(offset)) checkedMask |= 1U << i;
            }
            // Vertices entering the delay to the next offset, by the set of operands holding
            std::map<unsigned, SvaStateVertex*> holdp;
            for (const auto& maskVtx : livep) {
                const unsigned mask = maskVtx.first;
                SvaStateVertex* const fromp = maskVtx.second;
                // The attempt fails when no operand still matching holds
                m_graph.addLink(fromp, sinkVtxp, newAnyHoldsp(ops, mask, offset, flp))
                    ->m_rejectOnFail
                    = true;
                // It matches when an operand ending here holds
                unsigned endedMask = 0;
                for (size_t i = 0; i < ops.size(); ++i) {
                    if ((mask & (1U << i)) && ops[i].length == offset) endedMask |= 1U << i;
                }
                if (endedMask) {
                    guardedLink(fromp, matchVtxp, newAnyHoldsp(ops, endedMask, offset, flp), flp);
                }
                // Otherwise it continues with the operands that hold. An operand with no check
                // here holds.
                const unsigned contMask = mask & ~endedMask;
                const unsigned uncheckedMask = contMask & ~checkedMask;
                for (unsigned checkedSub = contMask & checkedMask;;
                     checkedSub = (checkedSub - 1) & contMask & checkedMask) {
                    const unsigned sub = checkedSub | uncheckedMask;
                    if (sub) {
                        ++transitions;
                        AstNodeExpr* condp = newAllHoldp(ops, sub, offset, true, flp);
                        if (const unsigned failMask = (contMask & ~sub) | endedMask) {
                            condp = new AstLogAnd{flp, condp,
                                                  newAllHoldp(ops, failMask, offset, false, flp)};
                        }
                        SvaStateVertex*& toVtxp = holdp[sub];
                        if (!toVtxp) toVtxp = scopedCreateVertex();
                        guardedLink(fromp, toVtxp, condp, flp);
                    }
                    if (!checkedSub) break;
                }
            }
            std::map<unsigned, SvaStateVertex*> nextp;
            for (const auto& subVtx : holdp) {
                const unsigned gap = static_cast<unsigned>(*std::next(it) - offset);
                // The attempt fails at the end of simulation while only strong operands remain
                VL_RESTORER(m_markStrongPending);
                m_markStrongPending = !(subVtx.first & ~strongMask);
                subVtx.second->m_strongPending = m_markStrongPending;
                SvaStateVertex* const nextVtxp = addDelayChain(subVtx.second, gap, flp);
                if (m_markStrongPending && nextVtxp->m_delayRingSize) {
                    nextVtxp->m_strongAlwaysRing = true;
                }
                nextp[subVtx.first] = nextVtxp;
            }
            livep = std::move(nextp);
        }
        V3Stats::addStatSum("Assertions, NFA 'or' operand set transitions", transitions);
        return {matchVtxp, nullptr, {}};
    }
    // The conjunction of the checks of a sequence of boolean leaves with no cycle delay, or
    // nullptr for other sequences
    static AstNodeExpr* newZeroLengthCondp(AstNodeExpr* nodep, FileLine* flp) {
        std::map<int, std::vector<AstNodeExpr*>> checks;
        if (!flattenFixedSeq(nodep, 0, checks) || checks.size() != 1 || checks.count(0) != 1) {
            return nullptr;
        }
        AstNodeExpr* condp = nullptr;
        for (AstNodeExpr* const leafp : checks[0]) {
            AstNodeExpr* const clonep = newLeafCondp(leafp);
            condp = condp ? new AstLogAnd{flp, condp, clonep} : clonep;
        }
        return condp;
    }
    // Whether an operand of 'or' is a property rather than a sequence (IEEE 1800-2023 16.12)
    static bool isPropertyOperand(const AstNode* const nodep) {
        return nodep->exists([](const AstNodeExpr* const np) {
            const AstLogNot* const notp = VN_CAST(np, LogNot);
            return VN_IS(np, Implication) || VN_IS(np, Until) || VN_IS(np, PropAlways)
                   || VN_IS(np, SEventually) || VN_IS(np, AbortOn)
                   || (notp && notp->lhsp()->exists([](const AstNodeExpr* const exprp) {
                          return exprp->isMultiCycleSva();
                      }));
        });
    }
    // Whether `b or p`, with b boolean, keeps the merge vertex of an 'or' instead of
    // buildBoolOrProp, which does not see an attempt in which both operands fail. An 'always' of
    // more than two ticks rejects through a delay ring, which would count the failures of the
    // attempts entering p on different ticks once per tick. A ranged or unbounded end rejects
    // through its ring at the match vertex, which p does not reach, and the attempts in an
    // unbounded state share it, so they would fail together once, and so does an accept_on,
    // whose acceptance ends p at any tick. A 'not' of a multi-cycle sequence is no boolean leaf.
    static bool boolOrKeepsMerge(const AstNodeExpr* boolp, const AstNodeExpr* propp) {
        if (VN_IS(boolp, Const)) return false;
        if (VN_IS(propp, LogNot)
            && propp->exists([](const AstNodeExpr* np) { return np->isMultiCycleSva(); })) {
            return true;
        }
        return propp->exists([](const AstNode* np) {
            if (const AstAbortOn* const abortp = VN_CAST(np, AbortOn)) {
                return abortp->kind().isAccept();
            }
            if (const AstPropAlways* const alwaysp = VN_CAST(np, PropAlways)) {
                return VN_IS(alwaysp->hiBoundp(), Unbounded)
                       || getConstUInt(alwaysp->hiBoundp()) - getConstUInt(alwaysp->loBoundp())
                              > 1;
            }
            if (const AstDelay* const delayp = VN_CAST(np, Delay)) return delayp->isRangeDelay();
            if (const AstSConsRep* const repp = VN_CAST(np, SConsRep)) {
                return repp->maxCountp() || repp->unbounded();
            }
            return VN_IS(np, SGotoRep) || VN_IS(np, SNonConsRep) || VN_IS(np, SEventually)
                   || VN_IS(np, Until);
        });
    }

    // Build `b or p` at the end of an asserted property, with b boolean
    BuildResult buildBoolOrProp(AstNodeExpr* boolp, AstNodeExpr* propp, SvaStateVertex* entryVtxp,
                                FileLine* flp) {
        // It holds at once when b holds and otherwise exactly when p does (IEEE 1800-2023
        // 16.12.4). So p is evaluated only when b is false, with the rejections of a top-level
        // property.
        // In a negated property, a success through b would not be counted with the vacuous
        // successes of an implication in p, which fail it too.
        const AstImplication* implp = nullptr;
        if (m_trackVacuous) {
            propp->exists([&implp](const AstImplication* np) {
                if (!np->isFollowedBy()) implp = np;
                return implp != nullptr;
            });
        }
        if (implp) {
            implp->v3warn(E_UNSUPPORTED, "Unsupported: implication inside another property "
                                         "operator in a negated property.");
            return BuildResult::failWithError();
        }
        VL_RESTORER(m_wantBoolLeaf);
        m_wantBoolLeaf = true;
        // A constant b holds on every attempt, or never so that only p decides
        if (const AstConst* const constp = VN_CAST(boolp, Const)) {
            if (constp->isZero()) return buildExpr(propp, entryVtxp, /*isTopLevelStep=*/true);
            return {entryVtxp, boolp->cloneTreePure(false), {}};
        }
        SvaStateVertex* const propEntryp = scopedCreateVertex();
        guardedLink(entryVtxp, propEntryp,
                    new AstLogNot{flp, sampled(boolp->cloneTreePure(false))}, flp);
        const BuildResult prop = buildExpr(propp, propEntryp, /*isTopLevelStep=*/true);
        if (!prop.valid()) return prop;
        SvaStateVertex* const propTermp = prop.termVertexp;
        UASSERT_OBJ(prop.midSources.empty() && !propTermp->m_isUnbounded, propp,
                    "Ranged or unbounded end of a property 'or' operand");
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
        // An attempt fails once every operand fails (IEEE 1800-2023 16.9.7), which the merge
        // vertex below does not see. Nothing fails in a cover, an event control or an
        // antecedent.
        const bool canFail
            = !m_noEosFailure && !m_isSeqEvent && !m_inAntecedent && !m_inMergeFallback;
        // Where the attempt can fail, a disjunction that holds or fails at once must reject
        const bool foldBool = wantBoolLeaf || (canFail && !m_inEmptyMatchConsequent);
        if (foldBool) {
            // Operands with no cycle delay hold or fail at once, as the boolean OR-fold below
            if (AstNodeExpr* const lhsCondp = newZeroLengthCondp(lhsp, flp)) {
                if (AstNodeExpr* const rhsCondp = newZeroLengthCondp(rhsp, flp)) {
                    return {entryVtxp, new AstLogOr{flp, lhsCondp, rhsCondp}, {}};
                }
                VL_DO_DANGLING(lhsCondp->deleteTree(), lhsCondp);
            }
        }
        if (canFail && wantBoolLeaf && (!isPlainBoolean(lhsp) || !isPlainBoolean(rhsp))) {
            const BuildResult fixedOr = buildFixedSeqOrProp(lhsp, rhsp, entryVtxp, flp);
            if (fixedOr.valid() || fixedOr.errorEmitted) return fixedOr;
            if (isPlainBoolean(lhsp) && isPropertyOperand(rhsp) && !boolOrKeepsMerge(lhsp, rhsp)) {
                return buildBoolOrProp(lhsp, rhsp, entryVtxp, flp);
            }
            if (isPlainBoolean(rhsp) && isPropertyOperand(lhsp) && !boolOrKeepsMerge(rhsp, lhsp)) {
                return buildBoolOrProp(rhsp, lhsp, entryVtxp, flp);
            }
        }
        // Other operands meet at a merge vertex, which does not see an attempt in which every
        // operand fails: such an attempt is not reported (a limit). Their own 'or's keep their
        // merge vertices too, as an operand rejecting alone would fail the attempt.
        VL_RESTORER(m_inMergeFallback);
        if (canFail && (!isPlainBoolean(lhsp) || !isPlainBoolean(rhsp))) m_inMergeFallback = true;
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
        if (booleanOnly && foldBool) {
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
            if (lhs.finalCondp) {
                guardedLink(lhs.termVertexp, mergeVtxp,
                            sampled(lhs.finalCondp->cloneTreePure(false)), flp);
            } else {
                guardedLink(lhs.termVertexp, mergeVtxp, flp);
            }
            if (rhs.finalCondp) {
                guardedLink(rhs.termVertexp, mergeVtxp,
                            sampled(rhs.finalCondp->cloneTreePure(false)), flp);
            } else {
                guardedLink(rhs.termVertexp, mergeVtxp, flp);
            }
        }
        freeUnlinkedCondp(lhs.finalCondp);
        freeUnlinkedCondp(rhs.finalCondp);
        return {mergeVtxp, nullptr, {}};
    }

    // Vertex active the given number of ticks after the operand matched
    SvaStateVertex* delayedMatchVertex(const BuildResult& operand, unsigned ticks, FileLine* flp) {
        SvaStateVertex* const matchVtxp = scopedCreateVertex();
        if (operand.finalCondp) {
            guardedLink(operand.termVertexp, matchVtxp,
                        sampled(operand.finalCondp->cloneTreePure(false)), flp);
        } else {
            guardedLink(operand.termVertexp, matchVtxp, flp);
        }
        return addDelayChain(matchVtxp, ticks, flp);
    }

    // Build combiner for SAnd/SIntersect (IEEE 1800-2023 16.9.5), with done-latches for
    // operands of variable length.
    BuildResult buildAndCombiner(AstNodeExpr* lhsExprp, AstNodeExpr* rhsExprp,
                                 SvaStateVertex* entryVtxp, FileLine* flp) {
        m_hasAndLatch = true;
        // Snapshot-restore scope so LHS liveness does not leak into RHS.
        const bool savedScope = m_inUnboundedScope;
        const bool savedAfterDelay = m_afterUnboundedDelay;
        const BuildResult lhs = buildExpr(lhsExprp, entryVtxp);
        const bool lhsScope = m_inUnboundedScope;
        const bool lhsAfterDelay = m_afterUnboundedDelay;
        m_inUnboundedScope = savedScope;
        m_afterUnboundedDelay = savedAfterDelay;
        const BuildResult rhs = buildExpr(rhsExprp, entryVtxp);
        const bool rhsScope = m_inUnboundedScope;
        m_inUnboundedScope = savedScope || lhsScope || rhsScope;
        m_afterUnboundedDelay = savedAfterDelay || lhsAfterDelay || m_afterUnboundedDelay;
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
        // With fixed lengths, an operand match identifies the start of its attempt, so the
        // shorter operand's match delayed to the composite end pairs with the longer
        // operand's match of the same attempt. A done-latch is shared by overlapping attempts.
        const int lhsLen = fixedLength(lhsExprp);
        const int rhsLen = fixedLength(rhsExprp);
        combVtxp->m_andAligned = lhsLen >= 0 && rhsLen >= 0;
        if (combVtxp->m_andAligned && lhsLen < rhsLen) {
            combVtxp->m_andLhsTermp = delayedMatchVertex(lhs, rhsLen - lhsLen, flp);
        } else {
            combVtxp->m_andLhsTermp = lhs.termVertexp;
            if (lhs.finalCondp) combVtxp->m_andLhsCondp = lhs.finalCondp->cloneTreePure(false);
        }
        if (combVtxp->m_andAligned && rhsLen < lhsLen) {
            combVtxp->m_andRhsTermp = delayedMatchVertex(rhs, lhsLen - rhsLen, flp);
        } else {
            combVtxp->m_andRhsTermp = rhs.termVertexp;
            if (rhs.finalCondp) combVtxp->m_andRhsCondp = rhs.finalCondp->cloneTreePure(false);
        }
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
        if (const AstPropAlways* const alwaysp = VN_CAST(nodep, PropAlways)) {
            // A bounded always of a boolean checks it on each tick of its range
            const int hi = fixedLength(nodep);
            if (hi < 0) return false;
            for (int i = getConstUInt(alwaysp->loBoundp()); i <= hi; ++i) {
                out[baseOffset + i].push_back(alwaysp->propp());
            }
            return true;
        }
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
        if (AstSThroughout* const throughp = VN_CAST(nodep, SThroughout)) {
            // Over a single-cycle sequence, both conditions hold at that tick (IEEE 1800-2023
            // 16.9.9)
            if (fixedLength(throughp->rhsp()) != 0 || !isPlainBoolean(throughp->lhsp())
                || !flattenFixedSeq(throughp->rhsp(), baseOffset, out)) {
                return false;
            }
            out[baseOffset].push_back(throughp->lhsp());
            return true;
        }
        if (const AstImplication* const implp = VN_CAST(nodep, Implication)) {
            // A boolean leaf if single-cycle, see newLeafCondp
            std::map<int, std::vector<AstNodeExpr*>> lhsChecks;
            std::map<int, std::vector<AstNodeExpr*>> rhsChecks;
            if (!implp->isOverlapped() || implp->isFollowedBy()
                || !flattenFixedSeq(implp->lhsp(), 0, lhsChecks)
                || !flattenFixedSeq(implp->rhsp(), 0, rhsChecks) || lhsChecks.size() != 1
                || !lhsChecks.count(0) || rhsChecks.size() != 1 || !rhsChecks.count(0)) {
                return false;
            }
            out[baseOffset].push_back(nodep);
            return true;
        }
        if (!isPlainBoolean(nodep)) return false;
        out[baseOffset].push_back(nodep);
        return true;
    }
    // The condition of a leaf of a fixed-length sequence (see flattenFixedSeq)
    static AstNodeExpr* newLeafCondp(AstNodeExpr* leafp) {
        const AstImplication* const implp = VN_CAST(leafp, Implication);
        if (!implp) return leafp->cloneTreePure(false);
        // A single-cycle overlapped implication holds unless its antecedent holds and its
        // consequent does not (IEEE 1800-2023 16.12.7)
        FileLine* const flp = implp->fileline();
        AstNodeExpr* const notAntp = new AstLogNot{flp, newZeroLengthCondp(implp->lhsp(), flp)};
        notAntp->dtypeSetBit();
        AstNodeExpr* const condp
            = new AstLogOr{flp, notAntp, newZeroLengthCondp(implp->rhsp(), flp)};
        condp->dtypeSetBit();
        return condp;
    }

    // Conjoin two equal-length fixed sequences into one: at each clock offset
    // AND the boolean checks of both operands (IEEE 1800-2023 16.9.6 -- both
    // operands match the same window). Returns null if either operand is not a
    // plain fixed sequence of boolean leaves.
    static AstNodeExpr* conjoinFixedSeqs(AstNodeExpr* lhsp, AstNodeExpr* rhsp, FileLine* flp) {
        std::map<int, std::vector<AstNodeExpr*>> checks;
        if (!flattenFixedSeq(lhsp, 0, checks) || !flattenFixedSeq(rhsp, 0, checks)) return nullptr;
        if (checks.empty()) return nullptr;
        AstNodeExpr* resultp = nullptr;
        int prevOffset = 0;
        for (const auto& offsetChecks : checks) {
            const int offset = offsetChecks.first;
            AstNodeExpr* condp = nullptr;
            for (AstNodeExpr* const leafp : offsetChecks.second) {
                AstNodeExpr* const clonep = newLeafCondp(leafp);
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

    // Whether a thread at vtxp may come through a range delay not under a throughout guard
    static bool afterRangeDelay(const SvaStateVertex* vtxp) {
        std::vector<const SvaStateVertex*> todo{vtxp};
        std::unordered_set<const SvaStateVertex*> seen;
        while (!todo.empty()) {
            const SvaStateVertex* const fromp = todo.back();
            todo.pop_back();
            if (!seen.insert(fromp).second) continue;
            if (fromp->m_delayRingSize && !fromp->m_isFixedDelayRing
                && fromp->m_throughoutConds.empty()) {
                return true;
            }
            for (const V3GraphEdge& edger : fromp->inEdges()) {
                todo.push_back(static_cast<const SvaStateVertex*>(edger.fromp()));
            }
        }
        return false;
    }

    BuildResult buildThroughout(AstSThroughout* nodep, SvaStateVertex* entryVtxp,
                                bool isTopLevelStep = false) {
        // After a range delay, the candidates of an attempt merge, so the guard failing on the
        // last tick of one candidate would fail the attempt while another may still match, as
        // a drop does (see hasThroughoutAfterRange); there the final check is left as it was
        const bool checkFinal = !afterRangeDelay(entryVtxp);
        // Mark entryVtxp so "cond false at tick 0" is detected as throughout-drop.
        entryVtxp->m_throughoutConds.push_back(nodep->lhsp()->cloneTreePure(false));
        m_temporalGuardStack.push_back(nodep->lhsp());
        BuildResult result = buildExpr(nodep->rhsp(), entryVtxp, isTopLevelStep);
        m_temporalGuardStack.pop_back();
        if (!checkFinal) return result;
        // The guard must also hold on the tick of the final check, which without a final
        // condition, as for a within or an and, is the tick the terminal vertex is reached
        if (AstNodeExpr* finalCondp = result.finalCondp) {
            if (finalCondp->backp()) finalCondp = finalCondp->cloneTreePure(false);
            result.finalCondp = new AstLogAnd{nodep->fileline(), finalCondp,
                                              sampled(nodep->lhsp()->cloneTreePure(false))};
        } else if (result.valid()) {
            result.finalCondp = sampled(nodep->lhsp()->cloneTreePure(false));
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
        waitRp->m_strongPending = nodep->isStrong() && !m_noEosFailure;

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
    // Whether an 'and' combines its operands' matches, whose threads of one attempt can each
    // fail
    bool hasAndLatch() const { return m_hasAndLatch; }
    // Whether a miss of one candidate of a range delay in the last part built rejects
    bool candidateMissRejects() const { return m_candidateMissRejects; }
    // Whether a throughout guard outside an antecedent checks threads that came through a range
    // delay before it, where the threads of an attempt's candidates merge and each fails on its
    // own. A range delay under the guard keeps one thread per attempt.
    bool hasThroughoutAfterRange() const {
        std::vector<const SvaStateVertex*> todo;
        for (const V3GraphVertex& vtxr : m_graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            if (vtxp->m_delayRingSize && !vtxp->m_isFixedDelayRing
                && vtxp->m_throughoutConds.empty()) {
                todo.push_back(vtxp);
            }
        }
        std::unordered_set<const SvaStateVertex*> seen;
        while (!todo.empty()) {
            const SvaStateVertex* const vtxp = todo.back();
            todo.pop_back();
            if (!seen.insert(vtxp).second) continue;
            if (!vtxp->m_throughoutConds.empty() && !vtxp->m_isAntecedent) return true;
            for (const V3GraphEdge& edger : vtxp->outEdges()) {
                todo.push_back(static_cast<const SvaStateVertex*>(edger.top()));
            }
        }
        return false;
    }
    // Free a dropped sub-result condition that is not linked into the AST
    // (abort folds synthesize unparented finalCondp trees).
    static void freeUnlinkedCondp(AstNodeExpr* condp) {
        if (condp && !condp->backp()) VL_DO_DANGLING(condp->deleteTree(), condp);
    }

    SvaNfaBuilder(SvaGraph& graph, AstNodeModule* modp, V3UniqueNames& propTempNames,
                  bool isCoverSeq = false, bool isSeqEvent = false, bool noEosFailure = false,
                  bool trackVacuous = false)
        : m_graph{graph}
        , m_modp{modp}
        , m_propTempNames{propTempNames}
        , m_noEosFailure{noEosFailure}
        , m_isCoverSeq{isCoverSeq}
        , m_isSeqEvent{isSeqEvent}
        , m_trackVacuous{trackVacuous} {}

    bool rangeFallback() const { return m_rangeFallback; }
    // Lower the property with the earlier lowering of its ranges of counts, before anything is
    // built (see needsRangeFallback)
    void presetRangeFallback() { m_rangeFallback = true; }
    // True if sexprp follows a goto repetition range with a later element
    static bool isGotoRangeTail(const AstSExpr* sexprp) {
        const AstNodeExpr* const prep = sexprp->preExprp();
        return prep && prep->exists([](const AstSGotoRep* repp) {
            return repp->maxCountp()
                   && getConstUInt(repp->maxCountp()) != getConstUInt(repp->countp());
        });
    }
    // True if a range of counts in bodyp, the body or consequent of a property, keeps its
    // earlier lowering (see m_rangeFallback): a goto repetition range followed by a later
    // element. The whole property is then so lowered, decided before anything is built, as a
    // vertex built before the range would take the other lowering.
    static bool needsRangeFallback(AstNodeExpr* bodyp, AstNodeExpr* antp, bool noEosFailure) {
        // A zero-minimum repetition next to a ranged delay, or on both sides of one delay, in
        // the antecedent too
        const auto zeroMinNextToRange = [](AstSExpr* sexprp) {
            const AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            if (!delayp || !delayp->isCycleDelay()) return false;
            const bool pre = zeroMinRep(sexprp->preExprp());
            const bool post = zeroMinRep(sexprp->exprp());
            return (pre || post) && (delayp->isRangeDelay() || (pre && post));
        };
        if (bodyp->exists(zeroMinNextToRange) || (antp && antp->exists(zeroMinNextToRange))) {
            return true;
        }
        if (noEosFailure) return false;
        // The elements of the operands of ranged delays
        std::unordered_set<const AstSExpr*> candps;
        bodyp->foreach([&](const AstSExpr* sexprp) {
            const AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            if (!delayp || !delayp->isRangeDelay()) return;
            sexprp->exprp()->foreach([&](const AstSExpr* innerp) { candps.insert(innerp); });
        });
        return bodyp->exists([&](AstSExpr* sexprp) {
            if (isGotoRangeTail(sexprp)) return true;
            // A consecutive repetition range followed by a later element, other than the form
            // buildConsRepRangeTail lowers outside the candidates of a ranged delay
            const AstNodeExpr* const prep = sexprp->preExprp();
            return prep && prep->exists([](const AstSConsRep* repp) {
                return repp->maxCountp() != nullptr;
            }) && (!rangeTailRep(sexprp) || candps.count(sexprp));
        });
    }
    // Reset scope between antecedent and consequent: liveness must not leak.
    // m_outerAbortStack survives: an abort wrapping the implication covers the
    // consequent too (IEEE 1800-2023 16.12.14).
    void resetScope() {
        m_inUnboundedScope = false;
        m_candidateMissRejects = false;
        m_afterUnboundedDelay = false;
        m_temporalGuardStack.clear();
    }

    BuildResult buildExpr(AstNodeExpr* nodep, SvaStateVertex* entryVtxp,
                          bool isTopLevelStep = false) {
        VL_RESTORER(m_wantBoolLeaf);
        VL_RESTORER(m_atPropEnd);
        const bool wantBoolLeaf = m_wantBoolLeaf;
        const bool atPropEnd = wantBoolLeaf || m_atPropEnd;
        m_wantBoolLeaf = false;
        m_atPropEnd = false;
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
        if (VN_IS(nodep, SNonConsRep)) return BuildResult::fail();
        if (AstImplication* const implp = VN_CAST(nodep, Implication)) {
            // A vacuous success is a success of the whole property only when nothing follows
            // the implication
            const bool trackVacuous = m_trackVacuous && !implp->isFollowedBy();
            if (trackVacuous && !atPropEnd) {
                implp->v3warn(E_UNSUPPORTED, "Unsupported: implication inside another property "
                                             "operator in a negated property.");
                return BuildResult::failWithError();
            }
            return buildImplicationEdges(
                implp->lhsp(), implp->rhsp(), entryVtxp, implp->isOverlapped(),
                implp->isFollowedBy(), implp->lhsp(), implp->fileline(), trackVacuous, atPropEnd);
        }
        if (AstUntil* const untilp = VN_CAST(nodep, Until)) {
            return buildUntil(untilp, entryVtxp, isTopLevelStep);
        }
        // Boolean leaf (including LogAnd): return as finalCond
        return {entryVtxp, nodep, {}};
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
                                      bool trackVacuous = false, bool atPropEnd = false) {
        // Vertices are appended, so those after the current tail belong to the antecedent
        V3GraphVertex::List& vertices = m_graph.m_graph.vertices();
        const V3GraphVertex* const lastPrep = vertices.backp();
        // entryVtxp can be shared with other operands, so is not marked; instead the
        // guards the antecedent adds to it are removed again below
        std::vector<AstNodeExpr*>& entryConds = entryVtxp->m_throughoutConds;
        const size_t entryCondsNum = entryConds.size();
        const BuildResult antResult = [&] {
            VL_RESTORER(m_inAntecedent);
            m_inAntecedent = true;
            return buildExpr(antExprp, entryVtxp);
        }();
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
                                                  "implication in a negated property.");
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
            SvaTransEdge* const rejectp = m_graph.addLink(antResult.termVertexp, sinkVtxp,
                                                          antMatchp->cloneTreePure(false));
            rejectp->m_rejectOnFail = true;
            rejectp->m_followedByAntecedent = true;
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
        VL_RESTORER(m_atPropEnd);
        VL_RESTORER(m_inEmptyMatchConsequent);
        m_inEmptyMatchConsequent = hasZeroMinRep(antExprp);
        m_wantBoolLeaf = !isFollowedBy && !m_inEmptyMatchConsequent;
        m_atPropEnd = isFollowedBy && atPropEnd;
        return buildExpr(bodyExprp, bodyEntryp, /*isTopLevelStep=*/true);
    }

    BuildResult build(AstNodeExpr* exprp) {
        m_graph.m_startVertexp = scopedCreateVertex();
        VL_RESTORER(m_wantBoolLeaf);
        m_wantBoolLeaf = true;
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

// exprp, a copy of conditions of a property the lowering evaluates again, without their sequence
// match items (IEEE 1800-2023 16.10), so that evaluating it does not run them again. A copy is
// never a bare match item. Takes ownership.
static AstNodeExpr* withoutMatchItemsp(AstNodeExpr* exprp) {
    std::vector<AstExprStmt*> itemps;
    exprp->foreach([&](AstExprStmt* itemp) {
        if (itemp->isMatchItem()) itemps.push_back(itemp);
    });
    // Inner ones first, as an outer one's statements are deleted with it
    for (auto it = itemps.rbegin(); it != itemps.rend(); ++it) {
        AstExprStmt* const itemp = *it;
        itemp->replaceWith(itemp->resultp()->unlinkFrBack());
        VL_DO_DANGLING(itemp->deleteTree(), itemp);
    }
    return exprp;
}

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
        bool trackAntecedentEnd;  // Compute SignalSet::antecedentEndCountp
        bool needSuccessCount;  // Compute SignalSet::successCountp
        bool needRejectCount;  // Compute SignalSet::rejectCountp
        bool exactCounts = false;  // Count threads exactly, each being one attempt
        // With exactCounts, top-level synchronous abort, if any
        const AstAbortOn* exactAbortp = nullptr;
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
    static AstNodeExpr* newOrTree(FileLine* flp, std::vector<AstNodeExpr*>::const_iterator beginIt,
                                  std::vector<AstNodeExpr*>::const_iterator endIt) {
        // A term per NFA step: a left-deep chain would make V3Const quadratic
        if (beginIt == endIt) return nullptr;
        if (endIt - beginIt == 1) return *beginIt;
        const auto midIt = beginIt + (endIt - beginIt) / 2;
        return new AstLogOr{flp, newOrTree(flp, beginIt, midIt), newOrTree(flp, midIt, endIt)};
    }
    static AstNodeExpr* newAddTree(FileLine* flp,
                                   std::vector<AstNodeExpr*>::const_iterator beginIt,
                                   std::vector<AstNodeExpr*>::const_iterator endIt) {
        // Of a nonempty range, balanced as newOrTree
        if (endIt - beginIt == 1) return *beginIt;
        const auto midIt = beginIt + (endIt - beginIt) / 2;
        return new AstAdd{flp, newAddTree(flp, beginIt, midIt), newAddTree(flp, midIt, endIt)};
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
    static AstNodeExpr* delayRingHeadCount(FileLine* flp, const SvaStateVertex* vtxp) {
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
    static AstNodeExpr* delayRingOutputCount(FileLine* const flp,
                                             const SvaStateVertex* const vtxp) {
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
        // Antecedents ending without a match this tick, vacuous successes, if tracked
        AstNodeExpr* antecedentEndCountp = nullptr;
        AstNodeExpr* vacuousp = nullptr;  // Vacuous success of an implication, if tracked
        AstNodeExpr* successCountp = nullptr;  // Matches and vacuous successes on this tick
        // Rejections on this tick, of threads and at the end of the sequence
        AstNodeExpr* rejectCountp = nullptr;
        AstNodeExpr* antecedentRejectp = nullptr;  // A followed-by's antecedent not matching
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
        // Later states first, so that an earlier attempt's match items read the local
        // variables before a later attempt's assign them (IEEE 1800-2023 16.10)
        std::vector<const SvaStateVertex*> vtxps;
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices())
            vtxps.push_back(static_cast<const SvaStateVertex*>(&vtxr));
        for (auto it = vtxps.rbegin(); it != vtxps.rend(); ++it) {
            const SvaStateVertex* const vtxp = *it;
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

    // The rejection of basep, threads reaching the end of the sequence, by its final condition
    static AstNodeExpr* newTerminalRejectp(const LowerCtx& c, AstNodeExpr* basep) {
        if (!c.matchCondp) return basep;
        return new AstLogAnd{c.flp, basep,
                             new AstLogNot{c.flp, sampled(c.matchCondp->cloneTreePure(false))}};
    }
    // Condition under which a rejectOnFail Link keeps its source threads, without the match
    // items of the step, which run where its threads advance
    static AstNodeExpr* newRequiredStepCondp(LowerCtx& c, const SvaTransEdge& tedge) {
        if (!tedge.m_condVtxp) return withoutMatchItemsp(tedge.m_condp->cloneTreePure(false));
        UASSERT_OBJ(tedge.m_condVtxp->datap()->stateSigp, tedge.m_condVtxp,
                    "rejectOnFail condVtxp missing stateSig");
        AstNodeExpr* const condp = tedge.m_condVtxp->datap()->stateSigp->cloneTreePure(false);
        if (!tedge.m_condp) return condp;
        return new AstLogOr{c.flp, condp, withoutMatchItemsp(tedge.m_condp->cloneTreePure(false))};
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
                guardp = guardp ? static_cast<AstNodeExpr*>(new AstLogAnd{c.flp, guardp, sp}) : sp;
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
                                 std::map<int, AstNodeExpr*>& vertexFailps) {
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
                AstNodeExpr*& vertexFailp = vertexFailps[vtxp->color()];
                vertexFailp = orExprs(c.flp, vertexFailp,
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
            sigs.throughoutRejectp = orExprs(c.flp, sigs.throughoutRejectp,
                                             new AstLogAnd{c.flp, stateExprp, rejectCondp});
        }
    }

    // The number of attempts whose antecedent of the implication of the property ends without
    // a match on this tick, which then succeed vacuously (IEEE 1800-2023 16.12.7): with one
    // thread per attempt, a thread of the antecedent, or an attempt starting, that no transition
    // continues, or the threads of a fixed delay ring cleared. Nullptr if the antecedent has a
    // vertex of another kind.
    AstNodeExpr* newAntecedentEndCountp(LowerCtx& c) {
        // From zero, for an antecedent that only ends matching
        std::vector<AstNodeExpr*> endps{newTypedConstp(c.flp, m_u32DTypep, 0)};
        const auto fail = [&]() {
            for (AstNodeExpr* const endp : endps) VL_DO_DANGLING(endp->deleteTree(), endp);
            return nullptr;
        };
        const auto oneIfp = [&](AstNodeExpr* condp) {
            return new AstCond{c.flp, condp, newTypedConstp(c.flp, m_u32DTypep, 1),
                               newTypedConstp(c.flp, m_u32DTypep, 0)};
        };
        for (const V3GraphVertex& vtxr : c.graph.m_graph.vertices()) {
            const SvaStateVertex* const vtxp = static_cast<const SvaStateVertex*>(&vtxr);
            if (!vtxp->m_isAntecedent && vtxp != c.graph.m_startVertexp) continue;
            // A ring not advancing on a tick keeps the thread at its output
            if (vtxp->m_isAndCombiner || !vtxp->m_throughoutConds.empty() || vtxp->m_abortClearp
                || vtxp->m_abortRejectp || (vtxp->m_delayRingSize && !vtxp->m_isFixedDelayRing)
                || vtxp->m_delayRingAdvanceCondp) {
                return fail();
            }
            // The threads of the ring, beside the one at its output
            if (vtxp->m_delayRingSize && vtxp->m_delayRingClearCondp) {
                AstVar* const liveCountVarp = vtxp->datap()->delayRingLiveCountVarp;
                AstNodeExpr* const clearedp
                    = new AstSub{c.flp, new AstVarRef{c.flp, liveCountVarp, VAccess::READ},
                                 delayRingOutputCount(c.flp, vtxp)};
                endps.push_back(
                    new AstCond{c.flp, sampled(vtxp->m_delayRingClearCondp->cloneTreePure(false)),
                                new AstExtend{c.flp, clearedp, m_u32DTypep->width()},
                                newTypedConstp(c.flp, m_u32DTypep, 0)});
            }
            bool alwaysContinues = false;
            for (const V3GraphEdge& edger : vtxp->outEdges()) {
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                if (tedger.m_condVtxp) return fail();
                if (!tedger.m_condp) {
                    alwaysContinues = true;
                    break;
                }
            }
            if (alwaysContinues) continue;
            AstNodeExpr* continuesp = new AstConst{c.flp, AstConst::BitFalse{}};
            for (const V3GraphEdge& edger : vtxp->outEdges()) {
                const SvaTransEdge& tedger = static_cast<const SvaTransEdge&>(edger);
                continuesp = new AstLogOr{
                    c.flp, continuesp, withoutMatchItemsp(tedger.m_condp->cloneTreePure(false))};
            }
            AstNodeExpr* const statep = vtxp->datap()->stateSigp->cloneTreePure(false);
            endps.push_back(
                oneIfp(new AstLogAnd{c.flp, statep, new AstLogNot{c.flp, continuesp}}));
        }
        AstNodeExpr* const countp = newAddTree(c.flp, endps.cbegin(), endps.cend());
        AstNodeExpr* livep = notKillActive(c);
        if (c.disableExprp) {
            livep = new AstLogAnd{c.flp, livep,
                                  new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)}};
        }
        return new AstCond{c.flp, livep, countp, newTypedConstp(c.flp, m_u32DTypep, 0)};
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
                             const bool needThroughoutThreadFailCount, const bool needMatchCount,
                             const bool countAttempts) {
        SignalSet sigs;

        // Exact counts always count failures, from zero
        if (c.exactCounts) sigs.threadFailCountp = newTypedConstp(c.flp, m_u32DTypep, 0);
        // Each terminal thread fails when the final condition is false.
        AstNodeExpr* terminalCountp = nullptr;
        // Not a final condition that a later pass lowers, as of an 's_eventually'
        const bool needTerminalCount = needThroughoutThreadFailCount && c.matchCondp
                                       && !c.matchCondp->exists([](const AstNodeExpr* np) {
                                              return np->isMultiCycleSva();
                                          });
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
        // A thread failing several checks on one tick, such as its next step and a throughout
        // guard, is one rejected thread, so count the rejections by source vertex.
        std::map<int, AstNodeExpr*> vertexFailps;
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
                AstNodeExpr*& vertexFailp = vertexFailps[fromVtxp->color()];
                vertexFailp = orExprs(c.flp, vertexFailp, rawFailp->cloneTreePure(false));
            }
            AstNodeExpr* const failp = gateNotKill(c, rawFailp);
            if (tedgep->m_followedByAntecedent) {
                sigs.antecedentRejectp
                    = orExprs(c.flp, sigs.antecedentRejectp, failp->cloneTreePure(false));
            }
            sigs.requiredStepRejectp = orExprs(c.flp, sigs.requiredStepRejectp, failp);
        }

        computeThroughoutReject(c, sigs, needThroughoutThreadFailCount, vertexFailps);
        for (const auto& it : vertexFailps) {
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
            if (c.needSuccessCount) {
                vacuousCountp = addCountp(
                    c.flp, vacuousCountp,
                    new AstExtend{c.flp, sigp->cloneTreePure(false), m_u32DTypep->width()});
            }
        }
        sigs.vacuousp = gateNotKill(c, sigs.vacuousp);
        sigs.rejectBasep = gateNotKill(c, sigs.rejectBasep);
        sigs.throughoutRejectp = gateNotKill(c, sigs.throughoutRejectp);

        if (c.trackAntecedentEnd) sigs.antecedentEndCountp = newAntecedentEndCountp(c);

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
            if (sigs.antecedentRejectp) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.antecedentRejectp = new AstLogAnd{c.flp, sigs.antecedentRejectp, notDisp};
            }
            if (sigs.vacuousp) {
                AstNodeExpr* const notDisp
                    = new AstLogNot{c.flp, c.disableExprp->cloneTreePure(false)};
                sigs.vacuousp = new AstLogAnd{c.flp, sigs.vacuousp, notDisp};
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

        // Matches and vacuous successes of different attempts can coincide; the NFA state
        // aggregates attempts, so the match and each implication count at most once per tick
        if (c.needSuccessCount) {
            AstNodeExpr* matchp = sigs.terminalActivep->cloneTreePure(false);
            if (c.matchCondp) {
                matchp = new AstLogAnd{c.flp, matchp, sampled(c.matchCondp->cloneTreePure(false))};
            }
            sigs.successCountp
                = addCountp(c.flp, nullptr, new AstExtend{c.flp, matchp, m_u32DTypep->width()});
            if (vacuousCountp) {
                sigs.successCountp = addCountp(c.flp, sigs.successCountp, vacuousCountp,
                                               sigs.vacuousp->cloneTreePure(false));
            }
        }
        // The rejected threads, each once, also at the end of the sequence
        if (c.needRejectCount && sigs.threadFailCountp) {
            sigs.rejectCountp = sigs.threadFailCountp->cloneTreePure(false);
        } else if (c.needRejectCount && sigs.rejectBasep) {
            AstNodeExpr* const terminalRejectp
                = newTerminalRejectp(c, sigs.rejectBasep->cloneTreePure(false));
            sigs.rejectCountp = addCountp(
                c.flp, nullptr, new AstExtend{c.flp, terminalRejectp, m_u32DTypep->width()});
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
            AstNodeExpr* matchLp
                = buildMatchNow(c.flp, lhsTermp->datap()->stateSigp, vtxp->m_andLhsCondp);
            AstNodeExpr* matchRp
                = buildMatchNow(c.flp, rhsTermp->datap()->stateSigp, vtxp->m_andRhsCondp);
            if (!vtxp->m_andAligned) {
                // Both operands matched since the attempt started. The done latches are
                // cleared once this holds, so they are never both set and one operand
                // matches now.
                matchLp = new AstLogOr{
                    c.flp, new AstVarRef{c.flp, vtxp->datap()->doneLVarp, VAccess::READ}, matchLp};
                matchRp = new AstLogOr{
                    c.flp, new AstVarRef{c.flp, vtxp->datap()->doneRVarp, VAccess::READ}, matchRp};
            }
            vtxp->datap()->stateSigp = new AstLogAnd{c.flp, matchLp, matchRp};
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
                    AstNodeExpr* const enablep
                        = withoutMatchItemsp(te.m_condp->cloneTreePure(false));
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
                // Without a final condition, reaching a terminal is a match, not a rejection
                AstNodeExpr* notPMatchp = nullptr;
                if (matchCondp && rejectBasep) {
                    AstNodeExpr* const sampledCondp = sampled(matchCondp->cloneTreePure(false));
                    notPMatchp = new AstLogAnd{flp, rejectBasep->cloneTreePure(false),
                                               new AstLogNot{flp, sampledCondp}};
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

    SvaNfaLowering(AstNodeModule* const modp, V3UniqueNames& actionNames)
        : m_modp{modp}
        , m_u32DTypep{modp->findBasicDType(VBasicDTypeKwd::UINT32)}
        , m_actionNames{actionNames} {}
    ~SvaNfaLowering() {
        V3Stats::addStatSum("Assertions, NFA delay ring edge visits", m_statDelayRingEdgeVisits);
        V3Stats::addStatSum("Assertions, NFA link edge visits", m_statLinkEdgeVisits);
    }

    // Lower NFA graph to synthesizable AstAlways blocks and raw result signals.
    // Links are combinational; Edges are registered (NBA).
    SignalSet lower(AstNodeCoverOrAssert* const assertp, SvaGraph& graph,
                    AstSenTree* const senTreep, AstNodeExpr* const matchCondp,
                    AstNodeExpr* const disableExprp, const bool needThreadFailCount,
                    const bool needThroughoutThreadFailCount, const bool trackAntecedentEnd,
                    const bool needSuccessCount = false, const bool needRejectCount = false,
                    const bool exactCounts = false, const AstAbortOn* const exactAbortp = nullptr,
                    const bool countAttempts = false) {
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
                if (vtx[i]->m_andAligned) continue;
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
        LowerCtx c{flp,
                   senTreep,
                   disableExprp,
                   matchCondp,
                   assertType,
                   directiveType,
                   killVarp,
                   graph,
                   trackAntecedentEnd,
                   needSuccessCount,
                   needRejectCount,
                   exactCounts,
                   exactAbortp};

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
        const SignalSet sigs = computeSignals(
            c, needThreadFailCount, needThroughoutThreadFailCount, countMatches, countAttempts);

        // Strong s_always[m:n] end-of-simulation liveness: if any in-window state
        // is still set at $finish, the universal-quantifier window never completed
        // (IEEE 1800-2023 16.12.11 strong semantics). Fire the assertion failure
        // from a final block; V3Assert turns the DT_ERROR display into the standard
        // "Assertion failed in %m" message.
        // pending = |{strong state registers, strong delay live counts != 0};
        AstNodeExpr* pendingp = nullptr;
        for (int i = 0; i < N; ++i) {
            if (!vtx[i]->m_strongPending) continue;
            AstNodeExpr* pendingExprp = nullptr;
            if (vtx[i]->datap()->stateVarp) {
                pendingExprp = new AstVarRef{flp, vtx[i]->datap()->stateVarp, VAccess::READ};
            } else if (vtx[i]->m_strongAlwaysRing) {
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
            // The action block belongs to the directive (IEEE 1800-2023 16.14.6)
            AstNodeStmt* firep;
            AstAssert* const assertNodep = VN_CAST(assertp, Assert);
            if (AstNodeStmt* const failsp = assertNodep ? assertNodep->failsp() : nullptr) {
                firep = V3AssertCommon::cloneAction(failsp, m_actionNames);
            } else {
                AstDisplay* const dispp
                    = new AstDisplay{flp, VDisplayType::DT_ERROR, "", nullptr, nullptr};
                dispp->fmtp()->timeunit(m_modp->timeunit());
                firep = dispp;
                if (v3Global.opt.stopFail()) firep->addNext(new AstStop{flp, false});
            }
            m_modp->addStmtsp(new AstFinal{flp, new AstIf{flp, condp, firep}});
        }

        // Clear userp on every vertex before vertexData is destroyed.
        for (int i = 0; i < N; ++i) vtx[i]->userp(nullptr);
        return sigs;
    }
};

}  // namespace

//######################################################################
// Top-level visitor

class AssertNfaVisitor final : public VNVisitor {
    // STATE
    AstNodeModule* m_modp = nullptr;  // Current module being processed
    AstClocking* m_defaultClockingp = nullptr;  // Default clocking
    AstDefaultDisable* m_defaultDisablep = nullptr;  // Default disable iff
    SvaNfaLowering* m_loweringp = nullptr;  // NFA-to-hardware lowering engine
    AstSenTree* m_sampledValueClockp = nullptr;  // Inherited clock during scoped attachment
    V3UniqueNames m_propTempNames{"__VnfaSampled"};  // Hoisted $sampled(propp) temps
    V3UniqueNames m_failCountNames{"__VnfaRemainingFailCount"};  // Fail replay counter names
    V3UniqueNames m_passCountNames{"__VnfaRemainingPassCount"};  // Pass replay counter names
    // Reactive action temporaries, and automatics of cloned actions
    V3UniqueNames m_actionNames{"__VnfaAction"};
    std::vector<const AstBegin*> m_namedBeginps;  // Named blocks around the current assertion
    AstNode* m_containerp = nullptr;  // Current module or generate block
    bool m_procSuspends = false;  // Current procedure may suspend
    V3AssertReactive m_reactive;  // Makes the actions run in the Reactive region

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

    static bool hasMultiCycleExpr(const AstNode* nodep) {
        return nodep->exists([](const AstNode* np) {
            if (const auto* const ep = VN_CAST(np, NodeExpr)) return ep->isMultiCycleSva();
            return false;
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

    // True if an attempt of a sequence has at most one thread at a time
    static bool oneThreadPerAttempt(const AstNodeExpr* nodep) {
        if (const AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            const AstDelay* const delayp = VN_CAST(sexprp->delayp(), Delay);
            return delayp && !delayp->isRangeDelay()
                   && (!sexprp->preExprp() || oneThreadPerAttempt(sexprp->preExprp()))
                   && oneThreadPerAttempt(sexprp->exprp());
        }
        // A goto repetition repeats a boolean (IEEE 1800-2023 16.9.2); a consecutive repetition
        // of a multi-cycle sequence is reported as unsupported
        if (const AstSGotoRep* const repp = VN_CAST(nodep, SGotoRep)) return !repp->maxCountp();
        if (const AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            // cppcheck-suppress knownConditionTrueFalse
            return !repp->maxCountp() && !repp->unbounded();
        }
        // A boolean
        return !nodep->exists([](const AstNodeExpr* exprp) { return exprp->isMultiCycleSva(); });
    }

    // Prefix stmtsp, the pass actions of attempts passing on a tick when another attempt fails,
    // to the fail action, once per assertion. The fail control applies to the fail action only
    // (IEEE 1800-2023 20.11), so it is gated here instead of by V3Assert.
    static void prependPassToFail(AstAssert* const assertp, AstNodeStmt* const stmtsp) {
        // finishDirective gave an assertion with a pass action a fail action
        AstNodeStmt* const failsp = assertp->failsp()->unlinkFrBackWithNext();
        assertp->addFailsp(newIfAssertFailOn(failsp, assertp->directive(), assertp->userType()));
        assertp->failsGated(true);
        assertp->prependFailsp(stmtsp);
    }
    // The fail action of an assertion without one
    AstNodeStmt* newDefaultFailp(FileLine* flp) const {
        // V3Assert turns the DT_ERROR display into the standard "Assertion failed in %m"
        AstDisplay* const dispp
            = new AstDisplay{flp, VDisplayType::DT_ERROR, "'assert' failed.", nullptr, nullptr};
        dispp->fmtp()->timeunit(m_modp->timeunit());
        // %m names the assertion's scope also where its fail action is replayed
        dispp->fmtp()->scopeNamep(new AstScopeName{flp, true});
        AstNodeStmt* const stmtsp = dispp;
        if (v3Global.opt.stopFail()) stmtsp->addNext(new AstStop{flp, false});
        return stmtsp;
    }

    AstNodeDType* u32DTypep() const { return m_modp->findBasicDType(VBasicDTypeKwd::UINT32); }
    // One if condp holds, else zero
    AstNodeExpr* newCountp(FileLine* flp, AstNodeExpr* condp) const {
        return new AstCond{flp, condp, newTypedConstp(flp, u32DTypep(), 1),
                           newTypedConstp(flp, u32DTypep(), 0)};
    }
    // Run the pass action once for each of countp attempts succeeding on this tick, from a
    // count taken before the action, which may suspend
    void addCountedPassActions(AstAssert* const assertp, AstNodeExpr* countp) {
        FileLine* const flp = assertp->fileline();
        countp = withoutMatchItemsp(countp);
        AstNodeStmt* const passsp = assertp->passsp()->unlinkFrBackWithNext();
        AstVar* const countVarp
            = new AstVar{flp, VVarType::MODULETEMP, m_passCountNames.get(""), u32DTypep()};
        countVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        m_modp->addStmtsp(countVarp);
        AstNodeStmt* const stmtsp = new AstAssign{
            flp, new AstVarRef{flp, countVarp, VAccess::WRITE}, countp->cloneTreePure(false)};
        AstLoop* const loopp = new AstLoop{flp};
        loopp->addStmtsp(
            new AstLoopTest{flp, loopp,
                            new AstGt{flp, new AstVarRef{flp, countVarp, VAccess::READ},
                                      newTypedConstp(flp, countVarp->dtypep(), 0)}});
        loopp->addStmtsp(passsp);
        loopp->addStmtsp(
            new AstAssign{flp, new AstVarRef{flp, countVarp, VAccess::WRITE},
                          new AstSub{flp, new AstVarRef{flp, countVarp, VAccess::READ},
                                     newTypedConstp(flp, countVarp->dtypep(), 1)}});
        stmtsp->addNext(loopp);
        AstIf* const ifp = new AstIf{
            flp, new AstNeq{flp, countp, newTypedConstp(flp, countVarp->dtypep(), 0)}, stmtsp};
        ifp->isBoundsCheck(true);
        ifp->isAssertPassGate(true);
        ifp->user1(true);
        // Another attempt failing on the same tick runs the fail action instead
        prependPassToFail(assertp, V3AssertCommon::cloneAction(ifp, m_actionNames));
        assertp->addPasssp(ifp);
    }

    void splitImplicationPassActions(AstAssert* const assertp, const PropertyParts& parts,
                                     AstNodeExpr* const nonvacuousMatchp) {
        FileLine* const flp = assertp->fileline();

        AstNodeStmt* const passsp = assertp->passsp()->unlinkFrBackWithNext();
        AstNodeStmt* splitsp = nullptr;

        if (!parts.isFollowedBy) {
            // A vacuous success is of the attempt starting on this tick
            AstNodeExpr* const vacuousp = new AstLogAnd{
                flp, assertOnCond(flp, assertp->userType(), assertp->directive()),
                new AstLogNot{flp, sampled(parts.triggerExprp->cloneTreePure(false))}};
            AstNodeStmt* const vacuousBodyp = V3AssertCommon::cloneAction(passsp, m_actionNames);
            splitsp = newPassOnIf(flp, vacuousp, vacuousBodyp, assertp->userType(),
                                  assertp->directive(), /*vacuous=*/true);
        }

        AstIf* const nonvacuousp
            = newPassOnIf(flp, nonvacuousMatchp, passsp, assertp->userType(), assertp->directive(),
                          /*vacuous=*/false);
        splitsp = AstNode::addNextNull<AstNodeStmt>(splitsp, nonvacuousp);
        // Another attempt failing on the same tick runs the fail action instead
        prependPassToFail(assertp, V3AssertCommon::cloneAction(splitsp, m_actionNames));
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

    // Hoist a leading clocking event (IEEE 1800-2023 16.7):
    bool hoistClockedSeq(AstPropSpec* specp) {
        while (AstSClocked* const clockedp = VN_CAST(specp->propp(), SClocked)) {
            if (specp->sensesp()) {
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
            specp->sensesp(clockedp->sensesp()->unlinkFrBackWithNext());
            AstNodeExpr* const bodyp = clockedp->exprp()->unlinkFrBack();
            clockedp->replaceWith(bodyp);
            VL_DO_DANGLING(pushDeletep(clockedp), clockedp);
        }
        // A clocking event anywhere else in the sequence is not supported.
        const AstSClocked* nestedp = nullptr;
        specp->propp()->foreach([&](const AstSClocked* p) {
            if (!nestedp) nestedp = p;
        });
        if (nestedp) {
            nestedp->v3warn(E_UNSUPPORTED,
                            "Unsupported: clocking event inside sequence expression");
            replaceBodyOnBuildError(specp->fileline(), specp, true);
            return true;
        }
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

    // Statements adding countp, a count of threads as addCountp builds, to varp: one for each
    // term of its sums, under its conditions, adding it if set. A C++ compiler takes much
    // memory for one long sum, and for adding to a local, so the caller reads varp first to
    // keep it a member. Takes ownership.
    static AstNodeStmt* newCountAddsp(FileLine* flp, AstVar* varp, AstNodeExpr* countp) {
        if (AstCond* const condp = VN_CAST(countp, Cond)) {
            AstNodeExpr* const gatep = condp->condp()->unlinkFrBack();
            AstNodeExpr* const thenp = condp->thenp()->unlinkFrBack();
            AstNodeExpr* const elsep = condp->elsep()->unlinkFrBack();
            VL_DO_DANGLING(condp->deleteTree(), condp);
            return new AstIf{flp, gatep, newCountAddsp(flp, varp, thenp),
                             newCountAddsp(flp, varp, elsep)};
        }
        if (countp->isZero()) {
            VL_DO_DANGLING(countp->deleteTree(), countp);
            return nullptr;
        }
        // addCountp builds a sum with its later terms on the right
        std::vector<AstNodeExpr*> termps;
        while (AstAdd* const addp = VN_CAST(countp, Add)) {
            termps.push_back(addp->rhsp()->unlinkFrBack());
            countp = addp->lhsp()->unlinkFrBack();
            VL_DO_DANGLING(addp->deleteTree(), addp);
        }
        if (!termps.empty()) {
            AstNodeStmt* stmtsp = newCountAddsp(flp, varp, countp);
            for (auto it = termps.rbegin(); it != termps.rend(); ++it)
                stmtsp = AstNode::addNext(stmtsp, newCountAddsp(flp, varp, *it));
            return stmtsp;
        }
        // A term, as a thread's bit, added only if set
        AstNodeExpr* const nonzerop = new AstNeq{flp, countp->cloneTreePure(false),
                                                 newTypedConstp(flp, countp->dtypep(), 0)};
        return new AstIf{
            flp, nonzerop,
            new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE},
                          new AstAdd{flp, new AstVarRef{flp, varp, VAccess::READ}, countp}}};
    }

    // Install pass-action gating and replay simultaneous per-thread failures.
    void attachActionHandlers(AstAssert* const assertp, AstNodeExpr* matchExprp,
                              AstSenTree* const threadFailReplaySenTreep,
                              AstNodeExpr* threadFailCountp) {
        if (threadFailCountp) {
            threadFailCountp = withoutMatchItemsp(threadFailCountp);
            UASSERT_OBJ(threadFailReplaySenTreep, assertp,
                        "Thread fail count missing sensitivity tree");
            AstNodeStmt* const failsp = assertp->failsp();
            FileLine* const flp = assertp->fileline();
            // IEEE 1800-2023 16.12 requires one action-block evaluation per failed
            // thread. AstAssert handles the first, so replay the rest here.
            AstVar* const remainingFailCountVarp
                = new AstVar{flp, VVarType::MODULETEMP, m_failCountNames.get(""),
                             m_modp->findBasicDType(VBasicDTypeKwd::UINT32)};
            remainingFailCountVarp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(remainingFailCountVarp);
            // Clear what the last replays left, testing it first to keep it a member, see
            // newCountAddsp
            AstNodeStmt* const replayStmtsp = new AstIf{
                flp,
                new AstNeq{flp, new AstVarRef{flp, remainingFailCountVarp, VAccess::READ},
                           newTypedConstp(flp, remainingFailCountVarp->dtypep(), 0)},
                new AstAssign{flp, new AstVarRef{flp, remainingFailCountVarp, VAccess::WRITE},
                              newTypedConstp(flp, remainingFailCountVarp->dtypep(), 0)}};
            replayStmtsp->addNext(newCountAddsp(flp, remainingFailCountVarp, threadFailCountp));
            AstLoop* const replayLoopp = new AstLoop{flp};
            replayLoopp->addStmtsp(new AstLoopTest{
                flp, replayLoopp,
                new AstGt{flp, new AstVarRef{flp, remainingFailCountVarp, VAccess::READ},
                          newTypedConstp(flp, remainingFailCountVarp->dtypep(), 1)}});
            replayLoopp->addStmtsp(
                newIfAssertFailOn(V3AssertCommon::cloneAction(failsp, m_actionNames),
                                  assertp->directive(), assertp->userType()));
            AstSub* const decrementedFailCountp
                = new AstSub{flp, new AstVarRef{flp, remainingFailCountVarp, VAccess::READ},
                             newTypedConstp(flp, remainingFailCountVarp->dtypep(), 1)};
            replayLoopp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, remainingFailCountVarp, VAccess::WRITE},
                              decrementedFailCountp});
            replayStmtsp->addNext(replayLoopp);
            m_modp->addStmtsp(
                newAssertAlways(flp, VAlwaysKwd::ALWAYS, threadFailReplaySenTreep, replayStmtsp));
        }
        // Gate pass handler on match to prevent vacuous-pass firings. This follows the
        // replays, as they clone the fail action, which must not run the pass action again.
        if (matchExprp) {
            // needMatch implies passsp() was non-null when evaluated above;
            // lowering does not mutate the assert's pass-action between the
            // two reads, so passsp() is still non-null here.
            AstNodeStmt* passsp = assertp->passsp();
            UASSERT_OBJ(passsp, assertp, "needMatch set but passsp is null");
            passsp->unlinkFrBackWithNext();
            FileLine* const flp = assertp->fileline();
            // Gated by the pass control here, as V3Assert leaves an if it takes as gated
            AstIf* const ifp = newPassOnIf(flp, matchExprp, passsp, assertp->userType(),
                                           assertp->directive(), /*vacuous=*/false);
            assertp->addPasssp(ifp);
            // Fail-handler prefix for overlapping instances (IEEE 16.12):
            // fires when reject=1 && match=1 in the same cycle.
            prependPassToFail(assertp, V3AssertCommon::cloneAction(ifp, m_actionNames));
        }
    }

    void makeActionsReactive(AstNodeCoverOrAssert* assertp, AstSenTree* senTreep) {
        // A sequence event control resumes its waiters from the cover action
        const AstCover* const coverp = VN_CAST(assertp, Cover);
        if (coverp && coverp->isSeqEvent()) return;
        // A procedure that may suspend may evaluate it in a later time step
        if (m_procSuspends) return;
        std::string scope;
        for (const AstBegin* const beginp : m_namedBeginps) scope += "__DOT__" + beginp->name();
        const V3AssertReactive::Site site{assertp, m_modp, m_containerp, senTreep, scope};
        if (AstNodeStmt* const passsp = assertp->passsp()) {
            passsp->unlinkFrBackWithNext();
            assertp->addPasssp(m_reactive.newPending(site, passsp, m_actionNames));
        }
        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        if (AstNodeStmt* const failsp = assertAssertp ? assertAssertp->failsp() : nullptr) {
            failsp->unlinkFrBackWithNext();
            assertAssertp->addFailsp(m_reactive.newPending(site, failsp, m_actionNames));
        }
    }

    static bool splitsImplicationPasssp(const AstNodeCoverOrAssert* assertp,
                                        const PropertyParts& parts) {
        const AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        return assertAssertp && assertAssertp->passsp() && parts.hasImplication
               && canSplitImplicationPassActions(parts);
    }

    // Takes ownership of outputp, and of matchp, matchCountp and threadFailCountp if non-null
    void finishDirective(AstNodeCoverOrAssert* assertp, const PropertyParts& parts,
                         AstSenTree* senTreep, AstNodeExpr* outputp, AstNodeExpr* matchp,
                         AstNodeExpr* matchCountp, AstNodeExpr* threadFailCountp,
                         AstNodeExpr* antecedentEndCountp, AstNodeExpr* rejectCountp,
                         AstNodeExpr* antecedentRejectp) {
        AstNodeExpr* outputExprp = outputp;
        FileLine* const flp = assertp->fileline();
        AstPropSpec* const propp = VN_AS(assertp->propp(), PropSpec);
        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        // Without 'else', a failure calls $error (IEEE 1800-2023 16.14.1). V3Assert adds it only
        // where the fail action is empty, and the pass actions of other attempts are put in the
        // fail action below, so it is added here first, also to be replayed for each attempt.
        if (assertAssertp && !assertAssertp->failsp()) {
            assertAssertp->addFailsp(newDefaultFailp(flp));
        }
        if (countsMatches(assertp)) {
            UASSERT_OBJ(matchCountp, assertp, "Cover sequence missing match count");
            VL_DO_DANGLING(outputExprp->deleteTree(), outputExprp);
            propp->matchCountp(matchCountp);
            outputExprp = new AstNeq{flp, matchCountp->cloneTreePure(false),
                                     newTypedConstp(flp, matchCountp->dtypep(), 0)};
        } else if (matchCountp) {
            propp->matchCountp(matchCountp);
        }

        // Its actions run in the Reactive region, from the decisions at the evaluation, which
        // the gating and replays below make
        makeActionsReactive(assertp, senTreep);
        assertp->nfaLowered(true);

        if (splitsImplicationPasssp(assertp, parts)) {
            // The fail replays come first, so that they do not run the pass actions
            if (threadFailCountp) {
                attachActionHandlers(assertAssertp, nullptr, senTreep->cloneTree(false),
                                     threadFailCountp);
            }
            splitImplicationPassActions(assertAssertp, parts, matchp);
        } else {
            attachActionHandlers(assertAssertp, parts.hasImplication ? nullptr : matchp,
                                 threadFailCountp ? senTreep->cloneTree(false) : nullptr,
                                 threadFailCountp);
            if (rejectCountp) {
                // A pass of a negated property is a rejection of its operand, vacuous when the
                // antecedent of a followed-by does not match (IEEE 1800-2023 16.12.3, 16.12.9)
                AstNodeExpr* const antRejectCountp
                    = antecedentRejectp ? newCountp(flp, antecedentRejectp) : nullptr;
                AstNodeExpr* nonvacuousCountp = rejectCountp;
                if (antRejectCountp) {
                    nonvacuousCountp
                        = new AstSub{flp, nonvacuousCountp, antRejectCountp->cloneTreePure(false)};
                }
                AstNodeExpr* countp
                    = new AstCond{flp,
                                  assertPassOnCond(flp, assertp->userType(), assertp->directive(),
                                                   /*vacuous=*/false),
                                  nonvacuousCountp, newTypedConstp(flp, u32DTypep(), 0)};
                if (antRejectCountp) {
                    countp = new AstAdd{
                        flp, countp,
                        new AstCond{flp,
                                    assertPassOnCond(flp, assertp->userType(),
                                                     assertp->directive(), /*vacuous=*/true),
                                    antRejectCountp, newTypedConstp(flp, u32DTypep(), 0)}};
                }
                addCountedPassActions(assertAssertp, countp);
            } else if (antecedentEndCountp) {
                // A vacuous success is the antecedent of an attempt ending without a match, and
                // a nonvacuous one the consequent matching; starts are gated by assertOn, so the
                // attempts already executing still pass after Off
                AstNodeExpr* const vacuousCountp
                    = new AstCond{flp,
                                  assertPassOnCond(flp, assertp->userType(), assertp->directive(),
                                                   /*vacuous=*/true),
                                  antecedentEndCountp, newTypedConstp(flp, u32DTypep(), 0)};
                AstNodeExpr* const nonvacuousp
                    = new AstLogAnd{flp, matchp,
                                    assertPassOnCond(flp, assertp->userType(),
                                                     assertp->directive(), /*vacuous=*/false)};
                addCountedPassActions(assertAssertp,
                                      new AstAdd{flp, vacuousCountp, newCountp(flp, nonvacuousp)});
            } else if (matchp && parts.hasImplication) {
                // Without a match per attempt, the pass of a delayed antecedent follows from no
                // rejection. After Off, only the attempts already executing still pass.
                AstNodeStmt* const passsp = assertAssertp->passsp()->unlinkFrBackWithNext();
                AstNodeExpr* const onp
                    = assertOnCond(flp, assertp->userType(), assertp->directive());
                assertAssertp->addPasssp(newPassOnIf(flp, new AstLogOr{flp, onp, matchp}, passsp,
                                                     assertp->userType(), assertp->directive(),
                                                     /*vacuous=*/false));
            }
        }

        AstNode* const innerPropp = propp->propp();
        innerPropp->replaceWith(outputExprp);
        VL_DO_DANGLING(pushDeletep(innerPropp), innerPropp);
        assertp->nfaLowered(true);
    }

    // Replace one VarRef to a captured local var with $past(rhs, K)
    // (or rhs inline when K == 0). No-op if refp is not in matchMap.
    void substituteMatchItemRef(AstVarRef* refp, unsigned K,
                                const std::unordered_map<const AstVar*, AstNodeExpr*>& matchMap) {
        const auto it = matchMap.find(refp->varp());
        if (it == matchMap.end()) return;
        AstNodeExpr* newp = it->second->cloneTreePure(false);
        if (K > 0) {
            AstConst* const ticksp = new AstConst{refp->fileline(), AstConst::WidthedValue{}, 32,
                                                  static_cast<uint32_t>(K)};
            AstPast* const pastp = new AstPast{refp->fileline(), newp, ticksp, nullptr,
                                               /* propertyTiming */ true};
            pastp->dtypeFrom(newp);
            newp = pastp;
        }
        refp->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(refp), refp);
        return;
    }

    // Recursively walk a consequent. Returns cycle length consumed and
    // substitutes each VarRef to a captured local var with $past(rhs, K)
    // (or rhs inline when K == 0). Reports E_UNSUPPORTED on non-constant
    // delays or composite sequence operators and returns -1 on failure.
    int
    walkSubstituteMatchItems(AstNodeExpr* nodep, unsigned K,
                             const std::unordered_map<const AstVar*, AstNodeExpr*>& matchItems) {
        if (AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            // IEEE 1800-2023 16.9.2: cycle_delay's lhsp is a constant_expression
            // and the delay form in a sequence is always `##N`, folded by
            // V3Const + V3Param before V3AssertNfa. Range form `##[m:n]` is the
            // only user-visible reject here.
            AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
            UASSERT_OBJ(delayp->isCycleDelay() && VN_IS(delayp->lhsp(), Const), sexprp,
                        "SVA cycle delay must have a constant lhsp");
            if (delayp->isRangeDelay()) {
                sexprp->v3warn(E_UNSUPPORTED, "Unsupported: property local variable used across "
                                              "non-constant cycle delay in consequent"
                                              " (IEEE 1800-2023 16.10)");
                return -1;
            }
            const unsigned delayCycles = VN_AS(delayp->lhsp(), Const)->toUInt();
            int preLen = 0;
            if (AstNodeExpr* const prep = sexprp->preExprp()) {
                preLen = walkSubstituteMatchItems(prep, K, matchItems);
                if (preLen < 0) return -1;
            }
            const int bodyLen
                = walkSubstituteMatchItems(sexprp->exprp(), K + preLen + delayCycles, matchItems);
            if (bodyLen < 0) return -1;
            return preLen + delayCycles + bodyLen;
        }
        if (nodep->isMultiCycleSva()) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: property local variable used across "
                                         "composite sequence operator in consequent"
                                         " (IEEE 1800-2023 16.10)");
            return -1;
        }
        std::vector<AstVarRef*> refs;
        nodep->foreach([&refs](AstVarRef* p) { refs.push_back(p); });
        for (AstVarRef* const refp : refs) substituteMatchItemRef(refp, K, matchItems);
        return 0;
    }

    // Lower property-local match-item assignments before NFA construction.
    // Without this, the antecedent's AstExprStmt(<x = rhs_expr>, antBool)
    // survives into every NFA edge as a continuous-alias side-effect, so the
    // local-var temp tracks the current cycle's rhs_expr rather than the
    // antecedent-match cycle's value -- wrong for `|-> ##N` and `|=> ##N`
    // with N > 0 (issue #7587). Each consequent reference to the local var
    // is replaced with `$past(rhs_expr, K)` where K = (overlapped ? 0 : 1)
    // plus any accumulated `##N` delay. Returns true if E_UNSUPPORTED was
    // emitted; caller must replace the body with BitFalse and bail.
    bool liftMatchItemSubstitutions(PropertyParts& parts, AstNodeExpr* seqBodyp) {
        if (!parts.hasImplication) return false;
        AstExprStmt* const exprStmtp = VN_CAST(parts.triggerExprp, ExprStmt);
        if (!exprStmtp) return false;
        // IEEE 1800-2023 16.10 BNF requires `(expr, match_item {, match_item})`
        // with at least one match item; V3LinkParse only emits ExprStmt for
        // this form and only emits AstAssign with VarRef LHS for each item.
        std::unordered_map<const AstVar*, AstNodeExpr*> matchItems;
        for (AstNode* const stmtp : exprStmtp->stmtspList()) {
            AstAssign* const assignp = VN_AS(stmtp, Assign);
            AstVarRef* const lhsRefp = VN_AS(assignp->lhsp(), VarRef);
            matchItems[lhsRefp->varp()] = assignp->rhsp();
        }
        const unsigned startK = parts.isOverlapped ? 0 : 1;
        const int length = walkSubstituteMatchItems(seqBodyp, startK, matchItems);
        // Match-item substitution / strip mutates ancestor purity. Release
        // builds don't auto-clear caches on edits, so refresh here.
        VIsCached::clearCacheTree();
        if (length < 0) return true;
        AstNodeExpr* const antBoolp = exprStmtp->resultp()->unlinkFrBack();
        exprStmtp->replaceWith(antBoolp);
        VL_DO_DANGLING(pushDeletep(exprStmtp), exprStmtp);
        parts.triggerExprp = antBoolp;
        return false;
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

    // Success and nonvacuity of a property evaluated on its start tick
    struct SingleTickProp final {
        AstNodeExpr* successp = nullptr;  // Holds when the property holds
        AstNodeExpr* nonvacuousp = nullptr;  // Holds when nonvacuous; nullptr if always
    };
    static AstNodeExpr* newOrNonvacuous(FileLine* flp, AstNodeExpr* lhsp, AstNodeExpr* rhsp) {
        if (!lhsp || !rhsp) {
            if (lhsp) VL_DO_DANGLING(lhsp->deleteTree(), lhsp);
            if (rhsp) VL_DO_DANGLING(rhsp->deleteTree(), rhsp);
            return nullptr;
        }
        return new AstLogOr{flp, lhsp, rhsp};
    }
    static AstNodeExpr* newAndNonvacuous(FileLine* flp, AstNodeExpr* condp, AstNodeExpr* nonvacp) {
        return nonvacp ? new AstLogAnd{flp, condp, nonvacp} : condp;
    }
    static void deleteSingleTickProp(SingleTickProp& prop) {
        if (prop.successp) VL_DO_DANGLING(prop.successp->deleteTree(), prop.successp);
        if (prop.nonvacuousp) VL_DO_DANGLING(prop.nonvacuousp->deleteTree(), prop.nonvacuousp);
    }
    // Build the success and nonvacuity of nodep (IEEE 1800-2023 16.14.8), or return false
    // if nodep is not evaluated on its start tick
    static bool buildSingleTickProp(AstNodeExpr* nodep, SingleTickProp& prop) {
        FileLine* const flp = nodep->fileline();
        SingleTickProp lhs;
        SingleTickProp rhs;
        if (AstImplication* const implp = VN_CAST(nodep, Implication)) {
            if (!implp->isOverlapped() || implp->isFollowedBy()) return false;
            // Match item assignments belong to the antecedent, not to its checks
            AstNodeExpr* antp = implp->lhsp();
            if (const AstExprStmt* const exprStmtp = VN_CAST(antp, ExprStmt)) {
                antp = exprStmtp->resultp();
            }
            if (!buildSingleTickProp(antp, lhs) || lhs.nonvacuousp
                || !buildSingleTickProp(implp->rhsp(), rhs)) {
                deleteSingleTickProp(lhs);
                deleteSingleTickProp(rhs);
                return false;
            }
            // 16.12.7, 16.14.8 h
            prop.successp = new AstLogOr{
                flp, new AstLogNot{flp, lhs.successp->cloneTreePure(false)}, rhs.successp};
            prop.nonvacuousp = newAndNonvacuous(flp, lhs.successp, rhs.nonvacuousp);
            return true;
        }
        if (const AstAbortOn* const abortp = VN_CAST(nodep, AbortOn)) {
            // On a single tick the abort condition holds during the evaluation if it holds
            // on the tick (16.12.14, 16.14.8 ab-ae)
            if (!buildSingleTickProp(abortp->propp(), rhs)) return false;
            AstNodeExpr* const condp = abortp->condp()->cloneTreePure(false);
            prop.successp = abortp->kind().isAccept()
                                ? static_cast<AstNodeExpr*>(new AstLogOr{flp, condp, rhs.successp})
                                : new AstLogAnd{flp, new AstLogNot{flp, condp}, rhs.successp};
            prop.nonvacuousp = newAndNonvacuous(
                flp, new AstLogNot{flp, abortp->condp()->cloneTreePure(false)}, rhs.nonvacuousp);
            return true;
        }
        if (const AstLogNot* const notp = VN_CAST(nodep, LogNot)) {
            // 16.12.3, 16.14.8 d
            if (!buildSingleTickProp(notp->lhsp(), lhs)) return false;
            prop.successp = new AstLogNot{flp, lhs.successp};
            prop.nonvacuousp = lhs.nonvacuousp;
            return true;
        }
        const AstNodeBiop* const biopp = VN_CAST(nodep, NodeBiop);
        const AstSAnd* const andp = VN_CAST(nodep, SAnd);
        if ((andp && !andp->propertyControl()) || VN_IS(nodep, SOr) || VN_IS(nodep, LogOr)) {
            if (!buildSingleTickProp(biopp->lhsp(), lhs)
                || !buildSingleTickProp(biopp->rhsp(), rhs)) {
                deleteSingleTickProp(lhs);
                deleteSingleTickProp(rhs);
                return false;
            }
            // 16.12.4, 16.12.5, 16.14.8 e and f
            prop.successp
                = andp ? static_cast<AstNodeExpr*>(new AstLogAnd{flp, lhs.successp, rhs.successp})
                       : new AstLogOr{flp, lhs.successp, rhs.successp};
            prop.nonvacuousp = newOrNonvacuous(flp, lhs.nonvacuousp, rhs.nonvacuousp);
            return true;
        }
        // A side effect is left where V3AssertPre evaluates it once
        if (!nodep->isPure() || hasMultiCycleExpr(nodep)
            || nodep->exists([](const AstImplication*) { return true; })) {
            return false;
        }
        prop.successp = nodep->cloneTreePure(false);  // A boolean, so nonvacuous (16.14.8 a)
        return true;
    }

    // V3AssertPre lowers a property evaluated on its start tick to a boolean, so when an
    // assertion of it can succeed vacuously, lower its operators here and split its pass
    // action on its nonvacuity (IEEE 1800-2023 16.14.8). Return true if so.
    bool lowerSingleTickProp(AstNodeCoverOrAssert* assertp) {
        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        if (!assertAssertp) return false;
        AstNodeExpr* const bodyp = VN_AS(assertp->propp(), PropSpec)->propp();
        if (!bodyp->exists(
                [](const AstNode* np) { return VN_IS(np, Implication) || VN_IS(np, AbortOn); })) {
            return false;
        }
        // A future value function delays the evaluation of the property
        // (IEEE 1800-2023 16.9.4), but not of a condition in its pass action
        if (bodyp->exists([](const AstNode* np) {
                return VN_IS(np, Future) || VN_IS(np, Rising) || VN_IS(np, Falling)
                       || VN_IS(np, Steady);
            })) {
            return false;
        }
        // A boolean body is left in place, with its match item assignments
        const bool lowerBody = hasMultiCycleExpr(bodyp);
        if (lowerBody && bodyp->exists([](const AstExprStmt*) { return true; })) return false;
        SingleTickProp prop;
        if (!buildSingleTickProp(bodyp, prop)) return false;
        if (!prop.nonvacuousp) {
            deleteSingleTickProp(prop);
            return false;
        }
        if (lowerBody) {
            bodyp->replaceWith(prop.successp);
            VL_DO_DANGLING(pushDeletep(bodyp), bodyp);
        } else {
            VL_DO_DANGLING(prop.successp->deleteTree(), prop.successp);
        }
        if (assertAssertp->passsp()) {
            // The pass action runs only when the property holds, under the pass control of a
            // nonvacuous success if N holds, else of a vacuous one. One action and a single test,
            // so a pass action that suspends does not see N change.
            FileLine* const flp = assertp->fileline();
            AstNodeStmt* const passsp = assertAssertp->passsp()->unlinkFrBackWithNext();
            AstNodeExpr* const passOnp
                = new AstCond{flp, sampled(prop.nonvacuousp),
                              assertPassOnCond(flp, assertp->userType(), assertp->directive(),
                                               /*vacuous=*/false),
                              assertPassOnCond(flp, assertp->userType(), assertp->directive(),
                                               /*vacuous=*/true)};
            AstIf* const ifp = new AstIf{flp, passOnp, passsp};
            ifp->isBoundsCheck(true);
            ifp->isAssertPassGate(true);
            ifp->user1(true);
            assertAssertp->addPasssp(ifp);
        } else {
            VL_DO_DANGLING(prop.nonvacuousp->deleteTree(), prop.nonvacuousp);
        }
        return true;
    }

    // Reject unsupported shapes.
    // Returns the PropSpec to lower, or nullptr when fully handled here.
    AstPropSpec* prepareAssertionProp(AstNodeCoverOrAssert* assertp) {
        if (AstPropSpec* const specp = VN_CAST(assertp->propp(), PropSpec)) {
            // Leave a chain of property instances to V3AssertPre: the NFA lowering
            // reports one fail for attempts failing in the same cycle, e.g. after a goto
            // repetition antecedent, but each attempt fails (IEEE 1800-2023 16.14.1).
            if (specp->fromInstanceChain()) return nullptr;
            if (hoistClockedSeq(specp)) return nullptr;
        }

        AstPropSpec* const propp = VN_AS(assertp->propp(), PropSpec);
        if (!VN_IS(assertp, Cover)
            && effectiveAssertPropStrength(propp) == VPropStrength::STRONG) {
            propp->v3warn(E_UNSUPPORTED,
                          "Unsupported: strong property in " + assertp->verilogKwd() + ".");
            replaceBodyOnBuildError(assertp->fileline(), propp, /*errorEmitted=*/true);
            return nullptr;
        }

        if (!hasMultiCycleExpr(propp)) return nullptr;
        if (isBareTopLevelUntil(propp)) return nullptr;
        return propp;
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
            // cppcheck-suppress knownConditionTrueFalse
            return !repp->maxCountp() && !repp->unbounded();
        }
        // A boolean
        return !nodep->exists([](const AstNodeExpr* exprp) { return exprp->isMultiCycleSva(); });
    }

    void processAssertion(AstNodeCoverOrAssert* assertp) {
        if (assertp->immediate()) return;

        AstPropSpec* const propp = prepareAssertionProp(assertp);
        if (lowerSingleTickProp(assertp) || !propp) return;

        PropertyParts parts = decomposeProperty(propp);
        UASSERT_OBJ(parts.seqExprp, propp, "Property body must be an expression");

        // Unwrap `not` (IEEE 1800-2023 16.12.1); odd count -> negated semantics.
        AstNodeExpr* seqBodyp = parts.seqExprp;
        bool negated = false;
        while (AstLogNot* const notp = VN_CAST(seqBodyp, LogNot)) {
            negated = !negated;
            seqBodyp = notp->lhsp();
        }

        const char* const propertyControlp
            = unsupportedPropertyControl(assertp, seqBodyp, negated);

        // Substitute property-local match-item refs in consequent with
        // $past(rhs, K) before NFA build (IEEE 1800-2023 16.10).
        if (liftMatchItemSubstitutions(parts, seqBodyp)) {
            AstPropSpec* const psp = VN_CAST(assertp->propp(), PropSpec);
            UASSERT_OBJ(psp, assertp, "Concurrent assertion must have PropSpec");
            replaceBodyOnBuildError(assertp->fileline(), psp, /*errorEmitted=*/true);
            return;
        }

        AstCover* const coverp = VN_CAST(assertp, Cover);
        const bool isCoverSeq = coverp && coverp->isCoverSeq();
        // A sequence event control is not an assertion directive; no default
        // disable iff, no assertion control
        const bool isSeqEvent = coverp && coverp->isSeqEvent();
        const bool countMatches = countsMatches(assertp);
        // Inherit module defaults (IEEE 14.12, 16.15) when assertion has none.
        if (!propp->sensesp() && m_defaultClockingp) {
            propp->sensesp(m_defaultClockingp->sentreep()->sensesp()->cloneTree(true));
        }
        if (!propp->disablep() && m_defaultDisablep && !isSeqEvent) {
            propp->disablep(m_defaultDisablep->condp()->cloneTreePure(true));
        }
        if (!propp->sensesp()) return;
        AstSenTree* senTreep
            = new AstSenTree{propp->fileline(), propp->sensesp()->cloneTree(true)};
        AstNodeExpr* const disableExprp = propp->disablep();

        // NFA lowering clones repeated operands and may hoist them into an
        // always_comb block. Resolve implicit sampled-value clocks first, while
        // the enclosing assertion clock is still available.
        {
            VL_RESTORER(m_sampledValueClockp);
            m_sampledValueClockp = senTreep;
            iterate(propp->propp());
            // The final block clones the action block, so resolve its clocks while in scope
            if (AstAssert* const ap = VN_CAST(assertp, Assert)) {
                iterateAndNextNull(ap->failsp());
            }
        }

        FileLine* const flp = assertp->fileline();

        SvaGraph graph;
        // A vacuous success fails a negated assertion (IEEE 1800-2023 16.12.3); a cover has no
        // failures, and a property if/case is reported below instead
        const bool trackVacuous = negated && !coverp && !propertyControlp;
        SvaNfaBuilder builder{graph,       m_modp,     m_propTempNames,
                              isCoverSeq,  isSeqEvent, coverp != nullptr,
                              trackVacuous};
        if (SvaNfaBuilder::needsRangeFallback(seqBodyp,
                                              parts.hasImplication ? parts.triggerExprp : nullptr,
                                              coverp != nullptr)) {
            builder.presetRangeFallback();
        }

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
        // Without coverage collection, a cover sequence counts matches only for its pass
        // statement
        if (countMatches && !v3Global.opt.coverageUser() && !assertp->passsp()) {
            SvaNfaBuilder::freeUnlinkedCondp(result.finalCondp);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
            AstNode* const innerPropp = propp->propp();
            innerPropp->replaceWith(new AstConst{flp, AstConst::BitFalse{}});
            VL_DO_DANGLING(pushDeletep(innerPropp), innerPropp);
            return;
        }

        AstAssert* const assertAssertp = VN_CAST(assertp, Assert);
        const bool needMatch = assertAssertp && assertAssertp->passsp();
        // Without a split by its antecedent's value, an implication's vacuous successes are
        // its antecedent's threads ending, when each attempt has one, also with a negated
        // consequent, whose nonvacuous successes are its operand failing
        const bool trackAntecedentEnd = needMatch && parts.hasImplication && !parts.isFollowedBy
                                        && !splitsImplicationPasssp(assertp, parts)
                                        && oneThreadPerAttempt(parts.triggerExprp);

        // The rejected threads of a negated property's operand are passes of the property,
        // vacuous when the antecedent of a followed-by does not match, and its matches and
        // vacuous successes failures
        // An assertion with no 'else' gets the default fail action, see finishDirective, which
        // is replayed like an explicit one, for each failing attempt, also of an implication
        // (IEEE 1800-2023 16.14.1). An implication with an 'and' combining its operands'
        // matches is not, as each operand of an attempt fails in its own thread, nor one whose
        // consequent has a range delay whose candidates each reject, or a throughout after a
        // range delay, whose guard fails each candidate of an attempt, nor one in a class,
        // whose replay would run outside the class.
        const bool replayFails
            = assertAssertp && !negated
              && !(parts.hasImplication
                   && (builder.hasAndLatch() || builder.candidateMissRejects()
                       || builder.rangeFallback() || builder.hasThroughoutAfterRange()
                       || VN_IS(m_modp, Class)));
        const bool replaySuccesses = assertAssertp && negated;
        const bool countPasses = needMatch && negated && !parts.hasImplication;
        // Counting threads counts the failed attempts when each attempt has one thread
        // Counting each state's threads evaluates the conditions of its incoming transitions
        // whether or not a thread takes them, so a sequence match item would run again or
        // without its thread (IEEE 1800-2023 16.10); such a property keeps the state bits
        const bool exactCounts
            = replayFails && !parts.hasImplication && oneThreadPerAttempt(seqBodyp, true)
              && !seqBodyp->exists([](const AstExprStmt* itemp) { return itemp->isMatchItem(); });
        const auto signals = m_loweringp->lower(
            assertp, graph, senTreep, result.finalCondp, disableExprp, replayFails || countPasses,
            replayFails || countPasses, trackAntecedentEnd, replaySuccesses, countPasses,
            exactCounts, exactCounts ? VN_CAST(seqBodyp, AbortOn) : nullptr,
            coverp && !isCoverSeq && !negated && v3Global.opt.coverageUser());
        AstNodeExpr* matchExprp = nullptr;
        AstNodeExpr* const outputExprp
            = m_loweringp->assembleResult(assertp, negated, result.finalCondp, signals,
                                          needMatch && !countPasses ? &matchExprp : nullptr);
        if (result.finalCondp && !result.finalCondp->backp()) pushDeletep(result.finalCondp);
        // The pass action is gated by a copy of the match, see withoutMatchItemsp
        if (matchExprp) matchExprp = withoutMatchItemsp(matchExprp);
        AstNodeExpr* antecedentRejectp = signals.antecedentRejectp;
        if (antecedentRejectp && !countPasses) {
            VL_DO_DANGLING(antecedentRejectp->deleteTree(), antecedentRejectp);
        }
        AstNodeExpr* threadFailCountp = signals.threadFailCountp;
        if (threadFailCountp && !replayFails) {
            VL_DO_DANGLING(threadFailCountp->deleteTree(), threadFailCountp);
        }
        finishDirective(assertp, parts, senTreep, outputExprp, matchExprp, signals.matchCountp,
                        replayFails ? threadFailCountp : signals.successCountp,
                        signals.antecedentEndCountp, signals.rejectCountp, antecedentRejectp);
        VL_DO_DANGLING(pushDeletep(senTreep), senTreep);

        UINFO(4, "NFA converted assertion at " << flp << endl);

        if (dumpGraphLevel() >= 6) graph.m_graph.dumpDotFilePrefixed("assert-nfa");
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_containerp);
        VL_RESTORER_COPY(m_actionNames);
        VL_RESTORER(m_loweringp);
        VL_RESTORER(m_defaultClockingp);
        VL_RESTORER(m_defaultDisablep);
        m_modp = nodep;
        m_containerp = nodep;
        m_actionNames.reset();
        // A class nested in a module is in the scope of the module's default clocking
        if (!VN_IS(nodep, Class)) m_defaultClockingp = nullptr;
        m_defaultDisablep = nodep->defaultDisablep();
        SvaNfaLowering lowering{nodep, m_actionNames};
        m_loweringp = &lowering;
        iterateChildren(nodep);
    }
    void visit(AstClocking* nodep) override {
        if (nodep->isDefault() && !m_defaultClockingp) m_defaultClockingp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        VL_RESTORER(m_containerp);
        m_defaultDisablep = nodep->defaultDisablep();
        m_containerp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER_CLEAR(m_namedBeginps);
        VL_RESTORER(m_procSuspends);
        // The process of a concurrent assertion item does not suspend
        m_procSuspends = !(VN_IS(nodep, Always)
                           && VN_AS(nodep, Always)->keyword() == VAlwaysKwd::ASSERT_COVER)
                         && V3AssertCommon::procSuspends(nodep->stmtsp());
        iterateChildren(nodep);
    }
    // A fork branch is a process of its own, which also suspends if its own statements may
    void visit(AstForkItem* nodep) override {
        VL_RESTORER(m_procSuspends);
        if (!nodep->disableWrapper()) {
            m_procSuspends = m_procSuspends || V3AssertCommon::procSuspends(nodep->stmtsp());
        }
        iterateChildren(nodep);
    }
    void visit(AstBegin* nodep) override {
        if (!nodep->name().empty()) m_namedBeginps.push_back(nodep);
        iterateChildren(nodep);
        if (!nodep->name().empty()) m_namedBeginps.pop_back();
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
