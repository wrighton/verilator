// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Make lookup tables
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
// TABLE TRANSFORMATIONS:
//      Look at all large always and assignments.
//      Count # of input bits and # of output bits, and # of statements
//      If high # of statements relative to inpbits*outbits,
//      replace with lookup table
//      If the logic is the same as logic already converted, other than
//      using different input/output variables in the same positions,
//      reuse the tables built for that logic instead of simulating again
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Table.h"

#include "V3ConstPool.h"
#include "V3Hasher.h"
#include "V3SharedTmps.h"
#include "V3Simulate.h"
#include "V3Stats.h"

#include <cmath>
#include <unordered_map>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Table class functions

// CONFIG
// 1MB is max table size (better be lots of instructs to be worth it!)
static constexpr int TABLE_MAX_BYTES = 1 * 1024 * 1024;
// 64MB is close to max memory of some systems (256MB or so), so don't get out of control
static constexpr int TABLE_TOTAL_BYTES = 64 * 1024 * 1024;
// Worth no more than 8 bytes of data to replace an instruction
static constexpr int TABLE_SPACE_TIME_MULT = 8;
// If < 32 instructions, not worth the effort
static constexpr int TABLE_MIN_NODE_COUNT = 32;
// Assume an instruction is 4 bytes
static constexpr int TABLE_BYTES_PER_INST = 4;

//######################################################################

class TableVisitor;

class TableSimulateVisitor final : public SimulateVisitor {
    // MEMBERS
    TableVisitor* const m_cbthisp;  ///< Class for callback

public:
    ///< Call other-this function on all new var references
    void varRefCb(AstVarRef* nodep) override;

    // CONSTRUCTORS
    explicit TableSimulateVisitor(TableVisitor* cbthisp)
        : m_cbthisp{cbthisp} {}
    ~TableSimulateVisitor() override = default;
};

//######################################################################
// Class for holding lookup table state during construction

class TableBuilder final {
    FileLine* const m_fl;  // FileLine used during construction
    AstConsArray* m_consp = nullptr;  // The lookup table initializer values
    AstVarScope* m_varScopep = nullptr;  // The scoped variable holding the table

public:
    explicit TableBuilder(FileLine* fl)
        : m_fl{fl} {}

    ~TableBuilder() {
        if (m_consp) VL_DO_DANGLING(m_consp->deleteTree(), m_consp);
    }

    void setTableSize(AstNodeDType* elemDTypep, unsigned size) {
        UASSERT_OBJ(!m_consp, m_fl, "Table size already set");
        UASSERT_OBJ(size > 0, m_fl, "Size zero");
        // TODO: Assert elemDType is a packed type
        // Create data type
        const int width = elemDTypep->width();
        AstNodeDType* const subDTypep
            = elemDTypep->isString() || elemDTypep->isDouble()
                  ? elemDTypep
                  : v3Global.rootp()->findBitDType(width, width, VSigning::UNSIGNED);
        AstUnpackArrayDType* const tableDTypep = new AstUnpackArrayDType{
            m_fl, subDTypep, new AstRange{m_fl, static_cast<int>(size), 0}};
        v3Global.rootp()->typeTablep()->addTypesp(tableDTypep);
        // Create table initializer (with default value 0)
        AstConst* const defaultp
            = elemDTypep->isString()   ? new AstConst{m_fl, AstConst::String{}, ""}
              : elemDTypep->isDouble() ? new AstConst{m_fl, AstConst::RealDouble{}, 0.0}
                                       : new AstConst{m_fl, AstConst::WidthedValue{}, width, 0};
        m_consp = new AstConsArray{m_fl, tableDTypep, defaultp};
    }

    void addValue(unsigned index, const V3Number& value) {
        UASSERT_OBJ(!m_varScopep, m_fl, "Table variable already created");
        // Default value is zero/empty string so don't add it
        if (value.isString() ? value.toString().empty() : value.isEqZero()) return;
        m_consp->valuep(index, new AstConst{m_fl, value});
    }

