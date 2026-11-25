// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Add temporaries, such as for inst nodes
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
// V3Inst's Transformations:
//
// Each module:
//      Pins:
//          Create a wire assign to interconnect to submodule
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Inst.h"

#include "V3Const.h"
#include "V3Control.h"
#include "V3EmitV.h"
#include "V3Width.h"

VL_DEFINE_DEBUG_FUNCTIONS;

static void markContinuousLhs(AstNode* const nodep) {
    nodep->foreach([](AstNodeVarRef* refp) {
        if (refp->access().isWriteOrRW()) refp->varp()->isContinuously(true);
    });
}

//######################################################################
// Collect port access before replacing any instance connection.
// The user slots are owned by InstVisitor and shared with its connection rewrite.
class InstPortAccessVisitor final : public VNVisitorConst {
    bool m_inInitial = false;  // Read before continuous assignments may have settled

    void iterateInitial(AstNode* nodep) {
        VL_RESTORER(m_inInitial);
        m_inInitial = true;
        iterateChildrenConst(nodep);
    }
    void visit(AstCell* nodep) override {
        nodep->modp()->user2Inc();
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (nodep->access().isWriteOrRW()) nodep->varp()->user3(true);
        if (m_inInitial && nodep->access().isReadOrRW()) nodep->varp()->user4(true);
    }
    void visit(AstInitial* nodep) override { iterateInitial(nodep); }
    void visit(AstInitialStatic* nodep) override { iterateInitial(nodep); }
    void visit(AstInitialAutomatic* nodep) override { iterateInitial(nodep); }
    void visit(AstNodeFTask* nodep) override { iterateInitial(nodep); }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

    explicit InstPortAccessVisitor(AstNetlist* nodep) { iterateConst(nodep); }
    ~InstPortAccessVisitor() override = default;

public:
    static void apply(AstNetlist* nodep) { InstPortAccessVisitor{nodep}; }
};

//######################################################################
// The default values of input ports, as connections

class InstPortDefaultVisitor final : public VNVisitor {
    // NODE STATE
    //  AstVar::user1p()        -> AstAssign*. Initializer of an input port with a default value
    //  AstVar::user2()         -> int. CONNECTED and/or UNCONNECTED, for its instances
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;
    enum : int { CONNECTED = 1, UNCONNECTED = 2 };

    // STATE
    std::vector<AstVar*> m_varps;  // Input ports with a default value
    std::vector<AstPin*> m_unconnectedps;  // Pins of those ports not connected
    AstNodeModule* m_modp = nullptr;  // Current module

    // METHODS
    // Make the Z bits of a default value X bits, so a value as for a variable
    static void zToX(AstNode* valuep) {
        std::vector<AstConst*> constps;
        valuep->foreach([&](AstConst* constp) {
            if (constp->num().hasZ()) constps.push_back(constp);
        });
        for (AstConst* const constp : constps) {
            V3Number num{constp->num()};
            for (int bit = 0; bit < num.width(); ++bit) {
                if (num.bitIsZ(bit)) num.setBit(bit, 'x');
            }
            constp->replaceWith(new AstConst{constp->fileline(), num});
            VL_DO_DANGLING(constp->deleteTree(), constp);
        }
    }

