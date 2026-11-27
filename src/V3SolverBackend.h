// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Interface between randomize() lowering and constraint solvers
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
// V3Randomize is split into a solver-neutral front end (V3Randomize.cpp) and
// a constraint solver back-end. See V3SolverBackend.cpp for the contract
// between them.
//
//*************************************************************************

#ifndef VERILATOR_V3SOLVERBACKEND_H_
#define VERILATOR_V3SOLVERBACKEND_H_

#include "config_build.h"
#include "verilatedos.h"

#include "V3Ast.h"

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class V3UniqueNames;
class VMemberMap;

//######################################################################
// Definitions shared by the randomize front end and the back-ends

// Separates the levels of the name of a global constraint flattened into a class
static constexpr const char* GLOBAL_CONSTRAINT_SEPARATOR = "__DT__";
// Name of the method randomizing the variables the solver does not
static constexpr const char* BASIC_RANDOMIZE_FUNC_NAME = "__VBasicRand";

// ######################################################################
// Stores info about a variable's rand_mode state/a constraint's constraint_mode state

union RandomizeMode final {
    // MEMBERS
    struct {
        bool usesMode : 1;  // Variable/constraint uses rand_mode/constraint_mode
        uint32_t index : 31;  // Index of var/constraint in rand_mode/constraint_mode vector
    };
    uint64_t asUQuad;  // Representation as int to be stored in nodep->user*
};

// A constraint made by cloning the constraint of an object, or of the objects of an array
struct ClonedConstraint final {
    AstNodeExpr* objp;  // The object, or object array, it was cloned for
    AstConstraint* origp;  // The constraint it was cloned from
};
using ClonedConstraints = std::map<const AstConstraint*, ClonedConstraint>;

// The per-element rand_mode() state of arrays, created on first use
class ElemRandModes final {
    // MEMBERS
    const std::unordered_set<AstVar*>& m_arrays;  // Arrays with per-element rand_mode()
    std::unordered_map<const AstVar*, AstVar*> m_modeVars;  // Array -> its element modes
    AstAssocArrayDType* m_dtypep = nullptr;  // Type of the element modes

public:
    // CONSTRUCTORS
    explicit ElemRandModes(const std::unordered_set<AstVar*>& arrays)
        : m_arrays{arrays} {}
    // METHODS
    // Whether no array has per-element rand_mode()
    bool empty() const { return m_arrays.empty(); }
    // Whether arrVarp has per-element rand_mode()
    bool hasModes(AstVar* arrVarp) const { return m_arrays.count(arrVarp); }
    // Get or create the per-element rand_mode state of an array, nullptr if it has none
    AstVar* modeVarp(AstVar* arrVarp) VL_MT_DISABLED;
};

// The rand_mode/constraint_mode state arrays created by the front end
class RandModeVars final {
    // MEMBERS
    // Static constraint_mode array per root class
    std::unordered_map<AstClass*, AstVar*> m_staticConstraintModeVars;
    // Static rand_mode array per root class
    std::unordered_map<AstClass*, AstVar*> m_staticRandModeVars;

public:
    // METHODS
    void addStaticConstraintModeVar(AstClass* classp, AstVar* varp) {
        m_staticConstraintModeVars.emplace(classp, varp);
    }
    void addStaticRandModeVar(AstClass* classp, AstVar* varp) {
        m_staticRandModeVars.emplace(classp, varp);
    }
    // Static constraint_mode array of classp, or of its nearest base class with one
    AstVar* staticConstraintModeVarp(AstClass* classp) const VL_MT_DISABLED;
    // Static rand_mode array of classp, or of its nearest base class with one
    AstVar* staticRandModeVarp(AstClass* classp) const VL_MT_DISABLED;
    // Per-instance constraint_mode array (AstClass::user4p) of classp or its nearest base
    static AstVar* constraintModeVarp(AstClass* classp) VL_MT_DISABLED;
    // Per-instance rand_mode array (__Vrandmode, AstNodeModule::user2p) of classp or its
    // nearest base. user2p is only set on the root class where __Vrandmode was created.
    static AstVar* randModeVarp(AstNodeModule* classp) VL_MT_DISABLED;
    // Guard stmtp by the mode bit, if the variable/constraint uses one
    static AstNodeStmt* wrapIfMode(const RandomizeMode mode, AstVar* modeVarp,
                                   AstNodeStmt* stmtp) VL_MT_DISABLED;
};

