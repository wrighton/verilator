// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Convert BLOCKTEMPs to local variables
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
// LOCALIZE TRANSFORMATIONS:
//      All modules:
//          VARSCOPE(BLOCKTEMP...
//             if only referenced in one CFUNC, make it local
//          VARSCOPE
//             if non-public, always written before used, make it local
//      All functions:
//          VAR local to the function
//             if only referenced in one C++ scope or 'if' branch, which writes it before
//             any other reference, make it local to that, with a C++ scope around a branch
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Localize.h"

#include "V3Stats.h"
#include "V3VNUserAllocator.h"

#include <deque>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// LocalizeVisitor

class LocalizeVisitor final : public VNVisitor {
    // NODE STATE
    //  AstVarScope::user1()    ->  bool.  VarScope is not optimizable
    //  AstCFunc::user1()       ->  bool.  CFunc is not a leaf function
    //  AstVarScope::user2()    ->  bool.  VarScope was fully assigned in current function
    //  AstVarScope::user3p()   ->  Set of CFuncs referencing this VarScope. (via m_accessors)
    //  AstCFunc::user4p()      ->  Multimap of 'VarScope -> VarRefs that reference that VarScope'
    //                              in this function. (via m_references)
    const VNUser1InUse m_user1InUse;
    const VNUser3InUse m_user3InUse;
    const VNUser4InUse m_user4InUse;

    VNUser3Allocator<AstVarScope, std::unordered_set<AstCFunc*>> m_accessors;
    VNUser4Allocator<AstCFunc, std::unordered_multimap<const AstVarScope*, AstVarRef*>>
        m_references;

    // STATE - across all visitors
    std::vector<AstVarScope*> m_varScopeps;  // List of variables to consider for localization
    VDouble0 m_statLocVars;  // Statistic tracking

    // STATE - for current visit position (use VL_RESTORER)
    AstCFunc* m_cfuncp = nullptr;  // Current active function
    uint32_t m_nodeDepth = 0;  // Node depth under m_cfuncp

    // METHODS
    bool isOptimizable(AstVarScope* nodep) {
        // Don't want to malloc/free the backing store all the time
        if (nodep->varp()->basicp() && nodep->varp()->basicp()->isNbaGenericQueue()) return false;
        if (VN_IS(nodep->dtypep()->skipRefp(), ClosurePoolDType)) return false;
        // Do not localize strings used in hot code. They result in unnecessary initialization
        // and bloated code size due to destructor calls when unused. In cold code this cost
        // is negligible, and localizing avoids a model member per string temporary.
        // TODO: Local variables should be pushed into the narrowest scope rather
        // than emitted at the top of the function. See discussion in #6969.
        if (nodep->dtypep()->skipRefp()->isString() && existsNonSlow(m_accessors(nodep))) {
            return false;
        }
        // Variables used in super constructor call can't be localized, because
        // in C++ there is no way to declare them before base class constructor call
        return ((!nodep->user1()  // Not marked as not optimizable, or ...
                                  // .. a block temp used in a single CFunc
                 || (nodep->varp()->varType() == VVarType::BLOCKTEMP
                     && m_accessors(nodep).size() == 1))
                // and under size limit
                && nodep->varp()->dtypep()->widthTotalBytes() <= v3Global.opt.localizeMaxSize());
    }

    static bool existsNonSlow(const std::unordered_set<AstCFunc*>& funcps) {
        for (const AstCFunc* const funcp : funcps) {
            if (!funcp->slow()) return true;
        }
        return false;
    }

    static bool existsNonLeaf(const std::unordered_set<AstCFunc*>& funcps) {
        for (const AstCFunc* const funcp : funcps) {
            if (funcp->user1()) return true;
        }
        return false;
    }

