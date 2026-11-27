// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Assertion expansion
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2005-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#ifndef VERILATOR_V3ASSERT_H_
#define VERILATOR_V3ASSERT_H_

#include "config_build.h"
#include "verilatedos.h"

#include "V3Ast.h"
#include "V3UniqueNames.h"

#include <map>
#include <unordered_map>

class V3UniqueNames;

//============================================================================

class V3AssertCommon final {
public:
    static void collectDefaultDisable(AstNetlist* nodep) VL_MT_DISABLED;
    // The default clocking declared directly in a module, or nullptr
    static AstClocking* moduleDefaultClockingp(const AstNodeModule* modp) VL_MT_DISABLED;
    // Add an event to scopep, a module or generate block, fired at each end point of sequence
    // instance schemaRefp, unless nullptr
    static AstVar* newSequenceEvent(FileLine* flp, AstNode* scopep, const string& name,
                                    AstSchemaRef* schemaRefp) VL_MT_DISABLED;
    // Add a count to scopep, a module or generate block, incremented at each end point of
    // sequence instance schemaRefp, unless nullptr
    static AstVar* newSequenceEndCount(FileLine* flp, AstNode* scopep, const string& name,
                                       AstSchemaRef* schemaRefp) VL_MT_DISABLED;
    static string assertCtlGetCall(VAssertCtlQuery query, VAssertType type,
                                   VAssertDirectiveType directiveType) VL_MT_DISABLED;
    // Direct per-instance query retaining its state reference as structured AST.
    static AstNodeExpr* newAssertCtlGetp(FileLine* flp, VAssertCtlQuery query, VAssertType type,
                                         VAssertDirectiveType directiveType,
                                         AstVar* statep = nullptr) VL_MT_DISABLED;
    static void bindControlQueries(AstNetlist* rootp) VL_MT_DISABLED;
    // True if $past, $sampled and $stable can store and compare values of the type
    static bool isSampledType(const AstNodeDType* dtypep) VL_MT_DISABLED;
    // Check an SVA value is within the implementation limit, else report it on nodep
    static bool checkSvaValueLimit(AstNode* nodep, const AstConst* constp,
                                   const char* what) VL_MT_DISABLED;
    // Fold the bounds of a cycle delay in a sequence, and check they are non-negative
    // elaboration-time constants (IEEE 1800-2023 16.7). If not, report it on errp, and replace
    // them with constants, so later steps do not fail after the error.
    static void checkSvaCycleDelay(AstDelay* nodep, AstNode* errp) VL_MT_DISABLED;
    // Fold and check the counts of a repetition (IEEE 1800-2023 16.9.2), reporting errors on errp;
    // emptyOk if the caller reduces a repetition that only matches empty
    static void checkSvaRepetition(AstSConsRep* nodep, AstNode* errp,
                                   bool emptyOk = false) VL_MT_DISABLED;
    static void checkSvaRepetition(AstSGotoRep* nodep, AstNode* errp) VL_MT_DISABLED;
    static void checkSvaRepetition(AstSNonConsRep* nodep, AstNode* errp) VL_MT_DISABLED;
    // Fold and check the tick count of a $past (IEEE 1800-2023 16.9.3), reporting errors on errp
    static void checkSvaPastTicks(AstPast* nodep, AstNode* errp) VL_MT_DISABLED;
    // Fold and check the bounds of an always range (IEEE 1800-2023 16.12.11)
    static void checkSvaAlwaysRange(AstPropAlways* nodep, AstNode* instp) VL_MT_DISABLED;
    // True if the expression references a formal argument of a sequence or property
    static bool refsSvaFormal(const AstNode* nodep) VL_MT_DISABLED;
    // True if the statements of a process may suspend it, so evaluate a procedural concurrent
    // assertion in a later time step than that of its clock
    static bool procSuspends(AstNode* stmtsp) VL_MT_DISABLED;
    // Clone an action block for one more execution site, naming its automatics from names
    static AstNodeStmt* cloneAction(AstNodeStmt* actionp, V3UniqueNames& names) VL_MT_DISABLED;
    // An action block of a concurrent assertion that may suspend, in a process of its own; each
    // action a pass or fail condition gates apart (IEEE 1800-2023 16.14.1)
    static AstNodeStmt* newSpawnedAction(AstNodeStmt* actionsp) VL_MT_DISABLED;
    // Check the constants of a sequence or property instance, reporting errors on instp
    static void checkSvaInstanceConstants(AstNode* nodep, AstNode* instp) VL_MT_DISABLED;
    // Create a module variable for each local variable of one sequence or property instance
    static std::unordered_map<const AstVar*, AstVar*>
    newSvaLocalVars(const AstNodeSchema* schemap, AstNodeModule* modp,
                    V3UniqueNames& names) VL_MT_DISABLED;
    // Relink a body inlined at instp to the instancing scope, returning the possibly replaced body
    static AstNode* relinkSvaInstanceBody(AstNode* bodyp,
                                          const AstSchemaRef* instp) VL_MT_DISABLED;
    // Remove the reduction of each single-bit actual argument substituted for a formal argument
    static void removeActualReductions(const std::vector<AstNodeExpr*>& actualps) VL_MT_DISABLED;
    // Check the references of formal arguments with a '$' actual argument, before substitution,
    // returning the possibly replaced body
    static AstNode*
    checkSvaUnboundedActuals(AstNode* nodep,
                             const std::unordered_map<const AstVar*, AstNodeExpr*>& portMap,
                             AstNode* instp) VL_MT_DISABLED;
    // Give the reads of local variables in one property instance their initial value
    static void lowerSvaLocalVarInits(
        AstProperty* propp, AstPropSpec* bodyp,
        const std::unordered_map<const AstVar*, AstVar*>& localVarMap) VL_MT_DISABLED;
    // Reduce a whole property 'always p' to p
    static void reducePlainAlways(AstPropSpec* specp) VL_MT_DISABLED;
    // Clock inferred from an always procedure, or nullptr (IEEE 1800-2023 16.14.6)
    static AstSenItem* inferredClock(const AstAlways* alwaysp) VL_MT_DISABLED;
    // Statement of an always procedure that prevents inferring its clock, or nullptr
    // (IEEE 1800-2023 16.14.6). 'taskBlocks' caches whether calling each task blocks.
    static const AstNode*
    inferenceBlockerp(const AstAlways* alwaysp,
                      std::unordered_map<const AstNodeFTask*, bool>& taskBlocks) VL_MT_DISABLED;
};

