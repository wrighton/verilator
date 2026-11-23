// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Code scheduling
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
// V3Sched::schedule is the top level entry-point to the scheduling algorithm
// at a high level, the process is:
//
//  - Gather and classify all logic in the design based on what triggers its execution
//  - Schedule static, initial and final logic classes in source order
//  - Break combinational cycles by introducing hybrid logic
//  - Create 'settle' region that restores the combinational invariant
//  - Partition the clocked and combinational (including hybrid) logic into pre/act/nba.
//    All clocks (signals referenced in an AstSenTree) generated via a blocking assignment
//    (including combinationally generated signals) are computed within the act region.
//  - Replicate combinational logic
//  - Create input combinational logic region
//  - Create the pre/act/nba triggers
//  - Create the 'act' region evaluation function
//  - Create the 'nba' region evaluation function
//
// The loops iterating these regions are not generated. They live in the
// run-time (VerilatedEvalLoop), which invokes the region evaluation
// functions created here on the generated model.
//
// Details of the algorithm are described in the internals documentation docs/internals.rst
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Sched.h"

#include "V3Const.h"
#include "V3EmitCBase.h"
#include "V3EmitV.h"
#include "V3Order.h"
#include "V3SenExprBuilder.h"
#include "V3Stats.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

namespace {

//============================================================================
// Utility functions

std::vector<const AstSenTree*>
getSenTreesUsedBy(const std::vector<const ProcessList*>& procListps) {
    const VNUser1InUse user1InUse;
    std::vector<const AstSenTree*> result;
    for (const ProcessList* const procListp : procListps) {
        for (const Process& process : *procListp) {
            AstSenTree* const senTreep = process.m_senTreep;
            if (senTreep->user1SetOnce()) continue;
            if (senTreep->hasClocked() || senTreep->hasHybrid()) result.push_back(senTreep);
        }
    }
    return result;
}

void addTriggerIndices(ProcessList& procList, const TriggerKit& trigKit, bool pre) {
    for (const Process& process : procList) {
        AstSenTree* const senTreep = process.m_senTreep;
        if (senTreep->hasCombo()) continue;
        procList.triggers(senTreep, trigKit.triggerIndices(senTreep, pre));
    }
}

// Add the VIF triggers that a given VarScope should be sensitive to.
// Case 2 (non-virtual interface read): sensitive to that specific VarScope's trigger only
// Case 3 (virtual interface read): also to all member triggers of the interface types it reaches
void addTriggeredIface(const AstVarScope* vscp, const VirtIfaceTriggers::VscpTrigMap& vscpToTrig,
                       const VirtIfaceTriggers& virtIfaceTriggers, std::set<uint32_t>& triggers) {
    // Interface member -- sensitive to this VarScope's trigger. This includes a virtual interface
    // variable that is itself an interface member written through a virtual interface.
    const auto ownIt = vscpToTrig.find(vscp);
    if (ownIt != vscpToTrig.end()) triggers.insert(ownIt->second);
    if (vscp->varp()->isVirtIface()) {
        // Virtual interface variable -- sensitive to all member triggers of this interface type,
        // and of the interface types of its virtual interface members, e.g. for 'vif.sub_vif.x'
        const std::set<const AstIface*> ifaceps = virtIfaceTriggers.reachableIfaces(
            VN_AS(vscp->varp()->dtypep()->skipRefp(), IfaceRefDType)->ifacep());
        for (const auto& entry : virtIfaceTriggers.m_triggers) {
            if (ifaceps.count(entry.m_ifacep)) {
                const auto it = vscpToTrig.find(entry.m_vscp);
                if (it != vscpToTrig.end()) triggers.insert(it->second);
            }
        }
    }
    // May add none if sensIfacep() is set but no VIF write targets this member
}

//============================================================================
// Eval region builder

// Create the evaluation function of a scheduling region. The loops iterating
// the regions live in the run-time library (see VerilatedEvalLoop), which
// invokes this function once per iteration of the region's loop via a virtual
// method on the model (see V3EmitCModel). The function returns true if the
// region did any work, in which case the loop iterates again.
void createEvalRegion(
    AstNetlist* netlistp,  //
    VEval eval,  // The entry point of the current region
    // Index of the region's 'first iteration' extra trigger, if it has one, otherwise ignored
    uint32_t firstIterTrigger,
    const TriggerKit& trigKit,  // The trigger kit
    AstVarScope* trigp,  // The trigger vector - may be nullptr if no triggers or using 'condp'
    AstNodeExpr* condp,  // Explicit condition that must be true to run 'phaseWorkp'
    AstNodeStmt* phasePrepp,  // Prep statements run before checking triggers
    AstNodeStmt* phaseWorkp  // The work to do if anything triggered
) {
    UASSERT(!trigp || !condp, "Cannot use both 'trigp' and 'condp' in 'createEvalRegion'");
    UASSERT(!eval.firstIteration() || trigp,
            "Region without triggers cannot need a first iteration flag");

    // All work is under a trigger or condition, so with neither the region has
    // nothing to evaluate, and what we create below reduces to a no-op function.

    const std::string tag = eval.tag();
    AstTopScope* const topScopep = netlistp->topScopep();
    FileLine* const flp = netlistp->fileline();

    // Populate the trigger dump entry point function
    if (trigp) {
        netlistp->dumpTriggersFuncp(eval)->addStmtsp(trigKit.newDumpCall(trigp, tag, false));
    }

    AstCFunc* const funcp = netlistp->evalFuncp(eval);

    // A flag is passed from the run-time eval loop if this is the first iteration of the
    // current loop
    if (eval.firstIteration()) {
        AstVarScope* const firstIterArgp = util::newArgument(funcp, netlistp->findBitDType(),
                                                             "firstIteration", VDirection::INPUT);

        // Set the region's 'first iteration' trigger straight from the argument
        funcp->addStmtsp(trigKit.newExtraTriggerAssignment(firstIterArgp, firstIterTrigger));

        // Only 'stl' also needs a module level flag, for design logic that reads
        // it directly (see V3Timing). Those reads can be anywhere in the design,
        // hence module level. Always created, even if nothing reads it.
        // TODO: get rid of this special case
        if (eval == VEval::STL) {
            AstVarScope* const firstIterp = netlistp->stlFirstIterationp();
            firstIterp->varp()->noReset(true);
            firstIterp->varp()->isInternal(true);
            funcp->addStmtsp(new AstAssign{flp, new AstVarRef{flp, firstIterp, VAccess::WRITE},
                                           new AstVarRef{flp, firstIterArgp, VAccess::READ}});
        }
    }

    {
        // Add the preparatory statements
        funcp->addStmtsp(phasePrepp);

        // The execute flag
        AstVarScope* const executeFlagp = topScopep->createTemp("__V" + tag + "Execute", 1);
        executeFlagp->varp()->noReset(true);

        // If there is work in this region, execute it if any triggers fired
        if (phaseWorkp) {
            AstNodeExpr* const lhsp = new AstVarRef{flp, executeFlagp, VAccess::WRITE};
            // If using explicit condition, that directly determines whether to execute,
            // otherwise check if any triggers are fired
            AstNodeExpr* const rhsp = condp ? condp : trigKit.newAnySetCall(trigp);
            funcp->addStmtsp(new AstAssign{flp, lhsp, rhsp});

            // Add the work
            AstIf* const ifp = new AstIf{flp, new AstVarRef{flp, executeFlagp, VAccess::READ}};
            ifp->addThensp(phaseWorkp);
            funcp->addStmtsp(ifp);
        }

        // The function returns true iff it did run work
        AstNodeExpr* const retp
            = phaseWorkp
                  ? static_cast<AstNodeExpr*>(new AstVarRef{flp, executeFlagp, VAccess::READ})
                  : static_cast<AstNodeExpr*>(new AstConst{flp, AstConst::BitFalse{}});
        funcp->addStmtsp(new AstCReturn{flp, retp});
    }
}

//============================================================================
// Collect and classify all logic in the design

// Whether a process commits the Re-NBAs (see V3Delayed), post logic of the reactive region
bool isReNbaCommit(const AstNetlist* netlistp, const AstNodeProcedure* procp) {
    const AstAlwaysPost* const postp = VN_CAST(procp, AlwaysPost);
    const AstNbaCommit* const commitp = postp ? VN_CAST(postp->stmtsp(), NbaCommit) : nullptr;
    return commitp && commitp->queuep()->varScopep() == netlistp->reNbaQueuep();
}

LogicClasses gatherLogicClasses(AstNetlist* netlistp) {
    LogicClasses result;
    VNDeleter deleter;  // Deletes the AstActives once their processes are moved

    netlistp->foreach([&](AstScope* scopep) {
        scopep->foreach([&](AstActive* activep) {
            AstSenTree* const senTreep = activep->sentreep();
            ProcessList* logicClassp = nullptr;
            if (senTreep->hasStatic()) {
                UASSERT_OBJ(!senTreep->sensesp()->nextp(), activep,
                            "static initializer with additional sensitivities");
                logicClassp = &result.m_static;
            } else if (senTreep->hasInitial()) {
                UASSERT_OBJ(!senTreep->sensesp()->nextp(), activep,
                            "'initial' logic with additional sensitivities");
                logicClassp = &result.m_initial;
            } else if (senTreep->hasFinal()) {
                UASSERT_OBJ(!senTreep->sensesp()->nextp(), activep,
                            "'final' logic with additional sensitivities");
                logicClassp = &result.m_final;
            } else if (senTreep->hasCombo()) {
                UASSERT_OBJ(!senTreep->sensesp()->nextp(), activep,
                            "combinational logic with additional sensitivities");
                if (activep->isPostponed()) {
                    UASSERT_OBJ(!activep->procsp()->nextp(), activep,
                                "AlwaysPostponed must be alone under its active");
                    logicClassp = &result.m_postponed;
                } else {
                    logicClassp = &result.m_comb;
                }
            } else {
                UASSERT_OBJ(senTreep->hasClocked(), activep, "What else could it be?");
                if (VN_IS(activep->procsp(), AlwaysObserved)) {
                    logicClassp = &result.m_observed;
                } else if (VN_IS(activep->procsp(), AlwaysReactive)
                           || isReNbaCommit(netlistp, activep->procsp())) {
                    logicClassp = &result.m_reactive;
                } else {
                    logicClassp = &result.m_clocked;
                }
            }
            // Move the processes to their class, the AstActive is no longer needed
            while (AstNodeProcedure* const procp = activep->procsp()) {
                procp->unlinkFrBack();
                // Only combinational logic has implicit sensitivities
                std::unordered_set<const AstVarScope*> implicitSensitivities;
                if (senTreep->hasCombo()) {
                    implicitSensitivities = util::computeImplicitSensitivities(procp);
                }
                logicClassp->add({scopep, senTreep, procp, std::move(implicitSensitivities)});
            }
            VL_DO_DANGLING(deleter.pushDeletep(activep->unlinkFrBack()), activep);
        });
    });

    return result;
}

//============================================================================
// Simple ordering in source order

void orderSequentially(AstCFunc* funcp, ProcessList& procList) {
    // Create new subfunc for scope
    const auto createNewSubFuncp = [&](AstScope* const scopep) {
        const string subName{funcp->name() + "__" + scopep->nameDotless()};
        AstCFunc* const subFuncp = new AstCFunc{scopep->fileline(), subName, scopep};
        subFuncp->isLoose(true);
        subFuncp->isConst(false);
        subFuncp->declPrivate(true);
        subFuncp->slow(funcp->slow());
        scopep->addBlocksp(subFuncp);
        // Call it from the top function
        funcp->addStmtsp(util::callVoidFunc(subFuncp));
        return subFuncp;
    };
    const VNUser1InUse user1InUse;  // AstScope -> AstCFunc: the sub-function for the scope
    const VNUser2InUse user2InUse;  // AstScope -> int: sub-function counter used for names
    for (const Process& process : procList) {
        AstScope* const scopep = process.m_scopep;
        AstNodeProcedure* const procp = process.m_procp;
        // Create a sub-function per scope so we can V3Combine them later
        if (!scopep->user1p()) scopep->user1p(createNewSubFuncp(scopep));
        // Add statements to sub-function
        auto* subFuncp = VN_AS(scopep->user1p(), CFunc);
        if (AstNodeStmt* const bodyp = procp->stmtsp()) {
            bodyp->unlinkFrBackWithNext();
            // If the process is suspendable, we need a separate function (a coroutine)
            if (procp->isSuspendable()) {
                funcp->slow(false);
                subFuncp = createNewSubFuncp(scopep);
                subFuncp->name(subFuncp->name() + "__Vtiming__" + cvtToStr(scopep->user2Inc()));
                subFuncp->rtnType("VlCoroutine");
            }
            subFuncp->addStmtsp(bodyp);
            if (procp->needsVlProcess()) subFuncp->setNeedsVlProcess();
            // A coroutine holds a single process, so it is complete here
            if (procp->isSuspendable()) util::splitCheck(subFuncp);
        }
    }
    // Split sub-functions once complete
    for (const Process& process : procList) {
        AstScope* const scopep = process.m_scopep;
        if (AstCFunc* const subFuncp = VN_AS(scopep->user1p(), CFunc)) {
            util::splitCheck(subFuncp);
            scopep->user1p(nullptr);
        }
    }
    procList.deleteProcesses();
}

//============================================================================
// Create simply ordered functions

AstCFunc* createStatic(AstNetlist* netlistp, LogicClasses& logicClasses) {
    AstCFunc* const funcp = netlistp->evalFuncp(VEval::STATIC);

    // Level-based module sorting can reorder packages so that an importing
    // package runs before the imported one.  Re-sort package entries by source
    // file position to restore compilation order (IEEE 1800-2023 26.3).
    ProcessList& procList = logicClasses.m_static;
    std::stable_sort(procList.begin(), procList.end(), [](const Process& a, const Process& b) {
        const AstNodeModule* const modAp = a.m_scopep->modp();
        const AstNodeModule* const modBp = b.m_scopep->modp();
        const bool isPkgA = VN_IS(modAp, Package);
        const bool isPkgB = VN_IS(modBp, Package);
        if (isPkgA != isPkgB) return isPkgA;  // Packages before non-packages
        if (isPkgA && isPkgB) {
            // Sort packages by source file position (compilation order)
            return modAp->fileline()->operatorCompare(*modBp->fileline()) < 0;
        }
        return false;  // Both non-package: preserve original order
    });

    orderSequentially(funcp, procList);
    return funcp;  // Not splitting yet as it is not final
}

void createInitial(AstNetlist* netlistp, LogicClasses& logicClasses) {
    AstCFunc* const funcp = netlistp->evalFuncp(VEval::INITIAL);
    orderSequentially(funcp, logicClasses.m_initial);
    util::splitCheck(funcp);
}

void createPostponed(AstNetlist* netlistp, LogicClasses& logicClasses) {
    AstCFunc* const funcp = netlistp->evalFuncp(VEval::POSTPONED);
    orderSequentially(funcp, logicClasses.m_postponed);
    util::splitCheck(funcp);
}

void createFinal(AstNetlist* netlistp, LogicClasses& logicClasses) {
    AstCFunc* const funcp = netlistp->evalFuncp(VEval::FINAL);
    orderSequentially(funcp, logicClasses.m_final);
    util::splitCheck(funcp);
}

//============================================================================
// Helper that creates virtual interface value-change triggers

void addVirtIfaceTriggerAssignments(AstNetlist* netlistp, AstCFunc* initFuncp,
                                    const VirtIfaceTriggers& virtIfaceTriggers,
                                    uint32_t firstIndex, const TriggerKit& trigKit) {
    uint32_t index = firstIndex;
    for (const auto& entry : virtIfaceTriggers.m_triggers) {
        trigKit.addValueChangeTriggerAssignment(netlistp, initFuncp, entry.m_vscp, index);
        ++index;
    }
}

// Order the combinational logic to create the 'stl' region
void createSettle(AstNetlist* netlistp, AstCFunc* const initFuncp, SenExprBuilder& senExprBulider,
                  LogicClasses& logicClasses, const CovergroupRefBindings& cgRefBindings) {
    // Clone, because ordering is destructive, but we still need them for the other regions
    ProcessList comb = logicClasses.m_comb.clone();
    ProcessList hybrid = logicClasses.m_hybrid.clone();

    // We have an extra trigger denoting this is the first iteration of the settle loop
    TriggerKit::ExtraTriggers extraTriggers;
    const uint32_t firstIterationTrigger = extraTriggers.allocate("first iteration");

    // Gather the relevant sensitivity expressions and create the trigger kit
    const auto& senTreeps = getSenTreesUsedBy({&comb, &hybrid});
    const TriggerKit trigKit = TriggerKit::create(netlistp, initFuncp, senExprBulider, {},
                                                  senTreeps, "stl", extraTriggers, true, false);
    util::splitCheck(trigKit.compBasep());

    // Add trigger indices (comb has none, so only do the hybrid)
    addTriggerIndices(hybrid, trigKit, false);

    // First trigger is for pure combinational triggers (first iteration)
    const uint32_t inputChanged = trigKit.extraTriggerIndex(firstIterationTrigger);

    // Create and the body function
    AstCFunc* const stlFuncp = V3Order::order(
        {&comb, &hybrid}, trigKit, trigKit.vscp(), cgRefBindings, "stl", false, true,
        [=](const AstVarScope*, std::set<uint32_t>& triggers) { triggers.insert(inputChanged); });
    util::splitCheck(stlFuncp);

    // Create the region evaluation function
    createEvalRegion(  //
        netlistp, VEval::STL, firstIterationTrigger, trigKit,
        // Use trigger
        trigKit.vscp(), nullptr,
        // Explicit condition
        // Prep statements: Compute the current 'stl' triggers
        [&trigKit] {
            AstNodeStmt* const stmtp = trigKit.newCompBaseCall();
            if (stmtp) stmtp->addNext(trigKit.newDumpCall(trigKit.vscp(), trigKit.name(), true));
            return stmtp;
        }(),
        // Work statements: Invoke the 'stl' function
        util::callVoidFunc(stlFuncp));
}

//============================================================================
// Order the replicated combinational logic to create the 'ico' region

// Change detection of the public read-write variables read by 'ico' logic, in place of the 'first
// iteration' trigger of their readers, with -fico-public-change-detect. A variable triggers if it
// differs from its value at the previous trigger computation, which catches any write in between,
// or if a flag set at the end of the previous evaluation records that it then differed from that
// value or from its value at the start of that evaluation, so a later write restoring either value
// is still seen. The value written by 'ico' logic, which its readers follow, counts as seen, and
// as the value at the start.
struct IcoPublicChangeDetect final {
    AstCFunc* m_updatep = nullptr;  // Takes the values after each trigger computation
    AstCFunc* m_seenp = nullptr;  // Takes the values written by 'ico' logic after it runs
    AstCFunc* m_endp = nullptr;  // Sets the flags at the end of an evaluation
    AstCFunc* m_startp = nullptr;  // Takes the values at the start of an evaluation
    AstCFunc* m_nowp = nullptr;  // Takes the time before each trigger computation
    AstVarScope* m_atStartp = nullptr;  // Set until the first trigger computation of an evaluation
};

// Whether the formatting may format a time (%t), or has a format only known at run time
bool icoFormatsTime(const AstSFormatF* fmtp) {
    if (fmtp->exprFormat()) return true;
    bool inPct = false;
    for (const char ch : fmtp->text()) {
        if (!inPct) {
            inPct = ch == '%';
        } else if (!std::isdigit(ch) && ch != '.' && ch != '-') {
            if (std::tolower(ch) == 't') return true;
            inPct = false;
        }
    }
    return false;
}

// Whether the node makes the result of logic depend on state that the change detection of the
// variables it reads does not see, so the result can differ between evaluations reading the same
// values. The first group is listed explicitly, as those nodes are pure for optimization
// (isPure()), which only means they have no side effect within one evaluation:
// - random numbers ($random, $urandom, $urandom_range, $dist_*, randomize), drawn from generator
//   state that each call advances;
// - the command line ($test$plusargs, $value$plusargs), which C++ code can extend, and
//   $get_initial_random_seed, which C++ code can change;
// - members of class objects read or written through a handle, also when formatted with the
//   object (%p), and static members of classes, which class methods and C++ code can change
//   without the scheduler seeing it;
// - formatting of the time (%t), which uses the $timeformat settings, unless only displayed,
//   while formatting an object (%p) is hidden state also when only displayed;
// - whether a named event was triggered (.triggered), which is cleared at the start of each
//   evaluation after the time slot it was triggered in.
// C++ expressions pure for optimization, such as the assertion controls, also read state that C++
// code can change; they are judged with the whole logic by icoLogicReadsHiddenState().
// The others are the nodes not pure in their own right rather than through a child, such as a
// call to C++ code (a DPI import not declared pure, $c) or to a function that is not inlined,
// file input and output ($fopen, $fgets, $fwrite, $fdisplay...) and $system, other than outputs
// to the user: a display to the standard output, $stop or $finish, and queueing the report of a
// deferred assertion, with the push and clear of the queue the scheduler does not consider
// written. The time is handled separately, by change detected temporaries. The kinds are listed,
// as no property of a node tells whether it reads state outside the variables of the design.
bool icoReadsHiddenState(AstNode* nodep) {
    if (VN_IS(nodep, Rand) || VN_IS(nodep, RandRNG) || VN_IS(nodep, URandomRange)
        || VN_IS(nodep, NodeDistBiop) || VN_IS(nodep, NodeDistTriop) || VN_IS(nodep, TestPlusArgs)
        || VN_IS(nodep, ValuePlusArgs) || VN_IS(nodep, GetInitialRandomSeed)) {
        return true;
    }
    if (const AstMemberRef* const refp = VN_CAST(nodep, MemberRef)) {
        // A member of a virtual interface instead has its own triggers
        if (VN_IS(refp->fromp()->dtypep()->skipRefp(), ClassRefDType)) return true;
    }
    if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
        if (refp->varp()->isClassMember()) return true;
    }
    if (const AstToStringN* const strp = VN_CAST(nodep, ToStringN)) {
        if (VN_IS(strp->lhsp()->dtypep()->skipRefp(), ClassRefDType)) return true;
    }
    if (const AstSFormatF* const fmtp = VN_CAST(nodep, SFormatF)) {
        const AstDisplay* const displayp = VN_CAST(fmtp->firstAbovep(), Display);
        if (icoFormatsTime(fmtp) && !(displayp && !displayp->filep())) return true;
    }
    if (const AstCMethodHard* const callp = VN_CAST(nodep, CMethodHard)) {
        if (callp->method() == VCMethod::EVENT_IS_TRIGGERED) return true;
    }
    if (nodep->isPure()) return false;
    for (AstNode* childp : {nodep->op1p(), nodep->op2p(), nodep->op3p(), nodep->op4p()}) {
        for (; childp; childp = childp->nextp()) {
            if (!childp->isPure()) return false;
        }
    }
    if (const AstDisplay* const displayp = VN_CAST(nodep, Display)) {
        return displayp->filep() != nullptr;
    }
    if (VN_IS(nodep, Stop) || VN_IS(nodep, Finish)) return false;
    if (const AstCMethodHard* const callp = VN_CAST(nodep, CMethodHard)) {
        const AstVarRef* const refp = VN_CAST(callp->fromp(), VarRef);
        if (refp
            && (callp->method() == VCMethod::ARRAY_PUSH_BACK
                || callp->method() == VCMethod::DYN_CLEAR)) {
            const AstVar* const varp = refp->varp();
            return !(varp->ignoreSchedWrite() && !varp->processQueue()
                     && VN_IS(varp->dtypep()->skipRefp(), QueueDType));
        }
    }
    return true;
}

