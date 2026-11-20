// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Expression width calculations
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
// V3WidthSel's Transformations:
//      Top down traversal:
//          Replace SELPLUS/SELMINUS with SEL
//          Replace SELEXTRACT with SEL
//          Replace SELBIT with SEL or ARRAYSEL
//
// This code was once in V3LinkResolve, but ascending bit range vectors won't
// work that early.  It was considered for V3Width and V3Param, but is
// fairly ugly both places as the nodes change in too strongly
// interconnected ways.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Const.h"
#include "V3Width.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Width state, as a visitor of each AstNode

class WidthSelVisitor final : public VNVisitor {

    // IMPORTANT
    //**** This is not a normal visitor, in that all iteration is instead
    //  done by the caller (V3Width).  This avoids duplicating much of the
    //  complicated GenCase/GenFor/Cell/Function call logic that all depends
    //  on if widthing top-down or just for parameters.
#define iterateChildren DO_NOT_iterateChildern_IN_V3WidthSel

    // STATE
    V3Width::SelOrigin* const m_originp;  // Type of a written position, for its width check

    // Record the type of a constant position, as written, when its storage offset differs
    void recordOrigin(const AstConst* constp) {
        if (!m_originp) return;
        m_originp->valid = true;
        m_originp->width = constp->width();
        m_originp->widthMin = constp->widthMin();
        m_originp->sized = constp->dtypep()->widthSized();
    }

    // METHODS

