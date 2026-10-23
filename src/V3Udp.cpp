// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Implementation of User defined primitives
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
// V3Udp's Transformations:
//
// For every table line create an always block containing if statements
// with condition depending on a combination of the input fields:
//
// 0 1 0 on a, b, c turns into !a&b&~c
//
// Before that, check that no two table lines can match the same input
// combination yet give different outputs. Each input field is reduced to the
// set of (previous, current) value pairs it matches: a level symbol matches
// only stable pairs, and an edge symbol only changing pairs, so level lines
// never overlap edge lines (level lines take precedence), and edges on
// different inputs never overlap.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Udp.h"

#include "V3Error.h"

#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

class UdpVisitor final : public VNVisitor {
    bool m_inInitial = false;  // Is inside of an initial block
    AstVar* m_oFieldVarp = nullptr;  // Output filed var of table line
    std::vector<AstVar*> m_inputVars;  // All the input vars in the AstPrimitive
    std::vector<AstVar*> m_outputVars;  // All the output vars in the AstPrimitive
    AstPrimitive* m_primp = nullptr;  // The current primitive
    bool m_isFirstOutput = false;  // Whether the first IO port is output
    AstVarRef* m_outputInitVerfp = nullptr;  // Initial output value for sequential UDP
    AstAlways* m_alwaysBlockp = nullptr;  // Main Always block in UDP transform

