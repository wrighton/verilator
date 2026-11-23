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

    // Return self-determined index 'indexp' as a value of 'toWidth' bits, extended as it is read
    // signed. The extension, or cast, is a boundary that keeps the index's own arithmetic at its
    // width and signedness, which the width pass would otherwise take from around it.
    static AstNodeExpr* newWidenedIndex(AstNodeExpr* indexp, int toWidth) {
        const bool isSigned = indexSigned(indexp);
        // Only operators take their width and signedness from around them
        if (indexp->width() == toWidth && isSigned == indexp->isSigned()
            && !VN_IS(indexp, NodeUniop) && !VN_IS(indexp, NodeBiop)
            && !VN_IS(indexp, NodeTriop)) {
            return indexp;
        }
        AstNodeExpr* extendp;
        if (indexp->width() == toWidth) {
            // A cast to the signedness, as an extension must widen
            if (isSigned) {
                extendp = new AstSigned{indexp->fileline(), indexp};
            } else {
                extendp = new AstUnsigned{indexp->fileline(), indexp};
            }
        } else if (isSigned) {
            extendp = new AstExtendS{indexp->fileline(), indexp, toWidth};
        } else {
            extendp = new AstExtend{indexp->fileline(), indexp, toWidth};
        }
        extendp->dtypeSetLogicSized(toWidth, VSigning::fromBool(isSigned));
        return extendp;
    }
    // Whether index 'indexp' is read as signed. An index of up to 32 bits is an integer, so a
    // 32-bit unsigned index with its top bit set is negative, as other simulators take it.
    static bool indexSigned(const AstNodeExpr* indexp) {
        return indexp->isSigned() || indexp->width() == VL_IDATASIZE;
    }

    // Return the bit position of 'indexp' in a packed select of 'width' bits: 'addend' minus
    // 'indexp' if 'negate', else 'indexp' plus 'addend', times 'scale'. A non-constant position
    // is signed like its index, and computed in 64 or more bits if 32-bit arithmetic could wrap
    // it into the selected value, so that V3Unknown's bounds check sees where it selects.
    AstNodeExpr* newPosition(AstNodeExpr* indexp, bool negate, int64_t addend, uint32_t scale,
                             int width) {
        FileLine* const flp = indexp->fileline();
        if (const AstConst* const constp = VN_CAST(indexp, Const)) {
            // The caller deletes the unused index
            if (!constp->num().isFourState()) {
                return newConstPosition(constp, negate, addend, scale);
            }
        }
        // The 32-bit arithmetic below needs the addend and its negation as integers
        const bool addendFits = addend > std::numeric_limits<int32_t>::min()
                                && addend <= std::numeric_limits<int32_t>::max();
        if (VN_IS(indexp, Const)
            || (!indexSigned(indexp) && addendFits
                && !positionMayWrap(indexp, negate, addend, scale, width))) {
            AstNodeExpr* const widenedp = newWidenedIndex(indexp, indexp->width());
            AstNodeExpr* posp = negate ? newSubNeg(static_cast<int32_t>(addend), widenedp)
                                       : newSubNeg(widenedp, static_cast<int32_t>(-addend));
            if (scale != 1) posp = newMulConst(flp, scale, posp);
            return posp;
        }
        const bool isSigned = indexSigned(indexp);
        if (!negate && addend == 0 && scale == 1 && isSigned == indexp->isSigned()) {
            // A narrower signed index is an integer, so a negative one stays out of range
            if (isSigned && indexp->width() < VL_IDATASIZE) {
                return newWidenedIndex(indexp, VL_IDATASIZE);
            }
            return indexp;
        }
        const bool wide = positionMayWrap(indexp, negate, addend, scale, width);
        const int posWidth = wide ? std::max(VL_QUADSIZE, std::max(indexp->width(), 33) + 2
                                                              + V3Number::log2b(scale) + 1)
                                  : 32;
        // Unsized, so the arithmetic widens to it without warning, as with an integer
        const auto newConst = [flp, posWidth, isSigned](int64_t value) {
            V3Number quad{flp, VL_QUADSIZE, 0};
            quad.setQuad(static_cast<uint64_t>(value));
            quad.isSigned(true);
            V3Number num{flp, posWidth, 0};
            num.opExtendS(quad, VL_QUADSIZE);
            num.isSigned(isSigned);
            num.width(posWidth, false);
            return new AstConst{flp, num};
        };
        AstNodeExpr* posp = newWidenedIndex(indexp, posWidth);
        if (negate) {
            posp = new AstSub{flp, newConst(addend), posp};
        } else if (addend > 0) {
            posp = new AstAdd{flp, posp, newConst(addend)};
        } else if (addend < 0) {
            posp = new AstSub{flp, posp, newConst(-addend)};
        }
        if (scale != 1) {
            posp = new AstMul{flp, newConst(scale), posp};
            posp->dtypeSetLogicSized(posWidth, VSigning::fromBool(isSigned));
        }
        return posp;
    }
    // Return the position of constant index 'constp', as newPosition describes, computed exactly.
    // A non-negative position under 2^31 of an element is scaled after; an unsigned position
    // keeps the index's width if it fits there and that is at most 32 bits, else takes 32 bits;
    // a negative integer one is in 32 bits. One far above any value, or below the integers, is
    // given as is, wider than an integer, all out of range.
    AstNodeExpr* newConstPosition(const AstConst* constp, bool negate, int64_t addend,
                                  uint32_t scale) {
        FileLine* const flp = constp->fileline();
        const int indexWidth = constp->width();
        // Wide enough for any such position
        const int posWidth
            = std::max(indexWidth, VL_IDATASIZE + 1) + 2 + V3Number::log2b(scale) + 1;
        const auto newNum = [flp, posWidth](int64_t value) {
            V3Number quad{flp, VL_QUADSIZE, 0};
            quad.setQuad(static_cast<uint64_t>(value));
            V3Number num{flp, posWidth, 0};
            num.opExtendS(quad, VL_QUADSIZE);
            return num;
        };
        V3Number index{flp, posWidth, 0};
        if (indexSigned(constp)) {
            index.opExtendS(constp->num(), indexWidth);
        } else {
            index.opAssign(constp->num());
        }
        V3Number offset{flp, posWidth, 0};
        if (negate) {
            offset.opSub(newNum(addend), index);
        } else {
            offset.opAdd(index, newNum(addend));
        }
        V3Number pos{flp, posWidth, 0};
        pos.opMul(offset, newNum(scale));
        pos.isSigned(true);
        const uint32_t posBits = pos.isNegative() ? 0 : pos.mostSetBitP1();
        // V3Width reports a position far above any value, or below the integers, as it is, then
        // reads it as an integer out of range
        V3Number farAbove{flp, 1, 0};
        farAbove.opGteS(pos, newNum(AstSel::FAR_POSITION));
        V3Number belowInt{flp, 1, 0};
        belowInt.opLtS(pos, newNum(std::numeric_limits<int32_t>::min()));
        if (farAbove.isNeqZero() || belowInt.isNeqZero()) return new AstConst{flp, pos};
        if (scale != 1 && !pos.isNegative() && posBits < static_cast<uint32_t>(VL_IDATASIZE)) {
            // An element in or above range, scaled without wrapping, as V3Const reports it
            return newMulConst(flp, scale,
                               new AstConst{flp, AstConst::WidthedValue{}, VL_IDATASIZE,
                                            static_cast<uint32_t>(offset.toUQuad())});
        }
        if (!pos.isNegative() && posBits <= static_cast<uint32_t>(indexWidth)
            && indexWidth <= VL_IDATASIZE) {
            V3Number num{flp, indexWidth, 0};
            num.opAssign(pos);
            return new AstConst{flp, num};
        }
        if (!pos.isNegative() && posBits <= VL_IDATASIZE) {
            return new AstConst{flp, AstConst::WidthedValue{}, VL_IDATASIZE,
                                static_cast<uint32_t>(pos.toUQuad())};
        }
        // A negative integer, as later passes read a constant position
        UASSERT_OBJ(pos.isNegative(), constp, "Constant position not handled above");
        V3Number num{flp, VL_IDATASIZE, 0};
        num.opAssign(pos);
        num.isSigned(true);
        return new AstConst{flp, num};
    }
    // Whether a position as newPosition describes may wrap, in 32 bits, from out of range into
    // a value of 'width' bits
    static bool positionMayWrap(const AstNodeExpr* indexp, bool negate, int64_t addend,
                                uint32_t scale, int width) {
        static constexpr int64_t WRAP = 1LL << 32;
        // Wider operands, or a large scale, are not worth the bound
        if (indexp->width() > 32 || scale > (1U << 20)) return true;
        const int64_t indexMin = indexSigned(indexp) ? -(1LL << (indexp->width() - 1)) : 0;
        const int64_t indexMax = indexSigned(indexp) ? (1LL << (indexp->width() - 1)) - 1
                                                     : (1LL << indexp->width()) - 1;
        const int64_t lo = (negate ? addend - indexMax : indexMin + addend) * scale;
        const int64_t hi = (negate ? addend - indexMin : indexMax + addend) * scale;
        return hi >= WRAP || lo <= -WRAP + width;
    }

    // Return the bit position of element 'indexp' of 'scale' bits in a packed range 'fromRange'
    // of 'width' bits. An index of up to 32 bits whose position could wrap, or is signed, takes
    // its offset from the low end of the range modulo its width, unsigned, if it can hold every
    // index in range: this maps the indices it can hold one to one onto offsets, and those in
    // range onto the offsets in range, so only the scaling needs checking.
    AstNodeExpr* newElementPosition(AstNodeExpr* indexp, const VNumRange& fromRange,
                                    uint32_t scale, int width) {
        const bool negate = fromRange.ascending();
        // Widened before negating, as the bound may be the most negative integer
        const int64_t addend = negate ? int64_t{fromRange.hi()} : -int64_t{fromRange.lo()};
        const int indexWidth = indexp->width();
        if (VN_IS(indexp, Const) || indexWidth > VL_IDATASIZE
            || (!indexSigned(indexp) && !positionMayWrap(indexp, negate, addend, scale, width))) {
            return newPosition(indexp, negate, addend, scale, width);
        }
        const int64_t indexMin = indexSigned(indexp) ? -(1LL << (indexWidth - 1)) : 0;
        const int64_t indexMax
            = indexSigned(indexp) ? (1LL << (indexWidth - 1)) - 1 : (1LL << indexWidth) - 1;
        // Scaling may wrap, unless the offset is first checked in range, which needs it twice
        const bool mayWrap = scale != 1 && indexWidth + V3Number::log2b(scale) + 1 > VL_IDATASIZE;
        // The index must be able to hold every index in range
        if (fromRange.lo() < indexMin || fromRange.hi() > indexMax
            || (mayWrap && !indexp->isRepeatable())) {
            return newPosition(indexp, negate, addend, scale, width);
        }
        // The end of the range the offset counts from
        const int64_t base = negate ? fromRange.hi() : fromRange.lo();
        FileLine* const flp = indexp->fileline();
        const auto newConst = [flp](int constWidth, uint64_t value) {
            V3Number num{flp, constWidth, 0};
            num.setQuad(value);
            return new AstConst{flp, num};
        };
        // The arithmetic and comparisons below are unsigned whatever the index's signedness
        AstNodeExpr* offsetp = newWidenedIndex(indexp, indexWidth);
        if (negate || base != 0) {
            offsetp = negate ? new AstSub{flp, newConst(indexWidth, static_cast<uint64_t>(base)),
                                          offsetp}
                             : new AstSub{flp, offsetp,
                                          newConst(indexWidth, static_cast<uint64_t>(base))};
            offsetp->dtypeSetLogicSized(indexWidth, VSigning::UNSIGNED);
        }
        AstNodeExpr* posp = mayWrap ? offsetp->cloneTreePure(false) : offsetp;
        if (indexWidth < VL_IDATASIZE) {
            posp = new AstExtend{flp, posp, VL_IDATASIZE};
            posp->dtypeSetLogicSized(VL_IDATASIZE, VSigning::UNSIGNED);
        }
        if (scale != 1) {
            posp = new AstMul{flp, newConst(VL_IDATASIZE, scale), posp};
            posp->dtypeSetLogicSized(VL_IDATASIZE, VSigning::UNSIGNED);
        }
        if (mayWrap) {
            // Scaled only if in range, so the scaling does not wrap; else the end of the value,
            // which stays out of range with a position within the element added, as a select
            // of the element composes
            AstNodeExpr* const inRangep = new AstGte{
                flp, newConst(indexWidth, static_cast<uint64_t>(fromRange.elements() - 1)),
                offsetp};
            inRangep->dtypeSetBit();
            posp = new AstCond{flp, inRangep, posp,
                               newConst(VL_IDATASIZE, static_cast<uint64_t>(width))};
            posp->dtypeSetLogicSized(VL_IDATASIZE, VSigning::UNSIGNED);
        }
        return posp;
    }
    // Return the bit position of bit 'indexp' of a vector with range 'fromRange'
    AstNodeExpr* newBitPosition(AstNodeExpr* indexp, const VNumRange& fromRange, int width) {
        if (!fromRange.ranged()) return indexp;
        return newElementPosition(indexp, fromRange, 1, width);
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

    // Report a selection index that is a constant with X or Z bits, and replace it with zero
    AstNodeExpr* checkTri(AstNodeExpr* nodep) {
        const AstConst* const constp = VN_CAST(nodep, Const);
        if (!constp || !constp->num().isFourState()) return nodep;
        nodep->v3error("Selection index is constantly unknown or tristated: " << nodep->name());
        AstNodeExpr* const newp
            = new AstConst{nodep->fileline(), AstConst::WidthedValue{}, nodep->width(), 0};
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        return newp;
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
            AstSel* const newp = new AstSel{
                nodep->fileline(), fromp,
                newElementPosition(rhsp, fromRange, elwidth, adtypep->width()), elwidth};
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
            AstSel* const newp = new AstSel{nodep->fileline(), fromp,
                                            newBitPosition(rhsp, fromRange, fromp->width()), 1};
            newp->declRange(fromRange);
            UINFO(6, "   new " << newp);
            UINFOTREE(9, newp, "", "SELBTn");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, NodeUOrStructDType)) {  // A bit from the packed struct
            // SELBIT(range, index) -> SEL(array, index, 1)
            AstSel* const newp = new AstSel{nodep->fileline(), fromp,
                                            newBitPosition(rhsp, fromRange, fromp->width()), 1};
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
        // Non-queue
        checkConstantOrReplace(nodep->leftp(),
                               "First value of [a:b] isn't a constant, maybe you want +: or -:");
        checkConstantOrReplace(nodep->rightp(),
                               "Second value of [a:b] isn't a constant, maybe you want +: or -:");
        AstNodeExpr* msbp = nodep->leftp()->unlinkFrBack();
        AstNodeExpr* lsbp = nodep->rightp()->unlinkFrBack();
        int32_t msb = VN_AS(msbp, Const)->toSInt();
        int32_t lsb = VN_AS(lsbp, Const)->toSInt();
        const int32_t elem = (msb > lsb) ? (msb - lsb + 1) : (lsb - msb + 1);
        if (VN_IS(ddtypep, UnpackArrayDType)) {
            // Slice extraction
            if (fromRange.elements() == elem
                && fromRange.lo() == lsb) {  // Extracting whole of original array
                nodep->replaceWith(fromp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
            } else {  // Slice
                AstSliceSel* const newp
                    = new AstSliceSel{nodep->fileline(), fromp,
                                      VNumRange{msb - fromRange.lo(), lsb - fromRange.lo()}};
                nodep->replaceWith(newp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
            }
        } else if (AstPackArrayDType* const adtypep = VN_CAST(ddtypep, PackArrayDType)) {
            // SELEXTRACT(array, msb, lsb) -> SEL(array,
            //             lsb*width-of-subindex, width-of-subindex*(msb-lsb))
            UASSERT_OBJ(!(!fromRange.elements() || (adtypep->width() % fromRange.elements()) != 0),
                        adtypep,
                        "Array extraction with width miscomputed " << adtypep->width() << "/"
                                                                   << fromRange.elements());
            // Below code assumes descending bit range; just works out if we swap
            if (fromRange.ascending()) std::swap(msb, lsb);
            if (lsb > msb) {
                nodep->v3warn(
                    SELRANGE,
                    "[" << msb << ":" << lsb
                        << "] Slice range has ascending bit ordering, perhaps you wanted [" << lsb
                        << ":" << msb << "]");
                std::swap(msb, lsb);
                std::swap(msbp, lsbp);  // Select starts at the new lsb
            }
            const int elwidth = adtypep->width() / fromRange.elements();
            AstSel* const newp
                = new AstSel{nodep->fileline(), fromp,
                             newPosition(lsbp, fromRange.ascending(),
                                         fromRange.ascending() ? int64_t{fromRange.hi()}
                                                               : -int64_t{fromRange.lo()},
                                         elwidth, adtypep->width()),
                             (msb - lsb + 1) * elwidth};
            newp->declRange(fromRange);
            newp->declElWidth(elwidth);
            newp->dtypeFrom(sliceDType(adtypep, msb, lsb));
            // UINFOTREE(9, newp, "", "EXTBTn");
            UASSERT_OBJ(newp->widthMin() == newp->widthConst(), nodep, "Width mismatch");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, BasicDType)) {
            // Below code assumes descending bit range; just works out if we swap
            if (fromRange.ascending()) std::swap(msb, lsb);
            if (lsb > msb) {
                nodep->v3warn(
                    SELRANGE,
                    "[" << msb << ":" << lsb
                        << "] Slice range has ascending bit ordering, perhaps you wanted [" << lsb
                        << ":" << msb << "]");
                std::swap(msb, lsb);
                std::swap(msbp, lsbp);  // Select starts at the new lsb
            }
            AstSel* const newp
                = new AstSel{nodep->fileline(), fromp,
                             newBitPosition(lsbp, fromRange, fromp->width()), msb + 1 - lsb};
            newp->declRange(fromRange);
            UINFO(6, "   new " << newp);
            // UINFOTREE(9, newp, "", "SELEXnew");
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else if (VN_IS(ddtypep, NodeUOrStructDType)) {
            // Classes don't have an ascending range
            if (lsb > msb) {
                nodep->v3warn(
                    SELRANGE,
                    "[" << msb << ":" << lsb
                        << "] Slice range has ascending bit ordering, perhaps you wanted [" << lsb
                        << ":" << msb << "]");
                std::swap(msb, lsb);
                std::swap(msbp, lsbp);  // Select starts at the new lsb
            }
            AstSel* const newp = new AstSel{nodep->fileline(), fromp, newSubLsbOf(lsbp, fromRange),
                                            msb + 1 - lsb};
            newp->declRange(fromRange);
            UINFO(6, "   new " << newp);
            // UINFOTREE(9, newp, "", "SELEXnew");
            nodep->replaceWith(newp);
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
        AstNodeExpr* const rhsp = checkTri(nodep->rhsp()->unlinkFrBack());
        AstNodeExpr* const widthp = nodep->thsp()->unlinkFrBack();
        const int width = VN_AS(widthp, Const)->toSInt();
        if (width > (1 << 28)) {
            nodep->v3error("Width of :+ or :- is huge; vector of over 1 billion bits: "
                           << widthp->prettyName());
        }
        if (width < 0) nodep->v3error("Width of :+ or :- is < 0: " << widthp->prettyName());
        const FromData fromdata = fromDataForArray(nodep, fromp);
        const AstNodeDType* const ddtypep = fromdata.m_dtypep;
        const VNumRange fromRange = fromdata.m_fromRange;
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
            int64_t addend = 0;
            if (VN_IS(nodep, SelPlus)) {
                // SELPLUS(from,lsb,width) -> SEL(from, (vector_msb-width+1)-sel, width) or
                // SEL(from, lsb-vector_lsb, width)
                addend
                    = ascending ? int64_t{fromRange.hi()} - width + 1 : -int64_t{fromRange.lo()};
            } else if (VN_IS(nodep, SelMinus)) {
                // SELMINUS(from,msb,width) -> SEL(from, msb-[bit]) or
                // SEL(from, msb-(width-1)-lsb#)
                addend = ascending ? int64_t{fromRange.hi()}
                                   : -(int64_t{fromRange.lo()} + (width - 1));
            } else {
                nodep->v3fatalSrc("Bad Case");
            }
            AstNodeExpr* const newlsbp
                = newPosition(rhsp, ascending, addend, elwidth, ddtypep->width());
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
    WidthSelVisitor() = default;
    ~WidthSelVisitor() override = default;
    AstNode* mainAcceptEdit(AstNode* nodep) { return iterateSubtreeReturnEdits(nodep); }
};

//######################################################################
// Width class functions

AstNode* V3Width::widthSelNoIterEdit(AstNode* nodep) {
    UINFO(4, __FUNCTION__ << ": " << nodep);
    WidthSelVisitor visitor;
    nodep = visitor.mainAcceptEdit(nodep);
    return nodep;
}

#undef iterateChildren