    void moveVarScopes() {
        for (AstVarScope* const nodep : m_varScopeps) {
            if (!isOptimizable(nodep)) continue;  // Not optimizable

            const std::unordered_set<AstCFunc*>& funcps = m_accessors(nodep);
            if (funcps.empty()) continue;  // No referencing functions at all

            // If more than one referencing function, but not all are leaf
            // functions, then don't localize, as one of the referencing
            // functions might be calling another, which the current analysis
            // cannot cope with. This should be rare (introduced by V3Depth).
            if (funcps.size() > 1 && existsNonLeaf(funcps)) continue;

            UINFO(4, "Localizing " << nodep);
            ++m_statLocVars;

            // Yank the VarScope from it's parent and schedule them for deletion. Leave the Var
            // for now, as not all VarScopes referencing this Var might be localized.
            pushDeletep(nodep->unlinkFrBack());  // TODO nodep used past here

            // In each referencing function, create a replacement local variable
            AstVar* const oldVarp = nodep->varp();
            for (AstCFunc* const funcp : funcps) {
                // Create the new local variable.
                const string newName
                    = nodep->scopep() == funcp->scopep()
                          ? oldVarp->name()
                          : nodep->scopep()->nameDotless() + "__DOT__" + oldVarp->name();
                AstVar* const newVarp
                    = new AstVar{oldVarp->fileline(), oldVarp->varType(), newName, oldVarp};
                newVarp->funcLocal(true);
                newVarp->noReset(oldVarp->noReset());
                newVarp->noSubst(oldVarp->noSubst());
                funcp->addVarsp(newVarp);

                // Fix up all the references within this function
                const auto er = m_references(funcp).equal_range(nodep);
                for (auto it = er.first; it != er.second; ++it) {
                    AstVarRef* const refp = it->second;
                    refp->varScopep(nullptr);
                    refp->varp(newVarp);
                }
            }
        }
        m_varScopeps.clear();
    }

    // VISITORS
    void visit(AstNetlist* nodep) override {
        iterateChildrenConst(nodep);
        moveVarScopes();
    }

    void visit(AstCAwait* nodep) override {
        m_cfuncp->user1(true);  // Mark caller as not a leaf function
        iterateChildrenConst(nodep);
    }

    void visit(AstCFunc* nodep) override {
        UINFO(4, "  CFUNC " << nodep);
        VL_RESTORER(m_cfuncp);
        VL_RESTORER(m_nodeDepth);
        m_cfuncp = nodep;
        m_nodeDepth = 0;
        const VNUser2InUse user2InUse;
        iterateChildrenConst(nodep);
    }

    void visit(AstCNew* nodep) override {
        m_cfuncp->user1(true);  // Mark caller as not a leaf function
        iterateChildren(nodep);
    }

    void visit(AstCCall* nodep) override {
        m_cfuncp->user1(true);  // Mark caller as not a leaf function
        iterateChildrenConst(nodep);
    }

    void visit(AstNodeAssign* nodep) override {
        // Analyze RHS first so "a = a + 1" is detected as a read before write
        iterate(nodep->rhsp());
        // For now we only consider an assignment that is directly under the function, (in
        // particular: not under an AstIf, or other kind of branch). This could be improved with
        // proper data flow analysis.
        if (m_nodeDepth == 0) {
            // Check if simple "VARREF = ..." assignment, i.e.: this assignment sets the whole
            // variable (and in particular, it is not assigned only in part).
            if (const AstVarRef* const refp = VN_CAST(nodep->lhsp(), VarRef)) {
                // Mark this VarScope as assigned in this function
                refp->varScopep()->user2(1);
            }
        }
        // Analyze LHS (in case it's not the above simple case
        iterate(nodep->lhsp());
    }

    void visit(AstVarScope* nodep) override {
        if (!nodep->varp()->isPrimaryIO()  // Not an IO the user wants to interact with
            && !nodep->varp()->isSigPublic()  // Not something the user wants to interact with
            && !nodep->varp()->isFuncLocal()  // Not already a function local (e.g.: argument)
            && !nodep->varp()->isClassMember()  // Statically exists in design hierarchy
            && !nodep->varp()->sensIfacep()  // Not sensitive to an interface
            && !nodep->varp()->isVirtIface()  // Not interface pointer
            && !nodep->varp()->constPoolEntry()  // Not a const pool entry
            && nodep->varp() != v3Global.rootp()->activityp()  // Not read by the runtime
            && !nodep->varp()->valuep()  // Does not have an initializer
        ) {
            UINFO(4, "Consider for localization: " << nodep);
            m_varScopeps.push_back(nodep);
        }
        // No iterate; Don't want varrefs under it (e.g.: in child dtype?)
    }