// Whether the variable is compiler state the scheduler does not consider written, such as the
// queue of deferred assertion reports
bool icoIsCompilerState(const AstVar* varp) {
    return varp->isInternal() && varp->ignoreSchedWrite();
}

// Whether the node writes a variable that design logic can read, rather than compiler state or
// an event of the compiler that only starts reports (see findIcoReportEvents())
bool icoWritesVariable(const AstNode* nodep,
                       const std::unordered_set<const AstVar*>& reportEvents) {
    return nodep->exists([&](const AstNodeVarRef* refp) {
        const AstVar* const varp = refp->varp();
        return refp->access().isWriteOrRW() && !icoIsCompilerState(varp)
               && !reportEvents.count(varp);
    });
}

// Whether the node takes a value from compiler state, such as a value of a deferred assertion
// report taken from its queue
bool icoTakesCompilerState(const AstNode* nodep) {
    const AstCMethodHard* const callp = VN_CAST(nodep, CMethodHard);
    if (!callp || callp->method() != VCMethod::ARRAY_POP_FRONT) return false;
    const AstVarRef* const refp = VN_CAST(callp->fromp(), VarRef);
    return refp && icoIsCompilerState(refp->varp());
}

// The events of the compiler whose triggering only starts outputs to the user, such as the one
// flushing the queue of deferred assertion reports when every action of those assertions is a
// report: all the logic sensitive to the event writes no variable other than compiler state, does
// nothing hidden other than outputs and operating on compiler state, and only formats the values
// it takes from compiler state, as the impurity of taking them must not hide that of their user.
// The only such events are those V3Assert creates for deferred assertions.
std::unordered_set<const AstVar*> findIcoReportEvents(const LogicRegions& regions) {
    std::unordered_set<const AstVar*> eventps;
    std::unordered_set<const AstVar*> statefulps;
    const auto reportOnly = [](AstNode* logicp) {
        return !logicp->exists([](AstNode* nodep) {
            if (const AstNodeVarRef* const refp = VN_CAST(nodep, NodeVarRef)) {
                return refp->access().isWriteOrRW() && !icoIsCompilerState(refp->varp());
            }
            // A display to a file writes it whatever its operands are. Defensive: such a display
            // is also not pure in its own right, or takes a value checked below
            if (const AstDisplay* const displayp = VN_CAST(nodep, Display)) {
                if (displayp->filep()) return true;
            }
            if (!VN_IS(nodep, SFormatF) && !VN_IS(nodep, SFormatArg)) {
                for (AstNode* childp :
                     {nodep->op1p(), nodep->op2p(), nodep->op3p(), nodep->op4p()}) {
                    for (; childp; childp = childp->nextp()) {
                        if (icoTakesCompilerState(childp)) return true;
                    }
                }
            }
            if (const AstCMethodHard* const callp = VN_CAST(nodep, CMethodHard)) {
                const AstVarRef* const refp = VN_CAST(callp->fromp(), VarRef);
                if (refp && icoIsCompilerState(refp->varp())) return false;
            }
            return icoReadsHiddenState(nodep);
        });
    };
    for (const ProcessList* const listp :
         {&regions.m_pre, &regions.m_act, &regions.m_nba, &regions.m_obs, &regions.m_react}) {
        for (const Process& process : *listp) {
            if (!process.m_senTreep) continue;
            process.m_senTreep->foreach([&](const AstVarRef* refp) {
                const AstVar* const varp = refp->varp();
                const AstBasicDType* const basicp = varp->basicp();
                if (!varp->isInternal() || !basicp || !basicp->isEvent()) return;
                eventps.emplace(varp);
                if (!reportOnly(process.m_procp)) statefulps.emplace(varp);
            });
        }
    }
    for (const AstVar* const varp : statefulps) eventps.erase(varp);
    return eventps;
}

