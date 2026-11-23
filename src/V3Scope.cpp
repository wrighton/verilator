// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Break always into sensitivity block domains
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
// V3Scope's Transformations:
//
//      For every CELL that references this module, create a
//              SCOPE
//                      {all blocked statements}
//
//      Make the last initial procedure of the programs to end call $finish
//      Kill the threads of a program when its initial procedures have ended
//
//      Share the ordered union of absolute assertion targets among callers with
//      the same applicable cohorts (proven routes shared by multiple callers).
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Scope.h"

#include "V3ConstPool.h"
#include "V3Control.h"
#include "V3Hash.h"

#include <cstring>
#include <map>
#include <unordered_map>
#include <unordered_set>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Scope class functions

class ScopeVisitor final : public VNVisitor {
    // NODE STATE
    // AstVar::user1p           -> AstVarScope*.  Replacement for this variable
    // AstCell::user2p          -> AstScope*.  The scope created inside the cell
    // AstTask::user2p          -> AstTask*.  Replacement task
    // AstRtmdHier::user2()     -> bool.  Iterated already, under the scope of its instance
    // AstNodeModule::user3()   -> uint64_t.  Pending instantiations of this module
    // AstAssertCtlTargetSet::user3() -> bool.  Referenced by a scoped operation
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;
    const VNUser3InUse m_inuser3;

    // TYPES
    // These cannot be unordered unless make a specialized hashing pair (gcc-8)
    using VarScopeMap = std::map<std::pair<AstVar*, AstScope*>, AstVarScope*>;

    // STATE, inside processing a single module
    AstNodeModule* m_modp = nullptr;  // Current module
    AstNodeProcedure* m_procedurep = nullptr;  // Current procedure
    AstScope* m_scopep = nullptr;  // Current scope we are building
    // STATE, for passing down one level of hierarchy (may need save/restore)
    AstCell* m_aboveCellp = nullptr;  // Cell that instantiates this module
    AstScope* m_aboveScopep = nullptr;  // Scope that instantiates this scope
    // Per module, the named blocks, and "" for the module itself, that hold a variable VPI can
    // reach, or an instance of a module that does. VPI looks up only the scopes above such
    // variables, so only these blocks get an AstCellInlineScope.
    std::unordered_map<const AstNodeModule*, std::unordered_set<std::string>> m_vpiBlocks;
    // m_vpiBlocks of the module being scoped, nullptr without VPI
    const std::unordered_set<std::string>* m_vpiBlocksp = nullptr;
    bool m_last = false;  // Scoping the last instantiation of the current module

    std::unordered_map<AstNodeModule*, AstScope*>
        m_classOrPackageScopes;  // Scopes for each class or package
    VarScopeMap m_varScopes;  // Varscopes created for each scope and var
    // Varrefs-in-scopes needing fixup when done
    std::vector<std::pair<AstVarRef*, AstScope*>> m_varRefScopes;
    std::vector<AstScope*> m_scopes;  // Scopes awaiting attachment to their modules
    std::vector<AstRtmdHier*> m_classRtmdps;  // Descriptors of classes, to place at the root
    // Initial procedures of program instances, with the program instance's scope
    std::vector<std::pair<AstInitial*, const AstScope*>> m_programInitials;

    using AssertCtlRoutes = std::vector<std::pair<size_t, AstAssertCtlTargetSet*>>;
    using AssertCtlComponents = std::vector<const AstAssertCtlTargetSet*>;
    struct AssertCtlComponentsHash final {
        size_t operator()(const AssertCtlComponents& components) const {
            V3Hash hash;
            for (const AstAssertCtlTargetSet* const setp : components) hash += setp;
            return hash.value();
        }
    };
    struct AssertCtlCallerRoutes final {
        AssertCtlRoutes routes;  // Routes private to this caller, in source order
        AssertCtlComponents cohorts;  // Shared absolute routes, in source order
        size_t uses = 0;  // Copies of the live source operations materialized for this caller
    };
    struct AssertCtlPlanIndex final {
        AssertCtlRoutes common;  // Unshared routes used by every caller
        std::unordered_map<const AstAssertCtlCaller*, AssertCtlCallerRoutes> byCaller;
        size_t sourceUses = 0;  // Surviving operation templates before scoping clones them
        AstAssertCtlTargetSet* sharedp = nullptr;  // Absolute targets common to all callers
        std::unordered_map<AssertCtlComponents, size_t, AssertCtlComponentsHash> cohortUses;
        std::unordered_map<AssertCtlComponents, AstAssertCtlTargetSet*, AssertCtlComponentsHash>
            unions;  // One absolute target list per distinct combination of components
    };
    std::vector<AstAssertCtlTargetSet*> m_assertCtlTargetSets;  // Awaiting attachment to top
    std::unordered_map<const AstAssertCtlTargetSet*, size_t> m_assertCtlRows;  // Base sizes
    // Lookup of the structural child occurrence by (parent occurrence, declaration).
    std::unordered_map<const AstAssertCtlCaller*,
                       std::unordered_map<const AstNode*, AstAssertCtlCaller*>>
        m_assertCtlCallers;
    std::unordered_map<const AstAssertCtlPlan*, AssertCtlPlanIndex>
        m_assertCtlPlans;  // Applicable routes in source order
    const AstAssertCtlCaller* m_assertCtlCallerp = nullptr;  // Current concrete occurrence

