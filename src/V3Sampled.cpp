// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Removal of SAMPLED
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
// V3Sampled's Transformations:
//
// Top Scope:
//   Replace each variable reference under SAMPLED with a new variable.
//   Sample only the ranges of a wide variable that constant selects read.
//   Capture whole-signal force reads by value, before sampling their children.
//   Make a process computing a value marked to follow the time read a new variable holding the
//   time, so it is computed at each evaluation.
//   Assign the new variables in the 'sample' eval function.
//   Remove SAMPLED.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Sampled.h"

#include "V3Sched.h"
#include "V3SharedTmps.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Clock state, as a visitor of each AstNode

class SampledVisitor final : public VNVisitor {
    // TYPES
    // A range of a variable that sampled constant selects read
    struct Range final {
        int m_lsb;  // First bit
        int m_width;  // Number of bits
        AstVarScope* m_sampledp;  // The variable sampling it, once made
    };
    // The ranges a variable's sampled reads take, merged where they overlap or touch
    struct VarRanges final {
        bool m_whole = false;  // Sample the whole variable
        std::vector<Range> m_ranges;  // Ranges read, by first bit
    };
    // Most ranges of a variable sampled separately, each with its own assignment
    static constexpr size_t MAX_RANGES = 16;

    // NODE STATE
    //  AstVarScope::user1()  -> AstVarScope*. The VarScope that stores sampled value
    //  AstVarRef::user1()    -> bool. Whether already converted
    const VNUser1InUse m_user1InUse;

    // STATE - across all visitors
    AstCFunc* const m_sampleFuncp;  // The 'sample' eval function assigning the sampled values
    V3SharedTmps m_sampledTmps{"__Vsampled", VVarType::MODULETEMP};  // Sampled variables
    V3SharedTmps m_forceTmps{"__VsampledForce", VVarType::MODULETEMP};  // Sampled force values
    // Keys remain in the tree as the sampled variables' value expressions.
    std::unordered_map<VNRef<AstNode>, AstVarScope*> m_forceSamples;
    // Ranges of wide variables that sampled expressions only read with constant selects
    std::unordered_map<const AstVarScope*, VarRanges> m_varRanges;
    VDouble0 m_statRanges;  // Ranges sampled instead of their whole variable

    // STATE - for current visit position (use VL_RESTORER)
    AstScope* m_scopep = nullptr;  // Current scope
    bool m_inSampled = false;  // True inside a sampled expression
    bool m_inProcedure = false;  // True inside a process
    bool m_timedFound = false;  // True once a value following the time is found in the process
    AstVarScope* m_timeVscp = nullptr;  // Variable holding the time in the current scope

    // METHODS

    // Create a variable in the current scope, assigned 'valuep' at the start of each evaluation
    AstVarScope* createSampledVar(V3SharedTmps& tmps, AstNodeExpr* valuep,
                                  const std::string& name) {
        FileLine* const flp = valuep->fileline();
        AstVarScope* const vscp = tmps.make(flp, m_scopep, valuep->dtypep(), name);
        vscp->varp()->sampled(true);
        AstVarRef* const lhsp = new AstVarRef{flp, vscp, VAccess::WRITE};
        m_sampleFuncp->addStmtsp(new AstAssign{flp, lhsp, valuep});
        UINFO(4, "New Sampled: " << vscp);
        return vscp;
    }