// Whether the logic reads hidden state (see icoReadsHiddenState()). A C++ expression pure for
// optimization reads state that C++ code can change, such as the assertion controls, so is hidden
// state too, unless it only decides whether outputs to the user run: an assertion with only
// reports reports when its logic runs, as other outputs, while one with actions writing variables
// must see the controls in every evaluation. Each If is walked for its writes, which is linear in
// the logic for each level of If nesting, and the logic of an input is small.
bool icoLogicReadsHiddenState(AstNode* logicp,
                              const std::unordered_set<const AstVar*>& reportEvents) {
    std::unordered_set<const AstCExpr*> outputCondps;
    logicp->foreach([&](const AstIf* ifp) {
        if (icoWritesVariable(ifp, reportEvents)) return;
        ifp->condp()->foreach([&](const AstCExpr* exprp) { outputCondps.emplace(exprp); });
    });
    return logicp->exists([&](AstNode* nodep) {
        if (const AstCExpr* const exprp = VN_CAST(nodep, CExpr)) {
            if (!outputCondps.count(exprp)) return true;
        }
        return icoReadsHiddenState(nodep);
    });
}

// Replace the reads of the time in the logic with temporaries taking it before each trigger
// computation, one per kind of read, so the logic reading the time runs when it advanced once
// they are change detected. Returns the temporaries.
std::vector<AstVarScope*> replaceIcoTimeReads(AstNetlist* netlistp, ProcessList& logic,
                                              IcoPublicChangeDetect& result) {
    FileLine* const flp = netlistp->fileline();
    // The kinds of reads are few ($time and $realtime in each time unit), so are searched
    std::vector<std::pair<const AstNodeExpr*, AstVarScope*>> nowVscps;
    for (Process& process : logic) {
        std::vector<AstNodeExpr*> timeps;
        process.m_procp->foreach([&](AstTime* timep) { timeps.push_back(timep); });
        process.m_procp->foreach([&](AstTimeD* timep) { timeps.push_back(timep); });
        for (AstNodeExpr* const timep : timeps) {
            const auto it = std::find_if(nowVscps.begin(), nowVscps.end(), [&](const auto& pair) {
                return timep->sameTree(pair.first);
            });
            AstVarScope* nowp = it == nowVscps.end() ? nullptr : it->second;
            if (!nowp) {
                if (!result.m_nowp) {
                    result.m_nowp = util::makeSubFunction(netlistp, "_ico_public_now", false);
                }
                nowp = netlistp->topScopep()->createTemp(
                    "__VicoPublicNow" + std::to_string(nowVscps.size()), timep->dtypep());
                AstNodeExpr* const valuep = timep->cloneTree(false);
                result.m_nowp->addStmtsp(
                    new AstAssign{flp, new AstVarRef{flp, nowp, VAccess::WRITE}, valuep});
                nowVscps.emplace_back(valuep, nowp);
            }
            timep->replaceWith(new AstVarRef{flp, nowp, VAccess::READ});
            VL_DO_DANGLING(timep->deleteTree(), timep);
            process.m_implicitSen.emplace(nowp);
        }
    }
    std::vector<AstVarScope*> vscps;
    for (const auto& pair : nowVscps) vscps.push_back(pair.second);
    return vscps;
}

