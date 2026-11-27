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
#include <vector>

//============================================================================

class V3AssertCommon final {
public:
    static void collectDefaultDisable(AstNetlist* nodep) VL_MT_DISABLED;
    static string assertCtlGetCall(const char* query, VAssertType type,
                                   VAssertDirectiveType directiveType) VL_MT_DISABLED;
    // Check an SVA value is within the implementation limit, else report it on nodep
    static bool checkSvaValueLimit(AstNode* nodep, const AstConst* constp,
                                   const char* what) VL_MT_DISABLED;
    // Fold the bounds of a cycle delay in a sequence, and check they are non-negative
    // elaboration-time constants (IEEE 1800-2023 16.7). If not, report it on errp, and replace
    // them with constants, so later steps do not fail after the error.
    static void checkSvaCycleDelay(AstDelay* nodep, AstNode* errp) VL_MT_DISABLED;
    // True if the expression references a formal argument of a sequence or property
    static bool refsSvaFormal(const AstNode* nodep) VL_MT_DISABLED;
    // True if the statements of a process may suspend it, so evaluate a procedural concurrent
    // assertion in a later time step than that of its clock
    static bool procSuspends(AstNode* stmtsp) VL_MT_DISABLED;
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
