// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Estimate instruction count to run the logic
//                         we would generate for any given AST subtree.
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

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3InstrCount.h"

#include "V3Stats.h"

#include <iomanip>
#include <unordered_map>
#include <unordered_set>

VL_DEFINE_DEBUG_FUNCTIONS;

/// Estimate the instruction cost for executing all logic within and below
/// a given AST node. Note this estimates the number of instructions we'll
/// execute, not the number we'll generate. That is, for conditionals,
/// we'll count instructions from either the 'if' or the 'else' branch,
/// whichever is larger. We know we won't run both.
///
/// Branch prediction, also used for V3Branch:
///     At each IF/(IF else) without a prediction yet.
///         Count underneath $display/$stop statements.
///         The branch with more is unlikely.
///     A branch predicted not taken has zero cost.
///
/// The functions called from a node are counted before the node, depth first with an explicit
/// stack, as call chains can be deeper than recursion can go on the C++ stack. To visit them in
/// the order the count reaches them, each node is first walked in a 'finding' mode, which records
/// the functions reached, then counted once they are all counted.

class InstrCountVisitor final : public VNVisitorConst {
    // NODE STATE
    //  AstNode::user1()        -> bool. Processed if assertNoDups
    //  AstNode::user2()        -> uint64_t.  Path cost + 1, 0 means don't dump
    const VNUser2InUse m_inuser2;

    // TYPES
    // Functions reached in order, and whether reached directly rather than called
    using FoundFuncs = std::vector<std::pair<AstCFunc*, bool>>;

    // MEMBERS
    uint32_t m_instrCount = 0;  // Running count of instructions
    const AstNode* const m_startNodep;  // Start node of count
    bool m_finding = false;  // Only finding the functions reached, see 'findFuncs'
    FoundFuncs* m_foundp = nullptr;  // In 'finding' mode, the functions reached
    bool m_inCFunc = false;  // Inside AstCFunc
    bool m_ignoreRemaining = false;  // Ignore remaining statements in the block
    int m_unlikely = 0;  // Excuses for branch likely not taken
    size_t m_statLikely = 0;  // Statistic tracking
    size_t m_statUnlikely = 0;  // Statistic tracking
    const bool m_assertNoDups;  // Check for duplicates
    const std::ostream* const m_osp;  // Dump file
    std::unordered_map<const AstCFunc*, uint32_t> m_funcCosts;  // Cost of each function
    // Functions counted where first reached directly from a netlist, rather than called
    std::unordered_set<const AstCFunc*> m_directFirst;

    // Little class to cleanly call startVisitBase/endVisitBase
    class VisitBase final {
        // MEMBERS
        uint32_t m_savedCount;  // Count before visit applied
        AstNode* const m_nodep;  // Node helper is visiting
        InstrCountVisitor* const m_visitorp;  // Visitor whose start/endVisitBase are called

    public:
        // CONSTRUCTORS
        VisitBase(InstrCountVisitor* visitorp, AstNode* nodep)
            : m_nodep{nodep}
            , m_visitorp{visitorp} {
            m_savedCount = m_visitorp->startVisitBase(nodep);
        }
        ~VisitBase() { m_visitorp->endVisitBase(m_savedCount, m_nodep); }

    private:
        VL_UNCOPYABLE(VisitBase);
    };

public:
    // CONSTRUCTORS
    InstrCountVisitor(AstNode* nodep, bool assertNoDups, std::ostream* osp)
        : m_startNodep{nodep}
        , m_assertNoDups{assertNoDups}
        , m_osp{osp} {
        countDepthFirst(nodep);
    }
    ~InstrCountVisitor() override {
        V3Stats::addStatSum("Optimizations, Branch prediction likely", m_statLikely);
        V3Stats::addStatSum("Optimizations, Branch prediction unlikely", m_statUnlikely);
    }

    // METHODS
    uint32_t instrCount() const { return m_instrCount; }

private:
    void reset() {
        m_instrCount = 0;
        m_ignoreRemaining = false;
    }

