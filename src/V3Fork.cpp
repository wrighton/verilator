// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Create separate tasks for forked processes that
//              can outlive their parents
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
// V3Fork's Transformations:
//
// Each module:
//      Look for FORKs [JOIN_NONE]/[JOIN_ANY]
//          VARREF(var) -> MEMBERREF(var->name, VARREF(dynscope)) (for refs a copy can't serve)
//          FORK(stmts) -> TASK(stmts), FORK(TASKREF(inits))
//
// FORKs that spawn tasks which might outlive their parents require those
// tasks to carry their own frames and as such they require their own
// variable scopes.
//
// There are two mechanisms that work together to achieve that. ForkVisitor
// moves bodies of forked processes into new tasks, which results in them getting their
// own scopes. The original statements get replaced with a call to the task which
// passes the required variables by value.
//
// The second mechanism, DynScopeVisitor, is designed to handle variables which can't be
// captured by value and instead require a reference. Those variables get moved into an
// "anonymous" object, ie. a class with appropriate fields gets generated and an object
// of this class gets instantiated in place of the original variable declarations.
// Any references to those variables are replaced with references to the object's field.
// Since objects are reference-counted this ensures that the variables are accessible
// as long as both the parent and the forked processes require them to be.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Fork.h"

#include "V3AstNodeExpr.h"
#include "V3MemberMap.h"
#include "V3Stats.h"

#include <limits>
#include <set>
#include <unordered_map>

VL_DEFINE_DEBUG_FUNCTIONS;

class ForkDynScopeInstance final {
public:
    AstClass* m_classp = nullptr;  // Class for holding variables of dynamic scope
    AstClassRefDType* m_refDTypep = nullptr;  // RefDType for the above
    AstVar* m_handlep = nullptr;  // Class handle for holding variables of dynamic scope

    // True if the instance exists
    bool initialized() const { return m_classp != nullptr; }
};

class ForkDynScopeFrame final {
    // MEMBERS
    AstNodeModule* const m_modp;  // Module to insert the scope into
    AstNode* const m_procp;  // Procedure/block associated with that dynscope
    std::deque<AstVar*> m_captureOrder;  // Variables to be moved into the dynscope
    std::set<AstVar*> m_captures;  // Variables to be moved into the dynscope
    ForkDynScopeInstance m_instance;  // Nodes to be injected into the AST to create the dynscope
    const size_t m_class_id;  // Dynscope class ID
    const size_t m_id;  // Dynscope ID

public:
    ForkDynScopeFrame(AstNodeModule* modp, AstNode* procp, size_t class_id, size_t id)
        : m_modp{modp}
        , m_procp{procp}
        , m_class_id{class_id}
        , m_id{id} {}

    ForkDynScopeInstance& createInstancePrototype() {
        UASSERT_OBJ(!m_instance.initialized(), m_procp, "Dynamic scope already instantiated.");

        m_instance.m_classp
            = new AstClass{m_procp->fileline(), generateDynScopeClassName(), m_modp->libname()};
        UINFO(9, "new dynscope class " << m_instance.m_classp);
        m_instance.m_refDTypep
            = new AstClassRefDType{m_procp->fileline(), m_instance.m_classp, nullptr};
        v3Global.rootp()->typeTablep()->addTypesp(m_instance.m_refDTypep);
        m_instance.m_handlep
            = new AstVar{m_procp->fileline(), VVarType::BLOCKTEMP,
                         generateDynScopeHandleName(m_procp), m_instance.m_refDTypep};
        m_instance.m_handlep->funcLocal(false);
        m_instance.m_handlep->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        UINFO(9, "new dynscope var " << m_instance.m_handlep);

        return m_instance;
    }

    const ForkDynScopeInstance& instance() const { return m_instance; }
    void captureVarInsert(AstVar* varp) {
        auto r = m_captures.emplace(varp);
        if (r.second) m_captureOrder.push_back(varp);
    }
    bool captured(AstVar* varp) { return m_captures.count(varp) != 0; }
    AstNode* procp() const { return m_procp; }

    void populateClass() {
        UASSERT_OBJ(m_instance.initialized(), m_procp, "No DynScope prototype");

        // Move variables into the class
        for (AstVar* varp : m_captureOrder) {
            if (varp->direction().isAny()) {
                varp = varp->cloneTree(false);
                varp->direction(VDirection::NONE);
            } else {
                varp->unlinkFrBack();
            }
            varp->funcLocal(false);
            varp->varType(VVarType::MEMBER);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            varp->usedLoopIdx(false);  // No longer unrollable
            UINFO(9, "insert DynScope member " << varp);
            m_instance.m_classp->addMembersp(varp);
        }

        // Create class's constructor
        AstFunc* const newp = new AstFunc{m_instance.m_classp->fileline(), "new"};
        newp->isConstructor(true);
        newp->classMethod(true);
        m_instance.m_classp->addMembersp(newp);
    }

