// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: LValue module/signal name references
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
// LinkLValue TRANSFORMATIONS:
//      Top-down traversal
//          Set lvalue() attributes on appropriate VARREFs.
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3LinkLValue.h"

#include "V3MemberMap.h"
#include "V3Task.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Link state, as a visitor of each AstNode

class LinkLValueVisitor final : public VNVisitor {
    // NODE STATE

    // STATE - across all visitors
    VMemberMap* const m_memberMapp;  // Struct members by name, nullptr if the tree is typed

    // STATE - for current visit position (use VL_RESTORER)
    bool m_setContinuously = false;  // Set that var has some continuous assignment
    bool m_setForcedByCode = false;  // Set that var is the target of an AstAssignForce/AstRelease
    bool m_setIfRand = false;  // Update VarRefs if var declared as rand
    bool m_setStrengthSpecified = false;  // Set that var has assignment with strength specified.
    bool m_inFunc = false;  // Set if inside AstNodeFTask
    bool m_inInitialStatic = false;  // Set if inside AstInitialStatic
    bool m_inInitialStaticStmt = false;  // Set if inside AstInitialStaticStmt
    // Non-procedural context, e.g. "a continuous assignment", if under one
    const char* m_nonProcContextp = nullptr;
    VAccess m_setRefLvalue;  // Set VarRefs to lvalues for pin assignments
    const AstNodeVarRef* m_handleRefp = nullptr;  // Handle read to write a member of its object
    // Untyped address data types already inferred, see addressDTypep
    std::map<const AstNodeExpr*, const AstNodeDType*> m_addressDTypes;

    // VISITORS
    // Result handing
    void visit(AstNodeVarRef* nodep) override {
        // VarRef: LValue its reference
        if (m_setIfRand && !(nodep->varp() && nodep->varp()->isRand())) return;
        if (m_setRefLvalue != VAccess::NOCHANGE) nodep->access(m_setRefLvalue);
        // Linked via an input-only modport by V3LinkDot, before it was known if written
        if (AstVarXRef* const xrefp = VN_CAST(nodep, VarXRef)) {
            // Writing a member of the object does not write its handle (IEEE 1800-2023 6.20.6)
            if (xrefp->readOnlyModport() && nodep->access().isWriteOrRW()
                && nodep != m_handleRefp) {
                nodep->v3error("Attempt to drive input-only modport: " << nodep->prettyNameQ());
            }
        }
        if (nodep->varp() && nodep->access().isWriteOrRW()) {
            if (nodep->varp()->isParam()) {
                // All parameters that did get constified happened before now
                // as V3LinkLValue runs after V3Param
                nodep->v3error("Storing to parameter variable "
                               << nodep->prettyNameQ()
                               << " in a context that is determined only at runtime");
            }
            if (m_setContinuously) {
                nodep->varp()->isContinuously(true);
                // Strength may only be specified in continuous assignment,
                // so it is needed to check only if m_setContinuously is true
                if (m_setStrengthSpecified) {
                    AstVar* const varp = nodep->varp();
                    varp->hasStrengthAssignment(true);
                    // An output port with an explicit data type but no net type is a
                    // variable (IEEE 1800-2023 23.2.2.3)
                    if (varp->varType() == VVarType::VAR
                        || (varp->varType() == VVarType::PORT
                            && varp->direction() == VDirection::OUTPUT && varp->isDeclTyped())) {
                        nodep->v3error("Drive strength specified for a variable, but drive "
                                       "strengths only apply to nets (IEEE 1800-2023 10.3.4): "
                                       << nodep->prettyNameQ());
                    }
                }
            }
            if (const AstClockingItem* const itemp
                = VN_CAST(nodep->varp()->backp(), ClockingItem)) {
                UINFO(5, "ClkOut " << nodep);
                if (itemp->outputp()) nodep->varp(itemp->outputp()->varp());
            }
            if (m_setForcedByCode) {
                nodep->varp()->setForcedByCode();
                // If a public signal is being forced in SystemVerilog and VPI
                // is enabled, mark it as forceable to ensure that the VPI
                // functions read the forced value correctly
                if (v3Global.opt.vpi()
                    && (nodep->varp()->isSigPublic() || nodep->varp()->isSigModPublic())) {
                    nodep->varp()->setForceable();
                }
            } else if (!nodep->varp()->isFuncLocal() && nodep->varp()->isReadOnly()) {
                // This is allowed with IEEE 1800-2009 module input with default value.
                // the checking now happens in V3Width::visit(AstNodeVarRef*)
                // If you were to check here, it would fail on module inputs with default value,
                // because Inputs are isReadOnly()=true, and we don't yet have visibility into
                // it being an Initial style procedure.
            }
        }
        iterateChildren(nodep);
    }