    void checkConstantOrReplace(AstNode* nodep, const string& message) {
        // See also V3Width::checkConstantOrReplace
        // Note can't call V3Const::constifyParam(nodep) here, as constify may change nodep on us!
        if (!VN_IS(nodep, Const)) {
            nodep->v3error(message);
            nodep->replaceWith(new AstConst{nodep->fileline(), AstConst::Unsized32{}, 1});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
    }

    // RETURN TYPE
    struct FromData final {
        AstNodeDType* const m_errp;  // Node that was found, for error reporting if not known type
        AstNodeDType* const m_dtypep;  // Data type for the 'from' slice
        VNumRange m_fromRange;  // Numeric range bounds for the 'from' slice
        FromData(AstNodeDType* errp, AstNodeDType* dtypep, const VNumRange& fromRange)
            : m_errp{errp}
            , m_dtypep{dtypep}
            , m_fromRange{fromRange} {}
        ~FromData() = default;
    };
    static FromData fromDataForArray(AstNode* nodep, AstNode* basefromp) {
        // What is the data type and information for this SEL-ish's from()?
        UINFO(9, "  fromData start ddtypep = " << basefromp);
        VNumRange fromRange;  // constructs to isRanged(false)
        UASSERT_OBJ(basefromp && basefromp->dtypep(), nodep, "Select with no from dtype");
        AstNodeDType* const ddtypep = basefromp->dtypep()->skipRefp();
        AstNodeDType* const errp = ddtypep;
        UINFO(9, "  fromData.ddtypep = " << ddtypep);
        if (const AstNodeArrayDType* const adtypep = VN_CAST(ddtypep, NodeArrayDType)) {
            fromRange = adtypep->declRange();
        } else if (VN_IS(ddtypep, AssocArrayDType)) {
        } else if (VN_IS(ddtypep, WildcardArrayDType)) {
        } else if (VN_IS(ddtypep, DynArrayDType)) {
        } else if (VN_IS(ddtypep, QueueDType)) {
        } else if (const AstNodeUOrStructDType* const adtypep
                   = VN_CAST(ddtypep, NodeUOrStructDType)) {
            fromRange = adtypep->declRange();
        } else if (const AstBasicDType* const adtypep = VN_CAST(ddtypep, BasicDType)) {
            if (adtypep->isString() && VN_IS(nodep, SelBit)) {
            } else if (adtypep->isRanged()) {
                UASSERT_OBJ(
                    !(adtypep->rangep()
                      && (!VN_IS(adtypep->rangep()->leftp(), Const)
                          || !VN_IS(adtypep->rangep()->rightp(), Const))),
                    nodep,
                    "Non-constant variable range; errored earlier");  // in constifyParam(bfdtypep)
                fromRange = adtypep->declRange();
            } else {
                nodep->v3error("Illegal bit or array select; type does not have a bit range, or "
                               << "bad dimension: data type is " << errp->prettyDTypeNameQ());
            }
        } else {
            nodep->v3error("Illegal bit or array select; type already selected, or bad dimension: "
                           << "data type is " << errp->prettyDTypeNameQ());
        }
        return FromData(errp, ddtypep, fromRange);
    }

    AstNodeExpr* newSubNeg(AstNodeExpr* lhsp, int32_t rhs, bool signedRhs = false) {
        // Return lhs-rhs, but if rhs is negative use an add, so we won't
        // have to deal with signed math and related 32bit sign extension problems
        if (rhs == 0) {
            return lhsp;
        } else if (VN_IS(lhsp, Const)) {
            // Optional vs just making add/sub below, but saves constification some work
            // At least 32 bits, as V3Width makes the add/sub below, so the result does not wrap
            const int width = std::max(lhsp->width(), 32);
            const V3Number& lhsNum = VN_AS(lhsp, Const)->num();
            V3Number lhsExtNum{lhsp, width};
            if (lhsp->isSigned()) {
                lhsExtNum.opExtendS(lhsNum, lhsNum.width());
            } else {
                lhsExtNum.opAssign(lhsNum);
            }
            V3Number rhsNum{lhsp, width};
            rhsNum.opExtendS(V3Number(lhsp, 32, rhs), 32);
            V3Number num{lhsp, width};
            num.opSub(lhsExtNum, rhsNum);
            num.isSigned(lhsp->isSigned());
            return new AstConst{lhsp->fileline(), num};
        }
        // Unsized, as a literal; a signed constant sign extends a narrower signed lhs
        V3Number offset{lhsp, 32, static_cast<uint32_t>(std::abs(rhs))};
        offset.width(32, false);
        offset.isSigned(signedRhs);
        AstConst* const offsetp = new AstConst{lhsp->fileline(), offset};
        if (rhs > 0) {
            AstNodeExpr* const newp = new AstSub{lhsp->fileline(), lhsp, offsetp};
            // We must make sure sub gets sign of original value, not from the constant
            newp->dtypeFrom(lhsp);
            return newp;
        } else {  // rhs < 0;
            AstNodeExpr* const newp = new AstAdd{lhsp->fileline(), lhsp, offsetp};
            // We must make sure sub gets sign of original value, not from the constant
            newp->dtypeFrom(lhsp);
            return newp;
        }
    }
    // Return an unsigned index one bit wider
    static AstNodeExpr* newIndexExtendp(AstNodeExpr* indexp) {
        // Adding the offset of a negative low bound to an index near its maximum would
        // wrap to a valid element. A narrower index is added at 32 bits, so cannot wrap.
        AstConst* const constp = VN_CAST(indexp, Const);
        if (!constp) return new AstExtend{indexp->fileline(), indexp, indexp->width() + 1};
        // Still a constant, for the SELRANGE check. The caller deletes the unlinked index.
        V3Number num{constp, constp->width() + 1};
        num.opAssign(constp->num());
        return new AstConst{constp->fileline(), num};
    }
    AstNodeExpr* newSubNeg(int32_t lhs, AstNodeExpr* rhsp) {
        // Return lhs-rhs
        // We must make sure sub gets sign of original value
        AstNodeExpr* const newp = new AstSub{
            rhsp->fileline(), new AstConst(rhsp->fileline(), AstConst::Unsized32{}, lhs), rhsp};
        newp->dtypeFrom(rhsp);  // Important as AstSub default is lhs's sign
        return newp;
    }

    // A constant position selects storage at its exact value, never at a truncated or wrapped
    // value that could address a different element. A count is read by its own signedness.
    static V3Number exactIndex(AstConst* const constp, const int bits,
                               const bool position = true) {
        V3Number index{constp, bits};
        if (position ? V3Width::selectPositionSigned(constp) : constp->isSigned()) {
            index.opExtendS(constp->num(), constp->width());
        } else {
            index.opAssign(constp->num());
        }
        index.isSigned(true);
        return index;
    }
    static int compactInt(const V3Number& signedNum) {
        V3Number lowWord{&signedNum, 32};
        lowWord.opAssign(signedNum);
        return lowWord.toSInt();
    }
    static V3Number exactPackedOffset(AstConst* const constp, const int64_t bound,
                                      const bool ascending, const int stride) {
        const int bits
            = std::max(constp->width(), 32) + 2 + (stride == 1 ? 0 : V3Number::log2b(stride) + 1);
        const V3Number index = exactIndex(constp, bits);
        V3Number boundNum{constp, bits};
        V3Number bound64{constp, 64};
        bound64.setQuad(static_cast<uint64_t>(bound));
        boundNum.opExtendS(bound64, 64);
        V3Number offset{constp, bits};
        if (ascending) {
            offset.opSub(boundNum, index);
        } else {
            offset.opSub(index, boundNum);
        }
        offset.isSigned(true);
        if (stride == 1) return offset;
        V3Number storageOffset{constp, bits};
        storageOffset.opMulS(offset, V3Number{constp, bits, static_cast<uint32_t>(stride)});
        storageOffset.isSigned(true);
        return storageOffset;
    }
    // Storage positions are unsigned when nonnegative
    static AstConst* packedOffsetConstp(FileLine* const flp, const V3Number& offset) {
        if (!offset.fitsInInt32(true)) return new AstConst{flp, offset};
        const int position = compactInt(offset);
        return position < 0 ? new AstConst{flp, AstConst::Signed32{}, position}
                            : new AstConst{flp, static_cast<uint32_t>(position)};
    }
    // Whether a packed part-select of a number of elements of a width would exceed the supported
    // width. Computed without overflow or division, so a receiver with an invalid element width
    // continues as before. More elements than the limit always exceed it, as each element of a
    // representable type has at least one bit.
    static bool exceedsPackedLimit(AstNode* nodep, const V3Number& count, int elementWidth) {
        if (V3Number{nodep, 1}
                .opGt(count, V3Number{nodep, count.width(), VL_PACKED_WIDTH_MAX})
                .isEqOne()) {
            return true;
        }
        return int64_t{count.toUInt()} * elementWidth > int64_t{VL_PACKED_WIDTH_MAX};
    }
    // The storage offset of a known constant position, or nullptr
    AstConst* packedOffsetp(AstNodeExpr* const indexp, const int64_t bound, const bool ascending,
                            const int stride) {
        AstConst* const constp = VN_CAST(indexp, Const);
        if (!constp || constp->num().isOpaque() || constp->num().isFourState()) return nullptr;
        recordOrigin(constp);
        return packedOffsetConstp(constp->fileline(),
                                  exactPackedOffset(constp, bound, ascending, stride));
    }

    AstNodeExpr* newSubLsbOf(AstNodeExpr* underp, const VNumRange& fromRange) {
        // Account for a variable's LSB in bit selections
        // Will likely become SUB(underp, lsb_of_signal).
        // Don't report WIDTH warnings etc here, as may be inside a
        // generate branch that will be deleted.
        // SUB #'s Not needed when LSB==0 and MSB>=0 (ie [0:-13] must still get added!)
        if (!fromRange.ranged()) {
            // vector without range, or 0 lsb is ok, for example a INTEGER x; y = x[21:0];
            return underp;
        } else {
            if (fromRange.ascending()) {
                // reg [1:3] was swapped to [3:1] (lsbEndianedp==3) and needs a SUB(3,under)
                return newSubNeg(fromRange.hi(), underp);
            } else {
                // reg [3:1] needs a SUB(under,1)
                return newSubNeg(underp, fromRange.lo());
            }
        }
    }
    // A constant bit position in an offset range is resolved exactly; an index that is
    // itself the bit offset, and a dynamic index, are lowered as before
    AstNodeExpr* bitOffsetp(AstNodeExpr* indexp, const VNumRange& fromRange) {
        const bool ascending = fromRange.ascending();
        const bool offsetIsIndex = !fromRange.ranged() || (!ascending && fromRange.lo() == 0);
        AstConst* const offsetp
            = offsetIsIndex ? nullptr
                            : packedOffsetp(indexp, ascending ? fromRange.hi() : fromRange.lo(),
                                            ascending, 1);
        // An unused index is deleted by the caller
        return offsetp ? offsetp : newSubLsbOf(indexp, fromRange);
    }
    AstNodeExpr* newMulConst(FileLine* fl, uint32_t elwidth, AstNodeExpr* indexp) {
        AstNodeExpr* extendp;
        const int widthMin = std::max(V3Number::log2b(elwidth) + 1, indexp->widthMin());
        if (indexp->width() > 32) {
            extendp = new AstSel{fl, indexp, 0, 32, widthMin};
        } else {
            extendp = new AstExtend{fl, indexp, 32, widthMin};
        }
        AstNodeExpr* const mulp
            = new AstMul{fl, new AstConst{fl, AstConst::Unsized32{}, elwidth},
                         // Extend needed as index might be e.g. 3 bits but constant e.g. 5 bits
                         extendp};
        return mulp;
    }

    AstNodeDType* sliceDType(AstPackArrayDType* nodep, int msb, int lsb) {
        // Return slice needed for msb/lsb, either as original dtype or a new slice dtype
        if (nodep->declRange().elements() == (msb - lsb + 1)  // Extracting whole of original array
            && nodep->declRange().lo() == lsb) {
            return nodep;
        } else {
            // Need a slice data type, which is an array of the extracted
            // type, but with (presumably) different size
            const VNumRange newRange{msb, lsb, nodep->declRange().ascending()};
            AstNodeDType* const vardtypep
                = new AstPackArrayDType{nodep->fileline(),
                                        nodep->subDTypep(),  // Need to strip off array reference
                                        new AstRange{nodep->fileline(), newRange}};
            v3Global.rootp()->typeTablep()->addTypesp(vardtypep);
            return vardtypep;
        }
    }

    AstNodeExpr* selQueueBackness(AstNode* nodep) {
        if (VN_IS(nodep, Unbounded)) {  // e.g. "[$]"
            return new AstConst{nodep->fileline(), AstConst::Signed32{}, 0};
        } else if (VN_IS(nodep, Sub) && VN_IS(VN_CAST(nodep, Sub)->lhsp(), Unbounded)) {
            // e.g. "q[$ - 1]", where 1 is subnodep
            AstNodeExpr* subrhsp = VN_CAST(nodep, Sub)->rhsp()->unlinkFrBack();
            return subrhsp;
        } else {
            return nullptr;
        }
    }

    void warnTri(AstNode* nodep) {
        if (VN_IS(nodep, Const) && VN_AS(nodep, Const)->num().isFourState()) {
            nodep->v3error(
                "Selection index is constantly unknown or tristated: " << nodep->name());
        }
    }

    // VISITORS
    // If adding new visitors, ensure V3Width's visit(TYPE) calls into here

    void visit(AstSelBit* nodep) override {
        // Select of a non-width specified part of an array, i.e. "array[2]"
        // This select style has a lsb and msb (no user specified width)
        UINFO(6, "SELBIT " << nodep);
        UINFOTREE(9, nodep->backp(), "", "SELBT0");
        // lhsp/rhsp do not need to be constant
        AstNodeExpr* const fromp = nodep->fromp()->unlinkFrBack();
        AstNodeExpr* const rhsp = nodep->bitp()->unlinkFrBack();  // bit we're extracting
        UINFOTREE(9, nodep, "", "SELBT2");
        const FromData fromdata = fromDataForArray(nodep, fromp);
        AstNodeDType* const ddtypep = fromdata.m_dtypep;
        const VNumRange fromRange = fromdata.m_fromRange;
        UINFO(6, "  ddtypep " << ddtypep);
        if (const AstUnpackArrayDType* const adtypep = VN_CAST(ddtypep, UnpackArrayDType)) {
            // SELBIT(array, index) -> ARRAYSEL(array, index)
            AstNodeExpr* subp = rhsp;
            if (fromRange.lo() != 0 || fromRange.hi() < 0) {
                if (fromRange.lo() < 0 && !subp->isSigned() && subp->width() >= 32) {
                    subp = newIndexExtendp(subp);
                }
                // Signed for a signed index, as V3Width keeps the index's full value
                AstNodeExpr* const extp = subp;
                subp = newSubNeg(subp, fromRange.lo(), subp->isSigned());
                // A constant is folded into a new one; the index itself is deleted below
                if (extp != rhsp && extp != subp && !extp->backp()) {
                    VL_DO_DANGLING(pushDeletep(extp), extp);
                }
            }
            AstArraySel* const newp = new AstArraySel{nodep->fileline(), fromp, subp};
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off array reference
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (const AstPackArrayDType* const adtypep = VN_CAST(ddtypep, PackArrayDType)) {
            // SELBIT(array, index) -> SEL(array, index*width-of-subindex, width-of-subindex)
            UASSERT_OBJ(!(!fromRange.elements() || (adtypep->width() % fromRange.elements()) != 0),
                        adtypep,
                        "Array extraction with width miscomputed " << adtypep->width() << "/"
                                                                   << fromRange.elements());
            // cppcheck-suppress zerodivcond
            const int elwidth = adtypep->width() / fromRange.elements();
            const bool ascending = fromRange.ascending();
            AstNodeExpr* lsbp = packedOffsetp(rhsp, ascending ? fromRange.hi() : fromRange.lo(),
                                              ascending, elwidth);
            if (!lsbp) {
                AstNodeExpr* const subp = ascending ? newSubNeg(fromRange.hi(), rhsp)
                                                    : newSubNeg(rhsp, fromRange.lo());
                lsbp = newMulConst(nodep->fileline(), elwidth, subp);
            }
            AstSel* const newp = new AstSel{nodep->fileline(), fromp, lsbp, elwidth};
            newp->declRange(fromRange);
            newp->declElWidth(elwidth);
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off array reference
            if (VN_IS(adtypep->subDTypep(), BasicDType)) {
                // IEEE 1800-2023 7.4.1 Packed arrays says:
                //   The individual elements of the array are unsigned
                //   unless they are of a named type declared as signed.
                newp->dtypep()->numeric(VSigning::fromBool(false));
            }
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (const AstAssocArrayDType* const adtypep = VN_CAST(ddtypep, AssocArrayDType)) {
            // SELBIT(array, index) -> ASSOCSEL(array, index)
            AstAssocSel* const newp = new AstAssocSel{nodep->fileline(), fromp, rhsp};
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off array reference
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (const AstWildcardArrayDType* const adtypep
                   = VN_CAST(ddtypep, WildcardArrayDType)) {
            // SELBIT(array, index) -> WILDCARDSEL(array, index)
            AstWildcardSel* const newp = new AstWildcardSel{nodep->fileline(), fromp, rhsp};
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off array reference
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (const AstDynArrayDType* const adtypep = VN_CAST(ddtypep, DynArrayDType)) {
            // SELBIT(array, index) -> CMETHODCALL(queue, "at", index)
            const VCMethod method
                = nodep->access().isWriteOrRW() ? VCMethod::ARRAY_AT_WRITE : VCMethod::ARRAY_AT;
            AstCMethodHard* const newp
                = new AstCMethodHard{nodep->fileline(), fromp, method, rhsp};
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off queue reference
            UINFOTREE(9, newp, "", "SELBTq");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (const AstQueueDType* const adtypep = VN_CAST(ddtypep, QueueDType)) {
            // SELBIT(array, index) -> CMETHODCALL(queue, "at", index)
            AstCMethodHard* newp;
            if (AstNodeExpr* const backnessp = selQueueBackness(rhsp)) {
                const VCMethod method = nodep->access().isWriteOrRW()
                                            ? VCMethod::DYN_AT_WRITE_APPEND_BACK
                                            : VCMethod::ARRAY_AT_BACK;
                newp = new AstCMethodHard{nodep->fileline(), fromp, method, backnessp};
            } else {
                const VCMethod method = nodep->access().isWriteOrRW()
                                            ? VCMethod::DYN_AT_WRITE_APPEND
                                            : VCMethod::ARRAY_AT;
                newp = new AstCMethodHard{nodep->fileline(), fromp, method, rhsp};
            }
            newp->dtypeFrom(adtypep->subDTypep());  // Need to strip off queue reference
            UINFOTREE(9, newp, "", "SELBTq");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, BasicDType) && ddtypep->isString()) {
            // SELBIT(string, index) -> GETC(string, index)
            AstNodeExpr* newp;
            if (fromp->isLValue()) {
                newp = new AstGetcRefN{nodep->fileline(), fromp, rhsp};
            } else {
                newp = new AstGetcN{nodep->fileline(), fromp, rhsp};
            }
            UINFO(6, "   new " << newp);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, BasicDType)) {
            // SELBIT(range, index) -> SEL(array, index, 1)
            AstSel* const newp
                = new AstSel{nodep->fileline(), fromp, bitOffsetp(rhsp, fromRange), 1};
            newp->declRange(fromRange);
            UINFO(6, "   new " << newp);
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, NodeUOrStructDType)) {  // A bit from the packed struct
            // SELBIT(range, index) -> SEL(array, index, 1)
            AstSel* const newp
                = new AstSel{nodep->fileline(), fromp, bitOffsetp(rhsp, fromRange), 1};
            newp->declRange(fromRange);
            UINFO(6, "   new " << newp);
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else {  // nullptr=bad extract, or unknown node type
            nodep->v3error("Illegal bit or array select; type already selected, or bad dimension: "
                           << "data type is " << fromdata.m_errp->prettyDTypeNameQ());
            // How to recover?  We'll strip a dimension.
            nodep->replaceWith(fromp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
        if (!rhsp->backp()) VL_DO_DANGLING(pushDeletep(rhsp), rhsp);
    }
    void visit(AstSelExtract* nodep) override {
        // Select of a range specified part of an array, i.e. "array[2:3]"
        // SELEXTRACT(from,msb,lsb) -> SEL(from, lsb, 1+msb-lsb)
        // This select style has a (msb or lsb) and width
        UINFO(6, "SELEXTRACT " << nodep);
        // UINFOTREE(9, nodep, "", "SELEX0");
        // Queue bounds need ordinary folding, not constant-function evaluation
        // (IEEE 1800-2023 7.10.1).
        if (VN_IS(nodep->fromp()->dtypep()->skipRefp(), QueueDType)) {
            V3Width::widthParamsEdit(nodep->leftp());  // May relink pointed to node
            V3Width::widthParamsEdit(nodep->rightp());  // May relink pointed to node
            V3Const::constifyEdit(nodep->leftp());  // May relink pointed to node
            V3Const::constifyEdit(nodep->rightp());  // May relink pointed to node
        } else {
            V3Const::constifyParamsNoWarnEdit(nodep->leftp());  // May relink pointed to node
            V3Const::constifyParamsNoWarnEdit(nodep->rightp());  // May relink pointed to node
        }
        // UINFOTREE(9, nodep, "", "SELEX3");
        AstNodeExpr* const fromp = nodep->fromp()->unlinkFrBack();
        const FromData fromdata = fromDataForArray(nodep, fromp);
        AstNodeDType* const ddtypep = fromdata.m_dtypep;
        const VNumRange fromRange = fromdata.m_fromRange;
        if (VN_IS(ddtypep, QueueDType) || VN_IS(ddtypep, DynArrayDType)) {
            AstNodeExpr* const qleftp = nodep->leftp()->unlinkFrBack();
            AstNodeExpr* const qrightp = nodep->rightp()->unlinkFrBack();
            AstNodeExpr* const qleftBacknessp = selQueueBackness(qleftp);
            AstNodeExpr* const qrightBacknessp = selQueueBackness(qrightp);
            // Use special methods to refer to back rather than math using
            // queue size, this allows a single queue reference, to support
            // for equations in side effects that select the queue to
            // operate upon.
            const VCMethod method = (qleftBacknessp    ? VCMethod::DYN_SLICE_BACK_BACK
                                     : qrightBacknessp ? VCMethod::DYN_SLICE_FRONT_BACK
                                                       : VCMethod::DYN_SLICE);
            AstCMethodHard* const newp = new AstCMethodHard{nodep->fileline(), fromp, method};
            if (qleftBacknessp) {
                VL_DO_DANGLING(pushDeletep(qleftp), qleftp);
                newp->addPinsp(qleftBacknessp);
            } else {
                newp->addPinsp(qleftp);
            }
            if (qrightBacknessp) {
                VL_DO_DANGLING(pushDeletep(qrightp), qrightp);
                newp->addPinsp(qrightBacknessp);
            } else {
                newp->addPinsp(qrightp);
            }
            newp->dtypep(ddtypep);
            newp->didWidth(true);
            newp->protect(false);
            UINFO(6, "   new " << newp);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        const bool constantEndpoints
            = VN_IS(nodep->leftp(), Const) && VN_IS(nodep->rightp(), Const);
        // Non-queue
        checkConstantOrReplace(nodep->leftp(),
                               "First value of [a:b] isn't a constant, maybe you want +: or -:");
        checkConstantOrReplace(nodep->rightp(),
                               "Second value of [a:b] isn't a constant, maybe you want +: or -:");
        AstNodeExpr* msbp = nodep->leftp()->unlinkFrBack();
        AstNodeExpr* lsbp = nodep->rightp()->unlinkFrBack();
        AstPackArrayDType* const packedp = VN_CAST(ddtypep, PackArrayDType);
        const bool packedRange
            = packedp || VN_IS(ddtypep, BasicDType) || VN_IS(ddtypep, NodeUOrStructDType);
        const bool unknownEndpoint = constantEndpoints
                                     && (VN_AS(msbp, Const)->num().isFourState()
                                         || VN_AS(lsbp, Const)->num().isFourState());
        if (packedRange && unknownEndpoint) {
            nodep->v3error("Range select index is constantly unknown or tristated: ["
                           << VN_AS(msbp, Const)->num().displayed(nodep, "%0d") << ":"
                           << VN_AS(lsbp, Const)->num().displayed(nodep, "%0d") << "]");
        }
        if (packedRange && (!constantEndpoints || unknownEndpoint)) {
            // The endpoints were already diagnosed; leave a small select for type recovery.
            nodep->replaceWith(new AstSel{nodep->fileline(), fromp, 0,
                                          packedp ? packedp->subDTypep()->width() : 1});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (packedRange && !VN_AS(msbp, Const)->num().isOpaque()
                   && !VN_AS(lsbp, Const)->num().isOpaque()) {
            FileLine* const flp = nodep->fileline();
            AstConst* highp = VN_AS(msbp, Const);
            AstConst* lowp = VN_AS(lsbp, Const);
            if (fromRange.ascending()) std::swap(highp, lowp);
            const int boundWidth = std::max({highp->width(), lowp->width(), 32}) + 2;
            V3Number high = exactIndex(highp, boundWidth);
            V3Number low = exactIndex(lowp, boundWidth);
            if (V3Number{nodep, 1}.opGtS(low, high).isEqOne()) {
                const string highStr = high.displayed(nodep, "%0d");
                const string lowStr = low.displayed(nodep, "%0d");
                nodep->v3warn(
                    SELRANGE,
                    "[" << highStr << ":" << lowStr
                        << "] Slice range has ascending bit ordering, perhaps you wanted ["
                        << lowStr << ":" << highStr << "]");
                std::swap(high, low);
                std::swap(highp, lowp);
            }
            if (packedp) {
                UASSERT_OBJ(
                    !(!fromRange.elements() || (packedp->width() % fromRange.elements()) != 0),
                    packedp,
                    "Array extraction with width miscomputed " << packedp->width() << "/"
                                                               << fromRange.elements());
            }
            const int stride = packedp ? packedp->width() / fromRange.elements() : 1;
            V3Number span{nodep, boundWidth};
            span.opSub(high, low);
            V3Number count{nodep, boundWidth};
            count.opAdd(span, V3Number{nodep, boundWidth, 1});
            if (exceedsPackedLimit(nodep, count, stride)) {
                nodep->v3warn(
                    E_UNSUPPORTED,
                    "Unsupported: Packed range select width exceeds the supported limit.");
                nodep->replaceWith(new AstConst{flp, AstConst::BitFalseErroring{}});
            } else {
                const int elements = span.toSInt() + 1;
                const bool ascending = fromRange.ascending();
                const int bound = ascending ? fromRange.hi() : fromRange.lo();
                AstConst* const lsbSourcep = ascending ? highp : lowp;
                recordOrigin(lsbSourcep);
                // A low endpoint that is itself the bit offset is used as authored
                const bool offsetIsIndex
                    = stride == 1 && (!fromRange.ranged() || (!ascending && bound == 0));
                AstConst* const indexp
                    = offsetIsIndex
                          ? lsbSourcep
                          : packedOffsetConstp(
                                flp, exactPackedOffset(lsbSourcep, bound, ascending, stride));
                AstSel* const newp = new AstSel{flp, fromp, indexp, elements * stride};
                newp->declRange(fromRange);
                newp->declElWidth(stride);
                if (packedp) {
                    if (high.fitsInInt32(true) && low.fitsInInt32(true)) {
                        newp->dtypeFrom(sliceDType(packedp, compactInt(high), compactInt(low)));
                    } else {
                        // Only the shape is needed when the declared endpoints exceed VNumRange.
                        AstPackArrayDType* const typep = new AstPackArrayDType{
                            flp, packedp->subDTypep(),
                            new AstRange{flp, VNumRange{elements - 1, 0, ascending}}};
                        v3Global.rootp()->typeTablep()->addTypesp(typep);
                        newp->dtypep(typep);
                    }
                    UASSERT_OBJ(newp->widthMin() == newp->widthConst(), nodep, "Width mismatch");
                }
                nodep->replaceWith(newp);
            }
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, UnpackArrayDType)) {
            const int32_t msb = VN_AS(msbp, Const)->toSInt();
            const int32_t lsb = VN_AS(lsbp, Const)->toSInt();
            const int32_t elem = (msb > lsb) ? (msb - lsb + 1) : (lsb - msb + 1);
            if (fromRange.elements() == elem && fromRange.lo() == lsb) {
                nodep->replaceWith(fromp);
            } else {
                nodep->replaceWith(
                    new AstSliceSel{nodep->fileline(), fromp,
                                    VNumRange{msb - fromRange.lo(), lsb - fromRange.lo()}});
            }
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else {  // nullptr=bad extract, or unknown node type
            nodep->v3error("Illegal range select; type already selected, or bad dimension: "
                           << "data type is " << fromdata.m_errp->prettyDTypeNameQ());
            UINFO(1, "    Related ddtype: " << ddtypep);
            // How to recover?  We'll strip a dimension.
            nodep->replaceWith(fromp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
        // delete whatever we didn't use in reconstruction
        if (!fromp->backp()) VL_DO_DANGLING(pushDeletep(fromp), fromp);
        if (!msbp->backp()) VL_DO_DANGLING(pushDeletep(msbp), msbp);
        if (!lsbp->backp()) VL_DO_DANGLING(pushDeletep(lsbp), lsbp);
    }

    void replaceSelPlusMinus(AstNodePreSel* nodep) {
        // Select of a range specified with +: or -:, i.e. "array[2+:3], [2-:3]"
        // This select style has a lsb and width
        UINFO(6, "SELPLUS/MINUS " << nodep);
        // Below 2 lines may change nodep->widthp()
        UINFOTREE(9, nodep, "", "SELPM0");
        V3Width::widthParamsEdit(nodep->rhsp());  // constifyEdit doesn't ensure widths finished
        V3Const::constifyEdit(nodep->rhsp());  // May relink pointed to node, ok if not const
        V3Const::constifyParamsEdit(nodep->thsp());  // May relink pointed to node
        checkConstantOrReplace(nodep->thsp(),
                               "Width of :+ or :- bit slice range isn't a constant");
        UINFOTREE(9, nodep, "", "SELPM3");
        // Now replace it with an AstSel
        AstNodeExpr* const fromp = nodep->fromp()->unlinkFrBack();
        AstNodeExpr* const rhsp = nodep->rhsp()->unlinkFrBack();
        AstNodeExpr* const widthp = nodep->thsp()->unlinkFrBack();
        warnTri(rhsp);
        const FromData fromdata = fromDataForArray(nodep, fromp);
        const AstNodeDType* const ddtypep = fromdata.m_dtypep;
        const VNumRange fromRange = fromdata.m_fromRange;
        const bool packedSelect = VN_IS(ddtypep, BasicDType) || VN_IS(ddtypep, PackArrayDType)
                                  || (VN_IS(ddtypep, NodeUOrStructDType)
                                      && VN_AS(ddtypep, NodeUOrStructDType)->packedUnsup());
        const AstPackArrayDType* const packArrayp = VN_CAST(ddtypep, PackArrayDType);
        const int elementWidth = packArrayp ? packArrayp->width() / fromRange.elements() : 1;
        AstConst* const countp = VN_AS(widthp, Const);
        int width = 0;
        if (packedSelect && !countp->num().isOpaque() && !countp->num().isFourState()) {
            const int countBits = std::max(countp->width(), 32) + 1;
            const V3Number count = exactIndex(countp, countBits, false);
            const auto exceeds = [&](uint32_t limit) {
                return V3Number{nodep, 1}.opGt(count, V3Number{nodep, countBits, limit}).isEqOne();
            };
            const bool huge = exceeds(VL_PACKED_WIDTH_MAX);
            if (count.isNegative()) {
                nodep->v3error("Width of :+ or :- is < 0: " << widthp->prettyName());
            } else if (huge || exceedsPackedLimit(nodep, count, elementWidth)) {
                if (huge) {
                    nodep->v3error("Width of :+ or :- is huge; vector of over 2**28 bits: "
                                   << widthp->prettyName());
                } else {
                    nodep->v3warn(
                        E_UNSUPPORTED,
                        "Unsupported: Indexed packed select result exceeds the supported width.");
                }
                // Stop, as no selection of that size can be represented
                AstConst* const recoveryp
                    = new AstConst{nodep->fileline(), AstConst::BitFalseErroring{}};
                nodep->replaceWith(recoveryp);
                VL_DO_DANGLING(pushDeletep(fromp), fromp);
                VL_DO_DANGLING(pushDeletep(rhsp), rhsp);
                VL_DO_DANGLING(pushDeletep(widthp), widthp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
                return;
            } else {
                width = count.toUInt();
            }
        } else if (countp->num().isFourState()) {
            nodep->v3error(
                "Width of :+ or :- is constantly unknown or tristated: " << widthp->prettyName());
            width = 1;  // Recover
        } else {
            width = countp->toSInt();
            if (width > static_cast<int>(VL_PACKED_WIDTH_MAX)) {
                nodep->v3error("Width of :+ or :- is huge; vector of over 2**28 bits: "
                               << widthp->prettyName());
            }
            if (width < 0) {
                nodep->v3error("Width of :+ or :- is < 0: " << widthp->prettyName());
            }
        }
        if (VN_IS(ddtypep, UnpackArrayDType)) {
            // Slice +: and -: extraction
            if (fromRange.elements() == width && VN_IS(rhsp, Const)
                && VN_AS(rhsp, Const)->toSInt()
                       == fromRange.lo()) {  // Extracting whole of original array
                nodep->replaceWith(fromp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
            } else if (VN_IS(rhsp, Const)) {  // Slice
                const int32_t rhs = VN_AS(rhsp, Const)->toSInt();
                // down array: lsb/lo +: width
                // down array: msb/hi -: width
                // up array:   msb/lo +: width
                // up array:   lsb/hi -: width
                const int32_t msb
                    = (VN_IS(nodep, SelPlus) ? rhs + width - 1 : rhs) - fromRange.lo();
                const int32_t lsb
                    = (VN_IS(nodep, SelPlus) ? rhs : rhs - width + 1) - fromRange.lo();
                AstSliceSel* const newp = new AstSliceSel{
                    nodep->fileline(), fromp, VNumRange{msb, lsb, fromRange.ascending()}};
                nodep->replaceWith(newp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
            } else {  // Slice with a variable position (IEEE 1800-2023 7.4.6)
                AstNodeExpr* const lsbp
                    = newSubNeg(rhsp, (VN_IS(nodep, SelPlus) ? 0 : width - 1) + fromRange.lo());
                AstSliceSel* const newp
                    = new AstSliceSel{nodep->fileline(), fromp,
                                      VNumRange{width - 1, 0, fromRange.ascending()}, lsbp};
                nodep->replaceWith(newp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
            }
        } else if (VN_IS(ddtypep, BasicDType) || VN_IS(ddtypep, PackArrayDType)
                   || (VN_IS(ddtypep, NodeUOrStructDType)
                       && VN_AS(ddtypep, NodeUOrStructDType)->packedUnsup())) {
            int elwidth = 1;
            int newwidth = width;
            if (const AstPackArrayDType* const adtypep = VN_CAST(ddtypep, PackArrayDType)) {
                elwidth = adtypep->width() / fromRange.elements();
                newwidth = width * elwidth;
            }
            const bool ascending = fromRange.ascending();
            const bool plus = VN_IS(nodep, SelPlus);
            // Compute the origin without overflowing the declared (32-bit) bounds.
            const int64_t bound = ascending ? int64_t{fromRange.hi()} - (plus ? width - 1 : 0)
                                            : int64_t{fromRange.lo()} + (plus ? 0 : width - 1);
            // An index that is itself the bit offset is used as authored
            const bool offsetIsIndex = elwidth == 1 && !ascending && bound == 0;
            AstNodeExpr* newlsbp = offsetIsIndex || width <= 0
                                       ? nullptr
                                       : packedOffsetp(rhsp, bound, ascending, elwidth);
            if (!newlsbp) {
                newlsbp = ascending ? newSubNeg(static_cast<int32_t>(bound), rhsp)
                                    : newSubNeg(rhsp, static_cast<int32_t>(bound));
                if (elwidth != 1) newlsbp = newMulConst(nodep->fileline(), elwidth, newlsbp);
            }
            AstSel* const newp = new AstSel{nodep->fileline(), fromp, newlsbp, newwidth};
            newp->declRange(fromRange);
            newp->declElWidth(elwidth);
            UINFO(6, "   new " << newp);
            UINFOTREE(9, newp, "", "SELNEW");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, QueueDType) || VN_IS(ddtypep, DynArrayDType)) {
            // SELPLUS(from,lsb,width) -> CMETHODHARD(from, slicePlus, lsb, width), so the position
            // is evaluated once
            AstNodeExpr* lsbp = rhsp;
            if (VN_IS(nodep, SelMinus)) {
                // Subtract in 32 bits, the width of the runtime position, so a narrow position
                // may go below 0
                if (rhsp->width() < 32 && rhsp->isSigned()) {
                    lsbp = new AstExtendS{rhsp->fileline(), rhsp, 32};
                } else if (rhsp->width() < 32) {
                    lsbp = new AstExtend{rhsp->fileline(), rhsp, 32};
                }
                lsbp = newSubNeg(lsbp, width - 1);
            }
            AstCMethodHard* const newp
                = new AstCMethodHard{nodep->fileline(), fromp, VCMethod::DYN_SLICE_PLUS, lsbp};
            newp->addPinsp(widthp);
            newp->dtypep(fromdata.m_dtypep);
            newp->didWidth(true);
            newp->protect(false);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else {  // nullptr=bad extract, or unknown node type
            nodep->v3error("Illegal +: or -: select; type already selected, or bad dimension: "
                           << "data type is " << fromdata.m_errp->prettyDTypeNameQ());
            // How to recover?  We'll strip a dimension.
            nodep->replaceWith(fromp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
        // delete whatever we didn't use in reconstruction
        if (!fromp->backp()) VL_DO_DANGLING(pushDeletep(fromp), fromp);
        if (!rhsp->backp()) VL_DO_DANGLING(pushDeletep(rhsp), rhsp);
        if (!widthp->backp()) VL_DO_DANGLING(pushDeletep(widthp), widthp);
    }
    void visit(AstSelPlus* nodep) override { replaceSelPlusMinus(nodep); }
    void visit(AstSelMinus* nodep) override { replaceSelPlusMinus(nodep); }
    // If adding new visitors, ensure V3Width's visit(TYPE) calls into here

    //--------------------
    // Default
    void visit(AstNode* nodep) override {  // LCOV_EXCL_LINE
        // See notes above; we never iterate
        nodep->v3fatalSrc("Shouldn't iterate in V3WidthSel");
    }

public:
    // CONSTRUCTORS
    explicit WidthSelVisitor(V3Width::SelOrigin* originp)
        : m_originp{originp} {}
    ~WidthSelVisitor() override = default;
    AstNode* mainAcceptEdit(AstNode* nodep) { return iterateSubtreeReturnEdits(nodep); }
};

//######################################################################
// Width class functions

AstNode* V3Width::widthSelNoIterEdit(AstNode* nodep, SelOrigin* originp) {
    UINFO(4, __FUNCTION__ << ": " << nodep);
    WidthSelVisitor visitor{originp};
    nodep = visitor.mainAcceptEdit(nodep);
    return nodep;
}

#undef iterateChildren
