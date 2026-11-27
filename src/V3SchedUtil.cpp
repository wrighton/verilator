// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Utility functions used by code scheduling
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
//
//
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3EmitCBase.h"
#include "V3EmitV.h"
#include "V3Order.h"
#include "V3Sched.h"
#include "V3SenExprBuilder.h"
#include "V3SenTree.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {
namespace util {

AstCFunc* makeSubFunction(AstNetlist* netlistp, const string& name, bool slow) {
    AstScope* const scopeTopp = netlistp->topScopep()->scopep();
    AstCFunc* const funcp = new AstCFunc{netlistp->fileline(), name, scopeTopp, ""};
    funcp->dontCombine(true);
    funcp->isStatic(false);
    funcp->isLoose(true);
    funcp->slow(slow);
    funcp->isConst(false);
    funcp->declPrivate(true);
    scopeTopp->addBlocksp(funcp);
    return funcp;
}

AstVarScope* newArgument(AstCFunc* funcp, AstNodeDType* dtypep, const string& name,
                         VDirection direction) {
    FileLine* const flp = funcp->fileline();
    AstScope* const scopep = funcp->scopep();
    AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP, name, dtypep};
    varp->funcLocal(true);
    varp->direction(direction);
    funcp->addArgsp(varp);
    AstVarScope* const vscp = new AstVarScope{flp, scopep, varp};
    scopep->addVarsp(vscp);
    return vscp;
}

AstNodeStmt* setVar(AstVarScope* vscp, uint32_t val) {
    FileLine* const flp = vscp->fileline();
    AstVarRef* const refp = new AstVarRef{flp, vscp, VAccess::WRITE};
    AstConst* const valp = new AstConst{flp, AstConst::DTyped{}, vscp->dtypep()};
    valp->num().setLong(val);
    return new AstAssign{flp, refp, valp};
}

AstNodeStmt* incrementVar(AstVarScope* vscp) {
    FileLine* const flp = vscp->fileline();
    AstVarRef* const wrefp = new AstVarRef{flp, vscp, VAccess::WRITE};
    AstVarRef* const rrefp = new AstVarRef{flp, vscp, VAccess::READ};
    AstConst* const onep = new AstConst{flp, AstConst::DTyped{}, vscp->dtypep()};
    onep->num().setLong(1);
    return new AstAssign{flp, wrefp, new AstAdd{flp, rrefp, onep}};
}

AstNodeStmt* callVoidFunc(AstCFunc* funcp) {
    if (!funcp) return nullptr;
    AstCCall* const callp = new AstCCall{funcp->fileline(), funcp};
    callp->dtypeSetVoid();
    return callp->makeStmt();
}

static AstCFunc* splitCheckCreateNewSubFunc(AstCFunc* ofuncp) {
    static std::map<AstCFunc*, uint32_t> s_funcNums;  // What split number to attach to a function
    const uint32_t funcNum = s_funcNums[ofuncp]++;
    const std::string name = ofuncp->name() + "__" + cvtToStr(funcNum);
    AstScope* const scopep = ofuncp->scopep();
    AstCFunc* const subFuncp = new AstCFunc{ofuncp->fileline(), name, scopep};
    scopep->addBlocksp(subFuncp);
    subFuncp->dontCombine(true);
    subFuncp->isStatic(ofuncp->isStatic());
    subFuncp->isLoose(true);
    subFuncp->slow(ofuncp->slow());
    subFuncp->ifdef(ofuncp->ifdef());
    subFuncp->declPrivate(ofuncp->declPrivate());
    if (ofuncp->needsVlProcess()) subFuncp->setNeedsVlProcess();
    for (AstVar* const argp : ofuncp->argspList()) {
        AstVar* const clonep = argp->cloneTree(false);
        subFuncp->addArgsp(clonep);
        AstVarScope* const vscp = new AstVarScope{clonep->fileline(), scopep, clonep};
        scopep->addVarsp(vscp);
        argp->user3p(vscp);
    }
    return subFuncp;
};