    // METHODS

    void indexAssertionPlans(AstNetlist* rootp) {
        for (AstNode* const miscp : rootp->miscspList()) {
            if (AstAssertCtlCaller* const callerp = VN_CAST(miscp, AssertCtlCaller)) {
                const bool inserted = m_assertCtlCallers[callerp->parentp()]
                                          .emplace(callerp->anchorp(), callerp)
                                          .second;
                UASSERT_OBJ(inserted, callerp, "Duplicate assertion selector caller identity");
            } else if (AstAssertCtlPlan* const planp = VN_CAST(miscp, AssertCtlPlan)) {
                AssertCtlPlanIndex& index = m_assertCtlPlans[planp];
                size_t ordinal = 0;
                for (AstAssertCtlTargetSet* const setp : planp->setspList()) {
                    if (!setp->callersp() && setp->targetsp()) {
                        index.common.emplace_back(ordinal, setp);
                    }
                    const AstVarXRef* const statep
                        = setp->targetsp() ? VN_CAST(setp->targetsp()->statep(), VarXRef)
                                           : nullptr;
                    // Only proven cohorts have non-optional absolute routes.
                    const bool cohort = setp->callersp() && setp->callersp()->nextp() && statep
                                        && statep->assertCtlAbsolute()
                                        && !statep->assertCtlOptional();
                    for (const AstAssertCtlCallerRef* const refp : setp->callerspList()) {
                        AssertCtlCallerRoutes& caller = index.byCaller[refp->callerp()];
                        if (cohort) {
                            caller.cohorts.push_back(setp);
                        } else {
                            caller.routes.emplace_back(ordinal, setp);
                        }
                    }
                    ++ordinal;
                }
                for (const auto& entry : index.byCaller) {
                    if (!entry.second.cohorts.empty()) ++index.cohortUses[entry.second.cohorts];
                }
            }
        }
    }
    AstAssertCtlCaller* takeAssertCtlChildp(const AstCell* cellp, const AstScope* parentp) {
        if (!cellp) return nullptr;
        const auto children = m_assertCtlCallers.find(m_assertCtlCallerp);
        if (children == m_assertCtlCallers.end()) return nullptr;
        const AstNode* anchorp = cellp;
        if (parentp->isTop()) {
            if (cellp->assertCtlIfaceOriginp()) {
                anchorp = cellp->assertCtlIfaceOriginp();
            } else {
                anchorp = cellp->modp();
            }
        }
        const auto found = children->second.find(anchorp);
        if (found == children->second.end()) return nullptr;
        AstAssertCtlCaller* const callerp = found->second;
        children->second.erase(found);
        if (children->second.empty()) m_assertCtlCallers.erase(children);
        return callerp;
    }

    // Count module instantiations, visiting cells the same way the traversal below does
    static void countInstantiations(AstNodeModule* modp) {
        modp->user3Inc();
        for (AstNode* const stmtp : modp->stmtspList()) {
            if (const AstCell* const cellp = VN_CAST(stmtp, Cell)) {
                countInstantiations(cellp->modp());
            }
        }
    }

    // Copy, or move (on the last instantiation), the given node under
    // the current scope, and return the version now under the scope
    template <typename T_Node>
    T_Node* cloneOrMove(T_Node* nodep) {
        T_Node* clonep;
        if (m_last) {
            nodep->unlinkFrBack();
            clonep = nodep;
        } else {
            clonep = nodep->cloneTree(false);
        }
        nodep->user2p(clonep);
        m_scopep->addBlocksp(clonep);
        return clonep;
    }

    void cleanupVarRefs() {
        for (const auto& itr : m_varRefScopes) {
            AstVarRef* const nodep = itr.first;
            AstScope* scopep = itr.second;
            if (nodep->classOrPackagep()
                && !VN_IS(nodep->classOrPackagep(),
                          Module)) {  // Module scopes are not in m_classOrPackageScopes
                const auto it2 = m_classOrPackageScopes.find(nodep->classOrPackagep());
                UASSERT_OBJ(it2 != m_classOrPackageScopes.end(), nodep,
                            "Can't locate class or package scope");
                scopep = it2->second;
            }
            nodep->classOrPackagep(nullptr);  // No longer needed after V3Scope
            // Search up the scope hierarchy for the variable
            AstVarScope* varscp = nullptr;
            AstScope* searchScopep = scopep;
            while (searchScopep) {
                const auto it3 = m_varScopes.find(std::make_pair(nodep->varp(), searchScopep));
                if (it3 != m_varScopes.end()) {
                    varscp = it3->second;
                    break;
                }
                searchScopep = searchScopep->aboveScopep();
            }
            UASSERT_OBJ(varscp, nodep, "Can't locate varref scope");
            nodep->varScopep(varscp);
        }
    }