    // The range of the variable of 'refp' that select 'selp' of it reads, if constant
    static bool constRange(const AstSel* selp, const AstVarRef* refp, int& lsb, int& width) {
        const AstConst* const lsbp = VN_CAST(selp->lsbp(), Const);
        if (!lsbp || lsbp->num().isFourState() || !lsbp->num().fitsInUInt()
            || lsbp->toUInt() + static_cast<uint64_t>(selp->widthConst())
                   > static_cast<uint64_t>(refp->width())) {
            return false;
        }
        lsb = static_cast<int>(lsbp->toUInt());
        width = selp->widthConst();
        return true;
    }
    // The select of reference 'refp', or of a sampled expression that is only 'refp', if any
    static const AstSel* selectOf(const AstVarRef* refp) {
        const AstNode* fromp = refp;
        if (VN_IS(refp->backp(), Sampled)) fromp = refp->backp();
        const AstSel* const selp = VN_CAST(fromp->backp(), Sel);
        return selp && selp->fromp() == fromp ? selp : nullptr;
    }
    // Whether 'nodep' is under a force read in sampled expression 'sampledp'
    static bool underForceRead(const AstNode* nodep, const AstSampled* sampledp) {
        for (; nodep != sampledp; nodep = nodep->backp()) {
            const AstCMethodHard* const methodp = VN_CAST(nodep, CMethodHard);
            if (methodp && methodp->method() == VCMethod::FORCE_READ) return true;
        }
        return false;
    }
    // Find the variables wider than a quad whose sampled reads are all constant selects, and
    // the ranges they read, if few and narrower than the variable
    void findRanges(AstNetlist* netlistp) {
        netlistp->foreach([&](const AstSampled* sampledp) {
            sampledp->exprp()->foreach([&](const AstVarRef* refp) {
                VarRanges& ranges = m_varRanges[refp->varScopep()];
                const AstSel* const selp = selectOf(refp);
                int lsb = 0;
                int width = 0;
                // Automatic variables and values following the time are not sampled
                if (refp->width() <= VL_QUADSIZE || !selp || !constRange(selp, refp, lsb, width)
                    || underForceRead(refp, sampledp) || refp->varp()->isFuncLocal()
                    || sampledp->timed()) {
                    ranges.m_whole = true;
                } else {
                    ranges.m_ranges.push_back(Range{lsb, width, nullptr});
                }
            });
        });
        for (auto& pair : m_varRanges) {
            VarRanges& ranges = pair.second;
            if (ranges.m_whole) continue;
            std::vector<Range>& list = ranges.m_ranges;
            std::sort(list.begin(), list.end(), [](const Range& a, const Range& b) {
                return a.m_lsb < b.m_lsb || (a.m_lsb == b.m_lsb && a.m_width < b.m_width);
            });
            std::vector<Range> merged;
            int width = 0;
            for (const Range& range : list) {
                if (!merged.empty()
                    && range.m_lsb <= merged.back().m_lsb + merged.back().m_width) {
                    Range& last = merged.back();
                    last.m_width = std::max(last.m_lsb + last.m_width, range.m_lsb + range.m_width)
                                   - last.m_lsb;
                } else {
                    merged.push_back(range);
                }
            }
            for (const Range& range : merged) width += range.m_width;
            list = merged;
            ranges.m_whole = list.size() > MAX_RANGES || width >= pair.first->width();
        }
    }