    // VISITORS
    void visit(AstNetlist* nodep) override {
        // Find the defaults
        for (AstNodeModule* modp = nodep->modulesp(); modp;
             modp = VN_AS(modp->nextp(), NodeModule)) {
            for (AstNode* itemp = modp->stmtsp(); itemp; itemp = itemp->nextp()) {
                const AstInitialStatic* const initp = VN_CAST(itemp, InitialStatic);
                AstAssign* const assignp = initp ? VN_CAST(initp->stmtsp(), Assign) : nullptr;
                const AstVarRef* const refp = assignp ? VN_CAST(assignp->lhsp(), VarRef) : nullptr;
                if (refp && refp->varp()->isInput() && refp->varp()->hasUserInit()) {
                    refp->varp()->user1p(assignp);
                    m_varps.push_back(refp->varp());
                }
            }
        }
        iterateChildren(nodep);
        // The default value applies only to instances that do not connect the port (IEEE
        // 1800-2023 23.2.2.4). If all do, it stays the port's initializer, otherwise it is a
        // connection of each of them.
        for (AstPin* const pinp : m_unconnectedps) {
            AstVar* const varp = pinp->modVarp();
            if (!(varp->user2() & CONNECTED)) continue;
            pinp->exprp(VN_AS(varp->user1p(), Assign)->rhsp()->cloneTree(false));
        }
        for (AstVar* const varp : m_varps) {
            AstAssign* const assignp = VN_AS(varp->user1p(), Assign);
            if (varp->user2() & CONNECTED) {
                VL_DO_DANGLING(assignp->backp()->unlinkFrBack()->deleteTree(), assignp);
            }
        }
    }
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        m_modp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstCell* nodep) override {
        for (AstPin* pinp = nodep->pinsp(); pinp; pinp = VN_AS(pinp->nextp(), Pin)) {
            AstVar* const varp = pinp->modVarp();
            AstAssign* const assignp = varp ? VN_AS(varp->user1p(), Assign) : nullptr;
            if (!assignp) continue;
            if (m_modp->isTop()) {
                // An input of the model takes its default when constructed (addPrimaryDefault),
                // and a value the user writes replaces it, so its Z bits are a value
                zToX(assignp->rhsp());
            } else if (pinp->exprp()) {
                varp->user2(varp->user2() | CONNECTED);
            } else {
                varp->user2(varp->user2() | UNCONNECTED);
                m_unconnectedps.push_back(pinp);
            }
        }
    }
    void visit(AstNodeExpr*) override {}  // Accelerate
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit InstPortDefaultVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~InstPortDefaultVisitor() override = default;
};

//######################################################################
// Inst state, as a visitor of each AstNode

class InstVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared each Cell:
    //  AstPin::user1p()        -> bool.  True if created assignment already
    // Set by InstPortAccessVisitor:
    //  AstNodeModule::user2()  -> int.   Number of instances of the module
    //  AstVar::user3()         -> bool.  Written by the design
    //  AstVar::user4()         -> bool.  Read in an initial block or a task/function
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;
    const VNUser3InUse m_inuser3;
    const VNUser4InUse m_inuser4;

    // STATE
    AstCell* m_cellp = nullptr;  // Current cell
    // Initializer of each input port of m_portDefaultsModp, see addPrimaryDefault
    std::unordered_map<const AstVar*, AstAssign*> m_portDefaults;
    const AstNodeModule* m_portDefaultsModp = nullptr;  // Module m_portDefaults indexes

    // METHODS
    // If appropriate, add an AstAlias to connect the given Cell pin to the given expression.
    // Returns true if an alias was made, in which case there is nothing else to do for this pin.
    bool tryAliasPin(AstPin* nodep, AstNodeExpr* exprp) {
        AstVar* const modVarp = nodep->modVarp();
        // An interface reference is aliased via AstAliasScope below, not as a variable
        if (modVarp->isIfaceRef()) return false;
        // A net delay of the port's net delays the connection's assignment to it
        // (IEEE 1800-2023 23.3.3, 28.16)
        if (modVarp->delayp()) return false;
        // An input port stays a variable of its own if its module is not inlined, so the
        // instances can share their code; V3Inline and V3Coalesce remove the rest. A
        // --lib-create wrapper calls into the library and an interface has no code of its
        // own, so neither has code to share. Inputs written by the design or read at time
        // zero are not kept, as initial blocks run before continuous assignments settle; a
        // read in any function or task counts, conservatively, as one might be called from
        // an initial block.
        if (modVarp->direction() == VDirection::INPUT && !m_cellp->modp()->verilatorLib()
            && !VN_IS(m_cellp->modp(), Iface) && !modVarp->user3() && !modVarp->user4()) {
            modVarp->keepPort(true);
            // A port connected to anything but a whole variable needs an assignment, and
            // stays kept; the port of a module instantiated once is otherwise aliased as
            // usual, as there is no other instance to share code with
            if (m_cellp->modp()->user2() > 1) return false;
        }
        // Only a whole variable can be aliased, anything else needs the assignment
        AstVarRef* const refp = VN_CAST(exprp, VarRef);
        if (!refp) return false;
        AstVar* const exprVarp = refp->varp();
        // A virtual interface port connected to a real interface can't be an alias
        if (exprVarp->isIfaceRef()) return false;
        // A ref port must become an alias
        if (!modVarp->direction().isRef()) {
            // V3FsmDetect recognizes the registers of an fsm_register_wrapper instance via
            // the assignments of its pins, so leave those as assignments
            AstNodeModule* const cellModp = m_cellp->modp();
            if (V3Control::getFsmRegisterWrapper(cellModp->origName())
                || V3Control::getFsmRegisterWrapper(cellModp->prettyDehashOrigOrName())) {
                return false;
            }
            // A virtual interface method call is dispatched at run time, so the body of an
            // interface reached that way must use the signals of the instance it is called
            // on, not those of whichever instance this connection happens to be made to
            if (const AstIface* const ifacep = VN_CAST(m_cellp->modp(), Iface)) {
                if (ifacep->hasVirtualRef()) return false;
            }
            // Forced signals must keep their own storage, the two sides can be forced separately
            if (modVarp->isForced() || exprVarp->isForced()) return false;
            // Same for public
            if (modVarp->isSigUserRWPublic() || exprVarp->isSigUserRWPublic()) return false;
            // V3Tristate resolved the connected net already, and drives it from the
            // resolution it built for it, so a port merged into it would be driven by
            // the resolution of the instance as well
            if (exprVarp->isTristate()) return false;
            // The default value of an input is used only when it is not connected
            // (IEEE 1800-2023 23.2.2.4), so it must not initialize the connected variable
            if (modVarp->isInput() && modVarp->hasUserInit()) return false;
        }
        // They will become the same variable, so propagate file-line and attributes
        exprVarp->fileline()->modifyStateInherit(modVarp->fileline());
        modVarp->fileline()->modifyStateInherit(exprVarp->fileline());
        exprVarp->propagateAttrFrom(modVarp);
        modVarp->propagateAttrFrom(exprVarp);
        refp->access(VAccess::READWRITE);
        FileLine* const flp = exprp->fileline();
        AstNodeExpr* const itemsp
            = new AstVarXRef{flp, modVarp, m_cellp->name(), VAccess::READWRITE};
        itemsp->addNext(exprp);
        m_cellp->addNextHere(new AstAlias{flp, itemsp});
        return true;
    }

    // Whether defaultVerilog can write the default value
    static bool defaultWritable(const AstNode* valuep) {
        return !valuep->exists([](const AstNode* nodep) {
            return !VN_IS(nodep, Const) && !VN_IS(nodep, ConsArray)
                   && !VN_IS(nodep, ConsArrayItem);
        });
    }
    // The default value as Verilog for the --lib-create wrapper (V3ProtectLib)
    static string defaultVerilog(const AstNode* valuep) {
        const AstConsArray* const consp = VN_CAST(valuep, ConsArray);
        if (!consp) {
            const V3Number& num = VN_AS(valuep, Const)->num();
            std::ostringstream os;
            if (num.isString()) {
                // As a literal, with its escapes
                V3EmitV::verilogForTree(valuep, os);
            } else if (num.isDouble()) {
                // Exactly, including infinities and NaNs
                const double value = num.toDouble();
                uint64_t bits;
                std::memcpy(&bits, &value, sizeof(bits));
                os << "$bitstoreal(64'h" << std::hex << std::setw(16) << std::setfill('0') << bits
                   << ")";
            } else {
                // V3Unknown resolved any X or Z bits, so a hex digit is not partly X or Z
                UASSERT_OBJ(!num.isFourState(), valuep, "Default value should be two-state");
                os << num.width() << "'h" << num.displayed(valuep, "%0h");
            }
            return os.str();
        }
        // The indices of the items count from the lowest index of the array
        const AstUnpackArrayDType* const arrayp
            = VN_AS(consp->dtypep()->skipRefp(), UnpackArrayDType);
        string text;
        for (const AstConsArrayItem* itemp = consp->itemsp(); itemp;
             itemp = VN_AS(itemp->nextp(), ConsArrayItem)) {
            if (!text.empty()) text += ", ";
            text += cvtToStr(arrayp->lo() + static_cast<int>(itemp->index())) + ": "
                    + defaultVerilog(itemp->valuep());
        }
        // The elements without an item take the default
        if (const AstNodeExpr* const defaultp = consp->defaultp()) {
            if (!text.empty()) text += ", ";
            text += "default: " + defaultVerilog(defaultp);
        }
        return "'{" + text + "}";
    }

    // A primary input connected to an input port with a default value takes that value when
    // the model is constructed (see V3Sched), so before the user, or the parent of a
    // hierarchical block, writes it. Not as the port's own initializer, which runs at the first
    // evaluation, so after those writes.
    void addPrimaryDefault(AstVar* primaryp, const AstVar* portp) {
        if (!portp->hasUserInit()) return;
        // Index the module's port default values, which are its initializers of inputs
        AstNodeModule* const modp = m_cellp->modp();
        if (m_portDefaultsModp != modp) {
            m_portDefaultsModp = modp;
            m_portDefaults.clear();
            for (AstNode* itemp = modp->stmtsp(); itemp; itemp = itemp->nextp()) {
                const AstInitialStatic* const initp = VN_CAST(itemp, InitialStatic);
                AstAssign* const assignp = initp ? VN_CAST(initp->stmtsp(), Assign) : nullptr;
                const AstVarRef* const refp = assignp ? VN_CAST(assignp->lhsp(), VarRef) : nullptr;
                if (refp && refp->varp()->isInput()) m_portDefaults.emplace(refp->varp(), assignp);
            }
        }
        const auto it = m_portDefaults.find(portp);
        if (it == m_portDefaults.end()) return;
        const AstAssign* const assignp = it->second;
        UASSERT_OBJ(assignp->rhsp()->isConstantTree(), assignp,
                    "Input port default value should be constant (see V3Width)");
        FileLine* const flp = assignp->fileline();
        m_cellp->addNextHere(new AstInitialStatic{
            flp, new AstAssign{flp, new AstVarRef{flp, primaryp, VAccess::WRITE},
                               assignp->rhsp()->cloneTree(false)}});
        // Other types are not supported by --lib-create
        if (defaultWritable(assignp->rhsp())) {
            v3Global.rootp()->primaryDefault(primaryp, defaultVerilog(assignp->rhsp()));
        }
    }

    // VISITORS
    void visit(AstCell* nodep) override {
        UINFO(4, "  CELL   " << nodep);
        VL_RESTORER(m_cellp);
        m_cellp = nodep;
        // VV*****  We reset user1p() on each cell!!!
        AstNode::user1ClearTree();
        iterateChildren(nodep);
    }

    void visit(AstPin* nodep) override {
        // PIN(p,expr) -> ASSIGNW(VARXREF(p),expr)    (if sub's input)
        //            or  ASSIGNW(expr,VARXREF(p))    (if sub's output)
        UINFO(4, "   PIN  " << nodep);
        if (!nodep->user1()) {
            // Simplify it
            V3Inst::pinReconnectSimple(nodep, m_cellp, false);
        }
        UINFOTREE(9, nodep, "", "Pin_oldb");
        if (!nodep->exprp()) return;  // No-connect
        V3Inst::checkOutputShort(nodep);
        if (!nodep->exprp()) return;  // Connection removed by checkOutputShort
        // Use user1p on the PIN to indicate we created an assign for this pin
        if (!nodep->user1SetOnce()) {
            // Make an ASSIGNW (expr, pin)
            AstNodeExpr* const exprp = VN_AS(nodep->exprp(), NodeExpr)->cloneTree(false);
            UASSERT_OBJ(exprp->width() == nodep->modVarp()->width(), nodep,
                        "Width mismatch, should have been handled in pinReconnectSimple");
            if (nodep->modVarp()->isInout()) {
                nodep->v3fatalSrc("Unsupported: Verilator is a 2-state simulator");
            } else if (nodep->modVarp()->isWritable()) {
                if (!tryAliasPin(nodep, exprp)) {
                    AstNodeExpr* const rhsp = new AstVarXRef{exprp->fileline(), nodep->modVarp(),
                                                             m_cellp->name(), VAccess::READ};
                    markContinuousLhs(exprp);
                    AstAssignW* const assp = new AstAssignW{exprp->fileline(), exprp, rhsp};
                    m_cellp->addNextHere(new AstAlways{assp});
                }
            } else if (nodep->modVarp()->isNonOutput()) {
                const AstVarRef* const refp = VN_CAST(exprp, VarRef);
                if (refp && refp->varp()->isPrimaryIO()) {
                    addPrimaryDefault(refp->varp(), nodep->modVarp());
                }
                if (!tryAliasPin(nodep, exprp)) {
                    // Don't bother moving constants now,
                    // we'll be pushing the const down to the cell soon enough.
                    AstVarXRef* const lhsp = new AstVarXRef{exprp->fileline(), nodep->modVarp(),
                                                            m_cellp->name(), VAccess::WRITE};

                    markContinuousLhs(lhsp);
                    AstAssignW* const assp = new AstAssignW{exprp->fileline(), lhsp, exprp};
                    m_cellp->addNextHere(new AstAlways{assp});
                    UINFOTREE(9, assp, "", "_new");
                }
            } else if (nodep->modVarp()->isIfaceRef()) {
                // Create an AstAliasScope for Vars to Cells so we can
                // link with their scope later
                AstNodeExpr* const lhsp = new AstVarXRef{exprp->fileline(), nodep->modVarp(),
                                                         m_cellp->name(), VAccess::READ};
                const AstVarRef* const refp = VN_CAST(exprp, VarRef);
                const AstVarXRef* const xrefp = VN_CAST(exprp, VarXRef);
                UASSERT_OBJ(refp || xrefp, exprp,
                            "Interfaces: Pin is not connected to a VarRef or VarXRef");
                m_cellp->addNextHere(new AstAliasScope{exprp->fileline(), lhsp, exprp});
            } else {
                nodep->v3error("Assigned pin is neither input nor output");
            }
        }

        // We're done with the pin
        VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
    }

    // Save some time
    void visit(AstNodeExpr*) override {}
    void visit(AstNodeAssign*) override {}
    void visit(AstAlways*) override {}

    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit InstVisitor(AstNetlist* nodep) {
        InstPortAccessVisitor::apply(nodep);
        iterate(nodep);
    }
    ~InstVisitor() override = default;
};