    void linkNodes(VMemberMap& memberMap) {
        UASSERT_OBJ(m_instance.initialized(), m_procp, "No dynamic scope prototype");
        UASSERT_OBJ(!linked(), m_instance.m_handlep, "Handle already linked");

        if (AstFork* const forkp = VN_CAST(m_procp, Fork)) {
            linkNodesOfFork(memberMap, forkp);
            return;
        }

        AstNode* stmtp = getProcStmts();
        UASSERT(stmtp, "trying to instantiate dynamic scope while not under proc");
        VNRelinker stmtpHandle;
        stmtp->unlinkFrBackWithNext(&stmtpHandle);

        AstNew* const newp = new AstNew{m_procp->fileline()};
        newp->taskp(VN_AS(memberMap.findMember(m_instance.m_classp, "new"), NodeFTask));
        newp->dtypep(m_instance.m_refDTypep);
        newp->classOrPackagep(m_instance.m_classp);

        AstNode* const asgnp = new AstAssign{
            m_procp->fileline(),
            new AstVarRef{m_procp->fileline(), m_instance.m_handlep, VAccess::WRITE}, newp};

        AstNode* initsp = nullptr;  // Arguments need to be copied
        for (AstVar* varp : m_captureOrder) {
            if (!varp->direction().isAny()) continue;

            if (varp->direction().isNonOutput()) {
                AstMemberRef* const memberRefp = new AstMemberRef{
                    varp->fileline(),
                    new AstVarRef{varp->fileline(), m_instance.m_handlep, VAccess::WRITE},
                    VN_AS(memberMap.findMember(m_instance.m_classp, varp->name()), Var)};
                AstNode* initAsgnp
                    = new AstAssign{varp->fileline(), memberRefp,
                                    new AstVarRef{varp->fileline(), varp, VAccess::READ}};
                initsp = AstNode::addNext(initsp, initAsgnp);
            }

            if (AstBasicDType* const dtypep = VN_CAST(varp->dtypep()->skipRefp(), BasicDType)) {
                v3Global.setAssignsEvents();
                if (dtypep->isEvent()) continue;
            }

            if (varp->direction().isWritable()) {
                AstMemberRef* const memberRefp = new AstMemberRef{
                    varp->fileline(),
                    new AstVarRef{varp->fileline(), m_instance.m_handlep, VAccess::READ},
                    VN_AS(memberMap.findMember(m_instance.m_classp, varp->name()), Var)};
                AstNode* writebackAsgnp = new AstAssign{
                    varp->fileline(), new AstVarRef{varp->fileline(), varp, VAccess::WRITE},
                    memberRefp};
                stmtp = AstNode::addNext(stmtp, writebackAsgnp);
            }
        }
        if (initsp) AstNode::addNext(asgnp, initsp);

        stmtpHandle.relink(AstNode::addNext(asgnp, stmtp));
        if (AstBegin* const beginp = VN_CAST(m_procp, Begin)) {
            beginp->prependDeclsp(m_instance.m_handlep);
        } else {
            VN_AS(m_procp, NodeFTask)->prependDeclsp(m_instance.m_handlep);
        }
        m_modp->addStmtsp(m_instance.m_classp);
    }

    bool linked() const { return m_instance.initialized() && m_instance.m_handlep->backp(); }

private:
    AstAssign* instantiateDynScope(VMemberMap& memberMap) {
        AstNew* const newp = new AstNew{m_procp->fileline()};
        newp->taskp(VN_AS(memberMap.findMember(m_instance.m_classp, "new"), NodeFTask));
        newp->dtypep(m_instance.m_refDTypep);
        newp->classOrPackagep(m_instance.m_classp);

        return new AstAssign{
            m_procp->fileline(),
            new AstVarRef{m_procp->fileline(), m_instance.m_handlep, VAccess::WRITE}, newp};
    }

    // Declare the dynamic scope in the Fork and create it before the Fork's initializers
    void linkNodesOfFork(VMemberMap& memberMap, AstFork* forkp) {
        // A wrapping block would add its name to %m and to the names of the Fork's variables
        forkp->addDeclsp(m_instance.m_handlep);
        forkp->prependStmtsp(instantiateDynScope(memberMap));
        m_modp->addStmtsp(m_instance.m_classp);
    }

    string generateDynScopeClassName() { return "__VDynScope_" + cvtToStr(m_class_id); }

    string generateDynScopeHandleName(const AstNode* fromp) {
        return "__VDynScope_" + (!fromp->name().empty() ? (fromp->name() + "_") : "ANON_")
               + cvtToStr(m_id);
    }

    AstNode* getProcStmts() {
        AstNode* stmtsp = nullptr;
        if (!m_procp) return nullptr;
        if (AstBegin* const beginp = VN_CAST(m_procp, Begin)) {
            stmtsp = beginp->stmtsp();
        } else if (AstNodeFTask* const taskp = VN_CAST(m_procp, NodeFTask)) {
            stmtsp = taskp->stmtsp();
        } else {
            m_procp->v3fatalSrc("m_procp is not a begin block or a procedure");
        }
        return stmtsp;
    }
};

//######################################################################
// Find the variables that can change after their initialization, which forked processes
// therefore cannot copy (see DynScopeVisitor::shareWrittenVars)