    // Count 'nodep', the start node, after the functions it reaches, see the file header
    void countDepthFirst(AstNode* nodep) {
        if (!nodep) return;
        struct Frame final {
            AstNode* nodep;  // Start node or function to count
            FoundFuncs found;  // Functions it reaches
            size_t next;  // Index of next function in 'found' to consider
        };
        std::vector<Frame> stack;
        if (AstCFunc* const funcp = VN_CAST(nodep, CFunc)) m_funcCosts.emplace(funcp, 0);
        stack.push_back({nodep, findFuncs(nodep), 0});
        while (!stack.empty()) {
            Frame& frame = stack.back();
            if (frame.next < frame.found.size()) {
                AstCFunc* const funcp = frame.found[frame.next].first;
                const bool direct = frame.found[frame.next].second;
                ++frame.next;
                // Count each function once, where first reached. A function being counted costs
                // zero, as on a recursive call.
                if (!m_funcCosts.emplace(funcp, 0).second) continue;
                if (direct) m_directFirst.emplace(funcp);
                FoundFuncs found = findFuncs(funcp);
                stack.push_back({funcp, std::move(found), 0});
                continue;
            }
            AstNode* const countp = frame.nodep;
            stack.pop_back();
            if (AstCFunc* const funcp = VN_CAST(countp, CFunc)) {
                walkFunction(funcp);
                m_funcCosts.at(funcp) = m_instrCount;
            } else {
                reset();
                iterateConst(countp);
            }
        }
    }

    // Walk 'nodep' as when counting it, returning the functions reached in order
    FoundFuncs findFuncs(AstNode* nodep) {
        FoundFuncs found;
        VL_RESTORER(m_finding);
        VL_RESTORER(m_foundp);
        VL_RESTORER(m_instrCount);
        VL_RESTORER(m_ignoreRemaining);
        VL_RESTORER(m_unlikely);
        VL_RESTORER(m_inCFunc);
        m_finding = true;
        m_foundp = &found;
        if (AstCFunc* const funcp = VN_CAST(nodep, CFunc)) {
            walkFunction(funcp);
        } else {
            iterateConst(nodep);
        }
        return found;
    }

    // Walk the body of 'funcp', once the functions it calls are counted unless finding them
    void walkFunction(AstCFunc* funcp) {
        // The caller's branch counts the call, not the statements within
        VL_RESTORER(m_unlikely);
        VL_RESTORER(m_inCFunc);
        m_inCFunc = true;
        reset();
        const VisitBase vb{this, funcp};
        iterateChildrenConst(funcp);
    }

    // Do not dump 'nodep', as in a branch not taken
    void dontDump(AstNode* nodep) {
        if (nodep && !m_finding) nodep->user2(0);
    }
    uint32_t startVisitBase(AstNode* nodep) {
        UASSERT_OBJ(!m_ignoreRemaining, nodep, "Should not reach here if ignoring");
        if (nodep->isUnlikely()) ++m_unlikely;
        if (m_assertNoDups && !m_inCFunc && !m_finding) {
            // Ensure we don't count the same node twice
            //
            // We only enable this assert for the initial LogicMTask counts
            // in V3Order. We can't enable it for the 2nd pass in V3EmitC,
            // as we expect mtasks to contain common logic after V3Combine,
            // so this would fail.
            //
            // Also, we expect some collisions within calls to CFuncs
            // (which at the V3Order stage represent verilog tasks, not to
            // the CFuncs that V3Order will generate.) So don't check for
            // collisions in CFuncs.
            UASSERT_OBJ(!nodep->user1p(), nodep,
                        "Node originally inserted below logic vertex "
                            << static_cast<AstNode*>(nodep->user1p()));
            nodep->user1p(const_cast<void*>(reinterpret_cast<const void*>(m_startNodep)));
        }

        // Save the count, and add it back in during ~VisitBase This allows
        // debug prints to show local cost of each subtree, so we can see a
        // hierarchical view of the cost when in debug mode.
        const uint32_t savedCount = m_instrCount;
        m_instrCount = nodep->instrCount();
        return savedCount;
    }
    void endVisitBase(uint32_t savedCount, AstNode* nodep) {
        if (!m_finding) {
            UINFO(8, "cost " << std::setw(6) << std::left << m_instrCount << "  " << nodep);
        }
        markCost(nodep);
        if (!m_ignoreRemaining) m_instrCount += savedCount;
    }
    void markCost(AstNode* nodep) {
        // Else don't mark to avoid writeback
        if (m_osp && !m_finding) nodep->user2(m_instrCount + 1);
    }