    // Create a counter of running initial procedures in the top scope
    static AstVarScope* newInitialsCounter(AstTopScope* topScopep, const string& name,
                                           uint32_t count) {
        AstVarScope* const countp = topScopep->createTemp(name, 32);
        FileLine* const flp = topScopep->fileline();
        topScopep->scopep()->addBlocksp(new AstInitialStatic{
            flp, new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE},
                               new AstConst{flp, AstConst::WidthedValue{}, 32, count}}});
        return countp;
    }
    // Decrement a counter at the end of an initial procedure, and return its is-zero condition
    static AstNodeExpr* makeCountDown(AstInitial* initialp, AstVarScope* countp) {
        FileLine* const fl = initialp->fileline();
        initialp->addStmtsp(
            new AstAssign{fl, new AstVarRef{fl, countp, VAccess::WRITE},
                          new AstSub{fl, new AstVarRef{fl, countp, VAccess::READ},
                                     new AstConst{fl, AstConst::WidthedValue{}, 32, 1}}});
        return new AstEq{fl, new AstVarRef{fl, countp, VAccess::READ},
                         new AstConst{fl, AstConst::WidthedValue{}, 32, 0}};
    }
    // Make the simulation finish when all program initial procedures have ended
    void makeProgramFinish(AstTopScope* topScopep) {
        // IEEE 1800-2023 24.7: Implicit $finish once all initial procedures within all
        // programs have ended. Count the running procedures down, and finish at zero.
        AstVarScope* const countp = newInitialsCounter(
            topScopep, "__VprogramInitials", static_cast<uint32_t>(m_programInitials.size()));
        // Also, once all initial procedures of one program have ended, their descendant threads
        // are killed. Each ended procedure waits for its program's count to reach zero, then
        // disables its own forks. Without --timing there are no such threads.
        const bool killThreads = v3Global.opt.timing().isSetTrue();
        std::map<const AstScope*, uint32_t> programCounts;
        for (const auto& pair : m_programInitials) ++programCounts[pair.second];
        std::map<const AstScope*, AstVarScope*> programCountps;
        for (const auto& pair : m_programInitials) {
            AstInitial* const initialp = pair.first;
            FileLine* const fl = initialp->fileline();
            initialp->addStmtsp(new AstIf{fl, makeCountDown(initialp, countp), new AstFinish{fl}});
            if (!killThreads) continue;
            AstVarScope*& programCountpr = programCountps[pair.second];
            if (!programCountpr) {
                programCountpr = newInitialsCounter(
                    topScopep, "__VprogramInitials" + cvtToStr(programCountps.size()),
                    programCounts[pair.second]);
            }
            initialp->addStmtsp(new AstWait{fl, makeCountDown(initialp, programCountpr), nullptr});
            initialp->addStmtsp(new AstDisableFork{fl});
        }
    }

    // Compute m_vpiBlocks of a module, after the modules of its instances.
    const std::unordered_set<std::string>& vpiBlocks(const AstNodeModule* const modp) {
        const auto pair = m_vpiBlocks.emplace(modp, std::unordered_set<std::string>{});
        std::unordered_set<std::string>& blocks = pair.first->second;
        if (!pair.second) return blocks;
        for (const AstNode* const nodep : modp->stmtspList()) {
            bool reached = false;
            if (const AstVar* const varp = VN_CAST(nodep, Var)) {
                reached = varp->isVpiVisible();
            } else if (const AstCell* const cellp = VN_CAST(nodep, Cell)) {
                const auto it = m_vpiBlocks.find(cellp->modp());
                UASSERT_OBJ(it != m_vpiBlocks.end(), cellp, "Instance scoped before its module");
                reached = !it->second.empty();
            }
            if (!reached) continue;
            // V3Begin named the item after the blocks around it: {block}__DOT__...{item}
            blocks.emplace("");
            const std::string& name = nodep->name();
            for (size_t pos = name.find("__DOT__"); pos != std::string::npos;
                 pos = name.find("__DOT__", pos + std::strlen("__DOT__"))) {
                blocks.emplace(name.substr(0, pos));
            }
        }
        return blocks;
    }

    // Assign first-occurrence order before partitioning the targets.
    static void separateAbsoluteTargets(AstAssertCtlTarget* targetsp, uint32_t& ordinal,
                                        AstAssertCtlTargetSet* sharedp) {
        for (AstAssertCtlTarget* const targetp : VNList<AstAssertCtlTarget>{targetsp}) {
            targetp->ordinal(ordinal++);
            if (!sharedp) continue;
            AstVarXRef* const refp = VN_CAST(targetp->statep(), VarXRef);
            if (!refp || !refp->assertCtlAbsolute() || refp->assertCtlOptional()) continue;
            refp->inlinedDots("");
            sharedp->addTargetsp(targetp->unlinkFrBack());
        }
    }

    size_t assertionTargetRows(const AstAssertCtlTargetSet* setp) {
        if (!setp) return 0;
        const auto entry = m_assertCtlRows.try_emplace(setp, 0);
        if (entry.second) {
            for (const AstAssertCtlTarget* const targetp : setp->targetspList()) {
                (void)targetp;
                ++entry.first->second;
            }
        }
        return entry.first->second;
    }

    AstAssertCtlTargetSet* shareAssertionTargets(AstAssertCtlApply* applyp,
                                                 AssertCtlPlanIndex& index,
                                                 const AssertCtlComponents& cohorts) {
        AstAssertCtlTargetSet* const sourcep = applyp->targetSetp();
        AstAssertCtlTargetSet* const commonp = index.sharedp;
        if (cohorts.empty() && !(sourcep && commonp)) return sourcep ? sourcep : commonp;

        const size_t sourceRows = assertionTargetRows(sourcep);
        const size_t commonRows = assertionTargetRows(commonp);
        if (!cohorts.empty() && (sourceRows || commonRows)) {
            const bool preferSource = sourceRows >= commonRows;
            const size_t baseRows = preferSource ? sourceRows : commonRows;
            size_t overlayRows = preferSource ? commonRows : sourceRows;
            for (const AstAssertCtlTargetSet* const routep : cohorts) {
                overlayRows += assertionTargetRows(routep);
            }
            // Compare one base copy in the interned union against the extra private
            // copies of the overlay if the base stays separate.
            const size_t copies = index.cohortUses.at(cohorts);
            if (baseRows / overlayRows >= copies - 1) {
                const AstAssertCtlTargetSet* const residualp = preferSource ? commonp : sourcep;
                if (residualp && residualp->targetsp()) {
                    applyp->addTargetsp(residualp->targetsp()->cloneTree(true));
                }
                for (const AstAssertCtlTargetSet* const routep : cohorts) {
                    UASSERT_OBJ(routep->targetsp(), routep, "A shared cohort must have targets");
                    applyp->addTargetsp(routep->targetsp()->cloneTree(true));
                }
                return preferSource ? sourcep : commonp;
            }
        }

        AssertCtlComponents components;
        components.reserve(cohorts.size() + 2);
        components.push_back(sourcep);
        components.push_back(commonp);
        components.insert(components.end(), cohorts.begin(), cohorts.end());
        const auto entry = index.unions.try_emplace(std::move(components), nullptr);
        if (!entry.second) return entry.first->second;
        AstAssertCtlTargetSet* const sharedp = new AstAssertCtlTargetSet{
            applyp->fileline(),
            sourcep && sourcep->targetsp() ? sourcep->targetsp()->cloneTree(true) : nullptr};
        entry.first->second = sharedp;
        v3Global.rootp()->addMiscsp(sharedp);
        m_assertCtlTargetSets.push_back(sharedp);

        // The source list comes first. Merge the ordered cohort and common streams by ordinal
        // so binding can keep the first occurrence and minimum depth for every concrete site.
        const VNList<AstAssertCtlTarget> common{commonp ? commonp->targetsp() : nullptr};
        auto next = common.begin();
        for (const AstAssertCtlTargetSet* const routep : cohorts) {
            for (AstAssertCtlTarget* const targetp : routep->targetspList()) {
                while (next != common.end() && (*next)->ordinal() < targetp->ordinal()) {
                    sharedp->addTargetsp((*next)->cloneTree(false));
                    ++next;
                }
                AstAssertCtlTarget* const clonep = targetp->cloneTree(false);
                VN_AS(clonep->statep(), VarXRef)->inlinedDots("");
                sharedp->addTargetsp(clonep);
            }
        }
        while (next != common.end()) {
            sharedp->addTargetsp((*next)->cloneTree(false));
            ++next;
        }
        return sharedp;
    }

    void prepareAssertionTargets(AstNetlist* rootp) {
        if (!v3Global.hasAssertCtlReads()) return;
        // Capture the live operations before changing their tree ownership.
        std::vector<AstAssertCtlApply*> applies;
        rootp->foreach([&](AstAssertCtlApply* applyp) { applies.push_back(applyp); });
        std::unordered_map<AstAssertCtlTargetSet*, uint32_t> sourceSets;
        for (AstAssertCtlApply* const applyp : applies) {
            AstAssertCtlTargetSet* const sourcep = applyp->targetSetp();
            uint32_t ordinal = 0;
            if (sourcep) {
                const auto source = sourceSets.try_emplace(sourcep, 0);
                if (source.second) {
                    m_assertCtlTargetSets.push_back(sourcep);
                    separateAbsoluteTargets(sourcep->targetsp(), source.first->second, nullptr);
                }
                ordinal = source.first->second;
            }
            AstAssertCtlPlan* const planp = applyp->planp();
            if (planp && m_assertCtlPlans[planp].sourceUses++) continue;
            if (!planp && !applyp->targetsp()) continue;
            AstAssertCtlTargetSet* const sharedp
                = sourcep && !planp ? nullptr
                                    : new AstAssertCtlTargetSet{applyp->fileline(), nullptr};
            separateAbsoluteTargets(applyp->targetsp(), ordinal, sharedp);
            if (!sharedp) continue;
            if (planp) {
                for (AstAssertCtlTargetSet* const setp : planp->setspList()) {
                    separateAbsoluteTargets(setp->targetsp(), ordinal,
                                            setp->callersp() ? nullptr : sharedp);
                }
            }
            if (sharedp->targetsp()) {
                rootp->addMiscsp(sharedp);
                m_assertCtlTargetSets.push_back(sharedp);
                if (planp) {
                    m_assertCtlPlans.at(planp).sharedp = sharedp;
                } else {
                    applyp->targetSetp(sharedp);
                }
            } else {
                VL_DO_DANGLING(sharedp->deleteTree(), sharedp);
            }
        }
    }

    // VISITORS
    void visit(AstNetlist* nodep) override {
        AstNodeModule* const modp = nodep->topModulep();
        if (!modp) {
            nodep->v3error("No top level module found");
            return;
        }
        // Each concrete caller must materialize each live source operation once.
        prepareAssertionTargets(nodep);
        if (v3Global.hasAssertCtlReads()) indexAssertionPlans(nodep);
        // Operate starting at the top of the hierarchy
        m_aboveCellp = nullptr;
        m_aboveScopep = nullptr;
        countInstantiations(modp);
        iterate(modp);
        for (AstAssertCtlTargetSet* const setp : m_assertCtlTargetSets) {
            setp->unlinkFrBack();
            if (setp->user3()) {
                nodep->topScopep()->scopep()->addBlocksp(setp);
            } else {
                VL_DO_DANGLING(pushDeletep(setp), setp);
            }
        }
        UASSERT_OBJ(m_assertCtlCallers.empty(), nodep, "Unscoped assertion selector callers");
        if (!V3Error::errorCount()) {
            for (const auto& plan : m_assertCtlPlans) {
                for (const auto& caller : plan.second.byCaller) {
                    UASSERT_OBJ(caller.second.uses == plan.second.sourceUses, plan.first,
                                "Assertion selector plan not consumed once per caller and use");
                }
            }
        }
        // Defer attachment until all instances are visited so cell collection and child
        // iteration do not rescan a growing list of completed scopes.
        for (AstScope* const scopep : m_scopes) scopep->modp()->addStmtsp(scopep);
        // Classes are not per instance, so their descriptors are under the root
        for (AstRtmdHier* const levelp : m_classRtmdps) {
            nodep->topScopep()->rtmdp()->addItemsp(levelp);
        }
        if (v3Global.opt.mtasks()) V3Control::applyThreadsGroupWorkers(m_scopes);
        cleanupVarRefs();
        if (!m_programInitials.empty()) makeProgramFinish(nodep->topScopep());
    }
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_vpiBlocksp);
        VL_RESTORER(m_assertCtlCallerp);
        m_assertCtlCallerp = takeAssertCtlChildp(m_aboveCellp, m_aboveScopep);
        // Create required blocks and add to module
        string scopename;
        if (!m_aboveScopep) {
            scopename = "TOP";
        } else {
            scopename = m_aboveScopep->name() + "." + m_aboveCellp->name();
            // The top modules are directly under 'TOP'
            if (m_aboveScopep->isTop() && VN_IS(nodep, Module)) {
                v3Global.rootp()->addL2Name(AstNode::prettyName(m_aboveCellp->name()));
            }
        }

        UINFO(4, " MOD AT " << scopename << "  " << nodep);
        AstNode::user1ClearTree();

        m_scopep = new AstScope{
            (m_aboveCellp ? static_cast<AstNode*>(m_aboveCellp) : static_cast<AstNode*>(nodep))
                ->fileline(),
            nodep, scopename, m_aboveScopep, m_aboveCellp};
        if (VN_IS(nodep, Package)) m_classOrPackageScopes.emplace(nodep, m_scopep);

        // Get list of cells before we edit, to avoid excess visits (issue #6059)
        std::deque<AstCell*> cells;
        for (AstNode* const cellnextp : nodep->stmtspList()) {
            if (AstCell* const cellp = VN_CAST(cellnextp, Cell)) cells.push_back(cellp);
        }

        // Now for each child cell, iterate the module this cell points to
        for (AstCell* const cellp : cells) {
            VL_RESTORER(m_scopep);  // Protects m_scopep set in called module
            // which is "above" in this code, but later in code execution order
            VL_RESTORER(m_aboveCellp);
            VL_RESTORER(m_aboveScopep);
            {
                m_aboveCellp = cellp;
                m_aboveScopep = m_scopep;
                AstNodeModule* const modp = cellp->modp();
                UASSERT_OBJ(modp, cellp, "Unlinked mod");
                iterate(modp);  // Recursive call to visit(AstNodeModule)
                // The top interface's structural identity is no longer needed.
                if (cellp->assertCtlIfaceOriginp()) cellp->assertCtlIfaceOriginp(nullptr);
                // Remember newly created scope
                cellp->user2p(m_scopep);
            }
        }

        // Create scope for the current usage of this module
        UINFO(4, " back AT " << scopename << "  " << nodep);
        AstNode::user1ClearTree();
        m_modp = nodep;
        if (v3Global.opt.vpi()) m_vpiBlocksp = &vpiBlocks(nodep);
        if (m_modp->isTop()) {
            v3Global.rootp()->createTopScope(m_scopep);
        } else {
            m_scopes.push_back(m_scopep);
        }

        // Copy blocks into this scope
        {
            VL_RESTORER(m_last);
            const uint64_t nInsts = nodep->user3();
            UASSERT_OBJ(nInsts, nodep, "Module scoped more times than instantiated");
            nodep->user3(nInsts - 1);
            m_last = nInsts == 1;
            iterateChildren(nodep);
        }

        // ***Note m_scopep is passed back to the caller of the routine (above)
    }
    void visit(AstClass* nodep) override {
        // The scope of the first instance of the containing module serves all instances
        if (m_classOrPackageScopes.count(nodep)) return;
        if (!m_last) {
            // V3Param copies a module per instance for such a reference, but not an
            // interface, as a virtual interface may refer to any instance
            if (const AstNode* const refp = nodep->instanceStateRefp()) {
                const AstNodeVarRef* const varrefp = VN_CAST(refp, NodeVarRef);
                if (VN_IS(refp, AssertCtlApply)
                    || (varrefp && varrefp->varp() && varrefp->varp()->assertCtlMask())) {
                    refp->v3warn(E_UNSUPPORTED,
                                 "Unsupported: Instance-dependent assertion control in a class of "
                                     << m_modp->verilogKwd() << " " << m_modp->prettyNameQ()
                                     << " instantiated more than once.");
                } else {
                    refp->v3warn(E_UNSUPPORTED, "Unsupported: Class referencing "
                                                    << refp->prettyNameQ() << " of "
                                                    << m_modp->verilogKwd() << " "
                                                    << m_modp->prettyNameQ()
                                                    << " instantiated more than once");
                }
            }
        }
        // Create required blocks and add to module
        VL_RESTORER(m_scopep);
        VL_RESTORER(m_aboveCellp);
        VL_RESTORER(m_aboveScopep);
        VL_RESTORER(m_modp);
        m_aboveScopep = m_scopep;
        m_modp = nodep;

        string scopename;
        if (!m_aboveScopep) {
            scopename = "TOP";
        } else {
            scopename = m_aboveScopep->name() + "." + nodep->name();
        }

        UINFO(4, " CLASS AT " << scopename << "  " << nodep);
        AstNode::user1ClearTree();

        const AstNode* const abovep
            = (m_aboveCellp ? static_cast<AstNode*>(m_aboveCellp) : static_cast<AstNode*>(nodep));
        m_scopep
            = new AstScope{abovep->fileline(), m_modp, scopename, m_aboveScopep, m_aboveCellp};
        m_classOrPackageScopes.emplace(nodep, m_scopep);

        // Create scope for the current usage of this cell
        AstNode::user1ClearTree();
        m_scopes.push_back(m_scopep);

        iterateChildren(nodep);
    }
    void visit(AstCellInline* nodep) override {  //
        if (!m_vpiBlocksp || !m_vpiBlocksp->count(nodep->name())) return;
        m_scopep->addInlinesp(
            new AstCellInlineScope{nodep->fileline(), nodep->name(), nodep->origModName()});
    }
    void visit(AstActive* nodep) override {  // LCOV_EXCL_LINE
        nodep->v3fatalSrc("Actives now made after scoping");
    }
    void visit(AstAssertCtlApply* nodep) override {
        if (const AstAssertCtlPlan* const planp = nodep->planp()) {
            UASSERT_OBJ(m_assertCtlCallerp, nodep, "Assertion selector lost its caller scope");
            AssertCtlPlanIndex& index = m_assertCtlPlans.at(planp);
            const auto found = index.byCaller.find(m_assertCtlCallerp);
            UASSERT_OBJ(found != index.byCaller.end(), nodep,
                        "Assertion selector plan has no route for this caller");
            AssertCtlCallerRoutes& caller = found->second;
            ++caller.uses;
            UASSERT_OBJ(caller.uses <= index.sourceUses, nodep,
                        "Assertion selector plan materialized too many times for this caller");
            nodep->targetSetp(shareAssertionTargets(nodep, index, caller.cohorts));
            const AssertCtlRoutes& local = caller.routes;
            auto a = index.common.begin();
            auto b = local.begin();
            while (a != index.common.end() || b != local.end()) {
                const bool common
                    = b == local.end() || (a != index.common.end() && a->first < b->first);
                const AstAssertCtlTargetSet* const setp = common ? (a++)->second : (b++)->second;
                if (AstAssertCtlTarget* const targetsp = setp->targetsp()) {
                    nodep->addTargetsp(targetsp->cloneTree(true));
                }
            }
            nodep->planp(nullptr);
        }
        if (AstAssertCtlTargetSet* const setp = nodep->targetSetp()) setp->user3(true);
        iterateChildren(nodep);
    }
    void visit(AstNodeProcedure* nodep) override {
        // Add to list of blocks under this scope
        // Check don't miss varref scope assignments
        UASSERT_OBJ(!m_procedurep, nodep, "prodedure in procedure");
        VL_RESTORER(m_procedurep);
        m_procedurep = nodep;
        UINFO(4, "    Move " << nodep);
        AstNodeProcedure* const clonep = cloneOrMove(nodep);
        AstInitial* const initialp = VN_CAST(clonep, Initial);
        const AstModule* const modp = VN_CAST(m_modp, Module);
        // Initial blocks created internally, e.g. from a constant continuous assignment, are
        // not initial procedures for IEEE 1800-2023 24.7
        if (initialp && initialp->fromSource() && modp && modp->isProgram()) {
            m_programInitials.emplace_back(initialp, m_scopep);
        }
        // We iterate under the *clone*
        iterateChildren(clonep);
    }
    void visit(AstAlias* nodep) override {
        // Add to list of blocks under this scope
        UINFO(4, "    Move " << nodep);
        // We iterate under the *clone*
        iterateChildren(cloneOrMove(nodep));
    }
    void visit(AstAliasScope* nodep) override {
        // Copy under the scope but don't recurse
        UINFO(4, "    Move " << nodep);
        // We iterate under the *clone*
        iterateChildren(cloneOrMove(nodep));
    }
    void visit(AstRtmdHier* nodep) override {
        // The level of an instance, spliced in after its instance entry,
        // was iterated already when the instance was scoped
        if (nodep->user2()) return;

        // A hierarchy level within the descriptor of a module (e.g. block/function/etc.)
        if (nodep != m_modp->rtmdp()) {
            iterateChildren(nodep);
            return;
        }

        // A class has a single scope, so its descriptor is moved, then placed at the root
        if (VN_IS(m_modp, Class)) {
            nodep->unlinkFrBack();
            iterateChildren(nodep);
            m_classRtmdps.push_back(nodep);
            return;
        }

        // The descriptor of the module itself
        AstRtmdHier* const clonep = m_last ? nodep->unlinkFrBack() : nodep->cloneTree(false);
        // Iterate under the *clone*, which inlines the descriptors of sub-instances
        iterateChildren(clonep);

        // The descriptor of the top scope is the root, all others were inlined into it
        if (m_modp->isTop()) {
            v3Global.rootp()->topScopep()->rtmdp(clonep);
            return;
        }

        // The instance entry in the parent inlines it
        clonep->user2(true);
        m_scopep->rtmdp(clonep);
    }
    void visit(AstRtmdInstance* nodep) override {
        // Inline the Rtmd of the instance after this descriptor
        AstRtmdHier* const levelp = VN_AS(nodep->cellp()->user2p(), Scope)->rtmdp();
        nodep->addNextHere(levelp);
        // It's independent of the cell from here on
        nodep->cellp(nullptr);
    }
    void visit(AstCFunc* nodep) override {
        // Add to list of blocks under this scope
        UINFO(4, "    CFUNC " << nodep);
        AstCFunc* const clonep = cloneOrMove(nodep);
        clonep->scopep(m_scopep);
        // We iterate under the *clone*
        iterateChildren(clonep);
    }
    void visit(AstNodeFTask* nodep) override {
        // Add to list of blocks under this scope
        UINFO(4, "    FTASK " << nodep);
        AstNodeFTask* const clonep = [&]() {
            VL_RESTORER(m_last);
            // Only one scope will be created, so avoid pointless cloning
            if (nodep->classMethod()) m_last = true;
            return cloneOrMove(nodep);
        }();
        clonep->user2p(clonep);  // For recursive self-references after cloneTree
        // We iterate under the *clone*
        iterateChildren(clonep);
    }
    void visit(AstVar* nodep) override {
        // Make new scope variable
        if (!nodep->user1p()) {
            AstScope* scopep = m_scopep;
            if (const AstIfaceRefDType* const ifrefp = VN_CAST(nodep->dtypep(), IfaceRefDType)) {
                // Attach every non-virtual interface variable its inner scope
                if (ifrefp->cellp()) scopep = VN_AS(ifrefp->cellp()->user2p(), Scope);
            }
            AstVarScope* const varscp = new AstVarScope{nodep->fileline(), scopep, nodep};
            UINFO(6, "   New scope " << varscp);
            if (m_aboveCellp && !m_aboveCellp->isTrace()) varscp->trace(false);
            nodep->user1p(varscp);
            UASSERT_OBJ(m_scopep, nodep, "No scope for var");
            m_varScopes.emplace(std::make_pair(nodep, m_scopep), varscp);
            m_scopep->addVarsp(varscp);
        }
        iterateChildren(nodep);
    }
    void visit(AstVarRef* nodep) override {
        // VarRef needs to point to VarScope
        // Make sure variable has made user1p.
        UASSERT_OBJ(nodep->varp(), nodep, "Unlinked");
        // We may have not made the variable yet, and we can't make it now as
        // the var's referenced package etc might not be created yet.
        // So push to a list and post-correct.
        // No check here for nodep->classOrPackagep(), will check when walk list.
        m_varRefScopes.emplace_back(nodep, m_scopep);
    }
    void visit(AstScopeName* nodep) override {
        // If there's a %m in the display text, we add a special node that will contain the name()
        const string prefix = "__DOT__"s + m_scopep->name();
        // TOP and above will be the user's name().
        // Note 'TOP.' is stripped by scopePrettyName
        // To keep correct visual order, must add before existing
        nodep->scopeAttr(prefix + nodep->scopeAttr());
        nodep->scopeEntr(prefix + nodep->scopeEntr());
        iterateChildren(nodep);
    }
    void visit(AstScope* nodep) override {
        UASSERT_OBJ(nodep->isTop(), nodep,
                    "Non-top scopes must remain detached until all instances are scoped");
    }
    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit ScopeVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~ScopeVisitor() override = default;
};