class ForkWrittenVisitor final : public VNVisitorConst {
    // NODE STATE
    // AstVar::user4()          -> bool.  Written other than by its initialization (set here)

    // VISITORS
    void visit(AstInitialAutomaticStmt* nodep) override {
        for (AstNodeStmt* const stmtp : nodep->stmtspList()) {
            AstNodeAssign* const assignp = VN_CAST(stmtp, NodeAssign);
            if (assignp && VN_IS(assignp->lhsp(), VarRef)) {
                // Initializes the variable on entry to its block, before any fork in it
                iterateAndNextConstNull(assignp->rhsp());
            } else {
                iterateConst(stmtp);
            }
        }
    }
    void visit(AstMemberRef* nodep) override {
        // A write to a member of an object changes the object, not the variable with its handle
        AstNodeExpr* fromp = nodep->fromp();
        while (const AstNodeSel* const selp = VN_CAST(fromp, NodeSel)) {
            iterateAndNextConstNull(selp->bitp());
            fromp = selp->fromp();
        }
        if (!VN_IS(fromp, VarRef)) iterateAndNextConstNull(fromp);
    }
    void visit(AstVarRef* nodep) override {
        if (nodep->access().isWriteOrRW()) nodep->varp()->user4(true);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit ForkWrittenVisitor(AstNetlist* nodep) { iterateConst(nodep); }
};

//######################################################################
// Dynamic scope visitor, creates classes and objects for dynamic scoping of variables and
// replaces references to variables that need a dynamic scope with references to object's
// members

class DynScopeVisitor final : public VNVisitor {
    // NODE STATE
    // AstVar::user1()          -> uint64_t.  timing-control fork nesting level of that variable
    // AstVar::user3()          -> uint64_t.  surviving fork nesting level of that variable
    // AstVar::user4()          -> bool.  Written other than by its initialization
    //                                    (ForkWrittenVisitor)
    // AstVarRef::user2()       -> bool.  Reads in a process of a fork, which may use a copy
    // AstVarRef::user3p()      -> AstFork*.  Fork that captures values, whose process reads here
    // AstAssignDly::user2()    -> bool.  Already visited
    // AstFork::user1p()        -> AstNodeModule*.  Module of a fork that captures values
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;
    const VNUser3InUse m_inuser3;
    const VNUser4InUse m_inuser4;

    // STATE
    AstNodeModule* m_modp = nullptr;  // Module we are currently under
    AstNode* m_procp = nullptr;  // Function/task/block we are currently under
    std::deque<AstNode*> m_frameOrder;  // Ordered list of frames (for determinism)
    std::map<AstNode*, ForkDynScopeFrame*> m_frames;  // Map nodes to related DynScopeFrames
    VMemberMap m_memberMap;  // Class member look-up
    uint64_t m_forkDepth = 0;  // Number of asynchronous forks we are currently under
    uint64_t m_survivingForkDepth = 0;  // Number of those forks that may outlive the task,
                                        // i.e. not immediately followed by 'disable fork'
    bool m_afterTimingControl = false;  // A timing control might've be executed in the current
                                        // process
    uint64_t m_capturesDepth = 0;  // m_forkDepth in the innermost fork that captures values
    AstFork* m_capturesForkp = nullptr;  // Innermost fork that captures values
    VDouble0 m_statVars;  // Statistic tracking: variables in dynamic scopes
    bool m_inNbaLhs = false;  // Under the destination of an NBA, diagnosed by V3WidthCommit
    size_t m_id = 0;  // Unique ID for a frame
    size_t m_class_id = 0;  // Unique ID for a frame class

    // METHODS

    ForkDynScopeFrame* frameOf(AstNode* nodep) {
        auto frameIt = m_frames.find(nodep);
        if (frameIt == m_frames.end()) return nullptr;
        return frameIt->second;
    }

    const ForkDynScopeFrame* frameOf(AstNode* nodep) const {
        auto frameIt = m_frames.find(nodep);
        if (frameIt == m_frames.end()) return nullptr;
        return frameIt->second;
    }

    ForkDynScopeFrame* pushDynScopeFrame(AstNode* procp) {
        ForkDynScopeFrame* const framep
            = new ForkDynScopeFrame{m_modp, procp, m_class_id++, m_id++};
        auto r = m_frames.emplace(procp, framep);
        UASSERT_OBJ(r.second, m_modp, "Procedure already contains a frame");
        m_frameOrder.push_back(procp);
        return framep;
    }

    void replaceWithMemberRef(AstVarRef* refp, const ForkDynScopeInstance& dynScope) {
        VNRelinker handle;
        refp->unlinkFrBack(&handle);
        AstMemberRef* const memberRefp = new AstMemberRef{
            refp->fileline(), new AstVarRef{refp->fileline(), dynScope.m_handlep, refp->access()},
            refp->varp()};
        memberRefp->access(refp->access());
        if (refp->varp()->direction().isAny()) {
            memberRefp->varp(
                VN_AS(m_memberMap.findMember(dynScope.m_classp, refp->varp()->name()), Var));
        } else {
            memberRefp->varp(refp->varp());
        }
        handle.relink(memberRefp);
        VL_DO_DANGLING(pushDeletep(refp), refp);
    }