    AstVarScope* varScopep() {
        if (!m_varScopep) {
            AstVarRef* const refp = V3ConstPool::find(m_consp);
            m_varScopep = refp->varScopep();
            VL_DO_DANGLING(refp->deleteTree(), refp);
        }
        return m_varScopep;
    }
};

//######################################################################
// Class for holding output variable state during table conversion of logic

class TableOutputVar final {
    AstVarScope* const m_varScopep;  // The output variable
    const unsigned m_ord;  // Output ordinal number in this block
    bool m_mayBeUnassigned = false;  // If true, then this variable may be unassigned through
                                     // some path through the block being table converted
    TableBuilder m_tableBuilder;

public:
    TableOutputVar(AstVarScope* varScopep, unsigned ord)
        : m_varScopep{varScopep}
        , m_ord{ord}
        , m_tableBuilder{varScopep->fileline()} {}

    AstVarScope* varScopep() const { return m_varScopep; }
    string name() const { return varScopep()->varp()->name(); }
    unsigned ord() const { return m_ord; }
    void setMayBeUnassigned() { m_mayBeUnassigned = true; }
    bool mayBeUnassigned() const { return m_mayBeUnassigned; }
    void setTableSize(unsigned size) { m_tableBuilder.setTableSize(varScopep()->dtypep(), size); }
    void addValue(unsigned index, const V3Number& value) { m_tableBuilder.addValue(index, value); }
    AstVarScope* tabeVarScopep() { return m_tableBuilder.varScopep(); }
};

//######################################################################
// Tables built for converted logic, and the logic they were built from

struct TableCacheEntry final {
    struct OutTable final {
        AstVarScope* const vscp;  // Table of the output value for each input value
        const bool mayBeUnassigned;  // Output may be unassigned for some input values
    };
    // Original statements of the logic, deleted at the end of the pass
    const AstNode* const stmtsp;
    // Number of each input/output variable, by position in the input/output lists
    std::unordered_map<AstVarScope*, uint32_t> varNums;
    AstVarScope* const assignedVscp;  // Table of the outputs assigned for each input value
    std::vector<OutTable> outTables;  // Per output
};

//######################################################################
// Table class functions

class TableVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared on each always/assignw
    //  AstVarScope::user4()    -> V3Hash. Variable number, see hashLogic (V3Hasher in use)

    // STATE
    double m_totalBytes = 0;  // Total bytes in tables created
    VDouble0 m_statTablesCre;  // Statistic tracking, including reused tables
    VDouble0 m_statTablesReused;  // Statistic tracking
    V3SharedTmps m_indexTmps{"__Vtableidx", VVarType::BLOCKTEMP};  // Table index variables

    //  State cleared on each scope
    AstScope* m_scopep = nullptr;  // Current SCOPE

    //  State cleared on each always/assignw
    bool m_assignDly = false;  // Consists of delayed assignments instead of normal assignments
    unsigned m_inWidthBits = 0;  // Input table width - in bits
    unsigned m_outWidthBytes = 0;  // Output table width - in bytes
    std::vector<AstVarScope*> m_inVarps;  // Input variable list
    std::vector<TableOutputVar> m_outVarps;  // Output variable list
    std::unordered_map<AstVarScope*, uint32_t> m_varNums;  // Number of each input/output variable

    // Converted logic, by hash of the statements with variables hashed by their number
    std::unordered_map<V3Hash, std::vector<TableCacheEntry>> m_cache;
    // Jump blocks of cached logic matched to the current logic, see sameLogic
    std::unordered_map<const AstNode*, const AstNode*> m_sameBlocks;

    // METHODS