void splitCheckFinishSubFunc(AstCFunc* ofuncp, AstCFunc* subFuncp,
                             const std::unordered_map<const AstVar*, AstVarScope*>& argVscps) {
    FileLine* const flp = subFuncp->fileline();
    AstCCall* const callp = new AstCCall{subFuncp->fileline(), subFuncp};
    callp->dtypeSetVoid();
    // Pass arguments through to subfunction
    for (AstVar* const argp : ofuncp->argspList()) {
        UASSERT_OBJ(argp->direction() == VDirection::CONSTREF, argp, "Unexpected direction");
        callp->addArgsp(new AstVarRef{flp, argVscps.at(argp), VAccess::READ});
    }

    bool containsAwait = false;
    subFuncp->foreach([&](AstNode* nodep) {
        // Record if it has a CAwait
        if (VN_IS(nodep, CAwait)) containsAwait = true;
        // Redirect references to arguments to the clone in the sub-function
        if (AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
            if (AstVarScope* const vscp = VN_AS(refp->varp()->user3p(), VarScope)) {
                refp->varp(vscp->varp());
                refp->varScopep(vscp);
            }
        }
    });

    if (ofuncp->isCoroutine() && containsAwait) {  // Wrap call with co_await
        subFuncp->rtnType("VlCoroutine");
        ofuncp->addStmtsp(new AstCAwait{flp, callp});
    } else {
        ofuncp->addStmtsp(callp->makeStmt());
    }
}

// Compute, for each top level statement of 'ofuncp', whether a new sub-function may begin there.
// Sub-functions are emitted as separate C++ functions, so they cannot see each other's automatic
// storage. A function-local AstVar declared among the top level statements must therefore end up
// in the same sub-function as every reference to it, otherwise the emitted C++ refers to an
// undeclared identifier (and the AstVar can be deleted from under the still-live references).
static std::vector<bool> splitCheckBreakable(const AstCFunc* ofuncp) {
    // Gather the top level statements, and where each locally declared variable is declared
    std::vector<const AstNode*> stmtps;
    std::unordered_map<const AstVar*, size_t> declIdx;  // Local var -> index it is declared at
    for (const AstNode* const nodep : ofuncp->stmtspList()) {
        if (const AstVar* const varp = VN_CAST(nodep, Var)) declIdx.emplace(varp, stmtps.size());
        stmtps.push_back(nodep);
    }

    // Find the last statement referencing each locally declared variable
    std::vector<size_t> lastUse(stmtps.size());
    for (size_t i = 0; i < stmtps.size(); ++i) {
        lastUse[i] = i;  // A declaration is live at least where it is declared
        stmtps[i]->foreach([&](const AstNodeVarRef* refp) {
            const auto it = declIdx.find(refp->varp());  // 'end()' if not one of our locals
            if (it != declIdx.end()) lastUse[it->second] = std::max(lastUse[it->second], i);
        });
    }

    // A break before statement 'i' is allowed only if no local declared before 'i' is still live
    std::vector<bool> breakable(stmtps.size(), true);
    size_t liveEnd = 0;  // Last index any so far declared local is referenced at
    for (size_t i = 0; i < stmtps.size(); ++i) {
        breakable[i] = liveEnd < i;
        if (VN_IS(stmtps[i], Var)) liveEnd = std::max(liveEnd, lastUse[i]);
    }
    return breakable;
}