//######################################################################
// Scope cleanup -- remove unused activates

class ScopeCleanupVisitor final : public VNVisitor {
    // STATE
    AstScope* m_scopep = nullptr;  // Current scope we are building

    // METHODS

    // VISITORS
    void visit(AstScope* nodep) override {
        // Want to ignore blocks under it
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        iterateChildren(nodep);
    }

    virtual void movedDeleteOrIterate(AstNode* nodep) {
        if (m_scopep) {
            // The new block; repair varrefs
            iterateChildren(nodep);
        } else {
            // A block that was just moved under a scope, Kill it.
            // Certain nodes can be referenced later in this pass, notably
            // an FTaskRef needs to access the FTask to find the cloned task
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
        }
    }

    void visit(AstAssertCtlCaller*) override {}  // Structural selector identity
    void visit(AstAssertCtlPlan*) override {}  // Prototype targets are not scoped code
    void visit(AstNodeProcedure* nodep) override { movedDeleteOrIterate(nodep); }
    void visit(AstAlias* nodep) override { movedDeleteOrIterate(nodep); }
    void visit(AstAliasScope* nodep) override { movedDeleteOrIterate(nodep); }
    void visit(AstRtmdHier*) override {}  // Nothing to clean up in descriptors
    void visit(AstNodeFTask* nodep) override { movedDeleteOrIterate(nodep); }
    void visit(AstCFunc* nodep) override { movedDeleteOrIterate(nodep); }