public:
    void simulateVarRefCb(AstVarRef* nodep) {
        // Called by TableSimulateVisitor on each unique varref encountered
        UINFO(9, "   SimVARREF " << nodep);
        AstVarScope* const vscp = nodep->varScopep();
        if (nodep->access().isWriteOrRW()) {
            // We'll make the table with a separate natural alignment for each output var, so
            // always have 8, 16 or 32 bit widths, so use widthTotalBytes
            m_outWidthBytes += nodep->varp()->dtypeSkipRefp()->widthTotalBytes();
            m_outVarps.emplace_back(vscp, static_cast<unsigned>(m_outVarps.size()));
        }
        if (nodep->access().isReadOrRW()) {
            m_inWidthBits += nodep->varp()->width();
            m_inVarps.push_back(vscp);
        }
    }

private:
    bool treeTest(AstAlways* nodep) {
        // Process alw/assign tree
        m_inWidthBits = 0;
        m_outWidthBytes = 0;
        m_inVarps.clear();
        m_outVarps.clear();

        // Collect stats
        TableSimulateVisitor chkvis{this};
        chkvis.mainTableCheck(nodep);
        m_assignDly = chkvis.isAssignDly();
        // Also sets m_inWidthBits
        // Also sets m_outWidthBytes
        // Also sets m_inVarps
        // Also sets m_outVarps

        // Calc data storage in bytes
        const size_t chgWidth = m_outVarps.size();
        const double space = std::pow<double>(2.0, m_inWidthBits) * (m_outWidthBytes + chgWidth);
        // Instruction count bytes (ok, it's space also not time :)
        const double time  // max(_, 1), so we won't divide by zero
            = std::max<double>(chkvis.instrCount() * TABLE_BYTES_PER_INST + chkvis.dataCount(), 1);
        if (chkvis.isImpure()) chkvis.clearOptimizable(nodep, "Table creates side effects");
        if (chkvis.isCoverage()) {
            chkvis.clearOptimizable(nodep, "Table removes coverage points");
        }
        // cppcheck-suppress knownConditionTrueFalse // set by TableSimulateVisitor
        if (!m_outWidthBytes || !m_inWidthBits) {
            chkvis.clearOptimizable(nodep, "Table has no outputs");
        }
        if (chkvis.instrCount() < TABLE_MIN_NODE_COUNT) {
            chkvis.clearOptimizable(nodep, "Table has too few nodes involved");
        }
        // cppcheck-suppress knownConditionTrueFalse
        if (space > TABLE_MAX_BYTES) {
            chkvis.clearOptimizable(nodep, "Table takes too much space");
        }
        if (space > time * TABLE_SPACE_TIME_MULT) {
            chkvis.clearOptimizable(nodep, "Table has bad tradeoff");
        }
        if (m_totalBytes > TABLE_TOTAL_BYTES) {
            chkvis.clearOptimizable(nodep, "Table out of memory");
        }
        UINFO(4, "  Test: Opt=" << (chkvis.optimizable() ? "OK" : "NO") << ", Instrs="
                                << chkvis.instrCount() << " Data=" << chkvis.dataCount()
                                << " in width (bits)=" << m_inWidthBits << " out width (bytes)="
                                << m_outWidthBytes << " Spacetime=" << (space / time) << "("
                                << space << "/" << time << ")" << ": " << nodep);
        if (chkvis.optimizable()) {
            UINFO(3, " Table Optimize spacetime=" << (space / time) << " " << nodep);
            m_totalBytes += space;
        }
        return chkvis.optimizable();
    }

    void numberVar(AstVarScope* const vscp) {
        // Number by position in the input/output lists, so logic in different scopes can match.
        // V3Simulate may use the value of a variable that has one instead of the input, so such
        // variables are not numbered and only match themselves.
        if (vscp->varp()->valuep()) return;
        // Numbers start at 1, as V3Hasher does not use a cached hash of 0
        m_varNums.emplace(vscp, m_varNums.size() + 1);
    }

    V3Hash hashLogic(AstNode* stmtsp) const {
        const V3Hasher hasher;
        // V3Hasher uses the hash cached in user4, so this hashes variables by their number
        for (const auto& pair : m_varNums) pair.first->user4(pair.second);
        V3Hash hash;
        for (AstNode* nodep = stmtsp; nodep; nodep = nodep->nextp()) hash += hasher(nodep);
        return hash;
    }

    static uint32_t varNum(const std::unordered_map<AstVarScope*, uint32_t>& varNums,
                           AstVarScope* const vscp) {
        const auto it = varNums.find(vscp);
        return it == varNums.end() ? 0 : it->second;
    }

    bool sameLogic(const TableCacheEntry& entry, const AstNode* ap, const AstNode* bp) {
        // Like AstNode::sameTree, but numbered variables must have the same number, and jumps
        // must go to corresponding blocks. Otherwise a mismatch needs a hash collision.
        while (true) {
            if (!ap || !bp) return ap == bp;
            if (ap->type() != bp->type()) return false;
            UASSERT_OBJ(!ap->dtypep() == !bp->dtypep(), ap,
                        "Comparison of a node with dtypep() with a node without dtypep()");
            if (ap->dtypep() && !ap->dtypep()->similarDType(bp->dtypep())) return false;
            if (const AstVarRef* const arefp = VN_CAST(ap, VarRef)) {
                const AstVarRef* const brefp = VN_AS(bp, VarRef);
                const uint32_t anum = varNum(entry.varNums, arefp->varScopep());
                if (anum ? (anum != varNum(m_varNums, brefp->varScopep())
                            || arefp->access() != brefp->access())
                         : !ap->isSame(bp)) {
                    return false;
                }
            } else if (const AstJumpGo* const agop = VN_CAST(ap, JumpGo)) {
                // The block encloses the jump, so is mapped already if the logic is the same
                if (m_sameBlocks[agop->blockp()] != VN_AS(bp, JumpGo)->blockp()) return false;
            } else if (!ap->isSame(bp)) {
                return false;
            } else if (VN_IS(ap, JumpBlock)) {
                m_sameBlocks[ap] = bp;
            }
            if (!sameLogic(entry, ap->op1p(), bp->op1p())
                || !sameLogic(entry, ap->op2p(), bp->op2p())
                || !sameLogic(entry, ap->op3p(), bp->op3p())
                || !sameLogic(entry, ap->op4p(), bp->op4p())) {
                return false;
            }
            ap = ap->nextp();
            bp = bp->nextp();
        }
    }

    void replaceWithTable(AstAlways* nodep) {
        // We've determined this table of nodes is optimizable, do it.
        ++m_statTablesCre;

        FileLine* const fl = nodep->fileline();

        // We will need a table index variable, create it here.
        AstVarScope* const indexVscp = m_indexTmps.make(fl, m_scopep, m_inWidthBits);

        // Find the tables of the same logic, or build them
        m_varNums.clear();
        m_varNums.reserve(m_inVarps.size() + m_outVarps.size());
        for (AstVarScope* const vscp : m_inVarps) numberVar(vscp);
        for (const TableOutputVar& tov : m_outVarps) numberVar(tov.varScopep());
        std::vector<TableCacheEntry>& entries = m_cache[hashLogic(nodep->stmtsp())];
        const TableCacheEntry* entryp = nullptr;
        for (const TableCacheEntry& entry : entries) {
            const bool same = sameLogic(entry, entry.stmtsp, nodep->stmtsp());
            m_sameBlocks.clear();
            if (same) {
                entryp = &entry;
                break;
            }
        }
        if (entryp) {
            ++m_statTablesReused;
            UASSERT_OBJ(entryp->outTables.size() == m_outVarps.size(), nodep,
                        "Reusing tables with a different number of outputs");
        } else {
            // The 'output assigned' table builder
            TableBuilder outputAssignedTableBuilder{fl};
            outputAssignedTableBuilder.setTableSize(
                nodep->findBitDType(m_outVarps.size(), m_outVarps.size(), VSigning::UNSIGNED),
                VL_MASK_I(m_inWidthBits));

            // Set sizes of output tables
            for (TableOutputVar& tov : m_outVarps) tov.setTableSize(VL_MASK_I(m_inWidthBits));

            // Populate the tables
            createTables(nodep, outputAssignedTableBuilder);

            AstVarScope* const assignedVscp = outputAssignedTableBuilder.varScopep();
            std::vector<TableCacheEntry::OutTable> outTables;
            outTables.reserve(m_outVarps.size());
            for (TableOutputVar& tov : m_outVarps) {
                outTables.push_back({tov.tabeVarScopep(), tov.mayBeUnassigned()});
            }
            entries.push_back(
                {nodep->stmtsp(), std::move(m_varNums), assignedVscp, std::move(outTables)});
            entryp = &entries.back();
        }

        AstNodeStmt* const stmtsp = createLookupInput(fl, indexVscp);
        createOutputAssigns(nodep, stmtsp, indexVscp, *entryp);

        // Link it in.
        // Replace the body, keeping the AstAlways itself under its AstActive.
        // A new cache entry needs the original statements until the end of the pass, the
        // statements of reused logic are freed now, as there may be many copies of it.
        AstNode* const oldStmtsp = nodep->stmtsp()->unlinkFrBackWithNext();
        if (oldStmtsp == entryp->stmtsp) {
            VL_DO_DANGLING(pushDeletep(oldStmtsp), oldStmtsp);
        } else {
            VL_DO_DANGLING(oldStmtsp->deleteTree(), oldStmtsp);
        }
        nodep->addStmtsp(stmtsp);
        UINFOTREE(6, nodep, "", "table_new");
    }

    void createTables(AstAlways* nodep, TableBuilder& outputAssignedTableBuilder) {
        // Create table
        // There may be a simulation path by which the output doesn't change value.
        // We could bail on these cases, or we can have a "change it" boolean.
        // We've chosen the latter route, since recirc is common in large FSMs.
        TableSimulateVisitor simvis{this};
        for (uint32_t i = 0; i <= VL_MASK_I(m_inWidthBits); ++i) {
            const uint32_t inValue = i;
            // Make a new simulation structure so we can set new input values
            UINFO(8, " Simulating " << std::hex << inValue);

            // Above simulateVisitor clears user 3, so
            // all outputs default to nullptr to mean 'recirculating'.
            simvis.clear();

            // Set all inputs to the constant
            uint32_t shift = 0;
            for (AstVarScope* invscp : m_inVarps) {
                // LSB is first variable, so extract it that way
                const AstConst cnst{invscp->fileline(), AstConst::WidthedValue{}, invscp->width(),
                                    VL_MASK_I(invscp->width()) & (inValue >> shift)};
                simvis.newValue(invscp, &cnst);
                shift += invscp->width();
                // We are using 32 bit arithmetic, because there's no way the input table can be
                // 2^32 bytes!
                UASSERT_OBJ(shift <= 32, nodep, "shift overflow");
                UINFO(8, "   Input " << invscp->name() << " = " << cnst.name());
            }

            // Simulate
            simvis.mainTableEmulate(nodep);
            UASSERT_OBJ(simvis.optimizable(), simvis.whyNotNodep(),
                        "Optimizable cleared, even though earlier test run said not: "
                            << simvis.whyNotMessage());

            // Build output value tables and the assigned flags table
            V3Number outputAssignedMask{nodep, static_cast<int>(m_outVarps.size()), 0};
            for (TableOutputVar& tov : m_outVarps) {
                if (V3Number* const outnump = simvis.fetchOutNumberNull(tov.varScopep())) {
                    UINFO(8, "   Output " << tov.name() << " = " << *outnump);
                    UASSERT_OBJ(!outnump->isAnyXZ(), outnump, "Table should not contain X/Z");
                    outputAssignedMask.setBit(tov.ord(), 1);  // Mark output as assigned
                    tov.addValue(inValue, *outnump);
                } else {
                    UINFO(8, "   Output " << tov.name() << " not set for this input");
                    tov.setMayBeUnassigned();
                }
            }

            // Set changed table
            outputAssignedTableBuilder.addValue(inValue, outputAssignedMask);
        }  // each value
    }

    AstNodeStmt* createLookupInput(FileLine* fl, AstVarScope* indexVscp) {
        // Concat inputs into a single temp variable (inside always)
        // First var in inVars becomes the LSB of the concat
        AstNodeExpr* concatp = nullptr;
        for (AstVarScope* invscp : m_inVarps) {
            AstVarRef* const refp = new AstVarRef{fl, invscp, VAccess::READ};
            if (concatp) {
                concatp = new AstConcat{fl, refp, concatp};
            } else {
                concatp = refp;
            }
        }

        return new AstAssign{fl, new AstVarRef{fl, indexVscp, VAccess::WRITE}, concatp};
    }

    AstArraySel* select(FileLine* fl, AstVarScope* fromp, AstVarScope* indexp) {
        AstVarRef* const fromRefp = new AstVarRef{fl, fromp, VAccess::READ};
        AstVarRef* const indexRefp = new AstVarRef{fl, indexp, VAccess::READ};
        return new AstArraySel{fl, fromRefp, indexRefp};
    }

    void createOutputAssigns(AstNode* nodep, AstNode* stmtsp, AstVarScope* indexVscp,
                             const TableCacheEntry& entry) {
        FileLine* const fl = nodep->fileline();
        for (const TableOutputVar& tov : m_outVarps) {
            const TableCacheEntry::OutTable& outTable = entry.outTables[tov.ord()];
            AstNodeExpr* const alhsp = new AstVarRef{fl, tov.varScopep(), VAccess::WRITE};
            AstNodeExpr* const arhsp = select(fl, outTable.vscp, indexVscp);
            AstNodeStmt* outsetp
                = m_assignDly ? static_cast<AstNodeStmt*>(new AstAssignDly{fl, alhsp, arhsp})
                              : static_cast<AstNodeStmt*>(new AstAssign{fl, alhsp, arhsp});

            // If this output is unassigned on some code paths, wrap the assignment in an If
            if (outTable.mayBeUnassigned) {
                V3Number outputChgMask{nodep, static_cast<int>(m_outVarps.size()), 0};
                outputChgMask.setBit(tov.ord(), 1);
                AstNodeExpr* const condp
                    = new AstNeq{fl,
                                 new AstAnd{fl, select(fl, entry.assignedVscp, indexVscp),
                                            new AstConst{fl, outputChgMask}},
                                 new AstConst{fl, AstConst::WidthedValue{},
                                              static_cast<int>(m_outVarps.size()), 0}};
                outsetp = new AstIf{fl, condp, outsetp};
            }

            stmtsp->addNext(outsetp);
        }
    }

    // VISITORS
    void visit(AstNode* nodep) override { iterateChildren(nodep); }
    void visit(AstScope* nodep) override {
        UINFO(4, " SCOPE " << nodep);
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        iterateChildren(nodep);
    }
    void visit(AstAlways* nodep) override {
        UINFO(4, "  ALWAYS  " << nodep);
        if (treeTest(nodep)) {
            // Well, then, I'll be a memory hog.
            replaceWithTable(nodep);
        }
    }
    void visit(AstNodeAssign* nodep) override {
        // It's nearly impossible to have a large enough assign to make this worthwhile
        // For now we won't bother.
        // Accelerated: no iterate
    }

public:
    // CONSTRUCTORS
    explicit TableVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~TableVisitor() override {  //
        V3Stats::addStat("Optimizations, Tables created", m_statTablesCre);
        V3Stats::addStat("Optimizations, Tables reused", m_statTablesReused);
    }
};

//######################################################################

void TableSimulateVisitor::varRefCb(AstVarRef* nodep) {
    // Called by checking on each new varref encountered
    // We cross-call into a TableVisitor function.
    m_cbthisp->simulateVarRefCb(nodep);
}

//######################################################################
// Table class functions

void V3Table::tableAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { TableVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("table", 0, dumpTreeEitherLevel() >= 3);
}