// Split large function according to --output-split-cfuncs
void splitCheck(AstCFunc* const ofuncp) {
    if (!ofuncp) return;
    UASSERT_OBJ(!ofuncp->varsp(), ofuncp, "Can't split function with local variables");
    if (!v3Global.opt.outputSplitCFuncs() || !ofuncp->stmtsp()) return;
    if (ofuncp->nodeCount() < v3Global.opt.outputSplitCFuncs()) return;

    // Statement boundaries that would separate a local declaration from a reference to it
    const std::vector<bool> breakable = splitCheckBreakable(ofuncp);

    // Need to find the AstVarScopes for the function arguments. They should be in the same Scope.
    std::unordered_map<const AstVar*, AstVarScope*> argVscps;
    for (AstVar* const argp : ofuncp->argspList()) {
        UASSERT_OBJ(argVscps.size() < 2, argp, "There should be at most 2 arguments, or O(n^2)");
        bool found = false;
        for (AstVarScope* const vscp : ofuncp->scopep()->varspList()) {
            if (vscp->varp() != argp) continue;
            argVscps[argp] = vscp;
            found = true;
            break;
        }
        UASSERT_OBJ(found, argp, "Can't find VarScope for function argument");
    }

    // AstVar::user3p(): AstVarScope for function argument in clone
    const VNUser3InUse user3InUse;

    size_t size = 0;
    AstCFunc* subFuncp = nullptr;

    // Move statements one by one to the new sub-functions
    AstNodeStmt* stmtsp = ofuncp->stmtsp()->unlinkFrBackWithNext();
    for (size_t index = 0; AstNodeStmt* const itemp = stmtsp; ++index) {
        stmtsp = VN_AS(stmtsp->nextp(), NodeStmt);
        if (stmtsp) stmtsp->unlinkFrBackWithNext();
        const size_t itemSize = static_cast<size_t>(itemp->nodeCount());
        size += itemSize;

        if (size > static_cast<size_t>(v3Global.opt.outputSplitCFuncs()) && breakable[index]) {
            if (subFuncp) splitCheckFinishSubFunc(ofuncp, subFuncp, argVscps);
            subFuncp = nullptr;
            size = itemSize;
        }

        if (!subFuncp) subFuncp = splitCheckCreateNewSubFunc(ofuncp);
        subFuncp->addStmtsp(itemp);
    }
    if (subFuncp) splitCheckFinishSubFunc(ofuncp, subFuncp, argVscps);
}

namespace {

// The largest value an expression of a select position can have, or -1 if not known to be small
int64_t maxPositionOf(const AstNodeExpr* nodep) {
    constexpr int64_t LIMIT = std::numeric_limits<int32_t>::max();
    if (const AstConst* const constp = VN_CAST(nodep, Const)) {
        if (constp->isWide() || constp->num().isFourState()) return -1;
        const uint64_t value = constp->toUQuad();
        return value <= static_cast<uint64_t>(LIMIT) ? static_cast<int64_t>(value) : -1;
    }
    if (const AstExtend* const extendp = VN_CAST(nodep, Extend)) {
        return maxPositionOf(extendp->lhsp());
    }
    if (const AstAdd* const addp = VN_CAST(nodep, Add)) {
        const int64_t lhs = maxPositionOf(addp->lhsp());
        const int64_t rhs = maxPositionOf(addp->rhsp());
        if (lhs < 0 || rhs < 0 || lhs + rhs > LIMIT) return -1;
        // The sum must not wrap around in the width of the addition
        if (nodep->width() < 31 && lhs + rhs >= (int64_t{1} << nodep->width())) return -1;
        return lhs + rhs;
    }
    if (nodep->width() < 31) return (int64_t{1} << nodep->width()) - 1;
    return -1;
}

// The smallest value an expression of a select position can have, with a known largest value
int64_t minPositionOf(const AstNodeExpr* nodep) {
    if (const AstConst* const constp = VN_CAST(nodep, Const)) return maxPositionOf(constp);
    if (const AstExtend* const extendp = VN_CAST(nodep, Extend)) {
        return minPositionOf(extendp->lhsp());
    }
    if (const AstAdd* const addp = VN_CAST(nodep, Add)) {
        return minPositionOf(addp->lhsp()) + minPositionOf(addp->rhsp());
    }
    return 0;
}

// The number of bits of a value of the data type, with those of the elements of an unpacked
// array in order, or 0 if it is of another, unpacked type
int flatWidthOf(const AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefp();
    if (const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType)) {
        const int64_t width = int64_t{flatWidthOf(arrayp->subDTypep())} * arrayp->elementsConst();
        return width <= std::numeric_limits<int32_t>::max() ? static_cast<int>(width) : 0;
    }
    return dtypep->isIntegralOrPacked() ? dtypep->width() : 0;
}