//######################################################################
// Helpers shared by the randomize front end and the back-ends

class RandomizeUtil final {
public:
    // Look through unpacked array dimensions to the element type
    static AstNodeDType* arrayElementDTypep(AstNodeDType* dtypep) VL_MT_DISABLED;
    // Offset of the element at declared index idxp of array arrDtp, as selects and the solver
    // use
    static AstNodeExpr* newElemOffsetp(FileLine* fl, const AstNodeDType* arrDtp,
                                       AstNodeExpr* idxp) VL_MT_DISABLED;
    // Element of array arrp at declared index idxVarp
    static AstNodeExpr* newIdxSelp(FileLine* fl, AstNodeExpr* arrp,
                                   AstVar* idxVarp) VL_MT_DISABLED;
    // Element of array arrp at the declared indices idxVarps, one for each dimension
    static AstNodeExpr* newElemSelp(FileLine* fl, AstNodeExpr* arrp,
                                    const std::vector<AstVar*>& idxVarps) VL_MT_DISABLED;
    // Whether varp is an unpacked array of class handles
    static bool isClassHandleArray(const AstVar* varp) VL_MT_DISABLED;
    // Return the random index select into a non-random array that exprp reads through
    static AstNodeExpr*
    randIndexSelp(AstNodeExpr* exprp,
                  bool (*isRandIndexp)(const AstNodeExpr* indexp)) VL_MT_DISABLED;
    // Return the random index select into a random array that exprp reads through
    static AstNodeExpr* randArrayIndexSelp(
        AstNodeExpr* exprp,
        const std::function<bool(const AstNodeExpr* indexp)>& isRandIndexp) VL_MT_DISABLED;
    // Whether the array element at indexp has rand_mode off, given the array's modesp
    static AstNodeExpr* newElemModeOffp(AstNodeExpr* modesp, AstNodeExpr* indexp) VL_MT_DISABLED;
    // Read reference to member varp of objp, or of 'this' if objp is nullptr
    static AstNodeExpr* newMemberRefp(FileLine* fl, AstNodeExpr* objp,
                                      AstVar* varp) VL_MT_DISABLED;
};

//######################################################################
// Lowering of the randomize sites of one V3Randomize pass, created by
// V3SolverBackend::newLowering()

// The rand class handles whose objects' constraints are those of the object's class, as a
// class derived from the handle's declares constraints (IEEE 1800-2023 18.5.2), so are solved
// at runtime by the object (see V3SolverSmt), not cloned from the handle's class
class RandDispatch final {
    // Classes with a derived class declaring constraints or rand class handles
    std::unordered_set<const AstClass*> m_dispatchps;
    // Classes whose objects may be merged by their own class: those and their derived
    // classes, and the classes of their rand class handles, and so on
    std::unordered_set<const AstClass*> m_mergedps;
    // While constructing
    std::unordered_map<const AstClass*, std::vector<const AstClass*>> m_derivedps;
    std::vector<const AstClass*> m_pending;  // Merged classes whose relations to merge