    // VISITORS
    void visit(AstSel* nodep) override {
        // A constant select of a sampled variable, inside or around its sampled expression
        const AstSampled* const sampledp = VN_CAST(nodep->fromp(), Sampled);
        const AstVarRef* const refp
            = VN_CAST(sampledp ? sampledp->exprp() : nodep->fromp(), VarRef);
        int lsb = 0;
        int width = 0;
        if (!refp || refp->user1() || !(m_inSampled || (sampledp && !sampledp->timed()))
            || !constRange(nodep, refp, lsb, width)) {
            iterateChildren(nodep);
            return;
        }
        const auto it = m_varRanges.find(refp->varScopep());
        if (it == m_varRanges.end() || it->second.m_whole) {
            iterateChildren(nodep);
            return;
        }
        // Read the sampled range holding the selected bits
        auto rangeIt
            = std::upper_bound(it->second.m_ranges.begin(), it->second.m_ranges.end(), lsb,
                               [](int value, const Range& range) { return value < range.m_lsb; });
        Range& range = *--rangeIt;
        FileLine* const flp = nodep->fileline();
        AstVarScope* const vscp = refp->varScopep();
        if (!range.m_sampledp) {
            AstSel* const valuep = new AstSel{flp, new AstVarRef{flp, vscp, VAccess::READ},
                                              range.m_lsb, range.m_width};
            valuep->dtypep(valuep->findBitOrLogicDType(range.m_width, range.m_width,
                                                       VSigning::UNSIGNED,
                                                       vscp->varp()->dtypep()->isFourstate()));
            ++m_statRanges;
            range.m_sampledp = createSampledVar(
                m_sampledTmps, valuep, vscp->varp()->name() + "__" + cvtToStr(range.m_lsb));
        }
        AstVarRef* const newRefp = new AstVarRef{flp, range.m_sampledp, VAccess::READ};
        newRefp->user1SetOnce();  // Don't sample this one
        AstNodeExpr* newp = newRefp;
        if (lsb != range.m_lsb || width != range.m_width) {
            newp = new AstSel{flp, newRefp, lsb - range.m_lsb, width};
            newp->dtypeFrom(nodep);
        }
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstScope* nodep) override {
        VL_RESTORER(m_scopep);
        VL_RESTORER(m_timeVscp);
        m_scopep = nodep;
        m_timeVscp = nullptr;
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_inProcedure);
        VL_RESTORER(m_timedFound);
        m_inProcedure = true;
        m_timedFound = false;
        iterateChildren(nodep);
        if (!m_timedFound) return;
        // Its time functions, also in functions it calls, are read at its evaluation, as
        // V3Sched evaluates logic reading a sampled variable at the first iteration of each
        // evaluation. The empty 'if' reading it is removed after scheduling.
        FileLine* const flp = nodep->fileline();
        if (!m_timeVscp) {
            m_timeVscp = createSampledVar(m_sampledTmps,
                                          new AstTime{flp, m_scopep->modp()->timeunit()}, "time");
        }
        AstVarRef* const refp = new AstVarRef{flp, m_timeVscp, VAccess::READ};
        refp->user1SetOnce();  // Don't sample this one
        nodep->addStmtsp(new AstIf{flp, refp});
    }
    void visit(AstSampled* nodep) override {
        VL_RESTORER(m_inSampled);
        // A value following the time reads the current value of the temps it reads
        m_inSampled = !nodep->timed();
        if (nodep->timed()) {
            UASSERT_OBJ(m_inProcedure, nodep, "Value following the time outside a process");
            m_timedFound = true;
        }
        iterateChildren(nodep);
        nodep->replaceWith(nodep->exprp()->unlinkFrBack());
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstCMethodHard* nodep) override {
        if (!m_inSampled || nodep->method() != VCMethod::FORCE_READ) {
            iterateChildren(nodep);
            return;
        }
        // Force vectors hold pointers to live RHS shadows. Copying the vector and base
        // separately would let later writes change the sampled value (IEEE 1800-2023 16.5.1).
        // Whole-signal reads have no user expressions to evaluate at the point of use.
        const auto pair = m_forceSamples.emplace(*nodep, nullptr);
        AstVarScope*& vscp = pair.first->second;
        FileLine* const flp = nodep->fileline();
        VNRelinker relinker;
        nodep->unlinkFrBack(&relinker);
        if (pair.second) {
            vscp = createSampledVar(m_forceTmps, nodep, "");
        } else {
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
        AstVarRef* const refp = new AstVarRef{flp, vscp, VAccess::READ};
        refp->user1SetOnce();
        relinker.relink(refp);
    }
    void visit(AstVarRef* nodep) override {
        iterateChildren(nodep);
        // The sampled value of an automatic variable is its current value (IEEE 1800-2023 16.5.1)
        if (m_inSampled && !nodep->varp()->isFuncLocal() && !nodep->user1SetOnce()) {
            UASSERT_OBJ(nodep->access().isReadOnly(), nodep, "Should have failed in V3Access");
            AstVarScope* const vscp = nodep->varScopep();
            if (!vscp->user1p()) {
                AstVarRef* const valuep = new AstVarRef{vscp->fileline(), vscp, VAccess::READ};
                vscp->user1p(createSampledVar(m_sampledTmps, valuep, vscp->varp()->name()));
            }
            AstVarScope* const sampledp = VN_AS(vscp->user1p(), VarScope);
            AstNode* const newp = new AstVarRef{nodep->fileline(), sampledp, VAccess::READ};
            newp->user1SetOnce();  // Don't sample this one
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
    }

    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit SampledVisitor(AstNetlist* netlistp)
        : m_sampleFuncp{netlistp->evalFuncp(VEval::SAMPLE)} {
        findRanges(netlistp);
        iterate(netlistp);
        V3Sched::util::splitCheck(m_sampleFuncp);
    }
    ~SampledVisitor() override {
        V3Stats::addStat("Optimizations, Sampled variable ranges", m_statRanges);
    }
};

//######################################################################
// Sampled class functions

void V3Sampled::sampledAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { SampledVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("sampled", 0, dumpTreeEitherLevel() >= 3);
}
