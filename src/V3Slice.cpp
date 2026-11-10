// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Parse module/signal name references
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
// Slice TRANSFORMATIONS:
//      Top-down traversal (SliceVisitor):
//        NODEASSIGN
//          ARRAYSEL
//            Compare the dimensions to the Var to check for implicit slices.
//            Using ->length() calculate the number of clones needed.
//          VARREF
//            Check the dimensions of the Var for an implicit slice.
//            Replace with ArraySel nodes if needed.
//          SEL, EXTEND
//            We might be assigning a 1-D packed array to a 2-D packed array,
//            this is unsupported.
//          SliceCloneVisitor (called if this node is a slice):
//            NODEASSIGN
//              Clone and iterate the clone:
//                ARRAYSEL
//                  Modify bitp() for the new value and set ->length(1)
//
// TODO: This code was written before SLICESEL was a type, it might be
// simplified to look primarily for SLICESELs.
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Slice.h"

#include "V3SharedTmps.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//*************************************************************************

class SliceVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared on netlist
    //  AstNodeAssign::user1()      -> bool.  True if find is complete
    //  AstNodeUniop::user1()       -> bool.  True if find is complete
    //  AstArraySel::user1p()       -> AstVarRef. The VarRef that the final ArraySel points to
    const VNUser1InUse m_inuser1;

    // STATE - across all visitors
    V3SharedTmps m_tmps{"__Vslice", VVarType::MODULETEMP};  // Temporaries of impure operands
    VDouble0 m_statAssigns;  // Statistic tracking
    VDouble0 m_statSliceElementSkips;  // Statistic tracking
    V3SharedTmps m_cvtTmps{"__VsliceCvt", VVarType::MODULETEMP};  // Converted slice sources

    // STATE - for current visit position (use VL_RESTORER)
    AstScope* m_scopep = nullptr;  // Current scope
    AstNode* m_assignp = nullptr;  // Assignment we are under
    bool m_assignError = false;  // True if the current assign already has an error
    bool m_okConsArray = false;  // Allow ConsArray children

    // METHODS
    AstNodeExpr* cloneAndSel(AstNodeExpr* const nodep, uint64_t elements, uint64_t elemIdx,
                             const bool needPure, const bool rvalue) {
        // Insert an ArraySel, except for a few special cases
        const AstUnpackArrayDType* const arrayp
            = VN_CAST(nodep->dtypep()->skipRefp(), UnpackArrayDType);
        if (!arrayp) {  // V3Width should have complained, but...
            if (!m_assignError && !nodep->fileline()->erroringOn()) {
                nodep->v3error(
                    nodep->prettyTypeName()
                    << " is not an unpacked array, but is in an unpacked array context");
            } else {
                V3Error::incErrors();  // Otherwise might infinite loop
            }
            m_assignError = true;
            // Likely will cause downstream errors
            return nodep->cloneTree(false, needPure);
        }
        if (static_cast<uint64_t>(arrayp->rangep()->elementsConst()) != elements) {
            if (!m_assignError) {
                nodep->v3error(
                    "Slices of arrays in assignments have different unpacked dimensions, "
                    << elements << " versus " << arrayp->rangep()->elementsConst());
            }
            m_assignError = true;
            elements = 1;
            elemIdx = 0;
        }
        if (rvalue && !nodep->isRepeatable() && !VN_IS(nodep, ExprStmt)) {
            // Evaluate a value that is not repeatable once, for the first element, into a
            // temporary that replaces it, so the other elements read the temporary
            UASSERT_OBJ(m_scopep, nodep, "Not under scope");
            FileLine* const flp = nodep->fileline();
            AstVarScope* const vscp = m_tmps.make(flp, m_scopep, nodep->dtypep());
            AstVarRef* const refp = new AstVarRef{flp, vscp, VAccess::READ};
            nodep->replaceWith(refp);
            AstAssign* const assignp
                = new AstAssign{flp, new AstVarRef{flp, vscp, VAccess::WRITE}, nodep};
            assignp->user1(true);  // Copied as a whole, not sliced
            {
                VL_RESTORER(m_okConsArray);
                m_okConsArray = true;
                iterateChildren(assignp);
            }
            return new AstExprStmt{flp, assignp,
                                   cloneAndSel(refp, elements, elemIdx, needPure, rvalue)};
        }
        AstNodeExpr* newp;
        if (AstConsArray* const consp = VN_CAST(nodep, ConsArray)) {
            UINFO(9, "  cloneConsArray(" << elements << "," << elemIdx << ") " << nodep);
            const uint64_t index
                = arrayp->rangep()->ascending() ? elemIdx : elements - 1 - elemIdx;
            newp = consp->valuep(index)->cloneTree(false, needPure);
        } else if (const AstCvtUnpackToUnpack* const cvtp = VN_CAST(nodep, CvtUnpackToUnpack)) {
            UINFO(9, "  cloneCvtUnpackToUnpack(" << elements << "," << elemIdx << ") " << nodep);
            // The element in the same left-to-right position of the source
            AstNodeExpr* const elemp
                = cloneAndSel(cvtp->fromp(), elements, elemIdx, needPure, rvalue);
            AstNodeDType* const subDTypep = arrayp->subDTypep();
            const AstUnpackArrayDType* const subArrayp
                = VN_CAST(subDTypep->skipRefp(), UnpackArrayDType);
            if (!subArrayp || !subArrayp->isReverseOf(elemp->dtypep())) return elemp;
            return new AstCvtUnpackToUnpack{nodep->fileline(), elemp, subDTypep};
        } else if (const AstCvtPackedToArray* const cvtp = VN_CAST(nodep, CvtPackedToArray)) {
            UINFO(9, "  cloneCvtPackedToArray(" << elements << "," << elemIdx << ") " << nodep);
            // The leftmost element takes the most significant bits
            AstNodeDType* const subDTypep = arrayp->subDTypep();
            const int elemWidth = subDTypep->widthStream();
            const int lsb = static_cast<int>(elements - 1 - elemIdx) * elemWidth;
            AstNodeExpr* fromp = cvtp->fromp()->cloneTree(false, needPure);
            if (fromp->width() < lsb + elemWidth) {
                fromp = new AstExtend{fromp->fileline(), fromp, lsb + elemWidth};
            }
            AstNodeExpr* const selp = new AstSel{nodep->fileline(), fromp, lsb, elemWidth};
            if (!VN_IS(subDTypep->skipRefp(), UnpackArrayDType)) return selp;
            return new AstCvtPackedToArray{nodep->fileline(), selp, subDTypep};
        } else if (AstCond* const snodep = VN_CAST(nodep, Cond)) {
            UINFO(9, "  cloneCond(" << elements << "," << elemIdx << ") " << nodep);
            return new AstCond{snodep->fileline(), snodep->condp()->cloneTree(false, needPure),
                               cloneAndSel(snodep->thenp(), elements, elemIdx, needPure, rvalue),
                               cloneAndSel(snodep->elsep(), elements, elemIdx, needPure, rvalue)};
        } else if (const AstSliceSel* const snodep = VN_CAST(nodep, SliceSel)) {
            UINFO(9, "  cloneSliceSel(" << elements << "," << elemIdx << ") " << nodep);
            // Offset from the lowest selected element
            const int offset = !snodep->declRange().ascending()
                                   ? snodep->declRange().elements() - 1 - elemIdx
                                   : elemIdx;
            AstNodeExpr* const fromp = snodep->fromp()->cloneTree(false, needPure);
            if (const AstConst* const lsbConstp = VN_CAST(snodep->lsbp(), Const)) {
                newp = new AstArraySel{nodep->fileline(), fromp, lsbConstp->toSInt() + offset};
            } else {
                AstNodeExpr* const lsbp = snodep->lsbp()->cloneTree(false, needPure);
                AstNodeExpr* const indexp
                    = new AstAdd{nodep->fileline(), lsbp,
                                 new AstConst{nodep->fileline(), AstConst::WidthedValue{},
                                              lsbp->width(), static_cast<uint32_t>(offset)}};
                indexp->dtypeFrom(lsbp);
                newp = new AstArraySel{nodep->fileline(), fromp, indexp};
            }
        } else if (const AstSampled* const snodep = VN_CAST(nodep, Sampled)) {
            UINFO(9, "  cloneSliceSel(" << elements << "," << elemIdx << ") " << nodep);
            AstNodeExpr* const exprp = VN_AS(snodep->exprp(), NodeExpr);
            AstNodeExpr* const selp = cloneAndSel(exprp, elements, elemIdx, needPure, rvalue);
            return new AstSampled{nodep->fileline(), selp, selp->dtypep(), snodep->internal()};
        } else if (AstExprStmt* const snodep = VN_CAST(nodep, ExprStmt)) {
            UINFO(9, "  cloneExprStmt(" << elements << "," << elemIdx << ") " << nodep);
            AstNodeExpr* const resultSelp
                = cloneAndSel(snodep->resultp(), elements, elemIdx, needPure, rvalue);
            if (snodep->stmtsp()) {
                return new AstExprStmt{nodep->fileline(), snodep->stmtsp()->unlinkFrBackWithNext(),
                                       resultSelp};
            } else {
                return resultSelp;
            }
        } else if (VN_IS(nodep, NodeVarRef) || VN_IS(nodep, NodeSel) || VN_IS(nodep, CMethodHard)
                   || VN_IS(nodep, MemberRef) || VN_IS(nodep, StructSel)
                   || VN_IS(nodep, CvtQueueToUnpack)) {
            UINFO(9, "  cloneSel(" << elements << "," << elemIdx << ") " << nodep);
            const int leOffset = !arrayp->rangep()->ascending()
                                     ? arrayp->rangep()->elementsConst() - 1 - elemIdx
                                     : elemIdx;
            newp = new AstArraySel{nodep->fileline(), nodep->cloneTree(false, needPure), leOffset};
        } else {
            if (!m_assignError) {
                nodep->v3error(nodep->prettyTypeName()
                               << " unexpected in assignment to unpacked array");
            }
            m_assignError = true;
            // Likely will cause downstream errors
            newp = nodep->cloneTree(false, needPure);
        }
        return newp;
    }

    bool assignOptimize(AstNodeAssign* nodep) {
        // Return true if did optimization
        AstNodeDType* const dtp = nodep->lhsp()->dtypep()->skipRefp();
        AstNode* stp = nodep->rhsp();
        const AstUnpackArrayDType* const arrayp = VN_CAST(dtp, UnpackArrayDType);
        if (!arrayp) return false;
        // A slice target can only be written element by element
        const bool lhsSlice = VN_IS(nodep->lhsp(), SliceSel);
        if (VN_IS(stp, CvtPackedToArray) && !lhsSlice) return false;
        if (VN_IS(stp, CvtArrayToArray)) {
            if (!lhsSlice) return false;
            if (VN_IS(nodep, AssignForce) || VN_IS(nodep, AssignCont)) {
                // Would need the temporary below to follow the stream continuously
                nodep->v3warn(E_UNSUPPORTED, "Unsupported: force or procedural continuous "
                                             "assignment of a stream of a dynamically sized "
                                             "array to an unpacked array slice");
                VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
                return true;
            }
            // Convert into a temporary of the slice's type, then copy that element by element
            FileLine* const flp = stp->fileline();
            AstVarScope* const tmpp = m_cvtTmps.make(flp, m_scopep, nodep->lhsp()->dtypep());
            AstVarRef* const tmpRefp = new AstVarRef{flp, tmpp, VAccess::WRITE};
            AstNodeExpr* const cvtp = VN_AS(stp, NodeExpr)->unlinkFrBack();
            AstNodeAssign* const cvtAssignp
                = VN_IS(nodep, AssignW)
                      ? static_cast<AstNodeAssign*>(new AstAssignW{flp, tmpRefp, cvtp})
                      : new AstAssign{flp, tmpRefp, cvtp};
            nodep->addHereThisAsNext(cvtAssignp);
            nodep->rhsp(new AstVarRef{flp, tmpp, VAccess::READ});
            stp = nodep->rhsp();
        }
        if (VN_IS(stp, CvtQueueToUnpack) && !lhsSlice) return false;
        if (VN_IS(stp, CReset)) return false;

        // Any isSc variables must be expanded regardless of --fno-slice, as must an array
        // pattern lvalue (e.g. an output port connection), which is not an lvalue in C++
        const bool hasSc
            = nodep->exists([&](const AstVarRef* refp) -> bool { return refp->varp()->isSc(); });
        const bool consLhs = VN_IS(nodep->lhsp(), ConsArray);
        // Slicing would evaluate a side that is not repeatable once per element, so copy the
        // whole array, unless writing a slice, which is only done element by element
        const bool impure = !nodep->lhsp()->isRepeatable() || !nodep->rhsp()->isRepeatable();
        if (!hasSc && !lhsSlice && !consLhs && (!v3Global.opt.fSlice() || impure)) {
            m_okConsArray = true;  // VL_RESTORER in visit(AstNodeAssign)
            return false;
        }

        // Skip optimization if array is too large
        const int elements = arrayp->rangep()->elementsConst();
        const int elementLimit = v3Global.opt.fSliceElementLimit();
        if (!lhsSlice && !consLhs && elements > elementLimit && elementLimit > 0) {
            ++m_statSliceElementSkips;
            m_okConsArray = true;  // VL_RESTORER in visit(AstNodeAssign)
            return false;
        }

        // Skip if this is a simple a = b assignment of identical arrays
        if (AstVarRef* const lhsp = VN_CAST(nodep->lhsp(), VarRef)) {
            if (AstVarRef* const rhsp = VN_CAST(nodep->rhsp(), VarRef)) {
                if (!hasSc && lhsp->dtypep()->skipRefp()->sameTree(rhsp->dtypep()->skipRefp())) {
                    m_okConsArray = true;  // VL_RESTORER in visit(AstNodeAssign)
                    return false;
                }
            }
        }

        UINFO(4, "Slice optimizing " << nodep);
        ++m_statAssigns;

        // Left and right could have different ascending/descending range,
        // but #elements is common and all variables are realigned to start at zero
        // Assign of an ascending range slice to a descending range one must reverse
        // the elements
        AstNodeAssign* newlistp = nullptr;
        for (uint64_t elemIdx = 0; elemIdx < static_cast<uint64_t>(elements); ++elemIdx) {
            // Original node is replaced, so it is safe to copy it one time even if it is impure.
            AstNodeAssign* const newp = nodep->cloneType(
                cloneAndSel(nodep->lhsp(), elements, elemIdx, elemIdx != 0, false),
                cloneAndSel(nodep->rhsp(), elements, elemIdx, elemIdx != 0, true));
            UINFOTREE(9, newp, "", "new");
            newlistp = AstNode::addNext(newlistp, newp);
        }
        UINFOTREE(9, nodep, "", "Deslice-Dn");
        nodep->replaceWith(newlistp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        // Normal edit iterator will now iterate on all of the expansion assignments
        // This will potentially call this function again to resolve next level of slicing
        return true;
    }

    // Split an assignment to a structure pattern into an assignment per member
    bool assignConsStruct(AstNodeAssign* nodep) {
        // Such an lvalue comes e.g. from an output port connection (IEEE 1800-2023 23.3.3)
        AstConsStruct* const consp = VN_CAST(nodep->lhsp(), ConsStruct);
        if (!consp) return false;
        AstNodeAssign* newlistp = nullptr;
        for (AstConsStructItem* itemp = consp->itemsp(); itemp;
             itemp = VN_AS(itemp->nextp(), ConsStructItem)) {
            // Original node is replaced, so it is safe to copy it one time even if it is impure.
            AstNodeExpr* const fromp = nodep->rhsp()->cloneTree(false, newlistp != nullptr);
            AstStructSel* const selp
                = new AstStructSel{fromp->fileline(), fromp, itemp->memberp()->name()};
            selp->dtypeFrom(itemp->memberp()->dtypep());
            newlistp = AstNode::addNext(newlistp,
                                        nodep->cloneType(itemp->valuep()->unlinkFrBack(), selp));
        }
        nodep->replaceWith(newlistp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        return true;
    }

    void visit(AstScope* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        iterateChildren(nodep);
    }

    void visit(AstNodeAssign* nodep) override {
        // Called recursively on newly created assignments
        if (nodep->user1SetOnce()) return;  // Process once
        UINFOTREE(9, nodep, "", "Deslice-In");
        VL_RESTORER(m_assignError);
        VL_RESTORER(m_assignp);
        VL_RESTORER(m_okConsArray);  // Set in assignOptimize
        m_assignError = false;
        m_assignp = nodep;
        if (assignOptimize(nodep) || assignConsStruct(nodep)) return;
        iterateChildren(nodep);
    }

    void visit(AstNodeCons* nodep) override {
        VL_RESTORER(m_okConsArray);
        m_okConsArray = true;
        iterateChildren(nodep);
    }
    void visit(AstConsArray* nodep) override {
        UASSERT_OBJ(!m_assignp || m_okConsArray, nodep,
                    "Array initialization should have been removed earlier");
        iterateChildren(nodep);
    }
    // An array value, e.g. from a cast, may be selected from, or converted whole, e.g. in a stream
    void iterateOkConsArray(AstNodeExpr* const nodep) {
        VL_RESTORER(m_okConsArray);
        m_okConsArray = true;
        iterateChildren(nodep);
    }
    void visit(AstCvtArrayToArray* nodep) override { iterateOkConsArray(nodep); }
    void visit(AstCvtArrayToPacked* nodep) override { iterateOkConsArray(nodep); }
    void visit(AstCvtUnpackToQueue* nodep) override { iterateOkConsArray(nodep); }

    template <typename T_NodeBiop>
    void expandBiOp(T_NodeBiop* biopp) {
        AstNodeBiop* nodep = biopp;
        if (nodep->user1SetOnce()) return;  // Process once
        UINFO(9, "  Bi-Eq/Neq expansion " << nodep);

        // Only expand if lhs is an unpacked array (we assume type checks already passed)
        const AstNodeDType* const fromDtp = nodep->lhsp()->dtypep()->skipRefp();
        if (const AstUnpackArrayDType* const adtypep = VN_CAST(fromDtp, UnpackArrayDType)) {
            AstNodeBiop* logp = nullptr;

            const int elements = adtypep->rangep()->elementsConst();
            for (int elemIdx = 0; elemIdx < elements; ++elemIdx) {
                // EQ(a,b) -> LOGAND(EQ(ARRAYSEL(a,0), ARRAYSEL(b,0)), ...[1])
                // Original node is replaced, so it is safe to copy it one time even if it is
                // impure.
                T_NodeBiop* const clonep = new T_NodeBiop{
                    nodep->fileline(),
                    cloneAndSel(nodep->lhsp(), elements, elemIdx, elemIdx != 0, true),
                    cloneAndSel(nodep->rhsp(), elements, elemIdx, elemIdx != 0, true)};
                if (!logp) {
                    logp = clonep;
                } else {
                    switch (nodep->type()) {
                    case VNType::Eq:  // FALLTHRU
                    case VNType::EqCase:
                        logp = new AstLogAnd{nodep->fileline(), logp, clonep};
                        break;
                    case VNType::Neq:  // FALLTHRU
                    case VNType::NeqCase:
                        logp = new AstLogOr{nodep->fileline(), logp, clonep};
                        break;
                    default: nodep->v3fatalSrc("Unknown node type processing array slice"); break;
                    }
                }
            }
            UASSERT_OBJ(logp, nodep, "Unpacked array with empty indices range");
            nodep->replaceWith(logp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            nodep = logp;
        }

        iterateChildren(nodep);
    }

    void visit(AstEq* nodep) override { expandBiOp(nodep); }
    void visit(AstNeq* nodep) override { expandBiOp(nodep); }
    void visit(AstEqCase* nodep) override { expandBiOp(nodep); }
    void visit(AstNeqCase* nodep) override { expandBiOp(nodep); }

    void visit(AstArraySel* nodep) override {
        // Select an element of a slice from the sliced array, so that it can be written
        AstSliceSel* const slicep = VN_CAST(nodep->fromp(), SliceSel);
        if (slicep) {
            // The index is the offset from the lowest selected element, at most as wide as
            // needed to index the slice (V3Width), so not wider than the 32-bit position
            FileLine* const fl = nodep->fileline();
            AstNodeExpr* const lsbp = slicep->lsbp()->unlinkFrBack();
            AstNodeExpr* offsetp = nodep->bitp()->unlinkFrBack();
            UASSERT_OBJ(offsetp->width() <= lsbp->width(), nodep, "Index wider than position");
            if (offsetp->width() < lsbp->width()) {
                offsetp = new AstExtend{fl, offsetp, lsbp->width()};
            }
            AstNodeExpr* const indexp = new AstAdd{fl, lsbp, offsetp};
            indexp->dtypeFrom(lsbp);
            AstArraySel* const newp = new AstArraySel{fl, slicep->fromp()->unlinkFrBack(), indexp};
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            iterate(newp);  // The sliced array may be a slice too
            return;
        }
        iterateOkConsArray(nodep);
    }

    void visit(AstSliceSel* nodep) override {
        // Slice used as a bare value, e.g. a $display argument. Build it via
        // VlUnpacked::slice<N_Out>(loIdx), as DYN_SLICE already does for Queues.
        iterateChildren(nodep);
        AstNodeExpr* const fromp = nodep->fromp()->unlinkFrBack();
        AstCMethodHard* const newp
            = new AstCMethodHard{nodep->fileline(), fromp, VCMethod::ARRAY_SLICE};
        newp->addPinsp(nodep->lsbp()->unlinkFrBack());
        newp->dtypeFrom(nodep);  // Reuse the already-correct sliced array dtype
        newp->didWidth(true);
        newp->protect(false);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit SliceVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~SliceVisitor() override {
        V3Stats::addStat("Optimizations, Slice array assignments", m_statAssigns);
        V3Stats::addStat("Optimizations, Slice array skips due to size limit",
                         m_statSliceElementSkips);
    }
};

//######################################################################
// Link class functions

void V3Slice::sliceAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { SliceVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("slice", 0, dumpTreeEitherLevel() >= 3);
}