// The variables feeding logic whose result depends on hidden state: the ones it reads, and those
// the logic computing them reads. Also collects the variables read by the logic, in order, and
// those it writes.
std::unordered_set<const AstVarScope*> findIcoHiddenStateFed(
    const ProcessList& logic, const std::unordered_set<const AstVar*>& reportEvents,
    std::vector<AstVarScope*>& readVscps, std::unordered_set<const AstVarScope*>& writtenVscps) {
    std::vector<size_t> readStarts;  // Where the reads of each process start in readVscps
    std::unordered_map<const AstVarScope*, std::vector<size_t>> writerIndices;
    std::unordered_set<const AstVarScope*> fedVscps;
    std::vector<const AstVarScope*> pendingVscps;
    for (const Process& process : logic) {
        const size_t index = readStarts.size();
        readStarts.push_back(readVscps.size());
        const bool hidden = icoLogicReadsHiddenState(process.m_procp, reportEvents);
        process.m_procp->foreach([&](const AstVarRef* refp) {
            AstVarScope* const vscp = refp->varScopep();
            if (refp->access().isWriteOrRW()) {
                writerIndices[vscp].push_back(index);
                writtenVscps.emplace(vscp);
            }
            if (refp->access().isReadOrRW()) {
                readVscps.push_back(vscp);
                if (hidden && fedVscps.emplace(vscp).second) pendingVscps.push_back(vscp);
            }
        });
    }
    readStarts.push_back(readVscps.size());
    // Walk back through the processes writing them. Each process and each variable is visited at
    // most once, so this is linear in the number of references.
    std::vector<bool> visited(readStarts.size(), false);
    while (!pendingVscps.empty()) {
        const AstVarScope* const vscp = pendingVscps.back();
        pendingVscps.pop_back();
        const auto it = writerIndices.find(vscp);
        if (it == writerIndices.end()) continue;
        for (const size_t index : it->second) {
            if (visited[index]) continue;
            visited[index] = true;
            for (size_t i = readStarts[index]; i < readStarts[index + 1]; ++i) {
                if (fedVscps.emplace(readVscps[i]).second) pendingVscps.push_back(readVscps[i]);
            }
        }
    }
    return fedVscps;
}

// What the change detection of the public variables needs to know about the logic
struct IcoPublicAnalysis final {
    std::vector<AstVarScope*> m_nowVscps;  // Temporaries replacing the reads of the time
    std::vector<AstVarScope*> m_readVscps;  // Variables read by the logic, in order
    std::unordered_set<const AstVarScope*> m_writtenVscps;  // Variables written by the logic
    // Variables feeding logic whose result depends on hidden state
    std::unordered_set<const AstVarScope*> m_hiddenFedVscps;
};

// Replace the reads of the time in the logic, and find the variables feeding hidden state reads,
// which the change detection of the top level inputs also leaves out
IcoPublicAnalysis analyzeIcoPublic(AstNetlist* netlistp, ProcessList& logic,
                                   const LogicRegions& regions, IcoPublicChangeDetect& result) {
    IcoPublicAnalysis analysis;
    analysis.m_nowVscps = replaceIcoTimeReads(netlistp, logic, result);
    analysis.m_hiddenFedVscps = findIcoHiddenStateFed(
        logic, findIcoReportEvents(regions), analysis.m_readVscps, analysis.m_writtenVscps);
    return analysis;
}

void createIcoPublicChangeDetect(AstNetlist* netlistp, const IcoPublicAnalysis& analysis,
                                 std::unordered_map<const AstVarScope*, AstSenTree*>& var2changedp,
                                 std::vector<AstSenTree*>& senTreeps,
                                 IcoPublicChangeDetect& result) {
    FileLine* const flp = netlistp->fileline();
    AstTopScope* const topScopep = netlistp->topScopep();
    const auto newRead
        = [flp](AstVarScope* vscp) { return new AstVarRef{flp, vscp, VAccess::READ}; };
    const auto newSet = [flp](AstVarScope* vscp, AstNodeExpr* valuep) {
        return new AstAssign{flp, new AstVarRef{flp, vscp, VAccess::WRITE}, valuep};
    };
    const std::vector<AstVarScope*>& nowVscps = analysis.m_nowVscps;
    const std::vector<AstVarScope*>& readVscps = analysis.m_readVscps;
    const std::unordered_set<const AstVarScope*>& writtenVscps = analysis.m_writtenVscps;
    const std::unordered_set<const AstVarScope*>& hiddenFedVscps = analysis.m_hiddenFedVscps;

    V3UniqueNames prevNames{"__VicoPublicPrev"};
    V3UniqueNames startNames{"__VicoPublicStart"};
    V3UniqueNames writtenNames{"__VicoPublicWritten"};
    size_t nPublic = 0;
    std::unordered_set<const AstVarScope*> hiddenVscps;
    // The time temporaries, which only change between evaluations, and the public variables
    std::vector<AstVarScope*> candidateVscps = nowVscps;
    candidateVscps.insert(candidateVscps.end(), readVscps.begin(), readVscps.end());
    for (size_t i = 0; i < candidateVscps.size(); ++i) {
        AstVarScope* const vscp = candidateVscps[i];
        const AstVar* const varp = vscp->varp();
        const bool isNow = i < nowVscps.size();
        if (!isNow) {
            // Not top level ports, which are left to the input change detection, as it handles
            // the ones that can be compared, nor forced variables, as for the inputs
            if (!varp->isSigUserRWPublic() || varp->isPrimaryIO() || varp->isForced()) continue;
            if (!vscp->dtypep()->skipRefp()->isIntegralOrPacked()) continue;
            // Its readers keep the 'first iteration' trigger if it feeds logic whose result
            // depends on hidden state
            if (hiddenFedVscps.count(vscp)) {
                hiddenVscps.emplace(vscp);
                continue;
            }
        }
        const auto pair = var2changedp.emplace(vscp, nullptr);
        if (!pair.second) continue;
        if (!result.m_updatep) {
            result.m_updatep = util::makeSubFunction(netlistp, "_ico_public_update", false);
        }
        AstVarScope* const prevp
            = topScopep->createTemp(prevNames.get(varp->name()), vscp->dtypep());
        result.m_updatep->addStmtsp(newSet(prevp, newRead(vscp)));
        AstNodeExpr* changedp = new AstNeq{flp, newRead(vscp), newRead(prevp)};
        if (!isNow) {
            ++nPublic;
            if (!result.m_endp) {
                result.m_endp = util::makeSubFunction(netlistp, "_ico_public_end", false);
                result.m_startp = util::makeSubFunction(netlistp, "_ico_public_start", false);
                result.m_atStartp = topScopep->createTemp("__VicoPublicAtStart", 1);
            }
            AstVarScope* const startp
                = topScopep->createTemp(startNames.get(varp->name()), vscp->dtypep());
            AstVarScope* const writtenp = topScopep->createTemp(writtenNames.get(varp->name()), 1);
            result.m_updatep->addStmtsp(newSet(writtenp, new AstConst{flp, AstConst::BitFalse{}}));
            result.m_startp->addStmtsp(newSet(startp, newRead(vscp)));
            if (writtenVscps.count(vscp)) {
                if (!result.m_seenp) {
                    result.m_seenp = util::makeSubFunction(netlistp, "_ico_public_seen", false);
                }
                result.m_seenp->addStmtsp(newSet(prevp, newRead(vscp)));
                result.m_seenp->addStmtsp(newSet(startp, newRead(vscp)));
            }
            result.m_endp->addStmtsp(
                newSet(writtenp, new AstOr{flp, new AstNeq{flp, newRead(vscp), newRead(prevp)},
                                           new AstNeq{flp, newRead(vscp), newRead(startp)}}));
            changedp = new AstOr{flp, changedp, newRead(writtenp)};
        }
        pair.first->second
            = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_TRUE, changedp}};
        senTreeps.push_back(pair.first->second);
    }
    if (result.m_atStartp) {
        result.m_startp->addStmtsp(
            newSet(result.m_atStartp, new AstConst{flp, AstConst::BitFalse{}}));
        result.m_updatep->addStmtsp(
            new AstIf{flp, newRead(result.m_atStartp), util::callVoidFunc(result.m_startp)});
        result.m_endp->addStmtsp(
            newSet(result.m_atStartp, new AstConst{flp, AstConst::BitTrue{}}));
    }
    V3Stats::addStat("Scheduling, 'ico' public variable change detects", nPublic);
    V3Stats::addStat("Scheduling, 'ico' time reads change detected", nowVscps.size());
    V3Stats::addStat("Scheduling, 'ico' public variables feeding hidden state reads",
                     hiddenVscps.size());
}