//######################################################################
// Inst static function

class InstStatic final {
    InstStatic() = default;  // Static class

    static AstNodeExpr* extendOrSel(FileLine* fl, AstNodeExpr* rhsp, const AstNode* cmpWidthp) {
        if (cmpWidthp->width() > rhsp->width()) {
            rhsp = (rhsp->isSigned() ? static_cast<AstNodeExpr*>(new AstExtendS{fl, rhsp})
                                     : static_cast<AstNodeExpr*>(new AstExtend{fl, rhsp}));
            // Need proper widthMin, which may differ from AstSel created above
            rhsp->dtypeFrom(cmpWidthp);
        } else if (cmpWidthp->width() < rhsp->width()) {
            rhsp = new AstSel{fl, rhsp, 0, cmpWidthp->width()};
            // Need proper widthMin, which may differ from AstSel created above
            rhsp->dtypeFrom(cmpWidthp);
        }
        // else don't change dtype, as might be e.g. array of something
        return rhsp;
    }

    // Value an unconnected input is pulled to by `unconnected_drive (IEEE 1800-2023 22.9). An
    // input with a data type made of integral bits is pulled, whatever its port kind; other
    // types, e.g. real, have no pull value, so return nullptr to leave the input unconnected.
    static AstNodeExpr* newPullValue(AstPin* pinp, AstNodeDType* dtypep, bool pull1) {
        FileLine* const fl = pinp->fileline();
        dtypep = dtypep->skipRefp();
        if (AstUnpackArrayDType* const adtypep = VN_CAST(dtypep, UnpackArrayDType)) {
            AstNodeExpr* const elementp = newPullValue(pinp, adtypep->subDTypep(), pull1);
            return elementp ? new AstConsArray{fl, adtypep, elementp} : nullptr;
        }
        if (dtypep->isIntegralOrPacked()) {
            AstConst* const constp = new AstConst{fl, AstConst::DTyped{}, dtypep};
            if (pull1) constp->num().setAllBits1();
            return constp;
        }
        if (AstStructDType* const sdtypep = VN_CAST(dtypep, StructDType)) {
            AstConsStruct* const consp = new AstConsStruct{fl, sdtypep};
            for (AstMemberDType* const memberp : sdtypep->memberspList()) {
                AstNodeExpr* const valuep = newPullValue(pinp, memberp->subDTypep(), pull1);
                if (!valuep) {
                    VL_DO_DANGLING(consp->deleteTree(), consp);
                    return nullptr;
                }
                consp->addItemsp(new AstConsStructItem{fl, memberp, valuep});
            }
            return consp;
        }
        if (VN_IS(dtypep, UnionDType)) {
            pinp->v3warn(E_UNSUPPORTED,
                         "Unsupported: `unconnected_drive of input with unpacked union type: "
                             << pinp->modVarp()->prettyNameQ());
        } else {
            pinp->v3error("Unconnected input port "
                          << pinp->modVarp()->prettyNameQ()
                          << " is of non-integral type, so it cannot be pulled by"
                             " `unconnected_drive.");
        }
        return nullptr;
    }

public:
    static AstAssignW* pinReconnectSimple(AstPin* pinp, AstCell* cellp, bool forTristate,
                                          bool alwaysCvt) {
        // If a pin connection is "simple" leave it as-is
        // Else create a intermediate wire to perform the interconnect
        // Return the new assignment, if one was made
        // Note this module calls cloneTree() via new AstVar
        AstVar* const pinVarp = pinp->modVarp();
        if (!pinp->exprp()) {
            // No-connect, perhaps promote based on `unconnected_drive,
            // otherwise done
            const VOptionBool drive = cellp->modp()->unconnectedDrive();
            if (pinVarp->direction() != VDirection::INPUT || drive.isDefault()) return nullptr;
            // An omitted or positionally blank input with a default value is connected to the
            // default (IEEE 1800-2023 23.2.2.4, 23.3.2.1), an explicit empty named connection
            // is not (IEEE 1800-2023 23.3.2.2).
            if (pinVarp->hasUserInit() && !pinp->svDotName()) return nullptr;
            AstNodeExpr* const pullp = newPullValue(pinp, pinVarp->dtypep(), drive.isSetTrue());
            if (!pullp) return nullptr;
            pinp->exprp(pullp);
        }
        const AstVarRef* const connectRefp = VN_CAST(pinp->exprp(), VarRef);
        const AstVarXRef* const connectXRefp = VN_CAST(pinp->exprp(), VarXRef);
        const AstNodeDType* const pinDTypep = pinVarp->dtypep()->skipRefp();
        const AstBasicDType* const pinBasicp = VN_CAST(pinDTypep, BasicDType);
        const AstNodeDType* const connDTypep
            = connectRefp ? connectRefp->varp()->dtypep()->skipRefp() : nullptr;
        const AstBasicDType* const connBasicp = VN_CAST(connDTypep, BasicDType);
        AstAssignW* assignp = nullptr;
        //
        if (!alwaysCvt && connectRefp && connDTypep->sameTree(pinDTypep)
            && !connectRefp->varp()->isSc()) {  // Need the signal as a 'shell' to convert types
            // Done. Same data type
        } else if (!alwaysCvt && connectRefp && connectRefp->varp()->isIfaceRef()) {
            // Done. Interface
        } else if (!alwaysCvt && connectXRefp && connectXRefp->varp()
                   && connectXRefp->varp()->isIfaceRef()) {
        } else if (!alwaysCvt && connBasicp && pinBasicp
                   && connBasicp->width() == pinBasicp->width()
                   && connBasicp->lo() == pinBasicp->lo()
                   && !connectRefp->varp()
                           ->isSc()  // Need the signal as a 'shell' to convert types
                   && connBasicp->width() == pinVarp->width()) {
            // Done. One to one interconnect won't need a temporary variable.
        } else if (!alwaysCvt && !forTristate && VN_IS(pinp->exprp(), Const)) {
            // Done. Constant. Still check for driving an output, like below.
            V3Inst::checkOutputShort(pinp);
            if (!pinp->exprp()) return nullptr;
        } else {
            // Make a new temp wire
            // UINFOTREE(9, pinp, "", "in_pin");
            V3Inst::checkOutputShort(pinp);
            if (!pinp->exprp()) return nullptr;
            // Simplify, so stuff like '{a[0], b[0]}[1]' produced during
            // instance array expansion are brought to normal 'a[0]'
            AstNodeExpr* const pinexprp
                = V3Const::constifyEdit(VN_AS(pinp->exprp(), NodeExpr)->unlinkFrBack());
            const string newvarname
                = (string{pinVarp->isWritable() ? "__Vcellout" : "__Vcellinp"}
                   // Prevent name conflict if both tri & non-tri add signals
                   + (forTristate ? "t" : "") + "__" + cellp->name() + "__" + pinp->name());
            AstVar* const newvarp
                = new AstVar{pinVarp->fileline(), VVarType::MODULETEMP, newvarname, pinVarp};
            // Important to add statement next to cell, in case there is a
            // generate with same named cell
            cellp->addNextHere(newvarp);
            if (pinVarp->isInout()) {
                pinVarp->v3fatalSrc("Unsupported: Inout connections to pins must be"
                                    " direct one-to-one connection (without any expression)");
                // V3Tristate should have cleared up before this point
            } else if (pinVarp->isWritable()) {
                // See also V3Inst
                AstNodeExpr* rhsp = new AstVarRef{pinp->fileline(), newvarp, VAccess::READ};
                UINFO(5, "pinRecon width " << pinVarp->width() << " >? " << rhsp->width() << " >? "
                                           << pinexprp->width());
                rhsp = extendOrSel(pinp->fileline(), rhsp, pinVarp);
                pinp->exprp(new AstVarRef{newvarp->fileline(), newvarp, VAccess::WRITE});
                markContinuousLhs(pinexprp);
                if (VN_IS(pinexprp, NodeStream)) {
                    assignp = new AstAssignW{pinp->fileline(), pinexprp, rhsp};
                    V3Width::streamAssignLowerEdit(assignp);
                } else {
                    AstNodeExpr* rhsSelp = extendOrSel(pinp->fileline(), rhsp, pinexprp);
                    // A reversed array is assigned by the left-to-right order of elements
                    // (IEEE 1800-2023 7.6)
                    const AstUnpackArrayDType* const arrayp
                        = VN_CAST(pinexprp->dtypep()->skipRefp(), UnpackArrayDType);
                    if (arrayp && arrayp->isReverseOf(rhsSelp->dtypep())) {
                        rhsSelp = new AstCvtUnpackToUnpack{pinp->fileline(), rhsSelp,
                                                           pinexprp->dtypep()};
                    }
                    assignp = new AstAssignW{pinp->fileline(), pinexprp, rhsSelp};
                }
            } else {
                // V3 width should have range/extended to make the widths correct
                newvarp->isContinuously(true);
                assignp = new AstAssignW{pinp->fileline(),
                                         new AstVarRef{pinp->fileline(), newvarp, VAccess::WRITE},
                                         pinexprp};
                pinp->exprp(new AstVarRef{pinexprp->fileline(), newvarp, VAccess::READ});
            }
            if (assignp) cellp->addNextHere(new AstAlways{assignp});
            // UINFOTREE(1, pinp, "", "out");
            // UINFOTREE(1, assignp, "", "aout");
        }
        return assignp;
    }
};