    static bool hasAsyncFork(AstNode* nodep) {
        return nodep->exists([](AstFork* forkp) { return !forkp->joinType().join(); })
               || nodep->exists([](AstAssignDly*) { return true; });
    }

    void bindNodeToDynScope(AstNode* nodep, ForkDynScopeFrame* framep) {
        auto r = m_frames.emplace(nodep, framep);
        if (r.second) m_frameOrder.push_back(nodep);
    }

    // Whether the reference is in a process of a fork in the scope of its automatic variable
    bool inForkProcess(const AstVarRef* refp) const {
        return m_forkDepth > refp->varp()->user1() && refp->varp()->lifetime().isAutomatic();
    }
    // Whether a fork between the variable and the reference captures values
    bool inCapturingFork(const AstVarRef* refp) const {
        return m_capturesDepth > refp->varp()->user1();
    }
    // Whether the reference needs the variable itself, through the dynamic scope, rather than a
    // copy made when its process is spawned: to write it, or, conservatively, to read a variable
    // of a task or function after a timing control or call. A process of a fork that captures
    // values, which runs an NBA or an assertion action, uses the values when it is spawned, and
    // refers to a variable of a task or function, which can end before the process, only to
    // write it.
    bool needsDynScope(const AstVarRef* refp) const {
        if (!inForkProcess(refp)) return false;
        const bool funcLocal = refp->varp()->isFuncLocal();
        if (inCapturingFork(refp)) return funcLocal && refp->access().isWriteOrRW();
        return refp->access().isWriteOrRW() || (funcLocal && m_afterTimingControl);
    }

    // A process of a fork shares the variables of its parent (IEEE 1800-2023 6.21). One that only
    // reads a variable uses a copy made when it is spawned if that surely holds the same value:
    // the variable has no write other than its initialization, which runs on entry to its block,
    // before any fork in it. A write elsewhere can come before the read, as a join_none process
    // starts only once its parent blocks (IEEE 1800-2023 9.3.2), and a loop can reach the read
    // again.
    void shareWrittenVars() {
        for (AstNode* const orderp : m_frameOrder) {
            const AstVarRef* const refp = VN_CAST(orderp, VarRef);
            if (!refp || !refp->user2()) continue;
            AstVar* const varp = refp->varp();
            if (!varp->user4()) continue;
            ForkDynScopeFrame* const framep = frameOf(varp);
            if (!framep->instance().initialized()) framep->createInstancePrototype();
            framep->captureVarInsert(varp);
        }
    }