void createIcoRegion(AstNetlist* netlistp, AstCFunc* const initFuncp,
                     SenExprBuilder& senExprBuilder, ProcessList& logic,
                     const LogicRegions& regions, const VirtIfaceTriggers& virtIfaceTriggers,
                     const CovergroupRefBindings& cgRefBindings) {
    // SystemC only: Any top level inputs feeding a combinational logic must be marked,
    // so we can make them sc_sensitive
    if (v3Global.opt.systemC()) {
        for (const Process& process : logic) {
            process.m_procp->foreach([](AstVarRef* refp) {
                if (refp->access().isWriteOnly()) return;
                AstVarScope* const vscp = refp->varScopep();
                if (vscp->scopep()->isTop() && vscp->varp()->isNonOutput()) {
                    vscp->varp()->scSensitive(true);
                }
            });
        }
    }

    // We have some extra trigger denoting external conditions
    AstVarScope* const dpiExportTriggerVscp = netlistp->dpiExportTriggerp();

    TriggerKit::ExtraTriggers extraTriggers;
    const uint32_t firstIterationTrigger = extraTriggers.allocate("first iteration");
    const uint32_t dpiExportTriggerIndex = dpiExportTriggerVscp
                                               ? extraTriggers.allocate("DPI export trigger")
                                               : std::numeric_limits<uint32_t>::max();
    const uint32_t firstVifTriggerIndex = extraTriggers.size();
    for (const auto& entry : virtIfaceTriggers.m_triggers) {
        extraTriggers.allocate("virtual interface member: " + entry.m_ifacep->name() + "."
                               + entry.m_memberp->name());
    }

    // Create the input change detect SenTrees.
    // If there is a lot of combinationallogic hanging of the top level inputs, we can save
    // a lot of work by only evaluating it if an input has actually changed. This in
    // paticular helps hierarchical models partitioned across combinaitonal boundaries.
    // The change detect itself should be fairly cheap otherwise so alway do it.
    // For correctness, don't create a change detect for top level inputs also written
    // by the design, as the change detect 'previous value' would get out of sync.
    // Also omit a SenTree for types that don't have the required '!=' operator.
    // Any signal that does not have an explicit change detect trigger will fall back to
    // using the 'first iteration' trigger, same as if this optimization was disabled.
    std::unordered_map<const AstVarScope*, AstSenTree*> inp2changedp;
    std::vector<AstSenTree*> icoChangeSenTreeps;
    IcoPublicChangeDetect publicChangeDetect;
    IcoPublicAnalysis publicAnalysis;
    const bool publicDetect
        = v3Global.opt.fIcoChangeDetect().isTrue() && v3Global.opt.fIcoPublicChangeDetect();
    if (publicDetect) {
        publicAnalysis = analyzeIcoPublic(netlistp, logic, regions, publicChangeDetect);
    }
    size_t nHiddenInputs = 0;
    if (v3Global.opt.fIcoChangeDetect().isTrue()) {
        FileLine* const flp = netlistp->fileline();
        AstScope* const scopep = netlistp->topScopep()->scopep();
        for (AstVarScope* const vscp : scopep->varspList()) {
            // Only for top level ports, assume outputs don't change externally
            if (!vscp->varp()->isPrimaryInish()) continue;
            // Don't do if written by the design - wouldn't update the change detect 'prev' value
            if (vscp->varp()->icoMaybeWritten()) continue;
            // Don't do if forceable, as we can't see the actual value - this is belt and braces
            if (vscp->varp()->isForced()) continue;
            // Can't handle unpacked arrays (they have special types when primary input)
            if (VN_IS(vscp->dtypep()->skipRefp(), UnpackArrayDType)) continue;
            // Similarly to arrays, can't handle SystemC types
            if (vscp->varp()->isSc()) continue;
            // With -fico-public-change-detect, nor if it feeds logic reading hidden state
            if (publicAnalysis.m_hiddenFedVscps.count(vscp)) {
                ++nHiddenInputs;
                continue;
            }
            // Create a sen tree triggered when this input changes
            AstSenTree*& senTreepr = inp2changedp[vscp];
            UASSERT_OBJ(!senTreepr, vscp, "Duplicate input change detect trigger");
            AstVarRef* const refp = new AstVarRef{flp, vscp, VAccess::READ};
            AstSenItem* const senItemp = new AstSenItem{flp, VEdgeType::ET_CHANGED, refp};
            senTreepr = new AstSenTree{flp, senItemp};
            icoChangeSenTreeps.push_back(senTreepr);
        }
    }
    V3Stats::addStat("Scheduling, 'ico' change detect triggers", icoChangeSenTreeps.size());

    if (publicDetect) {
        V3Stats::addStat("Scheduling, 'ico' inputs feeding hidden state reads", nHiddenInputs);
        createIcoPublicChangeDetect(netlistp, publicAnalysis, inp2changedp, icoChangeSenTreeps,
                                    publicChangeDetect);
    }

    // Gather the relevant sensitivity expressions and create the trigger kit
    std::vector<const AstSenTree*> senTreeps = getSenTreesUsedBy({&logic});
    senTreeps.insert(senTreeps.end(), icoChangeSenTreeps.begin(), icoChangeSenTreeps.end());
    const TriggerKit trigKit = TriggerKit::create(netlistp, initFuncp, senExprBuilder, {},
                                                  senTreeps, "ico", extraTriggers, false, false);
    std::ignore = senExprBuilder.getAndClearResults();

    if (dpiExportTriggerVscp) {
        trigKit.addExtraTriggerAssignment(dpiExportTriggerVscp, dpiExportTriggerIndex);
    }
    if (AstCFunc* const updatep = publicChangeDetect.m_updatep) {
        util::splitCheck(updatep);
        if (publicChangeDetect.m_seenp) util::splitCheck(publicChangeDetect.m_seenp);
        if (AstCFunc* const nowp = publicChangeDetect.m_nowp) {
            util::splitCheck(nowp);
            trigKit.compBasep()->stmtsp()->addHereThisAsNext(util::callVoidFunc(nowp));
        }
        trigKit.compBasep()->addStmtsp(util::callVoidFunc(updatep));
        if (AstCFunc* const endp = publicChangeDetect.m_endp) {
            util::splitCheck(endp);
            util::splitCheck(publicChangeDetect.m_startp);
            initFuncp->addStmtsp(util::setVar(publicChangeDetect.m_atStartp, 1));
            netlistp->evalFuncp(VEval::POSTPONED)->addStmtsp(util::callVoidFunc(endp));
        }
    }
    addVirtIfaceTriggerAssignments(netlistp, initFuncp, virtIfaceTriggers, firstVifTriggerIndex,
                                   trigKit);
    util::splitCheck(trigKit.compBasep());

    // Add trigger indices
    addTriggerIndices(logic, trigKit, false);

    // The 'first iteration' trigger for top level inputs
    const uint32_t firstIterTrigger = trigKit.extraTriggerIndex(firstIterationTrigger);

    const auto& vifVscpToTrigIco
        = virtIfaceTriggers.makeVscpToTrigMap(trigKit, firstVifTriggerIndex);

    // Create and Order the body function
    AstCFunc* const icoFuncp = V3Order::order(
        {&logic}, trigKit, trigKit.vscp(), cgRefBindings, "ico", false, false,
        [&](const AstVarScope* vscp, std::set<uint32_t>& triggers) {
            AstVar* const varp = vscp->varp();
            // If it has an explicit change detect trigger, use that,
            // otherwise fall back to using the 'first iteration' trigger
            auto it = inp2changedp.find(vscp);
            if (it != inp2changedp.end()) {
                triggers.insert(trigKit.senItem2TrigIdx(it->second->sensesp()));
            } else if (varp->isPrimaryInish() || varp->isSigUserRWPublic() || varp->sampled()) {
                triggers.insert(firstIterTrigger);
            }
            // Add other triggers
            if (varp->isWrittenByDpi())
                triggers.insert(trigKit.extraTriggerIndex(dpiExportTriggerIndex));
            if (vscp->varp()->sensIfacep() || vscp->varp()->isVirtIface()) {
                addTriggeredIface(vscp, vifVscpToTrigIco, virtIfaceTriggers, triggers);
            }
        });
    util::splitCheck(icoFuncp);

    // Create the region evaluation function
    createEvalRegion(  //
        netlistp, VEval::ICO, firstIterationTrigger, trigKit,
        // Use trigger
        trigKit.vscp(), nullptr,
        // Prep statements: Compute the current 'ico' triggers
        [&trigKit] {
            AstNodeStmt* const stmtp = trigKit.newCompBaseCall();
            if (stmtp) stmtp->addNext(trigKit.newDumpCall(trigKit.vscp(), trigKit.name(), true));
            return stmtp;
        }(),
        // Work statements: Invoke the 'ico' function
        AstNode::addNextNull(util::callVoidFunc(icoFuncp),
                             publicChangeDetect.m_seenp
                                 ? util::callVoidFunc(publicChangeDetect.m_seenp)
                                 : nullptr));

    // Release temporary input change detect SenTrees
    for (AstSenTree* const senTreep : icoChangeSenTreeps)
        VL_DO_DANGLING(senTreep->deleteTree(), senTreep);
    icoChangeSenTreeps.clear();
}

//============================================================================
// EvalKit groups items that have to be passed to createEval() for a given eval region

struct EvalKit final {
    // The AstVarScope representing the region's trigger vector
    AstVarScope* const m_vscp = nullptr;
    // The AstCFunc that evaluates the region's logic
    AstCFunc* const m_funcp = nullptr;
    // Is this kit used/required?
    bool empty() const { return !m_funcp; }
};

//============================================================================
// Create the evaluation function of each region of a time step

// The triggers of the reactive region
struct ReactTriggers final {
    std::set<uint32_t> m_logic;  // Of logic, triggering a next pass of the reactive region set
    std::set<uint32_t> m_reNbaCommit;  // Of the commit of the Re-NBAs
};