// Call 'f' on each part of bits [lo, hi) of a value of the data type (see flatWidthOf), with
// the indices of the elements of unpacked arrays holding it, and its data type and bits: a
// whole value, or bits of a packed value
void foreachBitsPart(
    const AstNodeDType* dtypep, int lo, int hi, std::vector<int>& indices,
    const std::function<void(const std::vector<int>&, const AstNodeDType*, int, int)>& f) {
    dtypep = dtypep->skipRefp();
    const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType);
    const int elemWidth = arrayp ? flatWidthOf(arrayp->subDTypep()) : 0;
    if (elemWidth && (lo != 0 || hi != flatWidthOf(dtypep))) {
        for (int index = lo / elemWidth; index * elemWidth < hi; ++index) {
            const int elemLo = index * elemWidth;
            indices.push_back(index);
            foreachBitsPart(arrayp->subDTypep(), std::max(lo, elemLo) - elemLo,
                            std::min(hi, elemLo + elemWidth) - elemLo, indices, f);
            indices.pop_back();
        }
        return;
    }
    f(indices, dtypep, lo, hi);
}

// The number of parts foreachBitsPart calls its function on, counted up to just over 'limit'
size_t countBitsParts(const AstNodeDType* dtypep, int lo, int hi, size_t limit) {
    dtypep = dtypep->skipRefp();
    const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType);
    const int elemWidth = arrayp ? flatWidthOf(arrayp->subDTypep()) : 0;
    if (!elemWidth || (lo == 0 && hi == flatWidthOf(dtypep))) return 1;
    size_t count = 0;
    for (int index = lo / elemWidth; index * elemWidth < hi && count <= limit; ++index) {
        const int elemLo = index * elemWidth;
        count += countBitsParts(arrayp->subDTypep(), std::max(lo, elemLo) - elemLo,
                                std::min(hi, elemLo + elemWidth) - elemLo, limit - count);
    }
    return count;
}

}  // namespace

BitRange accessedBits(const AstVarRef* refp, bool* exactp) {
    if (exactp) *exactp = true;
    const AstNodeDType* dtypep = refp->varScopep()->dtypep()->skipRefp();
    const int width = flatWidthOf(dtypep);
    if (!width) return {0, 1};  // As a whole
    int64_t lo = 0;
    int64_t hi = width;
    const AstNode* fromp = refp;
    // Elements of unpacked arrays: each index selects an element of 'elemWidth' bits
    while (const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType)) {
        const AstArraySel* const aselp = VN_CAST(fromp->backp(), ArraySel);
        if (!aselp || aselp->fromp() != fromp) {
            // A slice selects some of the elements
            if (exactp && VN_IS(fromp->backp(), SliceSel)) *exactp = false;
            return {lo, hi};
        }
        if (exactp) *exactp = false;
        const int64_t maxIndex = maxPositionOf(aselp->bitp());
        const int64_t minIndex = minPositionOf(aselp->bitp());
        const int64_t elemWidth = flatWidthOf(arrayp->subDTypep());
        if (maxIndex < 0 || minIndex >= arrayp->elementsConst()) return {lo, hi};
        hi = lo + std::min<int64_t>(maxIndex + 1, arrayp->elementsConst()) * elemWidth;
        lo += minIndex * elemWidth;
        if (minIndex != maxIndex) return {lo, hi};
        if (exactp) *exactp = true;
        dtypep = arrayp->subDTypep()->skipRefp();
        fromp = aselp;
    }
    // Zero extensions of the value keep the positions of its bits
    while (const AstExtend* const extendp = VN_CAST(fromp->backp(), Extend)) {
        if (extendp->lhsp() != fromp) break;
        fromp = extendp;
    }
    const AstSel* const selp = VN_CAST(fromp->backp(), Sel);
    if (!selp || selp->fromp() != fromp) return {lo, hi};
    // Positions not known to be small may be anywhere in the value
    const int64_t valueWidth = hi - lo;
    const int64_t maxLsb = maxPositionOf(selp->lsbp());
    const int64_t minLsb = maxLsb < 0 ? 0 : minPositionOf(selp->lsbp());
    const int64_t selLo = std::min<int64_t>(std::max<int64_t>(minLsb, 0), valueWidth);
    const int64_t selHi
        = maxLsb < 0 ? valueWidth : std::min<int64_t>(maxLsb + selp->widthConst(), valueWidth);
    if (selLo >= selHi) {
        if (exactp) *exactp = false;
        return {lo, hi};
    }
    if (exactp) *exactp = *exactp && maxLsb >= 0 && minLsb == maxLsb;
    return {static_cast<int>(lo + selLo), static_cast<int>(lo + selHi)};
}