    // A process of a fork that captures values reads a variable of an enclosing scope through a
    // copy made when it is spawned. For a variable in the dynamic scope, the fork gets a variable
    // of its own, initialized from it when the fork runs, as 'fork automatic T v = x;' would.
    void snapshotSharedReads() {
        // Snapshot variable of each variable, per fork
        std::unordered_map<const AstFork*, std::unordered_map<const AstVar*, AstVar*>> snapshots;
        // Iterate the nodes bound by the traversal only, not the ones bound here
        const size_t size = m_frameOrder.size();
        for (size_t i = 0; i < size; ++i) {
            AstVarRef* const refp = VN_CAST(m_frameOrder[i], VarRef);
            if (!refp || !refp->user3p()) continue;
            AstVar* const varp = refp->varp();
            ForkDynScopeFrame* const varFramep = frameOf(varp);
            if (!varFramep->captured(varp)) continue;
            AstFork* const forkp = VN_AS(refp->user3p(), Fork);
            ForkDynScopeFrame* forkFramep = frameOf(forkp);
            if (!forkFramep) {
                // Made only when needed, after the frames of the traversal
                VL_RESTORER(m_modp);
                m_modp = VN_AS(forkp->user1p(), NodeModule);
                forkFramep = pushDynScopeFrame(forkp);
            }
            AstVar*& snapp = snapshots[forkp][varp];
            if (!snapp) {
                FileLine* const flp = refp->fileline();
                snapp = new AstVar{flp, VVarType::BLOCKTEMP, "__Vspawn_" + varp->name(),
                                   varp->dtypep()};
                snapp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                forkp->addDeclsp(snapp);
                if (!forkFramep->instance().initialized()) forkFramep->createInstancePrototype();
                forkFramep->captureVarInsert(snapp);
                bindNodeToDynScope(snapp, forkFramep);
                AstVarRef* const lhsp = new AstVarRef{flp, snapp, VAccess::WRITE};
                AstVarRef* const rhsp = new AstVarRef{flp, varp, VAccess::READ};
                forkp->addStmtsp(new AstAssign{flp, lhsp, rhsp});
                bindNodeToDynScope(lhsp, forkFramep);
                bindNodeToDynScope(rhsp, varFramep);
            }
            refp->varp(snapp);
            m_frames[refp] = forkFramep;
        }
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        if (!VN_IS(nodep, Class)) m_modp = nodep;
        VL_RESTORER(m_id);
        m_id = 0;
        iterateChildren(nodep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_procp);
        m_procp = nodep;
        if (hasAsyncFork(nodep)) pushDynScopeFrame(m_procp);
        iterateChildren(nodep);
    }
    void visit(AstBegin* nodep) override {
        VL_RESTORER(m_procp);
        m_procp = nodep;
        if (hasAsyncFork(nodep)) pushDynScopeFrame(m_procp);
        iterateChildren(nodep);
    }
    void visit(AstFork* nodep) override {
        VL_RESTORER(m_forkDepth);
        VL_RESTORER(m_survivingForkDepth);
        VL_RESTORER(m_capturesDepth);
        VL_RESTORER(m_capturesForkp);
        const bool oldAfterTimingControl = m_afterTimingControl;

        ForkDynScopeFrame* framep = nullptr;
        if (nodep->declsp() || nodep->stmtsp()) framep = pushDynScopeFrame(nodep);

        // This can be probably optimized to detect cases in which dynscopes could be avoided
        for (AstNode* const declp : nodep->declspList()) {
            if (VN_IS(declp, Typedef)) continue;  // V3Begin lifts it to the module
            AstVar* const varp = VN_CAST(declp, Var);
            UASSERT_OBJ(varp, declp, "Invalid node under block item initialization part of fork");
            UASSERT_OBJ(!varp->lifetime().isNone(), nodep, "Variable's lifetime is unknown");
            if (varp->lifetime().isAutomatic()) {  // else V3Begin will move later
                if (!framep->instance().initialized()) framep->createInstancePrototype();
                framep->captureVarInsert(varp);
                bindNodeToDynScope(varp, framep);
            }
        }
        // The parent runs the initializations of the fork's variables, before the spawns
        iterateAndNextNull(nodep->stmtsp());

        if (!nodep->joinType().join()) {
            ++m_forkDepth;
            // A following 'disable fork' kills the children before the enclosing process
            // continues, so they cannot outlive the task
            if (!VN_IS(nodep->nextp(), DisableFork)) ++m_survivingForkDepth;
            if (nodep->capturesValues()) {
                m_capturesDepth = m_forkDepth;
                m_capturesForkp = nodep;
                nodep->user1p(m_modp);
            }
        }
        for (AstNode* const stmtp : nodep->forkspList()) {
            m_afterTimingControl = false;
            iterate(stmtp);
        }
        m_afterTimingControl = oldAfterTimingControl;
        if (nodep->isTimingControl()) m_afterTimingControl = true;
    }
    void visit(AstNodeFTaskRef* nodep) override {
        visit(static_cast<AstNodeExpr*>(nodep));
        // We are before V3Timing, so unfortunately we need to treat any calls as suspending,
        // just to be safe. This might be improved if we could propagate suspendability
        // before doing all the other timing-related stuff.
        m_afterTimingControl = true;
    }
    void visit(AstVar* nodep) override {
        nodep->user1(m_forkDepth);
        nodep->user3(m_survivingForkDepth);
        ForkDynScopeFrame* const framep = frameOf(m_procp);
        if (!framep) return;  // Cannot be legally referenced from a fork
        bindNodeToDynScope(nodep, framep);
    }
    void visit(AstVarRef* nodep) override {
        ForkDynScopeFrame* const framep = frameOf(nodep->varp());
        if (!framep) return;
        if (needsDynScope(nodep)) {
            bool isEvent = false;
            if (AstBasicDType* const dtypep = VN_CAST(nodep->dtypep()->skipRefp(), BasicDType)) {
                v3Global.setAssignsEvents();
                isEvent = dtypep->isEvent();
            }
            if (!isEvent && !m_inNbaLhs && m_afterTimingControl
                && m_survivingForkDepth > nodep->varp()->user3()
                && nodep->access().isWriteOrRW()) {
                if (nodep->varp()->isRef()) {
                    // Reference arguments can refer to caller storage that has already expired.
                    nodep->v3error(
                        "Writing 'ref' argument "
                        << nodep->prettyNameQ()
                        << " after a timing control in a fork that may outlive the"
                           " subroutine is not allowed (IEEE 1800-2023 9.3.2).\n"
                        << nodep->warnMore()
                        << "... Suggest copying it into a variable declared in the fork");
                } else if (nodep->varp()->isWritable()
                           && VN_IS(nodep->varp()->dtypep()->skipRefp(), AssocArrayDType)) {
                    nodep->v3warn(
                        E_UNSUPPORTED,
                        "Unsupported: Writing associative array argument or return variable "
                            << nodep->prettyNameQ()
                            << " after a timing control in a fork that may outlive the"
                               " subroutine.");
                }
            }
            if (!framep->instance().initialized()) framep->createInstancePrototype();
            framep->captureVarInsert(nodep->varp());
        } else if (inForkProcess(nodep)) {
            if (!inCapturingFork(nodep)) {
                nodep->user2(true);
            } else if (!nodep->access().isWriteOrRW()) {
                nodep->user3p(m_capturesForkp);
            }
        }
        bindNodeToDynScope(nodep, framep);
    }
    void visit(AstAssignDly* nodep) override {
        if (m_procp && !nodep->user2()  // Unhandled AssignDly in function/task
            && nodep->lhsp()->exists(  // And writes to a local variable
                [](AstVarRef* refp) {
                    return refp->access().isWriteOrRW() && refp->varp()->isFuncLocal();
                })) {
            nodep->user2(true);
            // Put it in a fork to prevent lifetime issues with the local
            FileLine* const flp = nodep->fileline();
            AstFork* const forkp = new AstFork{flp, VJoinType::JOIN_NONE};
            // The NBA uses the values variables have when it runs
            forkp->capturesValues(true);
            nodep->replaceWith(forkp);
            forkp->addForksp(new AstForkItem{flp, nodep});
            UINFO(9, "assign new fork " << forkp);
        } else {
            if (nodep->isTimingControl()) m_afterTimingControl = true;
            iterateAndNextNull(nodep->rhsp());
            {
                VL_RESTORER(m_inNbaLhs);
                m_inNbaLhs = true;
                iterateAndNextNull(nodep->lhsp());
            }
            iterateAndNextNull(nodep->timingControlp());
        }
    }
    void visit(AstNode* nodep) override {
        if (nodep->isTimingControl()) m_afterTimingControl = true;
        iterateChildren(nodep);
    }

public:
    // CONSTRUCTORS
    explicit DynScopeVisitor(AstNetlist* nodep) {
        { ForkWrittenVisitor{nodep}; }
        // Create Dynamic scope class prototypes and objects
        visit(nodep);

        shareWrittenVars();
        snapshotSharedReads();

        // Commit changes to AST
        bool typesAdded = false;
        for (auto orderp : m_frameOrder) {
            UINFO(9, "Frame commit " << orderp);
            auto frameIt = m_frames.find(orderp);
            UASSERT_OBJ(frameIt != m_frames.end(), orderp, "m_frames didn't contain m_frameOrder");
            ForkDynScopeFrame* framep = frameIt->second;
            if (!framep->instance().initialized()) continue;
            if (!framep->linked()) {
                framep->populateClass();
                framep->linkNodes(m_memberMap);
                typesAdded = true;
            }
            if (AstVarRef* const refp = VN_CAST(frameIt->first, VarRef)) {
                if (framep->captured(refp->varp())) replaceWithMemberRef(refp, framep->instance());
            } else if (AstVar* const varp = VN_CAST(frameIt->first, Var)) {
                if (framep->captured(varp)) ++m_statVars;
            }
        }

        if (typesAdded) v3Global.rootp()->typeTablep()->repairCache();
    }
    ~DynScopeVisitor() override {
        V3Stats::addStat("Fork, variables in dynamic scopes", m_statVars);
        std::set<ForkDynScopeFrame*> frames;
        for (auto node_frame : m_frames) frames.insert(node_frame.second);
        for (auto* framep : frames) delete framep;
    }
};

//######################################################################
// Fork visitor, transforms asynchronous blocks into separate tasks

class ForkVisitor final : public VNVisitor {
    // NODE STATE
    // AstVarRef::user2()       -> bool, 1 = Node is a class handle reference. The handle gets
    //                                       modified in the context of this reference.
    const VNUser2InUse m_inuser2;