//######################################################################
// Inst class functions

AstAssignW* V3Inst::pinReconnectSimple(AstPin* pinp, AstCell* cellp, bool forTristate,
                                       bool alwaysCvt) {
    return InstStatic::pinReconnectSimple(pinp, cellp, forTristate, alwaysCvt);
}

void V3Inst::checkOutputShort(const AstPin* nodep) {
    if (nodep->modVarp()->direction() == VDirection::OUTPUT) {
        if (VN_IS(nodep->exprp(), Const) || VN_IS(nodep->exprp(), Extend)
            || (VN_IS(nodep->exprp(), Concat)
                && (VN_IS(VN_AS(nodep->exprp(), Concat)->lhsp(), Const)))) {
            // Uses v3warn for error, as might be found multiple times
            nodep->v3warn(E_PORTSHORT, "Output port is connected to a constant pin,"
                                       " electrical short");
            // Delete so we don't create a 'CONST = ...' assignment
            nodep->exprp()->unlinkFrBack()->deleteTree();
        }
    }
}

//######################################################################
// Inst class visitor

void V3Inst::portDefaultsAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { InstPortDefaultVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("portdefaults", 0, dumpTreeEitherLevel() >= 3);
}

void V3Inst::instAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { InstVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("inst", 0, dumpTreeEitherLevel() >= 3);
}