void createEval(AstNetlist* netlistp,  //
                const TriggerKit& trigKit,  //
                const EvalKit& actKit,  //
                const EvalKit& nbaKit,  //
                const EvalKit& obsKit,  //
                const EvalKit& reactKit,  //
                const ReactTriggers& reactTriggers,  //
                TimingKit& timingKit  //
) {
    FileLine* const flp = netlistp->fileline();

    // Grab the delay scheduler variable, if any
    AstVarScope* const delaySchedVscp = timingKit.getDelayScheduler(netlistp);

    // 'createResume' consumes the contents that 'createReady' needs, so do the right order
    AstCCall* const timingReadyp = timingKit.createReady(trigKit.vscp());
    AstCCall* const timingResumep = timingKit.createResume(trigKit.vscp());

    // Create the 'act' region
    createEvalRegion(  //
        netlistp, VEval::ACT, 0, trigKit,
        // Use trigger
        actKit.m_vscp, nullptr,
        // Prep statements
        [&]() {
            // Compute the current 'act' triggers - the NBA triggers are the latched value
            AstNodeStmt* stmtsp = trigKit.newCompBaseCall();
            AstNodeStmt* const dumpp
                = stmtsp ? trigKit.newDumpCall(trigKit.vscp(), trigKit.name(), true) : nullptr;
            // Mark as ready for triggered awaits
            if (timingReadyp) stmtsp = AstNode::addNext(stmtsp, timingReadyp->makeStmt());
            if (AstVarScope* const vscAccp = trigKit.vscAccp()) {
                stmtsp = AstNode::addNext(stmtsp, trigKit.newOrIntoCall(actKit.m_vscp, vscAccp));
            }
            stmtsp = AstNode::addNext(stmtsp, trigKit.newCompExtCall(nbaKit.m_vscp));
            stmtsp = AstNode::addNext(stmtsp, dumpp);
            // Latch the 'act' triggers under the 'nba' triggers
            stmtsp = AstNode::addNext(stmtsp, trigKit.newOrIntoCall(nbaKit.m_vscp, actKit.m_vscp));
            //
            return stmtsp;
        }(),
        // Work statements
        [&]() {
            AstNodeStmt* workp = nullptr;
            if (AstVarScope* const actAccp = trigKit.vscAccp()) {
                AstCMethodHard* const cCallp = new AstCMethodHard{
                    flp, new AstVarRef{flp, actAccp, VAccess::WRITE}, VCMethod::UNPACKED_FILL,
                    new AstConst{flp, AstConst::Unsized64{}, 0}};
                cCallp->dtypeSetVoid();
                workp = AstNode::addNext(workp, cCallp->makeStmt());
            }
            // Resume triggered timing schedulers
            if (timingResumep) workp = AstNode::addNext(workp, timingResumep->makeStmt());
            // Invoke the 'act' function
            workp = AstNode::addNext(workp, util::callVoidFunc(actKit.m_funcp));
            //
            return workp;
        }());

    // Create the 'inact' region
    createEvalRegion(  //
        netlistp, VEval::INACT, 0, trigKit,
        // Use explicit condition
        nullptr,
        [&]() -> AstNodeExpr* {
            if (!delaySchedVscp) return nullptr;
            // Run if any zero delays are pending
            AstNodeExpr* const callp
                = new AstCMethodHard{flp, new AstVarRef{flp, delaySchedVscp, VAccess::READ},
                                     VCMethod::SCHED_AWAITING_ZERO_DELAY};
            callp->dtypeSetBit();
            return callp;
        }(),
        // Prep statements
        nullptr,
        // Work statements
        [&]() -> AstNodeStmt* {
            if (!delaySchedVscp) {
                // Nothing to do if there are no delays at all in the design
                return nullptr;
            } else if (v3Global.usesZeroDelay()) {
                // Resume processes watiting for #0 delay
                AstCMethodHard* const callp = new AstCMethodHard{
                    flp, new AstVarRef{flp, delaySchedVscp, VAccess::READWRITE},
                    VCMethod::SCHED_RESUME_ZERO_DELAY};
                callp->dtypeSetVoid();
                return callp->makeStmt();
            } else {
                // Assumption was that the design doesn't use #0 delays.
                // Die at run-time if it does.
                AstCStmt* const stmtp = new AstCStmt{flp};
                const FileLine* const locp = netlistp->topModulep()->fileline();
                const std::string& file = VIdProtect::protect(locp->filename());
                const std::string& line = std::to_string(locp->lineno());
                stmtp->add("VL_FATAL_MT(\"" + V3OutFormatter::quoteNameControls(file) + "\", "
                           + line
                           + ", \"\", \"ZERODLY: Design Verilated with '--no-sched-zero-delay', "
                           + "but #0 delay executed at runtime\");");
                return stmtp;
            }
        }());

    // Create the 'nba' region
    createEvalRegion(  //
        netlistp, VEval::NBA, 0, trigKit,
        // Use trigger
        nbaKit.m_vscp, nullptr,
        // Prep statements
        nullptr,
        // Work statements
        [&]() {
            AstNodeStmt* workp = nullptr;
            // Latch the 'nba' trigger flags under the following region's trigger flags
            if (!obsKit.empty()) {
                workp = trigKit.newOrIntoCall(obsKit.m_vscp, nbaKit.m_vscp);
            } else if (!reactKit.empty()) {
                workp = trigKit.newOrIntoCall(reactKit.m_vscp, nbaKit.m_vscp);
            }
            // Invoke the 'nba' function
            workp = AstNode::addNext(workp, util::callVoidFunc(nbaKit.m_funcp));
            // Clear the 'nba' triggers
            workp = AstNode::addNext(workp, trigKit.newClearCall(nbaKit.m_vscp));
            //
            return workp;
        }());

    // Create the 'obs' region
    createEvalRegion(  //
        netlistp, VEval::OBS, 0, trigKit,
        // Use trigger
        obsKit.m_vscp, nullptr,
        // Prep statements
        nullptr,
        // Work statements
        [&]() -> AstNodeStmt* {
            if (obsKit.empty()) return nullptr;
            AstNodeStmt* workp = nullptr;
            // Latch the Observed trigger flags under the Reactive trigger flags
            if (!reactKit.empty()) {
                workp = trigKit.newOrIntoCall(reactKit.m_vscp, obsKit.m_vscp);
            }
            // Invoke the 'obs' function
            workp = AstNode::addNext(workp, util::callVoidFunc(obsKit.m_funcp));
            // Clear the 'obs' triggers
            workp = AstNode::addNext(workp, trigKit.newClearCall(obsKit.m_vscp));
            //
            return workp;
        }());

    // Create the 'react' region. The reactive region set iterates until empty before the active
    // region set resumes (IEEE 1800-2023 4.5).
    AstVarScope* const inReactivep = netlistp->inReactivep();
    // The schedulers of processes continuing in the reactive region set (see V3Timing): those
    // waiting for the Re-Inactive region in the previous pass first, then those resumed
    // outside the reactive region set
    std::vector<AstVarScope*> contSchedps;
    for (AstVarScope* const schedp : {netlistp->reInactSchedp(), netlistp->reactSchedp()}) {
        if (schedp) contSchedps.push_back(schedp);
    }
    const auto newSchedCallp = [&](AstVarScope* schedp, VCMethod method) {
        AstCMethodHard* const callp
            = new AstCMethodHard{flp, new AstVarRef{flp, schedp, VAccess::READWRITE}, method};
        if (method == VCMethod::SCHED_EMPTY) {
            callp->dtypeSetBit();
        } else {
            callp->dtypeSetVoid();
            AstCExpr* const descp = new AstCExpr{flp, "\"reactive region set\""};
            descp->dtypeSetString();
            callp->addPinsp(descp);
        }
        return callp;
    };
    // An await readied a process waiting in the reactive region set, see V3SchedTrigger
    if (!timingKit.m_reactSchedps.empty()) {
        timingKit.m_reactReadyp = netlistp->topScopep()->createTemp("__VreactReady", 1);
    }
    AstVarScope* const reactReadyp = timingKit.m_reactReadyp;
    // Whether processes continue in the reactive region set, by 'schedps' or readied
    const auto newPendingp = [&](const std::vector<AstVarScope*>& schedps) -> AstNodeExpr* {
        AstNodeExpr* condp
            = reactReadyp ? new AstVarRef{flp, reactReadyp, VAccess::READ} : nullptr;
        for (AstVarScope* const schedp : schedps) {
            AstNodeExpr* const pendingp
                = new AstLogNot{flp, newSchedCallp(schedp, VCMethod::SCHED_EMPTY)};
            condp = condp ? new AstLogOr{flp, condp, pendingp} : pendingp;
        }
        return condp;
    };
    const auto newContinuationsp = [&]() { return newPendingp(contSchedps); };
    // Latch the triggers in 'indices' as the 'react' triggers
    const auto newLatchp = [&](const std::set<uint32_t>& indices) {
        std::map<uint32_t, uint64_t> wordMasks;
        for (const uint32_t index : indices) {
            wordMasks[index / TriggerKit::WORD_SIZE] |= 1ULL << (index % TriggerKit::WORD_SIZE);
        }
        AstNodeStmt* stmtsp = nullptr;
        for (const auto& wordMask : wordMasks) {
            const auto wordp = [&](AstVarScope* vscp, VAccess access) {
                return new AstArraySel{flp, new AstVarRef{flp, vscp, access},
                                       new AstConst{flp, AstConst::Unsized64{}, wordMask.first}};
            };
            AstNodeExpr* const valuep
                = new AstOr{flp, wordp(reactKit.m_vscp, VAccess::READ),
                            new AstAnd{flp, wordp(trigKit.vscp(), VAccess::READ),
                                       new AstConst{flp, AstConst::Unsized64{}, wordMask.second}}};
            stmtsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                stmtsp, new AstAssign{flp, wordp(reactKit.m_vscp, VAccess::WRITE), valuep});
        }
        return stmtsp;
    };
    // The Re-NBA commit: its trigger fires once per enqueuing into an empty queue, so it is noted
    // as pending until the reactive region set has no other work; then the commit is armed for
    // the next pass. A commit trigger reaching the 'react' region otherwise, e.g. through the
    // 'act' accumulator, is dropped.
    const std::set<uint32_t>& commitTriggers = reactTriggers.m_reNbaCommit;
    AstVarScope* pendingp = nullptr;
    AstVarScope* armedp = nullptr;
    std::map<uint32_t, uint64_t> commitMasks;
    if (!reactKit.empty() && !commitTriggers.empty()) {
        pendingp = netlistp->topScopep()->createTemp("__VreNbaPending", 1);
        armedp = netlistp->topScopep()->createTemp("__VreNbaArmed", 1);
        for (const uint32_t index : commitTriggers) {
            commitMasks[index / TriggerKit::WORD_SIZE] |= 1ULL << (index % TriggerKit::WORD_SIZE);
        }
    }
    const auto commitWordp = [&](uint32_t word, VAccess access) {
        return new AstArraySel{flp, new AstVarRef{flp, reactKit.m_vscp, access},
                               new AstConst{flp, AstConst::Unsized64{}, word}};
    };
    const bool useCond = !reactKit.empty() && (!contSchedps.empty() || reactReadyp);
    createEvalRegion(  //
        netlistp, VEval::REACT, 0, trigKit,
        // Use trigger, or with continuing processes, an explicit condition
        useCond ? nullptr : reactKit.m_vscp,
        useCond ? new AstLogOr{flp, trigKit.newAnySetCall(reactKit.m_vscp), newContinuationsp()}
                : nullptr,
        // Prep statements
        nullptr,
        // Work statements
        [&]() -> AstNodeStmt* {
            if (reactKit.empty()) return nullptr;
            // Note reactive logic runs, for V3Delayed and V3Timing
            AstNodeStmt* workp = nullptr;
            if (armedp) {
                AstIf* const ifp = new AstIf{
                    flp, new AstLogNot{flp, new AstVarRef{flp, armedp, VAccess::READ}}};
                for (const auto& wordMask : commitMasks) {
                    ifp->addThensp(new AstAssign{
                        flp, commitWordp(wordMask.first, VAccess::WRITE),
                        new AstAnd{flp, commitWordp(wordMask.first, VAccess::READ),
                                   new AstConst{flp, AstConst::Unsized64{}, ~wordMask.second}}});
                }
                workp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(workp, ifp);
                workp = AstNode::addNext(workp, util::setVar(armedp, 0));
            }
            if (inReactivep) workp = AstNode::addNext(workp, util::setVar(inReactivep, 1));
            // Resume the processes continuing in the Reactive region: those resumed outside the
            // reactive region set, and those triggered, waiting in it. Only once there are none,
            // nor Reactive logic to run, those waiting for the Re-Inactive region
            // (IEEE 1800-2023 4.5).
            AstNodeStmt* reactivep = reactReadyp ? util::setVar(reactReadyp, 0) : nullptr;
            AstVarScope* const reactSchedp = netlistp->reactSchedp();
            if (reactSchedp) {
                reactivep = AstNode::addNext(
                    reactivep,
                    newSchedCallp(reactSchedp, VCMethod::SCHED_MOVE_TO_RESUME_QUEUE)->makeStmt());
                reactivep = AstNode::addNext(
                    reactivep, newSchedCallp(reactSchedp, VCMethod::SCHED_RESUME)->makeStmt());
            }
            reactivep = AstNode::addNext(reactivep, timingKit.m_reactResumesp);
            if (AstVarScope* const reInactp = netlistp->reInactSchedp()) {
                AstNodeExpr* condp = trigKit.newAnySetCall(reactKit.m_vscp);
                std::vector<AstVarScope*> reactSchedps;
                if (reactSchedp) reactSchedps.push_back(reactSchedp);
                if (AstNodeExpr* const pendingp = newPendingp(reactSchedps)) {
                    condp = new AstLogOr{flp, condp, pendingp};
                }
                AstIf* const ifp = new AstIf{flp, condp, reactivep};
                ifp->addElsesp(
                    newSchedCallp(reInactp, VCMethod::SCHED_MOVE_TO_RESUME_QUEUE)->makeStmt());
                ifp->addElsesp(newSchedCallp(reInactp, VCMethod::SCHED_RESUME)->makeStmt());
                workp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(workp, ifp);
            } else if (reactivep) {
                workp = AstNode::addNext(workp, reactivep);
            }
            // Invoke the 'react' function
            workp = AstNode::addNext(workp, util::callVoidFunc(reactKit.m_funcp));
            if (inReactivep) workp = AstNode::addNext(workp, util::setVar(inReactivep, 0));
            // Clear the 'react' triggers
            workp = AstNode::addNext(workp, trigKit.newClearCall(reactKit.m_vscp));
            // Compute the triggers of what the pass changed: those of reactive logic trigger
            // the next pass, all are accumulated for 'act'
            workp = AstNode::addNext(workp, trigKit.newCompBaseCall());
            if (timingReadyp) {
                workp = AstNode::addNext(workp, timingReadyp->cloneTree(false)->makeStmt());
            }
            workp = AstNode::addNext(workp,
                                     trigKit.newOrIntoCall(trigKit.vscAccp(), trigKit.vscp()));
            // But not the Re-NBA commit trigger, which 'act' has no use for. The other triggers
            // of 'react' logic reach the 'react' region again through 'act', which reactive
            // logic tolerates: an action runner or a scheduler with nothing pending does nothing
            for (const auto& wordMask : commitMasks) {
                const auto accp = [&](VAccess access) {
                    return new AstArraySel{
                        flp, new AstVarRef{flp, trigKit.vscAccp(), access},
                        new AstConst{flp, AstConst::Unsized64{}, wordMask.first}};
                };
                workp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                    workp, new AstAssign{flp, accp(VAccess::WRITE),
                                         new AstAnd{flp, accp(VAccess::READ),
                                                    new AstConst{flp, AstConst::Unsized64{},
                                                                 ~wordMask.second}}});
            }
            std::set<uint32_t> logicTriggers = reactTriggers.m_logic;
            const std::set<uint32_t>& timingTriggers = timingKit.m_reactTriggers;
            logicTriggers.insert(timingTriggers.begin(), timingTriggers.end());
            workp = AstNode::addNext(workp, newLatchp(logicTriggers));
            // The Re-NBA region runs once the Reactive and Re-Inactive regions are empty
            // (IEEE 1800-2023 4.4.2.8, 4.5)
            if (pendingp) {
                workp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                    workp,
                    new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                  new AstLogOr{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                               new AstTriggered{flp,
                                                                trigKit.vscp(),
                                                                {commitTriggers.begin(),
                                                                 commitTriggers.end()}}}});
                AstNodeExpr* condp
                    = new AstLogAnd{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                    new AstLogNot{flp, trigKit.newAnySetCall(reactKit.m_vscp)}};
                if (AstNodeExpr* const contp = newContinuationsp()) {
                    condp = new AstLogAnd{flp, condp, new AstLogNot{flp, contp}};
                }
                AstIf* const ifp = new AstIf{flp, condp, util::setVar(pendingp, 0)};
                ifp->addThensp(util::setVar(armedp, 1));
                for (const auto& wordMask : commitMasks) {
                    ifp->addThensp(new AstAssign{
                        flp, commitWordp(wordMask.first, VAccess::WRITE),
                        new AstOr{flp, commitWordp(wordMask.first, VAccess::READ),
                                  new AstConst{flp, AstConst::Unsized64{}, wordMask.second}}});
                }
                workp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(workp, ifp);
            }
            return workp;
        }());
    // The flag is read through calls V3Life may not follow, e.g. virtual ones
    if (inReactivep) netlistp->evalFuncp(VEval::REACT)->noLife(true);
}

}  // namespace