    void visit(AstRtmdVar* nodep) override {
        // Descriptors read variables by address, so they cannot be localized
        if (!nodep->refp()) return;
        UINFO(4, "Not optimizable (rtmd): " << nodep);
        nodep->vscp()->user1(1);
    }
    void visit(AstVarRef* nodep) override {
        UASSERT_OBJ(m_cfuncp, nodep, "AstVarRef not under function");

        AstVarScope* const varScopep = nodep->varScopep();
        // Remember this function accesses this VarScope (we always need this as we might optimize
        // this VarScope into a local, even if it's not assigned. See 'isOptimizable')
        m_accessors(varScopep).insert(m_cfuncp);  // emplace performs a temporary malloc
        // Remember the reference so we can fix it up later (we always need this as well)
        m_references(m_cfuncp).emplace(varScopep, nodep);

        if (!varScopep->user1()) {  // Check if already marked as not optimizable
            // Note: we only check read variables, as it's ok to localize (and in fact discard)
            // any variables that are only written but never read.
            if (nodep->access().isReadOrRW() && !varScopep->user2()) {
                // Variable is read, but is not known to have been assigned in this function. Mark
                // as not optimizable.
                UINFO(4, "Not optimizable (not written): " << nodep);
                varScopep->user1(1);
            }
        }
        // No iterate; Don't want varrefs under it  (e.g.: in child dtype?)
    }

    void visit(AstNode* nodep) override {
        VL_RESTORER(m_nodeDepth);
        ++m_nodeDepth;
        iterateChildrenConst(nodep);
    }

public:
    // CONSTRUCTORS
    explicit LocalizeVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~LocalizeVisitor() override {
        V3Stats::addStat("Optimizations, Vars localized", m_statLocVars);
    }
};

//######################################################################
// LocalizeScopeVisitor

class LocalizeScopeVisitor final : public VNVisitor {
    // Move a local of a function into the innermost C++ scope (AstCLocalScope, such as that of
    // an inlined call) or branch of an 'if' containing all its references, if a statement
    // directly there assigns the whole variable before any other reference to it. A value from
    // before is then never read, so the variable can be made each time the scope or branch
    // runs, rather than each time the function runs. A branch gets a C++ scope around it. For
    // each point that may throw, the C++ compiler then destroys only the variables of the
    // scopes around it, rather than all variables of the function. A branch is not used in a
    // loop inside the C++ scope or function around it, where the variable would be made for
    // each iteration rather than once.

    // TYPES
    // A C++ scope or branch of an 'if', in the current function
    struct Region final {
        Region* const m_abovep;  // Region it is in, nullptr for the function
        AstCLocalScope* m_cscopep;  // The C++ scope, nullptr for a branch until it needs one
        AstIf* const m_ifp;  // For a branch, its 'if'
        const bool m_else;  // For a branch, the 'else' branch, else the 'then' branch
        const bool m_inLoop;  // For a branch, in a loop inside the C++ scope around it
        // While the visit is in it, itself, else the region it is in, so following these finds
        // the innermost region containing it that the visit is in
        Region* m_upp = nullptr;
    };

    // NODE STATE
    //  AstVar::user1p()    ->  Region*. Innermost region containing all references so far
    //  AstVar::user2p()    ->  Region*. Region directly holding the first reference, if it
    //                          assigns the whole variable, else nullptr
    const VNUser1InUse m_user1InUse;
    const VNUser2InUse m_user2InUse;

    // STATE - for current visit position (use VL_RESTORER)
    Region* m_regionp = nullptr;  // Innermost region
    bool m_inLoop = false;  // In a loop inside the innermost C++ scope

    // STATE - across all visitors
    std::deque<Region> m_regions;  // Regions of the current function, the first one being it
    VDouble0 m_statScopeVars;  // Statistic tracking
    VDouble0 m_statScopes;  // Statistic tracking