// Makes the actions of concurrent assertions run in the Reactive region, after the NBA updates
// of the time step of their evaluation (IEEE 1800-2023 16.14.1, 4.4.2.6). The evaluation makes
// an action pending, and one process per clock of each module or generate block runs the
// pending actions, unless an $assertkill came after their evaluation (IEEE 1800-2023 20.11).

class V3AssertReactive final {
public:
    struct Site final {  // Where an assertion is evaluated
        const AstNodeCoverOrAssert* assertp;  // The assertion
        AstNodeModule* modp;  // Its module
        AstNode* containerp;  // Module or generate block holding its process
        AstSenTree* senTreep;  // Clock of its evaluation
        string scope;  // Named blocks around it in its process, for %m
        // Its evaluation ends its attempts on an $assertkill, so a kill drops no pending action
        bool evalKills = false;
    };

private:
    struct Runner final {  // Process running the pending actions
        AstAlwaysReactive* runnerp;  // The process
        AstIf* bodyp;  // Its statements, run when something is pending
        AstSenTree* clockp;  // Clock of the assertions it runs the actions of, owned
        AstNode* lastCheckp;  // Last $assertkill check, before the actions, or nullptr
    };
    // Runners by the module or generate block holding them
    std::unordered_map<const AstNode*, std::vector<Runner>> m_runners;
    size_t m_statRunners = 0;  // Statistic tracking
    size_t m_statKillChecks = 0;  // Statistic tracking
    // An $assertkill may run, so pending actions are checked against it
    const bool m_killChecks;
    static bool mayKill() VL_MT_DISABLED;

    Runner& runnerFor(const Site& site, V3UniqueNames& names) VL_MT_DISABLED;
    static AstNodeExpr* newKillCountp(const Site& site) VL_MT_DISABLED;

public:
    V3AssertReactive() VL_MT_DISABLED : m_killChecks{mayKill()} {}
    ~V3AssertReactive() VL_MT_DISABLED;
    // Return what makes actionsp pending at the evaluation, or actionsp if it stays there
    AstNodeStmt* newPending(const Site& site, AstNodeStmt* actionsp,
                            V3UniqueNames& names) VL_MT_DISABLED;
};

class V3Assert final {
public:
    static void assertAll(AstNetlist* nodep) VL_MT_DISABLED;
};

#endif  // Guard