    void visit(AstVarXRef* nodep) override {
        // The crossrefs are dealt with in V3LinkDot. An assertion control site that might be
        // of another elaboration keeps its variable, which V3LinkDot checks it binds to.
        if (!nodep->assertCtlOptional()) nodep->varp(nullptr);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        // The crossrefs are dealt with in V3LinkDot
        UINFO(9, "   Old pkg-taskref " << nodep);
        if (nodep->classOrPackagep()) {
            // Point to the clone
            UASSERT_OBJ(nodep->taskp(), nodep, "Unlinked");
            AstNodeFTask* const newp = VN_AS(nodep->taskp()->user2p(), NodeFTask);
            UASSERT_OBJ(newp, nodep, "No clone for package function");
            nodep->taskp(newp);
            UINFO(9, "   New pkg-taskref " << nodep);
        } else if (!VN_IS(nodep, MethodCall)) {
            nodep->taskp(nullptr);
            VIsCached::clearCacheTree();
            UINFO(9, "   New pkg-taskref " << nodep);
        }
        iterateChildren(nodep);
    }
    void visit(AstModportFTaskRef* nodep) override {
        // The modport persists only for JSON dump
        // The crossrefs are dealt with in V3LinkDot
        nodep->ftaskp(nullptr);
        iterateChildren(nodep);
    }

    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit ScopeCleanupVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~ScopeCleanupVisitor() override = default;
};

//######################################################################
// Scope class functions

void V3Scope::scopeAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    {
        const ScopeVisitor visitor{nodep};
        ScopeCleanupVisitor{nodep};
    }  // Destruct before checking
    if (v3Global.hasAssertCtlReads()) {
        UASSERT_OBJ(!nodep->exists([](const AstAssertCtlApply* applyp) {
            return applyp->planp() != nullptr;
        }),
                    nodep, "Unconsumed assertion selector plan");
        VNDeleter metadata;
        for (AstNode* const miscp : nodep->miscspList()) {
            if (VN_IS(miscp, AssertCtlCaller) || VN_IS(miscp, AssertCtlPlan)) {
                VL_DO_DANGLING(metadata.pushDeletep(miscp->unlinkFrBack()), miscp);
            }
        }
    }
    V3ConstPool::setScoped();
    V3Global::dumpCheckGlobalTree("scope", 0, dumpTreeEitherLevel() >= 3);
}