    // VISITORS
    void visit(AstNodeSel* nodep) override {
        if (m_ignoreRemaining) return;
        // This covers both AstArraySel and AstWordSel
        //
        // If some vector is a bazillion dwords long, and we're selecting 1
        // dword to read or write from it, our cost should be small.
        //
        // Hence, exclude the child of the AstWordSel from the computation,
        // whose cost scales with the size of the entire (maybe large) vector.
        const VisitBase vb{this, nodep};
        iterateAndNextConstNull(nodep->bitp());
    }
    void visit(AstSel* nodep) override {
        if (m_ignoreRemaining) return;
        // Similar to AstNodeSel above, a small select into a large vector
        // is not expensive. Count the cost of the AstSel itself (scales with
        // its width) and the cost of the lsbp() and widthp() nodes, but not
        // the fromp() node which could be disproportionately large.
        const VisitBase vb{this, nodep};
        iterateAndNextConstNull(nodep->lsbp());
    }
    void visit(AstConcat* nodep) override {
        if (m_ignoreRemaining) return;
        // Ignore the cost of the concat node itself. The problem with
        // counting concat is that when we have many things concatted
        // together, it's not a single operation, but this:
        //
        //  concat(a, concat(b, concat(c, concat(d, ... ))))
        //
        // Then if we account a cost to each 'concat' that scales with its
        // width, this whole operation ends up with a cost accounting that
        // scales with N^2. Of course, the real operation isn't that
        // expensive: we won't copy each element over and over, we'll just
        // copy it once from its origin into its destination, so the actual
        // cost is linear with the size of the data. We don't need to count
        // the concat at all to reflect a linear cost; it's already there
        // in the width of the destination (which we count) and the sum of
        // the cost of the operands.
        iterateChildrenConst(nodep);
        markCost(nodep);
    }
    void visit(AstIf* nodep) override {
        if (m_ignoreRemaining) return;
        const VisitBase vb{this, nodep};
        // Unlikely statements below count only for the branch they are in
        VL_RESTORER(m_unlikely);
        iterateAndNextConstNull(nodep->condp());
        const uint32_t savedCount = m_instrCount;

        UINFO(8, "thensp:");
        reset();
        m_unlikely = 0;
        iterateAndNextConstNull(nodep->thensp());
        uint32_t ifCount = m_instrCount;
        const int thenUnlikely = m_unlikely;

        UINFO(8, "elsesp:");
        reset();
        m_unlikely = 0;
        iterateAndNextConstNull(nodep->elsesp());
        uint32_t elseCount = m_instrCount;
        const int elseUnlikely = m_unlikely;

        if (nodep->branchPred().unknown() && !m_finding) {
            if (elseUnlikely > thenUnlikely) {
                nodep->branchPred(VBranchPred::BP_LIKELY);
                ++m_statLikely;
            } else if (elseUnlikely < thenUnlikely) {
                nodep->branchPred(VBranchPred::BP_UNLIKELY);
                ++m_statUnlikely;
            }  // else leave unknown
        }
        if (nodep->branchPred().unlikely()) ifCount = 0;
        if (nodep->branchPred().likely()) elseCount = 0;

        reset();
        if (ifCount >= elseCount) {
            m_instrCount = savedCount + ifCount;
            dontDump(nodep->elsesp());
        } else {
            m_instrCount = savedCount + elseCount;
            dontDump(nodep->thensp());
        }
    }
    void visit(AstCond* nodep) override {
        if (m_ignoreRemaining) return;
        // Just like if/else above, the ternary operator only evaluates
        // one of the two expressions, so only count the max.
        const VisitBase vb{this, nodep};
        iterateAndNextConstNull(nodep->condp());
        const uint32_t savedCount = m_instrCount;

        UINFO(8, "?");
        reset();
        iterateAndNextConstNull(nodep->thenp());
        const uint32_t ifCount = m_instrCount;

        UINFO(8, ":");
        reset();
        iterateAndNextConstNull(nodep->elsep());
        const uint32_t elseCount = m_instrCount;

        reset();
        if (ifCount >= elseCount) {
            m_instrCount = savedCount + ifCount;
            dontDump(nodep->elsep());
        } else {
            m_instrCount = savedCount + elseCount;
            dontDump(nodep->thenp());
        }
    }
    void visit(AstCAwait* nodep) override {
        if (m_ignoreRemaining) return;
        iterateChildrenConst(nodep);
        // Anything past a co_await is irrelevant
        m_ignoreRemaining = true;
    }
    void visit(AstFork* nodep) override {
        if (m_ignoreRemaining) return;
        const VisitBase vb{this, nodep};
        iterateAndNextConstNull(nodep->stmtsp());
        uint32_t totalCount = m_instrCount;
        // Sum counts in each statement until the first await
        for (AstNode* const stmtp : nodep->forkspList()) {
            reset();
            iterateConst(stmtp);
            totalCount += m_instrCount;
        }
        m_instrCount = totalCount;
        m_ignoreRemaining = false;
    }
    void visit(AstActive* nodep) override {
        // You'd think that the OrderLogicVertex's would be disjoint trees
        // of stuff in the AST, but it isn't so: V3Order makes an
        // OrderLogicVertex for each ACTIVE, and then also makes an
        // OrderLogicVertex for each statement within the ACTIVE.
        //
        // To avoid double-counting costs, stop recursing and short-circuit
        // the computation for each ACTIVE.
        //
        // Our intent is that this only stops at the root node of the
        // search; there should be no actives beneath the root, as there
        // are no actives-under-actives.  In any case, check that we're at
        // root:
        markCost(nodep);
        UASSERT_OBJ(nodep == m_startNodep, nodep, "Multiple actives, or not start node");
    }
    void visit(AstNodeCCall* nodep) override {
        if (m_ignoreRemaining) return;
        const VisitBase vb{this, nodep};
        iterateChildrenConst(nodep);
        if (m_finding) {
            m_foundp->emplace_back(nodep->funcp(), false);
            return;
        }
        // The function is counted already, or is being counted and costs zero on this recursive
        // call
        m_instrCount += m_funcCosts.at(nodep->funcp());
    }
    void visit(AstCFunc* nodep) override {
        // Only reached directly from a netlist, as the start node and called functions are
        // walked by 'walkFunction'. From a netlist, count each CFunc once, where first reached.
        UASSERT_OBJ(VN_IS(m_startNodep, Netlist), nodep,
                    "AstCFunc not under AstCCall, or not start node");
        if (m_finding) {
            m_foundp->emplace_back(nodep, true);
            return;
        }
        if (!m_directFirst.count(nodep)) return;
        UASSERT_OBJ(!m_ignoreRemaining, nodep, "Should not be ignoring at the start of a CFunc");
        m_instrCount += m_funcCosts.at(nodep);
    }
    void visit(AstNodeCons* nodep) override {
        if (m_ignoreRemaining) return;
        const VisitBase vb{this, nodep};
        // A constant value is not built at run time, so its parts cost nothing
        if (!nodep->isConstantTree()) iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override {
        if (m_ignoreRemaining) return;
        const VisitBase vb{this, nodep};
        iterateChildrenConst(nodep);
    }

    VL_UNCOPYABLE(InstrCountVisitor);
};

// Iterate the graph printing the critical path marked by previous visitation
class InstrCountDumpVisitor final : public VNVisitorConst {
    // NODE STATE
    //  AstNode::user2()        -> int.  Path cost, 0 means don't dump