    // STATE - for current AstNodeModule
    AstNodeModule* m_modp = nullptr;  // Class/module we are currently under
    AstTask* m_tasksp = nullptr;  // Tasks exrtracted under current module
    size_t m_nForkTasks = 0;  // Sequence numbers for task names

    // STATE - for current AstFork item
    bool m_inFork = false;  // Traversal in an async fork
    bool m_hasNestedFork = false;  // Branch being taskified contains a nested fork
    bool m_inInitStmt = false;  // Traversal in InitialStaticStmt/InitialAutomaticStmt
    AstNodeFTask* m_ftaskp = nullptr;  // Enclosing function/task
    std::set<AstVar*> m_forkLocalsp;  // Variables local to a given fork
    AstVar* m_capturedVarsp = nullptr;  // Local copies of captured variables
    AstArg* m_capturedArgsp = nullptr;  // References to captured variables (as args)

    // METHODS
    AstVar* capture(AstVarRef* refp) {
        for (AstVar* const varp : VNList<AstVar>{m_capturedVarsp}) {
            if (varp->name() == refp->name()) return varp;
        }

        // Create a local copy to capture
        FileLine* const flp = refp->fileline();
        AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP, refp->name(), refp->dtypep()};
        varp->direction(VDirection::INPUT);
        varp->funcLocal(true);
        varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        varp->isPastValue(refp->varp()->isPastValue());
        m_capturedVarsp = AstNode::addNext(m_capturedVarsp, varp);
        // Pass variable as argument
        AstArg* const argp = new AstArg{flp, refp->name(), refp->cloneTree(false)};
        m_capturedArgsp = AstNode::addNext(m_capturedArgsp, argp);
        return varp;
    }