    // METHODS
    static bool declaresDispatch(const AstClass* classp) VL_MT_DISABLED;
    static bool isMergeable(const AstClass* classp) VL_MT_DISABLED;
    static void addDispatchBases(const AstClass* classp,
                                 std::unordered_set<const AstClass*>& basesr) VL_MT_DISABLED;
    std::unordered_set<const AstClass*>
    mergedClosure(const std::unordered_set<const AstClass*>& dispatchps) VL_MT_DISABLED;
    void addMerged(const AstClass* classp) VL_MT_DISABLED;
    void mergePending() VL_MT_DISABLED;

public:
    explicit RandDispatch(AstNetlist* netlistp) VL_MT_DISABLED;
    // Whether objects of classp may be merged by their own class (has __Vnested_merge)
    bool isMerged(const AstClass* classp) const { return m_mergedps.count(classp); }
    // Whether the object of a rand class handle of handleClassp, held by an object of
    // holderClassp, is merged by its own class, rather than solved by clones of the
    // constraints of handleClassp: if objects of a derived class declare constraints, or if
    // the holder's object is merged, as its handles' constraints are not cloned into it
    bool mergesHandle(const AstClass* holderClassp, const AstClass* handleClassp) const {
        return m_dispatchps.count(handleClassp) || m_mergedps.count(holderClassp);
    }
    // Class of a rand class handle member, else nullptr
    static AstClass* randHandleClassp(const AstVar* varp) VL_MT_DISABLED;
    // The paths of rand class handles, from classp through the handles of unmerged objects, to
    // the handles of merged objects, which classp's randomizer merges
    std::vector<std::vector<AstVar*>> mergedPaths(AstClass* classp) const VL_MT_DISABLED;
};

class V3SolverLowering VL_NOT_FINAL {
protected:
    // MEMBERS, shared with the front end for one V3Randomize pass
    VMemberMap& m_memberMap;  // Member names cached for fast lookup
    V3UniqueNames& m_uniqueNames;  // Unique names of temporaries, and of blocks holding them
    const RandModeVars& m_modeVars;  // rand_mode/constraint_mode state arrays
    ElemRandModes& m_elemModes;  // Per-element rand_mode() state
    const ClonedConstraints& m_cloneObjps;  // Constraints cloned from objects
    const RandDispatch& m_dispatch;  // Rand class handles whose objects' constraints dispatch
    VNDeleter& m_deleter;  // Deferred deletion of nodes removed by the back-end

public:
    // Directly derived classes of each class
    using DerivedClassMap = std::unordered_map<const AstClass*, std::vector<AstClass*>>;

protected:
    DerivedClassMap m_derivedClassps;  // Directly derived classes, see addFailureRestore
    bool m_derivedBuilt = false;  // m_derivedClassps is built
    std::unordered_set<const AstClass*> m_savedClasses;  // Classes copying their variables

    // CONSTRUCTORS
    V3SolverLowering(VMemberMap& memberMap, V3UniqueNames& uniqueNames,
                     const RandModeVars& modeVars, ElemRandModes& elemModes,
                     const ClonedConstraints& cloneObjps, const RandDispatch& dispatch,
                     VNDeleter& deleter)
        : m_memberMap{memberMap}
        , m_uniqueNames{uniqueNames}
        , m_modeVars{modeVars}
        , m_elemModes{elemModes}
        , m_cloneObjps{cloneObjps}
        , m_dispatch{dispatch}
        , m_deleter{deleter} {}

    // METHODS
    void pushDeletep(AstNode* nodep) { m_deleter.pushDeletep(nodep); }

public:
    virtual ~V3SolverLowering() = default;

    // Copy the random variables of the object of funcp, of classp or a derived class, also
    // those of the objects of its rand class handles, which a failed randomize() leaves
    // unchanged (IEEE 1800-2023 18.6.3), adding the call copying them to funcp now, and return
    // the statement, run after the solves, assigning them back if funcp failed, or discarding
    // the copies otherwise
    AstNodeStmt* addFailureRestore(AstFunc* funcp, AstClass* classp);

private:
    void addDerivedClass(AstClass* classp);

public:
    // Per class. prepareClass() is called before any class is lowered, for each
    // class that has constraint blocks, declared or inherited.
    virtual void prepareClass(AstClass* classp) = 0;
    // Called when the front end starts lowering classp, and again when it
    // resumes classp after lowering another class (that of a rand member)
    virtual void startClass(AstClass* classp) = 0;
    // Called, as the front end walks the class, for each method call in a
    // constraint block of modp, e.g. to rewrite '.size()' in place
    virtual void lowerConstraintMethod(AstNodeModule* modp, AstConstraint* constrp,
                                       AstCMethodHard* nodep)
        = 0;