    // MEMBERS
    std::ostream* const m_osp;  // Dump file
    unsigned m_depth = 0;  // Current tree depth for printing indent

public:
    // CONSTRUCTORS
    InstrCountDumpVisitor(AstNode* nodep, std::ostream* osp)
        : m_osp{osp} {
        // No check for nullptr output, so...
        UASSERT_OBJ(osp, nodep, "Don't call if not dumping");
        if (nodep) iterateConst(nodep);
    }
    ~InstrCountDumpVisitor() override = default;

private:
    // METHODS
    string indent() const { return string(m_depth, ':') + " "; }
    void visit(AstNode* nodep) override {
        ++m_depth;
        if (const unsigned costPlus1 = nodep->user2()) {
            *m_osp << "  " << indent() << "cost " << std::setw(6) << std::left << (costPlus1 - 1)
                   << "  " << nodep << '\n';
            iterateChildrenConst(nodep);
        }
        --m_depth;
    }

    VL_UNCOPYABLE(InstrCountDumpVisitor);
};

uint32_t V3InstrCount::count(AstNode* nodep, bool assertNoDups, std::ostream* osp) {
    const InstrCountVisitor visitor{nodep, assertNoDups, osp};
    if (osp) const InstrCountDumpVisitor dumper{nodep, osp};
    return visitor.instrCount();
}