    // Wrap body of the given AstFork branch in an AstTask, and replace body with a call to that
    // task. Returns true iff wrapped.
    bool taskify(AstForkItem* itemp) {
        // Visit statement to gather variables (And recursively process)
        VL_RESTORER_CLEAR(m_forkLocalsp);
        VL_RESTORER(m_hasNestedFork);
        m_hasNestedFork = false;
        VL_RESTORER(m_capturedVarsp);
        VL_RESTORER(m_capturedArgsp);
        m_capturedVarsp = nullptr;
        m_capturedArgsp = nullptr;
        iterate(itemp);

        // No need to do it if no variabels are captured
        if (m_forkLocalsp.empty() && !m_capturedVarsp && !v3Global.opt.fTaskifyAll()) return false;

        // Create task holding the statement and repalce statement with call to that task
        FileLine* const flp = itemp->fileline();
        const std::string name = "__VforkTask_" + std::to_string(m_nForkTasks++);
        AstTask* const taskp = new AstTask{flp, name};
        taskp->addDeclsp(m_capturedVarsp);
        taskp->forkBranch(true);
        // A branch that spawns another process must hand its captured variables over to it
        if (m_hasNestedFork) {
            taskp->classMethod(VN_IS(m_modp, Class));
            taskp->isStatic(m_ftaskp && m_ftaskp->isStatic());
        }
        // Prepend, so each task precedes those of forks nested in it, and V3Begin visits its call
        // before the task
        m_tasksp = AstNode::addNext(taskp, m_tasksp);
        if (itemp->declsp()) taskp->addDeclsp(itemp->declsp()->unlinkFrBackWithNext());
        AstTaskRef* const callp = new AstTaskRef{flp, taskp, m_capturedArgsp};
        AstBegin* const beginp
            = itemp->stmtsp() ? VN_CAST(itemp->stmtsp()->lastp(), Begin) : nullptr;
        if (beginp && !beginp->name().empty()) {
            // A named block stays at the fork with the call, so V3Begin keeps its scope for
            // hierarchical references recorded relative to it (see BeginXRefScopeVisitor)
            if (beginp->declsp()) taskp->addDeclsp(beginp->declsp()->unlinkFrBackWithNext());
            // Statements before the block, e.g. the start sentinel, still run first
            while (itemp->stmtsp() != beginp) taskp->addStmtsp(itemp->stmtsp()->unlinkFrBack());
            if (beginp->stmtsp()) taskp->addStmtsp(beginp->stmtsp()->unlinkFrBackWithNext());
            beginp->addStmtsp(callp->makeStmt());
        } else {
            if (itemp->stmtsp()) taskp->addStmtsp(itemp->stmtsp()->unlinkFrBackWithNext());
            itemp->addStmtsp(callp->makeStmt());
        }

        // Variables were moved under the task, so make sure they are marked as funcLocal
        for (AstVar* const localp : m_forkLocalsp) localp->funcLocal(true);

        // We did wrap the body
        return true;
    }
    static bool isForkJoinNoneSentinelDelay(const AstNode* const nodep) {
        const AstDelay* const delayp = VN_CAST(nodep, Delay);
        return delayp && delayp->isForkBranchStart();
    }
    static bool isDisableQueuePushSelfPrefix(AstNode* nodep) {
        while (AstJumpBlock* const jumpBlockp = VN_CAST(nodep, JumpBlock)) {
            nodep = jumpBlockp->stmtsp();
        }
        return nodep && nodep->isDisableQueuePushSelfStmt();
    }
    template <typename T_Owner>
    static bool insertForkSentinelAfterDisableQueuePushes(T_Owner* const ownerp,
                                                          AstNode* const firstStmtp,
                                                          AstNodeStmt* const delayp) {
        AstNode* insertBeforep = firstStmtp;
        while (insertBeforep && insertBeforep->isDisableQueuePushSelfStmt()) {
            insertBeforep = insertBeforep->nextp();
        }
        if (AstJumpBlock* const jumpBlockp = VN_CAST(insertBeforep, JumpBlock)) {
            if (insertForkSentinelAfterDisableQueuePushes(jumpBlockp, jumpBlockp->stmtsp(),
                                                          delayp)) {
                return true;
            }
        }
        if (insertBeforep == firstStmtp) return false;
        if (insertBeforep) {
            insertBeforep->addHereThisAsNext(delayp);
        } else {
            ownerp->addStmtsp(delayp);
        }
        return true;
    }
    static void moveForkSentinelAfterDisableQueuePushes(AstForkItem* const itemp) {
        AstNodeStmt* const firstStmtp = itemp->stmtsp();
        if (!isForkJoinNoneSentinelDelay(firstStmtp)) return;
        AstNode* const afterSentinelp = firstStmtp->nextp();
        if (!isDisableQueuePushSelfPrefix(afterSentinelp)) return;

        AstNodeStmt* const delayp = firstStmtp->unlinkFrBack();
        const bool moved
            = insertForkSentinelAfterDisableQueuePushes(itemp, afterSentinelp, delayp);
        UASSERT_OBJ(moved, itemp, "Failed to move fork sentinel after disable queue pushes");
    }
    static bool forkIsDisableable(AstFork* const nodep) {
        for (AstForkItem* const itemp : nodep->forkspList()) {
            if (isDisableQueuePushSelfPrefix(itemp->stmtsp())) return true;
        }
        return false;
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_nForkTasks);
        VL_RESTORER(m_tasksp);
        m_modp = nodep;
        m_nForkTasks = 0;
        m_tasksp = nullptr;
        iterateChildren(nodep);
        // Add extracted tasks, they don't need to be visited again
        if (m_tasksp) nodep->addStmtsp(m_tasksp);
    }

    void visit(AstFork* nodep) override {
        m_hasNestedFork = true;
        // IEEE 1800-2023 9.3.2: In all cases, processes spawned by a fork-join block shall not
        // start executing until the parent process is blocked or terminates. Because join and
        // join_any block the parent process, deferring branch start with a synthetic #0 delay is
        // normally only needed for join_none. A fork that can be disabled by name needs the same
        // deferral for every join type so all branches register their processes before any branch
        // body can disable the block. Compiler-generated immediate-start forks already have the
        // required ordering and must arm their event controls before the parent continues.
        if ((nodep->joinType().joinNone() && !nodep->immediateStart())
            || forkIsDisableable(nodep)) {
            UINFO(9, "Adding fork branch start sentinels " << nodep);
            FileLine* fl = nodep->fileline();
            // The branch start goes to the ACTIVE region of the current time slot, unlike a #0
            for (AstForkItem* const itemp : nodep->forkspList()) {
                if (!itemp->stmtsp()) continue;
                AstDelay* const delayp = new AstDelay{fl, new AstConst{fl, 0}, false};
                delayp->isForkBranchStart(true);
                itemp->prependStmtsp(delayp);
                moveForkSentinelAfterDisableQueuePushes(itemp);
            }
        }

        iterateAndNextNull(nodep->declsp());
        iterateAndNextNull(nodep->stmtsp());

        // A plain 'join' blocks the parent until every branch finishes, so a branch cannot
        // outlive the variables it references and need not be extracted into a task; just
        // recurse to process any forks nested inside the branches. join_any and join_none
        // branches may outlive the fork, so each branch body is wrapped in a task that
        // captures the variables it references.
        if (nodep->joinType().join()) {
            iterateAndNextNull(nodep->forksp());
            return;
        }

        std::vector<AstForkItem*> wrappedp;
        {
            VL_RESTORER(m_inFork);
            m_inFork = true;
            for (AstForkItem* const itemp : nodep->forkspList()) {
                if (taskify(itemp)) wrappedp.push_back(itemp);
            }
        }
        // Analyze replacements in context of enclosing fork
        for (AstForkItem* const itemp : wrappedp) iterateAndNextNull(itemp);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_ftaskp);
        m_ftaskp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        if (m_inFork) m_forkLocalsp.insert(nodep);
    }
    void visit(AstVarRef* nodep) override {
        if (!m_inFork) return;
        AstVar* const varp = nodep->varp();
        // Not sure why this is OK ...
        if (!varp->isFuncLocal() && varp->isClassMember()) return;
        // We must know the lifetime at this point, otherwise we can't decide if need to capture
        UASSERT_OBJ(!varp->lifetime().isNone(), nodep, "Variable's lifetime is unknown");
        // Static variables are fine, they are always availabel
        if (varp->lifetime().isStatic()) return;
        // If this ref is to a variable that will move into the task, then nothing to do
        if (m_forkLocalsp.count(varp)) return;

        if (nodep->access().isWriteOrRW() && (!nodep->isClassHandleValue() || nodep->user2())
            && !m_inInitStmt) {
            nodep->v3warn(
                E_LIFETIME,
                "Invalid reference: Process might outlive variable "
                    << varp->prettyNameQ() << ".\n"
                    << varp->warnMore()
                    << "... Suggest use it as read-only to initialize a local copy at the "
                       "beginning of the process, or declare it as static. It is also "
                       "possible to refer by reference to objects and their members.");
            return;
        }

        // Capture variable and redirect reference to the capturede copy
        nodep->varp(capture(nodep));
    }
    void visit(AstAssign* nodep) override {
        if (VN_IS(nodep->lhsp(), VarRef) && nodep->lhsp()->isClassHandleValue()) {
            nodep->lhsp()->user2(true);
        }
        iterateChildren(nodep);
    }
    void visit(AstInitialAutomaticStmt* nodep) override {
        VL_RESTORER(m_inInitStmt);
        m_inInitStmt = true;
        iterateChildren(nodep);
    }
    void visit(AstInitialStaticStmt* nodep) override {
        VL_RESTORER(m_inInitStmt);
        m_inInitStmt = true;
        iterateChildren(nodep);
    }

    void visit(AstThisRef* nodep) override {}
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit ForkVisitor(AstNetlist* nodep) { visit(nodep); }
    ~ForkVisitor() override = default;
};

//######################################################################
// Fork class functions

void V3Fork::makeDynamicScopes(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { DynScopeVisitor{nodep}; }
    V3Global::dumpCheckGlobalTree("fork_dynscope", 0, dumpTreeEitherLevel() >= 3);
}

void V3Fork::makeTasks(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { ForkVisitor{nodep}; }
    V3Global::dumpCheckGlobalTree("fork_tasks", 0, dumpTreeEitherLevel() >= 3);
}