size_t bitsSenItemCount(const AstVarScope* vscp, const std::vector<BitRange>& ranges,
                        size_t limit) {
    size_t count = 0;
    for (const BitRange& bits : ranges) {
        if (count > limit) break;
        count += countBitsParts(vscp->dtypep(), bits.first, bits.second, limit - count);
    }
    return count;
}

AstSenTree* changeSenTree(SenTreeFinder& finder, const AstNodeProcedure* procp,
                          const std::unordered_set<const AstVarScope*>& vscps,
                          const ReadRangesList& triggers) {
    FileLine* const flp = procp->fileline();
    AstSenItem* senItemsp = nullptr;
    std::unordered_set<const AstVarScope*> added;
    procp->foreach([&](const AstVarRef* refp) {
        AstVarScope* const vscp = refp->varScopep();
        if (!vscps.count(vscp) || !added.emplace(vscp).second) return;
        AstVarRef* const newRefp = new AstVarRef{flp, vscp, VAccess::READ};
        senItemsp
            = AstNode::addNext(senItemsp, new AstSenItem{flp, VEdgeType::ET_HYBRID, newRefp});
    });
    std::vector<int> indices;
    for (const auto& pair : triggers) {
        AstVarScope* const vscp = pair.first;
        for (const BitRange& bits : pair.second) {
            foreachBitsPart(vscp->dtypep(), bits.first, bits.second, indices,
                            [&](const std::vector<int>& elemIndices, const AstNodeDType* dtypep,
                                int lo, int hi) {
                                AstNodeExpr* exprp = new AstVarRef{flp, vscp, VAccess::READ};
                                for (const int index : elemIndices) {
                                    exprp = new AstArraySel{flp, exprp, index};
                                }
                                if (lo != 0 || hi != flatWidthOf(dtypep)) {
                                    exprp = new AstSel{flp, exprp, lo, hi - lo};
                                }
                                senItemsp = AstNode::addNext(
                                    senItemsp, new AstSenItem{flp, VEdgeType::ET_HYBRID, exprp});
                            });
        }
    }
    AstSenTree* const senTreep = new AstSenTree{flp, senItemsp};
    AstSenTree* const resultp = finder.getSenTree(senTreep);
    // SenTreeFinder::getSenTree clones, so clean up
    VL_DO_DANGLING(senTreep->deleteTree(), senTreep);
    return resultp;
}

SoleWriterMap computeSoleWriters(AstNetlist* netlistp) {
    SoleWriterMap soleWriters;
    // Static initializers run before any process, so do not count as writers
    netlistp->foreach([&](const AstActive* activep) {
        if (activep->sentreep()->hasStatic()) return;
        for (const AstNodeProcedure* const procp : activep->procspList()) {
            procp->foreach([&](const AstVarRef* refp) {
                if (!refp->access().isWriteOrRW()) return;
                const auto pair = soleWriters.emplace(refp->varScopep(), procp);
                if (pair.second) return;
                if (pair.first->second != procp) pair.first->second = nullptr;
            });
        }
    });
    // Writes in functions not inlined into a process, and outside the model, are other writers
    netlistp->foreach([&](const AstCFunc* funcp) {
        funcp->foreach([&](const AstVarRef* refp) {
            if (refp->access().isWriteOrRW()) soleWriters[refp->varScopep()] = nullptr;
        });
    });
    for (auto& pair : soleWriters) {
        const AstVar* const varp = pair.first->varp();
        if (varp->isForceable() || varp->isSigPublic() || varp->isWrittenByDpi()
            || varp->isInout()) {
            pair.second = nullptr;
        }
    }
    return soleWriters;
}