    // METHODS
    // Visit a statement directly in the current region
    void visitRegionStmt(AstNode* stmtp) {
        // The statements that assign a whole variable: '=' and '$sformat'. Their right hand
        // side is evaluated before the variable is written, and is visited once, as it may hold
        // nested inlined calls.
        AstNodeExpr* lhsp = nullptr;
        AstNode* rhsp = nullptr;
        if (AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
            UASSERT_OBJ(!assignp->timingControlp(), assignp, "Timing control after V3Timing");
            lhsp = assignp->lhsp();
            rhsp = assignp->rhsp();
        } else if (AstSFormat* const sformatp = VN_CAST(stmtp, SFormat)) {
            lhsp = sformatp->lhsp();
            rhsp = sformatp->fmtp();
        }
        AstVarRef* const refp = VN_CAST(lhsp, VarRef);
        if (!refp) {
            iterate(stmtp);
            return;
        }
        iterateAndNextNull(rhsp);
        if (!refp->varp()->user1p()) refp->varp()->user2p(m_regionp);
        iterate(refp);
    }
    // Visit the statements 'stmtsp' of a new region
    void visitRegion(AstCLocalScope* cscopep, AstIf* ifp, bool isElse, AstNode* stmtsp) {
        VL_RESTORER(m_regionp);
        m_regions.push_back(Region{m_regionp, cscopep, ifp, isElse, m_inLoop});
        m_regionp = &m_regions.back();
        m_regionp->m_upp = m_regionp;
        for (AstNode *stmtp = stmtsp, *nextp; stmtp; stmtp = nextp) {
            nextp = stmtp->nextp();
            visitRegionStmt(stmtp);
        }
        m_regionp->m_upp = m_regionp->m_abovep;
    }
    // The innermost region containing 'regionp' and the current position, which is in the
    // regions the visit is in. Halving the paths followed keeps them short over all calls.
    static Region* common(Region* regionp) {
        while (regionp->m_upp != regionp) {
            regionp->m_upp = regionp->m_upp->m_upp;
            regionp = regionp->m_upp;
        }
        return regionp;
    }
    // The C++ scope of 'regionp', made around its branch if needed
    AstCLocalScope* makeCScope(Region* regionp) {
        if (regionp->m_cscopep) return regionp->m_cscopep;
        AstIf* const ifp = regionp->m_ifp;
        AstNode* const stmtsp = regionp->m_else ? ifp->elsesp() : ifp->thensp();
        regionp->m_cscopep = new AstCLocalScope{stmtsp->fileline(),
                                                VN_AS(stmtsp->unlinkFrBackWithNext(), NodeStmt)};
        if (regionp->m_else) {
            ifp->addElsesp(regionp->m_cscopep);
        } else {
            ifp->addThensp(regionp->m_cscopep);
        }
        ++m_statScopes;
        return regionp->m_cscopep;
    }

    // VISITORS
    void visit(AstCFunc* nodep) override {
        // The regions of the previous function are gone
        VNUser1InUse::clear();
        VNUser2InUse::clear();
        VL_RESTORER(m_regionp);
        VL_RESTORER(m_inLoop);
        m_regions.push_back(Region{nullptr, nullptr, nullptr, false, false});
        m_regionp = &m_regions.back();
        m_regionp->m_upp = m_regionp;
        m_inLoop = false;
        iterateChildren(nodep);
        for (AstVar *varp = nodep->varsp(), *nextp; varp; varp = nextp) {
            nextp = VN_AS(varp->nextp(), Var);
            Region* const regionp = varp->user1u().to<Region*>();
            if (!regionp || !regionp->m_abovep || regionp->m_inLoop
                || varp->user2u().to<Region*>() != regionp) {
                continue;
            }
            makeCScope(regionp)->addVarsp(varp->unlinkFrBack());
            ++m_statScopeVars;
        }
        m_regions.clear();
    }
    void visit(AstCLocalScope* nodep) override {
        VL_RESTORER(m_inLoop);
        m_inLoop = false;
        visitRegion(nodep, nullptr, false, nodep->stmtsp());
    }
    void visit(AstLoop* nodep) override {
        VL_RESTORER(m_inLoop);
        m_inLoop = true;
        iterateChildren(nodep);
    }
    void visit(AstIf* nodep) override {
        iterateAndNextNull(nodep->condp());
        visitRegion(nullptr, nodep, false, nodep->thensp());
        visitRegion(nullptr, nodep, true, nodep->elsesp());
    }
    void visit(AstVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        Region* const regionp = varp->user1u().to<Region*>();
        varp->user1p(regionp ? common(regionp) : m_regionp);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit LocalizeScopeVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~LocalizeScopeVisitor() override {
        V3Stats::addStat("Optimizations, C++ scopes made for localized vars", m_statScopes);
        V3Stats::addStat("Optimizations, Vars localized to C++ scopes", m_statScopeVars);
    }
};

//######################################################################
// Localize class functions

void V3Localize::localizeAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { LocalizeVisitor{nodep}; }  // Destruct before checking
    { LocalizeScopeVisitor{nodep}; }
    V3Global::dumpCheckGlobalTree("localize", 0, dumpTreeEitherLevel() >= 6);
}