    // Nodes that start propagating down lvalues
    void visit(AstPin* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        if (nodep->modVarp() && nodep->modVarp()->isWritable()) {
            // When the varref's were created, we didn't know the I/O state
            // Now that we do, and it's from a output, we know it's a lvalue
            m_setRefLvalue = VAccess::WRITE;
            iterateChildren(nodep);
            m_setRefLvalue = VAccess::NOCHANGE;
        } else {
            iterateChildren(nodep);
        }
    }
    void visit(AstNodeAssign* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        VL_RESTORER(m_setContinuously);
        VL_RESTORER(m_setStrengthSpecified);
        VL_RESTORER(m_nonProcContextp);
        if (VN_IS(nodep, AssignW)) {
            m_nonProcContextp = "a continuous assignment";
        } else if (VN_IS(nodep, AssignCont) || VN_IS(nodep, AssignForce)) {
            m_nonProcContextp = "a procedural continuous assignment";
        }
        {
            m_setRefLvalue = VAccess::WRITE;
            m_setContinuously = VN_IS(nodep, AssignW);
            if (const AstAssignW* const assignwp = VN_CAST(nodep, AssignW)) {
                if (assignwp->strengthSpecp()) m_setStrengthSpecified = true;
            }
            {
                VL_RESTORER(m_setForcedByCode);
                m_setForcedByCode = VN_IS(nodep, AssignForce);
                iterateAndNextNull(nodep->lhsp());
            }
            m_setRefLvalue = VAccess::NOCHANGE;
            m_setContinuously = false;
            m_setStrengthSpecified = false;
            iterateAndNextNull(nodep->rhsp());
        }

        if ((m_inInitialStatic || m_inInitialStaticStmt) && m_inFunc) {
            const bool rhsHasIO = nodep->rhsp()->exists([](const AstNodeVarRef* const refp) {
                // Exclude module I/O referenced from a function/task.
                return refp->varp() && refp->varp()->isIO()
                       && refp->varp()->lifetime() != VLifetime::NONE;
            });
            if (rhsHasIO) {
                nodep->rhsp()->v3warn(E_UNSUPPORTED,
                                      "Static variable initializer\n"
                                          << nodep->rhsp()->warnMore()
                                          << "is dependent on function/task I/O variable");
            } else {
                const bool rhsHasAutomatic
                    = nodep->rhsp()->exists([](const AstNodeVarRef* const refp) {
                          return refp->varp() && refp->varp()->lifetime().isAutomatic();
                      });
                if (rhsHasAutomatic) {
                    nodep->rhsp()->v3error("Static variable initializer\n"
                                           << nodep->rhsp()->warnMore()
                                           << "is dependent on automatic variable");
                }
            }
        }
    }
    void visit(AstCell* nodep) override {
        VL_RESTORER(m_nonProcContextp);
        m_nonProcContextp = "an instance connection";
        iterateChildren(nodep);
    }
    void visit(AstSenItem* nodep) override {
        VL_RESTORER(m_nonProcContextp);
        m_nonProcContextp = "an event expression";
        iterateChildren(nodep);
    }
    void visit(AstAlias* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::READWRITE;
        iterateChildren(nodep);
    }
    void visit(AstInitialStatic* nodep) override {
        VL_RESTORER(m_inInitialStatic);
        m_inInitialStatic = true;
        iterateChildren(nodep);
    }
    void visit(AstInitialStaticStmt* nodep) override {
        VL_RESTORER(m_inInitialStaticStmt);
        m_inInitialStaticStmt = true;
        iterateChildren(nodep);
    }
    void visit(AstRelease* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        VL_RESTORER(m_setContinuously);
        VL_RESTORER(m_setForcedByCode);
        m_setRefLvalue = VAccess::WRITE;
        m_setContinuously = false;
        m_setForcedByCode = true;
        iterateAndNextNull(nodep->lhsp());
    }
    void visit(AstDeassign* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        VL_RESTORER(m_setContinuously);
        m_setRefLvalue = VAccess::WRITE;
        m_setContinuously = false;
        iterateAndNextNull(nodep->lhsp());
    }
    void visit(AstFireEvent* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->operandp());
    }
    void visit(AstCastDynamic* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->fromp());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->top());
    }
    void visit(AstFError* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->filep());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->strp());
    }
    void visit(AstFGetS* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->filep());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->strgp());
    }
    void visit(AstFRead* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->filep());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->memp());
    }
    void visit(AstFScanF* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->filep());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->exprsp());
    }
    void visit(AstFUngetC* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->filep());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->rhsp());
    }
    void visit(AstSScanF* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->exprsp());
    }
    void visit(AstSysIgnore* nodep) override {
        // Can't know if lvalue or not; presume not
        iterateChildren(nodep);
    }
    void visit(AstRand* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        if (!nodep->urandom()) m_setRefLvalue = VAccess::READWRITE;
        iterateAndNextNull(nodep->seedp());
    }
    void visit(AstReadMem* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->memp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->filenamep());
        iterateAndNextNull(nodep->lsbp());
        iterateAndNextNull(nodep->msbp());
    }
    void visit(AstTestPlusArgs* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->searchp());
    }
    void visit(AstValuePlusArgs* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->searchp());
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->outp());
    }
    void visit(AstSFormat* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->lhsp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->fmtp());
    }
    void visit(AstNodeDistBiop* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::READWRITE;
        iterateAndNextNull(nodep->lhsp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->rhsp());
    }
    void visit(AstNodeDistTriop* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::READWRITE;
        iterateAndNextNull(nodep->lhsp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->rhsp());
        iterateAndNextNull(nodep->thsp());
    }
    // cppcheck-suppress constParameterPointer
    void prepost_visit(AstNodeUniop* nodep) {
        VL_RESTORER(m_setRefLvalue);
        m_setRefLvalue = VAccess::WRITE;
        iterateAndNextNull(nodep->lhsp());
    }
    void visit(AstPreInc* nodep) override { prepost_visit(nodep); }
    void visit(AstPostInc* nodep) override { prepost_visit(nodep); }
    void visit(AstPreDec* nodep) override { prepost_visit(nodep); }
    void visit(AstPostDec* nodep) override { prepost_visit(nodep); }

    // Nodes that change LValue state
    void visit(AstSel* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        iterateAndNextNull(nodep->fromp());
        // Only set lvalues on the from
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->lsbp());
    }
    void visit(AstNodeSel* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        // Only set lvalues on the from
        iterateAndNextNull(nodep->fromp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->bitp());
    }
    void visit(AstCellArrayRef* nodep) override {
        VL_RESTORER(m_setRefLvalue);
        // selp is not an lvalue
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->selp());
    }
    void visit(AstNodePreSel* nodep) override {
        if (AstSelBit* const selbitp = VN_CAST(nodep, SelBit)) selbitp->access(m_setRefLvalue);
        VL_RESTORER(m_setRefLvalue);
        // Only set lvalues on the from
        iterateAndNextNull(nodep->fromp());
        m_setRefLvalue = VAccess::NOCHANGE;
        iterateAndNextNull(nodep->rhsp());
        iterateAndNextNull(nodep->thsp());
    }
    void visit(AstMemberSel* nodep) override {
        if (m_setRefLvalue != VAccess::NOCHANGE) {
            nodep->access(m_setRefLvalue);
            if (nodep->varp() && nodep->access().isWriteOrRW()) {
                if (const AstClockingItem* const itemp
                    = VN_CAST(nodep->varp()->backp(), ClockingItem)) {
                    UINFO(5, "ClkOut " << nodep);
                    if (itemp->outputp()) nodep->varp(itemp->outputp()->varp());
                }
            }
        } else {
            // If it doesn't have to be set to WRITE, it means that it is READ.
            // (V3Width marks the target of a modifying built-in method WRITE.)
            nodep->access(VAccess::READ);
        }
        VL_RESTORER(m_handleRefp);
        // Only the variable holding the handle is exempt, not e.g. one in an index
        const AstNodeDType* const fromDtypep = addressDTypep(nodep->fromp());
        if (fromDtypep && VN_IS(fromDtypep->skipRefOrNullp(), ClassRefDType)) {
            m_handleRefp = addressRootp(nodep->fromp());
        }
        iterateChildren(nodep);
    }
    // Variable an address expression selects from, or nullptr
    const AstNodeVarRef* addressRootp(const AstNodeExpr* exprp) {
        // Called for the address of a handle, it stops at a member of another class object,
        // which is the address of the next handle. So the walks over one address do not
        // overlap, and cost O(depth) in total.
        while (true) {
            if (const AstNodeSel* const selp = VN_CAST(exprp, NodeSel)) {
                exprp = selp->fromp();
            } else if (const AstNodePreSel* const selp = VN_CAST(exprp, NodePreSel)) {
                exprp = selp->fromp();
            } else if (const AstStructSel* const selp = VN_CAST(exprp, StructSel)) {
                exprp = selp->fromp();
            } else if (const AstMemberSel* const selp = VN_CAST(exprp, MemberSel)) {
                // A member of a struct, but not of another class object
                if (!structDTypep(addressDTypep(selp->fromp()))) return nullptr;
                exprp = selp->fromp();
            } else {
                return VN_CAST(exprp, NodeVarRef);
            }
        }
    }
    // Struct or union a data type is, or nullptr
    static const AstNodeUOrStructDType* structDTypep(const AstNodeDType* dtypep) {
        // Typedefs may not be linked yet
        return dtypep ? VN_CAST(dtypep->skipRefOrNullp(), NodeUOrStructDType) : nullptr;
    }
    // Data type of an address expression, also before V3Width set it, or nullptr
    const AstNodeDType* addressDTypep(const AstNodeExpr* exprp) {
        if (exprp->dtypep()) return exprp->dtypep();
        if (const AstNodeVarRef* const refp = VN_CAST(exprp, NodeVarRef)) {
            return refp->varp() ? refp->varp()->subDTypep() : nullptr;
        }
        // Each member select of a d-deep address asks for its prefix, so without the memo
        // inference would cost O(d^2). With it each prefix is inferred once, about
        // O(d log d + d log K) per address, for K members per struct looked up. A std::map,
        // as visitors are many and small. A node is only asked for while visiting an ancestor,
        // before visiting its subtree. Of what inference reads, the visit changes only a
        // clocking VarRef's varp, when visiting that VarRef, so an entry cannot become stale.
        // The memo lives as long as this visitor; it does not see later V3Width changes.
        const auto it = m_addressDTypes.find(exprp);
        if (it != m_addressDTypes.end()) return it->second;
        const AstNodeDType* const dtypep = inferDTypep(exprp);
        m_addressDTypes.emplace(exprp, dtypep);
        return dtypep;
    }
    // Data type of an untyped member or element select, or nullptr
    const AstNodeDType* inferDTypep(const AstNodeExpr* exprp) {
        // Member of a struct or union, from its declared members
        if (const AstMemberSel* const selp = VN_CAST(exprp, MemberSel)) {
            const AstNodeUOrStructDType* const sdtypep
                = structDTypep(addressDTypep(selp->fromp()));
            if (!sdtypep) return nullptr;
            UASSERT_OBJ(m_memberMapp, selp, "Untyped member select, but no member map");
            const AstMemberDType* const memberp
                = VN_CAST(m_memberMapp->findMember(sdtypep, selp->name()), MemberDType);
            return memberp ? memberp->subDTypep() : nullptr;
        }
        // Element of an unpacked, dynamic, associative array or queue; typed selects have a dtype
        const AstSelBit* const selp = VN_CAST(exprp, SelBit);
        const AstNodeDType* const fromDtypep = selp ? addressDTypep(selp->fromp()) : nullptr;
        // Typedefs may not be linked yet
        const AstNodeDType* const arrayp = fromDtypep ? fromDtypep->skipRefOrNullp() : nullptr;
        if (VN_IS(arrayp, UnpackArrayDType) || VN_IS(arrayp, DynArrayDType)
            || VN_IS(arrayp, AssocArrayDType) || VN_IS(arrayp, WildcardArrayDType)
            || VN_IS(arrayp, QueueDType)) {
            return arrayp->subDTypep();
        }
        return nullptr;
    }
    void visit(AstNodeFTaskRef* nodep) override {
        const AstNodeFTask* const taskp = nodep->taskp();
        // We'll deal with mismatching pins later
        if (!taskp) return;
        const V3TaskConnects tconnects
            = V3Task::taskConnects(nodep, taskp->stmtsp(), nullptr, false);
        for (const auto& tconnect : tconnects) {
            const AstVar* const portp = tconnect.first;
            const AstArg* const argp = tconnect.second;
            if (!argp) continue;
            AstNodeExpr* const pinp = argp->exprp();
            if (!pinp) continue;
            if (m_nonProcContextp && portp->direction().isWritable()) {
                nodep->v3error("Function "
                               << nodep->prettyNameQ() << " with output, inout or ref argument "
                               << portp->prettyNameQ() << " is called in " << m_nonProcContextp
                               << " (IEEE 1800-2023 13.4)");
            }
            VL_RESTORER(m_setRefLvalue);
            m_setRefLvalue = portp->direction().pinAccess();
            iterate(pinp);
        }
        if (nodep->withp()) iterate(nodep->withp());
    }
    void visit(AstConstraint* nodep) override {
        VL_RESTORER(m_setIfRand);
        m_setIfRand = true;
        iterateChildren(nodep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_inFunc);
        m_inFunc = true;
        iterateChildren(nodep);
    }

    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    LinkLValueVisitor(AstNode* nodep, VAccess start, VMemberMap* memberMapp)
        : m_memberMapp{memberMapp}
        , m_setRefLvalue{start} {
        iterate(nodep);
    }
    ~LinkLValueVisitor() override = default;
};

//######################################################################
// Link class functions

void V3LinkLValue::linkLValue(AstNetlist* nodep) {
    UINFO(4, __FUNCTION__ << ": ");
    VMemberMap memberMap;  // For this pass; V3Param may change structs before the next
    { LinkLValueVisitor{nodep, VAccess::NOCHANGE, &memberMap}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("linklvalue", 0, dumpTreeEitherLevel() >= 6);
}
void V3LinkLValue::linkLValueSet(AstNode* const nodep, const VAccess access,
                                 VMemberMap* const memberMapp) {
    // Called by later link functions when it is known a node needs
    // to be converted to a lvalue.
    UINFO(9, __FUNCTION__ << ": ");
    { LinkLValueVisitor{nodep, access, memberMapp}; }
}