std::unordered_set<const AstVarScope*>
computeImplicitSensitivities(const AstNodeProcedure* procp, const SoleWriterMap& soleWriters,
                             size_t& excludedr, ReadRangesList& triggersr) {
    // Dangerous assumption:
    // A variable read after the process assigned it earlier (in tree order, with a read-write
    // reference counting as an assignment) is not an implicit sensitivity, considering it
    // something like:
    //      foo = 1
    //      foo = foo + 1
    // Note this will break though:
    //      if (sometimes) foo = 1
    //      foo = foo + 1
    // TODO: Do this properly with liveness analysis (i.e.: if live, it's an implicit sensitivity)
    // The assignment covers only the bits it may write, so a read of other bits of the variable,
    // such as of another member of a packed structure written by another process, still is one.
    const AstAlways* const alwaysp = VN_CAST(procp, Always);
    const bool userComb = alwaysp && alwaysp->userComb();
    std::unordered_set<const AstVarScope*> implicitSensitivities;
    std::unordered_map<const AstVarScope*, BitRanges> assigned;  // Bits it may assign so far
    std::unordered_map<const AstVarScope*, BitRanges> exactAssigned;  // Bits it assigns all of
    std::unordered_map<const AstVarScope*, BitRanges> readFirst;  // Bits read, unassigned
    std::vector<AstVarScope*> readOrder;  // Variables in 'readFirst', in order
    std::unordered_set<const AstVarScope*> readBeforeAssigned;  // Read before assigning any bit
    constexpr size_t MAX_BITS_SENSITIVITIES = 64;  // Of a variable, see below
    // "Expressions used in assertion action blocks do not contribute to the implicit sensitivity
    // list of an always_comb" (IEEE 1800-2023 9.2.2.2.1). Variables read only there:
    std::unordered_set<const AstVarScope*> actionReads;
    // Internal variables whose writes scheduling ignores, such as the pending reports of a
    // deferred assertion, wake no combinational logic. What they hold is the process's own state
    // between runs, so an always_comb reading one is not idempotent.
    std::unordered_set<const AstVarScope*> internalReads;
    const size_t excludedBefore = excludedr;
    // A process with timing controls, even if only in forked processes, is not run on changes
    // (see below), so for one keep considering whole variables
    const bool precise = !procp->isSuspendable() && !procp->exists([](const AstNode* nodep) {
        return VN_IS(nodep, Fork) || VN_IS(nodep, CAwait);
    });
    const BitRange wholeBits{0, std::numeric_limits<int>::max()};
    procp->foreach([&](const AstVarRef* refp) {
        AstVarScope* const vscp = refp->varScopep();
        bool exact = true;
        const BitRange bits = precise ? accessedBits(refp, &exact) : wholeBits;
        if (refp->access().isWriteOrRW() && !refp->varp()->ignoreSchedWrite()) {
            assigned[vscp].add(bits);
            if (exact) exactAssigned[vscp].add(bits);
        }
        if (refp->access().isReadOrRW() && !assigned[vscp].covers(bits)) {
            if (refp->varp()->isInternal() && refp->varp()->ignoreSchedWrite()) {
                internalReads.emplace(vscp);
            } else if (userComb && refp->inAssertAction()) {
                actionReads.emplace(vscp);
            } else {
                if (implicitSensitivities.emplace(vscp).second) readOrder.push_back(vscp);
                if (assigned[vscp].empty()) readBeforeAssigned.emplace(vscp);
                for (const BitRange& part : assigned[vscp].uncovered(bits)) {
                    readFirst[vscp].add(part);
                }
            }
        }
    });
    for (const AstVarScope* const vscp : actionReads) {
        if (!implicitSensitivities.count(vscp)) ++excludedr;
    }
    excludedr += userComb ? internalReads.size() : 0;
    std::unordered_set<const AstVarScope*> unexcluded;  // Before anything is left out
    // A user's always_comb is not sensitive to what it writes (IEEE 1800-2023 9.2.2.2.1), so does
    // not wake itself. Only the whole variables it alone writes are excluded, as another process
    // may drive other parts (IEEE 1800-2023 9.2.2.2). A task's writes count, being inlined.
    if (userComb) {
        unexcluded = implicitSensitivities;
        unexcluded.insert(actionReads.begin(), actionReads.end());
        unexcluded.insert(internalReads.begin(), internalReads.end());
        for (const auto& pair : assigned) {
            const AstVarScope* const vscp = pair.first;
            const auto it = soleWriters.find(vscp);
            if (!pair.second.empty() && it != soleWriters.end() && it->second == procp
                && implicitSensitivities.erase(vscp)) {
                ++excludedr;
            }
        }
    }
    // A user's always_comb leaving a variable out is run only by changes of the rest (see
    // V3Sched). If a change of one of those cannot be detected, is of a variable whose writes
    // scheduling ignores, or is of a public variable, which may be written from outside the model
    // and whose readers the 'ico' region runs, leave nothing out: it then stays as before, a
    // cycle that is reported, rather than logic silently running more often than IEEE allows.
    if (excludedr != excludedBefore
        && !std::all_of(implicitSensitivities.begin(), implicitSensitivities.end(),
                        [](const AstVarScope* vscp) {
                            return SenExprBuilder::isSupportedDType(vscp->dtypep())
                                   && !vscp->varp()->ignoreSchedWrite()
                                   && !vscp->varp()->isSigPublic();
                        })) {
        excludedr = excludedBefore;
        implicitSensitivities = std::move(unexcluded);
    }
    // Reads through forced values the process computes itself do not trigger it either
    VarScopeSet forceReadEdgeIgnores;
    collectForceReadEdgeIgnores(procp, forceReadEdgeIgnores);
    for (const AstVarScope* const vscp : forceReadEdgeIgnores) implicitSensitivities.erase(vscp);
    // A variable the process also writes is a combinational cycle through the process, unless
    // the bits it reads are not ones it may write ('assigned' now has all of those): it then only
    // reads bits other processes write. Instead of being ordered after its writers, the process
    // is then run on changes of those bits. Not so for an unpacked array: processes each reading
    // elements before writing others are cheaper as the cycle they are when considering whole
    // variables, which is correct for them. A process that wrote bits of the variable before
    // reading any, so was not sensitive to it when considering whole variables, which is the
    // case this fixes, is run on changes of the bits it reads also if it may write some of them
    // at a position not known, which would otherwise newly be a cycle. It is run on changes of
    // the bits it reads other than those it writes at known positions, as it is not sensitive to
    // what it writes itself (IEEE 1800-2023 9.2.2.2.1), though it is to the bits a write at an
    // unknown position may write, unlike with the longest static prefix of IEEE, which changes
    // when it runs, not what it computes. Such processes in a cycle through bits of variables
    // are not reported as one, but fail to converge when run.
    for (AstVarScope* const vscp : readOrder) {
        const BitRanges& writtenBits = assigned[vscp];
        const BitRanges& readBits = readFirst[vscp];
        if (!precise || !implicitSensitivities.count(vscp) || writtenBits.empty()) continue;
        if (readBeforeAssigned.count(vscp)
            && (writtenBits.intersects(readBits)
                || VN_IS(vscp->dtypep()->skipRefp(), UnpackArrayDType))) {
            continue;
        }
        std::vector<BitRange> bits;
        for (const BitRange& range : readBits.ranges()) {
            for (const BitRange& part : exactAssigned[vscp].uncovered(range)) {
                bits.push_back(part);
            }
        }
        implicitSensitivities.erase(vscp);
        if (bits.empty()) continue;
        // Too many to check one by one, as across many elements of an unpacked array: run it on
        // a change of any bit, so also again after a change it makes itself
        if (bitsSenItemCount(vscp, bits, MAX_BITS_SENSITIVITIES) > MAX_BITS_SENSITIVITIES) {
            bits = {{0, flatWidthOf(vscp->dtypep())}};
        }
        triggersr.emplace_back(vscp, std::move(bits));
    }
    return implicitSensitivities;
}

}  // namespace util

}  // namespace V3Sched