//============================================================================
// Helper that builds virtual interface trigger sentrees

std::set<const AstIface*> VirtIfaceTriggers::reachableIfaces(const AstIface* ifacep) const {
    std::set<const AstIface*> result{ifacep};
    std::vector<const AstIface*> worklist{ifacep};
    while (!worklist.empty()) {
        const auto it = m_memberIfaces.find(worklist.back());
        worklist.pop_back();
        if (it == m_memberIfaces.end()) continue;
        for (const AstIface* const memberIfacep : it->second) {
            if (result.insert(memberIfacep).second) worklist.push_back(memberIfacep);
        }
    }
    return result;
}

VirtIfaceTriggers::VscpTrigMap VirtIfaceTriggers::makeVscpToTrigMap(const TriggerKit& trigKit,
                                                                    uint32_t firstIndex) const {
    VscpTrigMap map;
    uint32_t index = firstIndex;
    for (const auto& entry : m_triggers) {
        map.emplace(entry.m_vscp, trigKit.extraTriggerIndex(index));
        ++index;
    }
    return map;
}

//============================================================================
// Top level entry-point to scheduling

void schedule(AstNetlist* netlistp) {
    const auto addSizeStat = [](const string& name, const ProcessList& procList) {
        uint64_t size = 0;
        for (const Process& process : procList) size += process.m_procp->nodeCount();
        V3Stats::addStat("Scheduling, " + name, size);
    };

    // Step 2: Prepare external domains for timing and virtual interfaces
    // Create extra triggers for virtual interfaces
    const auto& virtIfaceTriggers = makeVirtIfaceTriggers(netlistp);
    // Resolve what covergroup reference formal arguments are bound to, which is visible here
    // but not from V3Order, where the reads through them must be modeled
    const CovergroupRefBindings& cgRefBindings = makeCovergroupRefBindings(netlistp);
    // Prepare timing-related logic and external domains
    TimingKit timingKit = prepareTiming(netlistp);

    // Step 3: Gather and classify all logic in the design
    LogicClasses logicClasses = gatherLogicClasses(netlistp);

    if (v3Global.opt.stats()) {
        V3Stats::statsStage("sched-gather");
        addSizeStat("size of class: static", logicClasses.m_static);
        addSizeStat("size of class: initial", logicClasses.m_initial);
        addSizeStat("size of class: final", logicClasses.m_final);
    }

    // Step 4: Schedule static, initial and final logic classes in source order
    AstCFunc* const staticp = createStatic(netlistp, logicClasses);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-static");

    createInitial(netlistp, logicClasses);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-initial");

    createFinal(netlistp, logicClasses);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-final");

    // Step 5: Break combinational cycles by introducing hybrid logic
    breakCycles(netlistp, logicClasses);
    if (v3Global.opt.stats()) {
        addSizeStat("size of class: clocked", logicClasses.m_clocked);
        addSizeStat("size of class: combinational", logicClasses.m_comb);
        addSizeStat("size of class: hybrid", logicClasses.m_hybrid);
        V3Stats::statsStage("sched-break-cycles");
    }

    // We pass around a single SenExprBuilder instance, as we only need one set of 'prev' variables
    // for edge/change detection in sensitivity expressions, which this keeps track of.
    AstTopScope* const topScopep = netlistp->topScopep();
    AstScope* const scopeTopp = topScopep->scopep();
    SenExprBuilder senExprBuilder{scopeTopp};

    // Step 6: Create 'settle' region that restores the combinational invariant
    createSettle(netlistp, staticp, senExprBuilder, logicClasses, cgRefBindings);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-settle");

    // Step 7: Partition the clocked and combinational (including hybrid) logic into pre/act/nba.
    // All clocks (signals referenced in an AstSenTree) generated via a blocking assignment
    // (including combinationally generated signals) are computed within the act region.
    LogicRegions logicRegions = partition(logicClasses);
    if (v3Global.opt.stats()) {
        addSizeStat("size of region: Active Pre", logicRegions.m_pre);
        addSizeStat("size of region: Active", logicRegions.m_act);
        addSizeStat("size of region: NBA", logicRegions.m_nba);
        addSizeStat("size of region: Observed", logicRegions.m_obs);
        addSizeStat("size of region: Reactive", logicRegions.m_react);
        V3Stats::statsStage("sched-partition");
    }

    // Step 8: Replicate combinational logic
    LogicReplicas logicReplicas = replicateLogic(logicRegions);
    if (v3Global.opt.stats()) {
        addSizeStat("size of replicated logic: Input", logicReplicas.m_ico);
        addSizeStat("size of replicated logic: Active", logicReplicas.m_act);
        addSizeStat("size of replicated logic: NBA", logicReplicas.m_nba);
        addSizeStat("size of replicated logic: Observed", logicReplicas.m_obs);
        addSizeStat("size of replicated logic: Reactive", logicReplicas.m_react);
        V3Stats::statsStage("sched-replicate");
    }

    // Step 9: Create the input combinational logic
    createIcoRegion(netlistp, staticp, senExprBuilder, logicReplicas.m_ico, logicRegions,
                    virtIfaceTriggers, cgRefBindings);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-create-ico");

    // Step 10: Create the triggers
    AstVarScope* const dpiExportTriggerVscp = netlistp->dpiExportTriggerp();
    netlistp->dpiExportTriggerp(nullptr);  // Finished with this here

    // We may have an extra trigger for variable updated in DPI exports
    TriggerKit::ExtraTriggers extraTriggers;
    const uint32_t dpiExportTriggerIndex = dpiExportTriggerVscp
                                               ? extraTriggers.allocate("DPI export trigger")
                                               : std::numeric_limits<uint32_t>::max();
    const uint32_t firstVifTriggerIndex = extraTriggers.size();
    for (const auto& entry : virtIfaceTriggers.m_triggers) {
        extraTriggers.allocate("virtual interface member: " + entry.m_ifacep->name() + "."
                               + entry.m_memberp->name());
    }

    const auto& preTreeps = getSenTreesUsedBy({&logicRegions.m_pre});
    const auto& senTreeps = getSenTreesUsedBy({&logicRegions.m_act,  //
                                               &logicRegions.m_nba,  //
                                               &logicRegions.m_obs,  //
                                               &logicRegions.m_react,  //
                                               &timingKit.m_procList});
    // The trigger accumulator also carries triggers computed in the 'react' region to 'act'
    const TriggerKit trigKit = TriggerKit::create(
        netlistp, staticp, senExprBuilder, preTreeps, senTreeps, "act", extraTriggers, false,
        v3Global.usesTiming() || !logicRegions.m_react.empty());

    // Add post updates from the timing kit
    if (timingKit.m_postUpdatesp) trigKit.compBasep()->addStmtsp(timingKit.m_postUpdatesp);

    if (dpiExportTriggerVscp) {
        trigKit.addExtraTriggerAssignment(dpiExportTriggerVscp, dpiExportTriggerIndex);
    }
    addVirtIfaceTriggerAssignments(netlistp, staticp, virtIfaceTriggers, firstVifTriggerIndex,
                                   trigKit);
    util::splitCheck(trigKit.compBasep());
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-create-triggers");

    // Note: Experiments so far show that running the Act (or Ico) regions on
    // multiple threads is always a net loss, so only use multi-threading for
    // NBA for now. This can be revised if evidence is available that it would
    // be beneficial

    // Step 11: Create the 'act' region evaluation function

    // Add the trigger indices of the input logic
    addTriggerIndices(logicRegions.m_pre, trigKit, true);
    addTriggerIndices(logicRegions.m_act, trigKit, false);
    addTriggerIndices(logicReplicas.m_act, trigKit, false);
    addTriggerIndices(timingKit.m_procList, trigKit, false);

    // External triggers of variables. Trigger indices are the same in all regions, so share.
    const std::map<const AstVarScope*, std::vector<uint32_t>> timingTriggers
        = timingKit.externalTriggerIndices(trigKit);
    const auto& vifVscpToTrig = virtIfaceTriggers.makeVscpToTrigMap(trigKit, firstVifTriggerIndex);
    const V3Order::ExternalTriggersProvider externalTriggers
        = [&](const AstVarScope* vscp, std::set<uint32_t>& triggers) {
              auto it = timingTriggers.find(vscp);
              if (it != timingTriggers.end())
                  triggers.insert(it->second.begin(), it->second.end());
              if (vscp->varp()->isWrittenByDpi()) {
                  triggers.insert(trigKit.extraTriggerIndex(dpiExportTriggerIndex));
              }
              if (vscp->varp()->sensIfacep() || vscp->varp()->isVirtIface()) {
                  addTriggeredIface(vscp, vifVscpToTrig, virtIfaceTriggers, triggers);
              }
          };

    AstCFunc* const actFuncp
        = V3Order::order({&logicRegions.m_pre, &logicRegions.m_act, &logicReplicas.m_act}, trigKit,
                         trigKit.vscp(), cgRefBindings, "act", false, false, externalTriggers);
    util::splitCheck(actFuncp);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-create-act");

    const EvalKit actKit{trigKit.vscp(), actFuncp};

    // Orders a region's logic and creates the region eval function
    const auto order = [&](const std::string& name,
                           const std::vector<V3Sched::ProcessList*>& logic) -> EvalKit {
        UINFO(2, "Scheduling " << name << " #logic = " << logic.size());
        AstVarScope* const trigVscp = trigKit.newTrigVec(name);
        // Add the trigger indices of the input logic
        for (ProcessList* procListp : logic) addTriggerIndices(*procListp, trigKit, false);

        AstCFunc* const funcp
            = V3Order::order(logic, trigKit, trigVscp, cgRefBindings, name,
                             name == "nba" && v3Global.opt.mtasks(), false, externalTriggers);

        return {trigVscp, funcp};
    };

    // Step 12: Create the 'nba' region evaluation function
    const EvalKit nbaKit = order("nba", {&logicRegions.m_nba, &logicReplicas.m_nba});
    util::splitCheck(nbaKit.m_funcp);
    if (v3Global.opt.stats()) V3Stats::statsStage("sched-create-nba");

    // Orders a region's logic and creates the region eval function (only if there is any logic in
    // the region)
    const auto orderIfNonEmpty
        = [&](const std::string& name, const std::vector<ProcessList*>& logic) -> EvalKit {
        if (logic[0]->empty())
            return {};  // if region is empty, replica is supposed to be empty as well
        const auto& kit = order(name, logic);
        if (v3Global.opt.stats()) V3Stats::statsStage("sched-create-" + name);
        return kit;
    };

    // Step 13: Create the 'obs' region evaluation function
    const EvalKit obsKit = orderIfNonEmpty("obs", {&logicRegions.m_obs, &logicReplicas.m_obs});

    // Step 14: Create the 'react' region evaluation function
    ReactTriggers reactTriggers;
    for (const Process& process : logicRegions.m_react) {
        // Observed deferred reports mature in the Observed region first (IEEE 1800-2023 16.4.1)
        const AstAlwaysReactive* const reactp = VN_CAST(process.m_procp, AlwaysReactive);
        if (reactp && reactp->deferredReports()) continue;
        const std::set<uint32_t>& indices = trigKit.triggerIndices(process.m_senTreep, false);
        std::set<uint32_t>& setr = isReNbaCommit(netlistp, process.m_procp)
                                       ? reactTriggers.m_reNbaCommit
                                       : reactTriggers.m_logic;
        setr.insert(indices.begin(), indices.end());
    }
    const EvalKit reactKit
        = orderIfNonEmpty("react", {&logicRegions.m_react, &logicReplicas.m_react});

    // Step 15: Create the 'postponed' region evaluation function
    createPostponed(netlistp, logicClasses);

    // Step 16: Populate the eval entry point function of each region of a time step
    createEval(netlistp, trigKit, actKit, nbaKit, obsKit, reactKit, reactTriggers, timingKit);

    // Step 17: Add neccessary evaluation before awaits
    beforeTrigVisitor(netlistp, senExprBuilder, trigKit, timingKit);

    // Step 18: Clean up
    netlistp->clearStlFirstIterationp();
    netlistp->nbaQueuep(nullptr);  // Finished with this here
    netlistp->reNbaQueuep(nullptr);
    netlistp->inReactivep(nullptr);
    netlistp->reactSchedp(nullptr);
    netlistp->reInactSchedp(nullptr);
    if (AstSenTree* const senTreesp = topScopep->senTreesp()) {
        VL_DO_DANGLING(senTreesp->unlinkFrBackWithNext()->deleteTree(), senTreesp);
    }

    if (v3Global.opt.stats()) {
        // A sample() call resolved to the union over its covergroup's constructions reads more
        // than it can, which orders it against more logic than necessary
        V3Stats::addStat("Scheduling, covergroup ref sample calls, per instance",
                         cgRefBindings.numExactCalls());
        V3Stats::addStat("Scheduling, covergroup ref sample calls, per type",
                         cgRefBindings.numUnionCalls());
    }

    // Haven't split static initializer yet
    util::splitCheck(staticp);

    // Record eval stats
    netlistp->addEvalStats("sched");

    // Dump
    V3Global::dumpCheckGlobalTree("sched", 0, dumpTreeEitherLevel() >= 3);
}

}  // namespace V3Sched