    void visit(AstInitial* nodep) override {
        VL_RESTORER(m_inInitial);
        if (m_primp) m_inInitial = true;
        iterateChildren(nodep);
    }
    void visit(AstAssign* nodep) override {
        if (m_inInitial) { m_outputInitVerfp = VN_CAST(nodep->lhsp(), VarRef); }
        iterateChildren(nodep);
    }
    void visit(AstPrimitive* nodep) override {
        UASSERT_OBJ(!m_primp, nodep, "Primitives cannot nest");
        VL_RESTORER(m_primp);
        VL_RESTORER(m_outputInitVerfp);
        VL_RESTORER(m_isFirstOutput);
        VL_RESTORER_CLEAR(m_inputVars);
        VL_RESTORER_CLEAR(m_outputVars);
        m_outputInitVerfp = nullptr;
        m_primp = nodep;
        m_isFirstOutput = false;
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        // Push the input and output vars for primitive.
        if (m_primp) {
            if (nodep->isIO()) {
                if (nodep->isInput()) {
                    m_inputVars.push_back(nodep);
                } else {
                    m_outputVars.push_back(nodep);
                }
                if ((m_inputVars.size() == 0) && (m_outputVars.size() == 1)) {
                    m_isFirstOutput = true;
                }
            }
        }
        iterateChildren(nodep);
    }
    void visit(AstUdpTable* nodep) override {
        FileLine* const fl = nodep->fileline();
        if (m_outputVars.size() != 1) {
            m_outputVars.back()->v3error(
                m_outputVars.size()
                << " output ports for UDP table, there must be one output port");
        }
        if (!m_isFirstOutput && m_outputVars.size()) {
            m_inputVars[0]->v3error("First UDP port must be the output port");
        }
        m_oFieldVarp = m_outputVars[0];
        checkConflicts(nodep);

        m_alwaysBlockp = new AstAlways{fl, VAlwaysKwd::ALWAYS, nullptr, nullptr};
        fl->warnOff(V3ErrorCode::LATCH, true);
        iterateChildren(nodep);

        nodep->replaceWith(m_alwaysBlockp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstUdpTableLine* nodep) override {
        FileLine* const fl = nodep->fileline();
        if (!nodep->udpIsCombo() && !m_oFieldVarp->isBitLogic()) {
            m_oFieldVarp->v3error("For sequential UDP, the output must be of 'reg' data type");
        }
        if (nodep->udpIsCombo() && m_oFieldVarp->isBitLogic()) {
            m_oFieldVarp->v3error(
                "For combinational UDP, the output must not be a 'reg' data type");
        }
        AstNode* iNodep = nodep->iFieldsp();
        AstNode* oNodep = nodep->oFieldsp();
        AstSenTree* edgetrigp = nullptr;

        AstLogAnd* logandp = new AstLogAnd{fl, new AstConst{fl, AstConst::BitTrue{}},
                                           new AstConst{fl, AstConst::BitTrue{}}};

        for (AstVar* const varp : m_inputVars) {
            if (!iNodep) break;
            if (AstUdpTableLineVal* linevalp = VN_CAST(iNodep, UdpTableLineVal)) {
                string valName = linevalp->name();
                if (isEdgeTrig(valName)) {
                    if (nodep->udpIsCombo()) {
                        linevalp->v3error(
                            "There should not be a edge trigger for combinational UDP table line");
                    }
                    if (edgetrigp) {
                        linevalp->v3error("There can be only one edge trigger signal");
                        VL_DO_DANGLING(pushDeletep(edgetrigp), edgetrigp);
                    }
                    edgetrigp = new AstSenTree{
                        fl, new AstSenItem{fl, VEdgeType::ET_BOTHEDGE,
                                           new AstVarRef{fl, varp, VAccess::READ}}};
                }
                if (valName == "0" || valName == "f") {
                    logandp = new AstLogAnd{
                        fl, logandp, new AstLogNot{fl, new AstVarRef{fl, varp, VAccess::READ}}};
                } else if (valName == "1" || valName == "r") {
                    logandp = new AstLogAnd{fl, logandp, new AstVarRef{fl, varp, VAccess::READ}};
                } else if (valName == "x" || valName == "X") {
                    // No x inputs supported yet, so this whole table line
                    // can never match. Drop the whole thing.
                    if (edgetrigp) VL_DO_DANGLING(pushDeletep(edgetrigp), edgetrigp);
                    if (logandp) VL_DO_DANGLING(pushDeletep(logandp), logandp);
                    return;
                }
            }
            iNodep = iNodep->nextp();
        }

        const size_t inputvars = nodep->iFieldspList().size();
        if (inputvars != m_inputVars.size()) {
            nodep->v3error("Incorrect number of input values, expected " << m_inputVars.size()
                                                                         << ", got " << inputvars);
        }

        string const oValName = nodep->udpIsCombo() ? oNodep->name() : oNodep->nextp()->name();
        if (oValName == "-") {
            if (edgetrigp) VL_DO_DANGLING(pushDeletep(edgetrigp), edgetrigp);
            if (logandp) VL_DO_DANGLING(pushDeletep(logandp), logandp);
            return;
        }

        if (!nodep->udpIsCombo()) {
            if (oNodep->name() == "0") {
                logandp = new AstLogAnd{
                    fl, logandp,
                    new AstLogNot{fl, new AstVarRef{fl, m_oFieldVarp, VAccess::READ}}};
            } else if (oNodep->name() == "1") {
                logandp
                    = new AstLogAnd{fl, logandp, new AstVarRef{fl, m_oFieldVarp, VAccess::READ}};
            } else if (oNodep->name() == "x" || oNodep->name() == "X") {
                // No x inputs supported yet, so this whole table line
                // can never match. Drop the whole thing.
                if (edgetrigp) VL_DO_DANGLING(pushDeletep(edgetrigp), edgetrigp);
                if (logandp) VL_DO_DANGLING(pushDeletep(logandp), logandp);
                return;
            }
        }

        fl->warnOff(V3ErrorCode::LATCH, true);
        // Edge-triggered lines are clocked logic, so update like a flop:
        // other clocked logic reading the output sees the pre-edge value, regardless of ordering
        AstNodeStmt* const assignp
            = newOutputAssign(fl, getOutputNum(nodep, oValName), edgetrigp != nullptr);
        AstIf* const ifp = new AstIf{fl, logandp, assignp};
        if (nodep->udpIsCombo()) {
            if (!isCombOutputSig(oValName)) {
                oNodep->v3error("Illegal value for combinational UDP line output");
            }
            m_alwaysBlockp->addStmtsp(ifp);
            if (edgetrigp) VL_DO_DANGLING(pushDeletep(edgetrigp), edgetrigp);
            return;
        }
        if (!isSequentOutputSig(oValName)) {
            oNodep->nextp()->v3error("Illegal value for sequential UDP line output");
        }
        m_alwaysBlockp->addNext(new AstAlways{fl, VAlwaysKwd::ALWAYS, edgetrigp, ifp});
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }
    void visit(AstLogAnd* nodep) override { iterateChildren(nodep); }
    void visit(AstLogNot* nodep) override { iterateChildren(nodep); }
    // Sets of table values, bit 0/1/2 for value 0/1/x
    static constexpr int VALUE_0 = 1;
    static constexpr int VALUE_1 = 2;
    static constexpr int VALUE_X = 4;
    static constexpr int VALUE_ANY = VALUE_0 | VALUE_1 | VALUE_X;
    // Set of values a level symbol matches
    static int levelValues(char symbol) {
        switch (symbol) {
        case '0': return VALUE_0;
        case '1': return VALUE_1;
        case 'x':
        case 'X': return VALUE_X;
        case 'b':
        case 'B': return VALUE_0 | VALUE_1;
        default: return VALUE_ANY;  // '?', or illegal symbols, which are reported elsewhere
        }
    }
    // Set of changing value pairs between value sets, bit 3*previous+current
    static int changes(int previous, int current) {
        int pairs = 0;
        for (int p = 0; p < 3; ++p) {
            for (int c = 0; c < 3; ++c) {
                if (p != c && (previous >> p & 1) && (current >> c & 1)) pairs |= 1 << (3 * p + c);
            }
        }
        return pairs;
    }
    // Set of (previous, current) value pairs an input field matches
    static int fieldPairs(const string& field) {
        if (field.size() == 2) return changes(levelValues(field[0]), levelValues(field[1]));
        switch (field[0]) {
        case 'r':
        case 'R': return changes(VALUE_0, VALUE_1);
        case 'f':
        case 'F': return changes(VALUE_1, VALUE_0);
        case 'p':
        case 'P': return changes(VALUE_0, VALUE_1 | VALUE_X) | changes(VALUE_X, VALUE_1);
        case 'n':
        case 'N': return changes(VALUE_1, VALUE_0 | VALUE_X) | changes(VALUE_X, VALUE_0);
        case '*': return changes(VALUE_ANY, VALUE_ANY);
        default: break;
        }
        const int values = levelValues(field[0]);
        int pairs = 0;
        for (int v = 0; v < 3; ++v) {
            if (values >> v & 1) pairs |= 1 << (4 * v);
        }
        return pairs;
    }
    // Whether two table lines can match the same inputs yet give different outputs
    static bool linesConflict(const AstUdpTableLine* ap, const AstUdpTableLine* bp) {
        for (const AstNode *aip = ap->iFieldsp(), *bip = bp->iFieldsp(); aip && bip;
             aip = aip->nextp(), bip = bip->nextp()) {
            if (!(fieldPairs(aip->name()) & fieldPairs(bip->name()))) return false;
        }
        // Current output values both lines match, any for combinational lines
        int states = VALUE_ANY;
        const AstNode* aOutp = ap->oFieldsp();
        if (!ap->udpIsCombo()) {
            states &= levelValues(aOutp->name()[0]);
            aOutp = aOutp->nextp();
        }
        const AstNode* bOutp = bp->oFieldsp();
        if (!bp->udpIsCombo()) {
            states &= levelValues(bOutp->name()[0]);
            bOutp = bOutp->nextp();
        }
        // Compare outputs per current output value, as '-' outputs that value
        for (int s = 0; s < 3; ++s) {
            if (!(states >> s & 1)) continue;
            const int aValue = aOutp->name() == "-" ? 1 << s : levelValues(aOutp->name()[0]);
            const int bValue = bOutp->name() == "-" ? 1 << s : levelValues(bOutp->name()[0]);
            if (aValue != bValue) return true;
        }
        return false;
    }
    static void checkConflicts(const AstUdpTable* nodep) {
        // Quadratic in table lines, but UDP tables are small
        for (const AstNode* linep = nodep->linesp(); linep; linep = linep->nextp()) {
            const AstUdpTableLine* const bp = VN_AS(linep, UdpTableLine);
            for (const AstNode* earlierp = nodep->linesp(); earlierp != linep;
                 earlierp = earlierp->nextp()) {
                const AstUdpTableLine* const ap = VN_AS(earlierp, UdpTableLine);
                if (linesConflict(ap, bp)) {
                    bp->v3error("UDP table line gives a different output than an earlier line"
                                " for the same inputs (IEEE 1800-2023 29.3.4)\n"
                                << bp->warnContextPrimary() << '\n'
                                << ap->warnOther() << "... Location of earlier line\n"
                                << ap->warnContextSecondary());
                    break;
                }
            }
        }
    }
    // For logic processing.
    static bool isEdgeTrig(std::string& valName) {
        if (valName == "x" || valName == "X") return false;
        if (valName == "*") return true;
        if (valName == "01" || valName == "p" || valName == "P" || valName == "r"
            || valName == "R") {
            valName = "r";
            return true;
        }
        if (valName == "10" || valName == "n" || valName == "N" || valName == "f"
            || valName == "F") {
            valName = "f";
            return true;
        }
        if (valName.size() == 2) {
            if (valName[0] == 'x' || valName[0] == 'X' || valName[1] == 'x' || valName[1] == 'X')
                valName = "x";
            else if (valName[0] == '1' || valName[1] == '0')
                valName = "f";
            else if (valName[0] == '0' || valName[1] == '1')
                valName = "r";
            return true;
        }
        if (valName[0] != '0' && valName[0] != '1') { valName = "?"; }
        return false;
    }
    static bool isCombOutputSig(const std::string& valName) {
        return (valName == "0" || valName == "1" || valName == "x" || valName == "X");
    }
    static bool isSequentOutputSig(const std::string& valName) {
        return (valName == "0" || valName == "1" || valName == "x" || valName == "X"
                || valName == "-");
    }
    AstNodeStmt* newOutputAssign(FileLine* fl, const V3Number& outNum, bool isDelayed) const {
        AstVarRef* const lhsp = new AstVarRef{fl, m_oFieldVarp, VAccess::WRITE};
        AstConst* const rhsp = new AstConst{fl, outNum};
        if (isDelayed) return new AstAssignDly{fl, lhsp, rhsp};
        return new AstAssign{fl, lhsp, rhsp};
    }
    static V3Number getOutputNum(AstNode* nodep, const std::string& fieldNames) {
        V3Number outputNum{nodep, 1};
        if (fieldNames == "0") {
            outputNum.setBit(0, 0);
        } else if (fieldNames == "1") {
            outputNum.setBit(0, 1);
        } else {
            outputNum.setBit(0, 'x');
        }
        return outputNum;
    }

public:
    // CONSTRUCTORS
    explicit UdpVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~UdpVisitor() override = default;
};

void V3Udp::udpResolve(AstNetlist* rootp) {
    UINFO(4, __FUNCTION__ << ": ");
    { const UdpVisitor visitor{rootp}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("udp", 0, dumpTreeEitherLevel() >= 3);
}