    // Per site
    // Class randomize(): add the solver setup to randomizep, and return the
    // solver result (also when the class has no constraints). If keepSolution, basic
    // randomization does not change the solved values, nor a failure of it the variables.
    virtual AstNodeExpr* lowerClassRandomize(AstClass* classp, AstFunc* randomizep,
                                             AstVar* randModeVarp, bool keepSolution)
        = 0;
    // Class randomize(): add statements that must follow the solver result,
    // after the front end has emitted the assignment that evaluates it
    virtual void addAfterClassSolve(AstClass* classp, AstFunc* randomizep) = 0;
    // Complete class solver lowering after the result assignment, before the front end emits
    // post_randomize callbacks, then call basicRandomizep only if the solve succeeded:
    // __VBasicRand, or __VBasicRandVars of a class whose member objects are randomized after
    // the solve, then afterp, if any. If the solve failed, run failp, if any.
    virtual void finishClassRandomize(AstClass* classp, AstFunc* randomizep,
                                      AstFunc* basicRandomizep, AstNodeStmt* afterp,
                                      AstNodeStmt* failp)
        = 0;
    // Ensure backend-required related classes are lowered before an inline site. The callback
    // remains front-end-owned so its visitor context is restored across nested class lowering.
    virtual void prepareInlineRandomize(AstClass* classp,
                                        const std::function<void(AstClass*)>& lowerClass)
        = 0;
    // randomize() with {...} called by nodep: lower the captured constraints
    // into randomizeFuncp, and assign its return value from the solver result
    // and, after a successful solve, basicp, the basic randomization updating it, and elemsp,
    // if any, then afterp, if any; if the solve failed, failp, and elemsFailp, the pre_randomize
    // of what elemsp randomizes, unless elemsp ran. With a solve of array sizes, elemsp runs after
    // the arrays are resized, in the final function-call round; its failure skips the final solve.
    // thisVarp is the captured 'this' of the caller.
    virtual void lowerInlineRandomize(AstNodeFTaskRef* nodep, AstClass* classp,
                                      AstFunc* randomizeFuncp, AstNode* capturedTreep,
                                      const AstVar* thisVarp, AstNodeStmt* basicp,
                                      AstNodeExpr* elemsp, AstNodeStmt* elemsFailp,
                                      AstNodeStmt* afterp, AstNodeStmt* failp)
        = 0;
    // std::randomize() with {...} called by nodep: lower the captured
    // constraints into randomizeFuncp, and return the solver result. stdrandp
    // is the module's std::randomize generator.
    virtual AstNodeExpr* lowerStdRandomizeWith(AstNodeFTaskRef* nodep, AstFunc* randomizeFuncp,
                                               AstNode* capturedTreep, AstVar* stdrandp)
        = 0;
    // Complete std::randomize solver lowering after its result assignment, before rollback.
    virtual void finishStdRandomizeWith(AstFunc* randomizep, AstVar* stdrandp) = 0;
    // randomize(null): add the constraint check to funcp, and return its result
    virtual AstNodeExpr* lowerCheckOnly(AstClass* classp, AstFunc* funcp) = 0;
    // After every class and site is lowered
    virtual void finish() = 0;
};

//######################################################################
// Constraint solver back-end selected for the run, see V3Global::solverBackendp()

class V3SolverBackend VL_NOT_FINAL {
public:
    virtual ~V3SolverBackend() = default;

    // Header of the runtime library, included by the generated code
    virtual std::string runtimeHeader() const VL_MT_DISABLED = 0;
    // Runtime C++ files compiled with the model
    virtual std::vector<std::string> runtimeCppFiles() const VL_MT_DISABLED = 0;
    // Flags for VM_USER_CFLAGS of the generated makefile, from the environment
    virtual std::vector<std::string> runtimeCFlags() const VL_MT_DISABLED = 0;

    // Lowering for one V3Randomize pass, sharing the given state with the front end
    virtual std::unique_ptr<V3SolverLowering>
    newLowering(VMemberMap& memberMap, V3UniqueNames& uniqueNames, const RandModeVars& modeVars,
                ElemRandModes& elemModes, const ClonedConstraints& cloneObjps,
                const RandDispatch& dispatch, VNDeleter& deleter) const VL_MT_DISABLED
        = 0;
};

#endif  // Guard
