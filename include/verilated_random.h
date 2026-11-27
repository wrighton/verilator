// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// Code available from: https://verilator.org
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2001-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
///
/// \file
/// \brief Verilated randomization header
///
/// This file is included automatically by Verilator in some of the C++ files
/// it generates if randomization features are used.
///
/// This file is not part of the Verilated public-facing API.
/// It is only for internal use.
///
/// See the internals documentation docs/internals.rst for details.
///
//*************************************************************************
#ifndef VERILATOR_VERILATED_RANDOM_H_
#define VERILATOR_VERILATED_RANDOM_H_

#include "verilated.h"

#include <functional>
#include <initializer_list>
#include <iomanip>
#include <iostream>
#include <ostream>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

//=============================================================================

// VlRandomExpr and subclasses represent expressions for the constraint solver.
class ArrayInfo final {
public:
    const std::string
        m_name;  // Name of the array variable, including index notation (e.g., arr[2][1])
    void* const m_datap;  // Reference to the array variable data
    const int m_index;  // Flattened (1D) index of the array element
    const std::vector<IData> m_indices;  // Multi-dimensional indices of the array element
    const std::vector<size_t> m_idxWidths;  // Multi-dimensional indices' bit widths

    ArrayInfo(const std::string& name, void* datap, int index, const std::vector<IData>& indices,
              const std::vector<size_t>& idxWidths)
        : m_name{name}
        , m_datap{datap}
        , m_index{index}
        , m_indices{indices}
        , m_idxWidths{idxWidths} {}
};
// Keyed by the array's base name and the element's ordinal, kept apart so that, e.g.,
// element 10 of 'a' and element 0 of 'a1' are distinct
using ArrayInfoMap = std::map<std::pair<std::string, int>, std::shared_ptr<const ArrayInfo>>;

class VlRandomVar VL_NOT_FINAL {
    std::string m_name;  // Variable name
    void* const m_datap;  // Reference to variable data
    const int m_width;  // Variable width in bits
    const int m_dimension;  //Variable dimension, default is 0
    const std::uint32_t m_randModeIdx;  // rand_mode index
    // Declared element by element, each a constant named by elementName(), as the compiler
    // found every constraint reads it only so (V3SolverSmt SolverScalarArrayVisitor)
    mutable bool m_scalar = false;
    mutable std::vector<std::string> m_elemNames;  // elementName() of each index, as built

public:
    VlRandomVar(const std::string& name, int width, void* datap, int dimension,
                std::uint32_t randModeIdx)
        : m_name{name}
        , m_datap{datap}
        , m_width{width}
        , m_dimension{dimension}
        , m_randModeIdx{randModeIdx} {}
    virtual ~VlRandomVar() = default;
    std::string name() const { return m_name; }
    int width() const { return m_width; }
    int dimension() const { return m_dimension; }
    virtual void* datap(int /*idx*/) const { return m_datap; }
    virtual bool isArray() const { return false; }  // Whether an array, of elements
    // A copy named 'name', with no rand_mode index, to merge into another randomizer
    virtual std::shared_ptr<const VlRandomVar> renamed(const std::string& name) const {
        return std::make_shared<const VlRandomVar>(name, m_width, m_datap, m_dimension,
                                                   std::numeric_limits<std::uint32_t>::max());
    }
    std::uint32_t randModeIdx() const { return m_randModeIdx; }
    bool scalar() const { return m_scalar; }
    void scalar(bool flag) const { m_scalar = flag; }
    // The constant declaring element 'index' of a scalar array, "<name>__Vs<8 hex digits>",
    // built once for each index up to the largest one an element of the array had
    const std::string& elementName(IData index) const {
        for (IData i = static_cast<IData>(m_elemNames.size()); i <= index; ++i) {
            m_elemNames.emplace_back();
            elementNameOf(m_elemNames.back(), m_name, i, "__Vs");
        }
        return m_elemNames[index];
    }
    // Into resultr, "<name><tag><8 hex digits of index>"
    static void elementNameOf(std::string& resultr, const std::string& name, IData index,
                              const char* tag) {
        static const char* const s_digits = "0123456789abcdef";
        resultr = name + tag + "00000000";
        for (size_t i = resultr.size(); index; index >>= 4) resultr[--i] = s_digits[index & 0xf];
    }
    bool randModeIdxNone() const { return randModeIdx() == std::numeric_limits<unsigned>::max(); }
    void set(const std::string& idx, const std::string& val) const;
    virtual void emitGetValue(std::ostream& s) const;
    virtual void emitExtract(std::ostream& s, int i) const;
    virtual void emitType(std::ostream& s) const;
    // Emit the expression referring to element j as a whole (the full var
    // for scalars, "(select arr idx...)" for array element j). Used by BSAT
    // to query/re-assert one whole element's value, not a single bit.
    virtual void emitElement(std::ostream& s, int j) const;
    // Emit the current runtime value of element j (see emitElement) as an SMT literal
    void emitConcreteValue(std::ostream& s, int j) const;
    virtual int totalWidth() const;
    mutable std::shared_ptr<const ArrayInfoMap> m_arrVarsRefp;
    void setArrayInfo(const std::shared_ptr<const ArrayInfoMap>& arrVarsRefp) const {
        m_arrVarsRefp = arrVarsRefp;
        // Counts depend on the array info, which may come from another randomizer
        // sharing this variable
        count_cache.clear();
    }
    mutable std::map<std::string, int> count_cache;
    int countMatchingElements(const ArrayInfoMap& arr_vars, const std::string& base_name) const {
        if (VL_LIKELY(count_cache.find(base_name) != count_cache.end()))
            return count_cache[base_name];
        int count = 0;
        for (int index = 0; arr_vars.find({base_name, index}) != arr_vars.end(); ++index) {
            ++count;
        }
        count_cache[base_name] = count;
        return count;
    }
    bool hasMatchingElements(const ArrayInfoMap& arr_vars, const std::string& base_name) const {
        return arr_vars.find({base_name, 0}) != arr_vars.end();
    }
};
// SMT key width per associative-array level (string = 128, integral = 8 * sizeof).
template <typename T>
struct VlRandomAssocKeyWidths final {
    static void push(std::vector<size_t>&) {}
};
template <typename T_Key, typename T_Value, typename T_KeyLess>
struct VlRandomAssocKeyWidths<VlAssocArray<T_Key, T_Value, T_KeyLess>> final {
    static void push(std::vector<size_t>& widths) {
        widths.push_back(std::is_same<T_Key, std::string>::value ? 128 : sizeof(T_Key) * 8);
        VlRandomAssocKeyWidths<T_Value>::push(widths);
    }
};
template <typename T>
class VlRandomArrayVarTemplate final : public VlRandomVar {
    // Static key widths per level for the empty-array declaration fallback
    const std::vector<size_t> m_fallbackIdxWidths;

public:
    VlRandomArrayVarTemplate(const std::string& name, int width, void* datap, int dimension,
                             std::uint32_t randModeIdx, const std::vector<size_t>& idxWidths = {})
        : VlRandomVar{name, width, datap, dimension, randModeIdx}
        , m_fallbackIdxWidths{idxWidths} {}
    bool isArray() const override { return true; }
    std::shared_ptr<const VlRandomVar> renamed(const std::string& name) const override {
        const auto copyp = std::make_shared<const VlRandomArrayVarTemplate>(
            name, width(), VlRandomVar::datap(0), dimension(),
            std::numeric_limits<std::uint32_t>::max(), m_fallbackIdxWidths);
        copyp->scalar(scalar());
        return copyp;
    }
    void* datap(int idx) const override {
        const auto it = m_arrVarsRefp->find({name(), idx});
        if (VL_LIKELY(it != m_arrVarsRefp->end())) return it->second->m_datap;
        VL_FATAL_MT(__FILE__, __LINE__, "randomize", "indexed_name not found in m_arr_vars");
        return nullptr;  // LCOV_EXCL_BR_LINE
    }
    void emitHexs(std::ostream& s, const std::vector<IData>& indices, const size_t bit_width,
                  size_t idx) const {
        for (int j = bit_width - 4; j >= 0; j -= 4) {
            s << "0123456789abcdef"[(indices[idx] >> j) & 0xf];
        }
    }
    void emitSelect(std::ostream& s, const std::vector<IData>& indices,
                    const std::vector<size_t>& idxWidths) const {
        if (scalar()) {
            s << elementName(indices[0]);
            return;
        }
        const size_t num_indices = idxWidths.size();
        size_t wide_size = 0;

        for (size_t idx = 0; idx < num_indices; ++idx) s << "(select ";
        s << name();

        for (size_t idx = 0; idx < num_indices; ++idx) {
            const size_t bit_width = idxWidths[idx];
            s << " #x";

            const size_t emit_count = (bit_width > 32) ? (idxWidths[idx] / 32) : 1;

            for (size_t i = 0; i < emit_count; ++i) {
                emitHexs(s, indices, (bit_width > 32) ? 32 : bit_width, wide_size + i);
            }

            wide_size += (idxWidths[idx] > 32) ? (idxWidths[idx] / 32) : 1;
            s << ")";
        }
    }
    void emitGetValue(std::ostream& s) const override {
        const int elementCounts = countMatchingElements(*m_arrVarsRefp, name());
        for (int i = 0; i < elementCounts; ++i) {
            const auto it = m_arrVarsRefp->find({name(), i});
            if (it != m_arrVarsRefp->end()) {
                const std::vector<IData>& indices = it->second->m_indices;
                const std::vector<size_t>& idxWidths = it->second->m_idxWidths;
                if (scalar()) s << ' ';
                emitSelect(s, indices, idxWidths);
            } else {
                VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                            "indexed_name not found in m_arr_vars");
            }
        }
    }
    void emitType(std::ostream& s) const override {
        const auto it = m_arrVarsRefp->find({name(), 0});
        if (it != m_arrVarsRefp->end()) {
            const std::vector<size_t>& idxWidths = it->second->m_idxWidths;
            if (dimension() > 0) {
                for (int i = 0; i < dimension(); ++i) {
                    s << "(Array (_ BitVec " << idxWidths[i] << ") ";
                }
                s << "(_ BitVec " << width() << ")";
                for (int i = 0; i < dimension(); ++i) s << ")";
            }
        } else {
            if (dimension() > 0) {
                // Empty array: declare from the static key widths, not a 32-bit default.
                for (int i = 0; i < dimension(); ++i) {
                    const size_t idxWidth = i < static_cast<int>(m_fallbackIdxWidths.size())
                                                ? m_fallbackIdxWidths[i]
                                                : 32;
                    s << "(Array (_ BitVec " << idxWidth << ") ";
                }
                s << "(_ BitVec " << width() << ")";
                for (int i = 0; i < dimension(); ++i) s << ")";
            } else {
                VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                            "indexed_name not found in m_arr_vars");
            }
        }
    }
    int totalWidth() const override {
        const int elementCounts = countMatchingElements(*m_arrVarsRefp, name());
        return width() * elementCounts;
    }
    void emitElement(std::ostream& s, int j) const override {
        const auto it = m_arrVarsRefp->find({name(), j});
        // Callers take j from totalWidth(), which counts these same keys, so the element
        // should always be there
        if (VL_UNCOVERABLE(it == m_arrVarsRefp->end())) {
            // LCOV_EXCL_START
            VL_FATAL_MT(__FILE__, __LINE__, "randomize", "indexed_name not found in m_arr_vars");
            return;
            // LCOV_EXCL_STOP
        }
        s << ' ';
        emitSelect(s, it->second->m_indices, it->second->m_idxWidths);
    }  // LCOV_EXCL_BR_LINE
    void emitExtract(std::ostream& s, int i) const override {
        const int j = i / width();
        i = i % width();
        s << " ((_ extract " << i << ' ' << i << ')';
        if (scalar()) s << ' ';
        const auto it = m_arrVarsRefp->find({name(), j});
        if (it != m_arrVarsRefp->end()) {
            const std::vector<IData>& indices = it->second->m_indices;
            const std::vector<size_t>& idxWidths = it->second->m_idxWidths;
            emitSelect(s, indices, idxWidths);
        } else {
            VL_FATAL_MT(__FILE__, __LINE__, "randomize", "indexed_name not found in m_arr_vars");
        }
        s << ')';
    }
};

class VlSolverSession;
enum class VlSolverStatus : uint8_t;

//=============================================================================
// Object holding constraints and variable references.
class VlRandomizer VL_NOT_FINAL {
    // MEMBERS
    std::vector<std::string> m_constraints;  // Solver-dependent hard constraints
    std::vector<std::string> m_freshVars;  // Solver constants of fresh_const()
    // Constants of indices a constraint selects from a scalar array that has no element there,
    // by name, with their widths: declared, so a guard of the select keeps its meaning (an
    // array whose size is solved has the elements of its size only after the size phase), but
    // never read back
    struct GhostElem final {
        int m_width;  // Width of the array's elements
        std::string m_array;  // Name of the array
        IData m_index;  // Index of the element
    };
    std::map<std::string, GhostElem> m_ghostElems;
    // Terms of elements a constraint selects from a scalar array at an index the solver gives
    // (q[$] of a queue whose size is solved, or with a random offset), in order: each defined,
    // see emitDeclares, as the element terms of its index, the earlier ones' if at theirs, or
    // a constant of its own
    struct ChainElem final {
        std::string m_name;  // Its constant
        std::string m_array;  // Name of the array
        std::string m_index;  // SMT term of its index, in the 32-bit index sort
    };
    std::vector<ChainElem> m_chainElems;
    // Each scalar array element's constant, by name, as last declared, see emitDeclares
    mutable std::unordered_map<std::string,
                               std::pair<const VlRandomVar*, std::shared_ptr<const ArrayInfo>>>
        m_scalarElems;
    // Solver variables the hard constraints name, flattened in m_constraints order; the
    // string literals of the generated code, so stored without copying
    std::vector<const char*> m_constraintVarNames;
    // Per hard constraint, the end of its names in m_constraintVarNames
    std::vector<size_t> m_constraintVarEnds;
    std::vector<std::string>
        m_constraints_line;  // fileline content of the constraint for unsat constraints
    std::vector<std::string> m_softConstraints;  // Soft constraints
    // Solver variables the soft constraints are disabled by, flattened in m_softConstraints
    // order; copied, as the name of an object in an array is formatted at runtime
    std::vector<std::string> m_softVarNames;
    // Per soft constraint, the end of its names in m_softVarNames
    std::vector<size_t> m_softVarEnds;
    std::map<std::string, std::shared_ptr<const VlRandomVar>> m_vars;  // Solver-dependent
    // Scratch buffer for randomConstraint(), reused across calls
    std::vector<const VlRandomVar*> m_randomConstraintVars;
    std::set<std::string> m_disabledVars;  // Variables with rand_mode off (skip write-back)
                                           // variables
    // Names and bytes of variables
    using KeptValues = std::vector<std::pair<std::string, std::string>>;
    KeptValues m_solution;  // The solved values, see keep_solution
    KeptValues m_prior;  // The values before the solve, see keep_prior
    std::map<std::string, std::set<uint64_t>> m_priorRandc;  // m_randcUsedValues then
    KeptValues m_roundValues;  // The values before a function-call solve round first set them
    std::unordered_set<std::string> m_roundKept;  // Variables in m_roundValues
    // Array size variables, by registered name, which a solve of array sizes alone sets
    std::unordered_set<std::string> m_sizeVars;
    std::unordered_set<std::string> m_heldLookups;  // See markHeldLookup
    // Size assignments the size solves of this call exclude (see exclude_sizes)
    std::vector<std::string> m_sizeExclusions;
    bool m_quietUnsat = false;  // An unsatisfied solve is not reported (see quiet_unsat)
    bool m_unsat = false;  // The last solve failed as its constraints are unsatisfied
    ArrayInfoMap m_arr_vars;  // Tracks each element in array structures for iteration
    // Arrays whose elements must be distinct grouped by unique constraint
    std::map<uint32_t, std::unordered_set<std::string>> m_uniqueArrays;
    // The values a hard constraint allows every element of an array, see uniqueDomainsUnsat
    struct UniqueDomain final {
        size_t constraint;  // Index of the constraint on the first element, for its warning
        uint32_t width;  // Of an element
        bool isSigned;
        std::vector<std::pair<uint64_t, uint64_t>> ranges;  // Keys of the values, in order
    };
    std::unordered_map<std::string, std::vector<UniqueDomain>> m_uniqueDomains;
    std::string m_uniqueDomainName;  // Of the array unique_range() adds values to
    // Variable name and constraint of each pin_frozen()
    std::vector<std::pair<std::string, std::string>> m_frozenPins;
    std::vector<std::string> m_tables;  // Body of each table
    std::vector<std::string> m_tableHeads;  // Head of each definition: parameter, value sort
    std::vector<std::string> m_tableNames;  // Name of each, kept by merge_nested()
    std::vector<uint8_t> m_tableNeeds;  // Of each, see TableNeeds
    std::unordered_multimap<size_t, size_t> m_tableIds;  // Own tables by hash of head and body
    std::string m_tablePrefix;  // Suffix of its tables' names, see table_prefix_from()
    size_t m_tablesMerged = 0;  // Objects table_prefix_from() named since clearConstraints()
    size_t m_pendingTablesHash = 0;  // Of the tables table_end() named for the next constraint
    std::vector<size_t> m_constraintTablesHash;  // Per hard constraint, of the tables it calls
    // The tables being built, innermost last, as an entry's value may read another
    struct TableBuilder final {
        std::string head;  // See m_tableHeads
        int indexWidth;  // Of the key
        bool positional;  // Whether the keys are the positions 0, 1, ... in order, none missing
        uint8_t needs;  // See TableNeeds
        std::vector<std::string> keys;
        std::vector<std::string> values;
    };
    std::vector<TableBuilder> m_tableBuilders;
    // Arrays clear_elem_vars() unregistered since clearConstraints()
    std::set<std::string> m_elemVarsCleared;
    const VlQueue<CData>* m_randmodep = nullptr;  // rand_mode state;
    const VlQueue<CData>* m_static_randmodep = nullptr;  // Static rand_mode state (shared)
    std::unordered_set<std::string> m_staticVars;  // Names of static rand vars
    int m_index = 0;  // Internal counter for key generation
    std::set<std::string> m_randcVarNames;  // Names of randc variables for cyclic tracking
    // Enum domain per variable: a Bool SMT term over '__Ve', asserted for each element.
    // A string literal from the generated code, so the pointer stays valid.
    std::map<std::string, const char*> m_enumDomains;
    // Previously used values per randc variable element, keyed by its solver term
    // (exclusion-based cycling)
    std::map<std::string, std::set<uint64_t>> m_randcUsedValues;
    size_t m_randcConstraintHash = 0;  // Hash of constraints when history was valid
    // A solve-before operand: bits [lsb, lsb + width) of a variable or array element, all if
    // width is 0
    struct SolveBeforeRef final {
        std::string name;
        IData lsb;
        IData width;
    };
    std::vector<std::pair<SolveBeforeRef, SolveBeforeRef>>
        m_solveBefore;  // Solve-before ordering pairs (before, after)
    // Bits [lo, hi) of a variable or array element that a solve-before operand orders
    struct SolveBeforeBits final {
        const VlRandomVar* rootp;  // Variable or array element
        const VlRandomVar* arrayp;  // Array of an array element, else nullptr
        IData lo;  // First bit
        IData hi;  // Bit after the last
    };
    // Array elements that solve-before pairs name, as variables of their solver terms
    std::map<std::string, std::shared_ptr<const VlRandomVar>> m_solveBeforeElems;
    // Arrays of the array elements that solve-before pairs name
    std::map<std::string, const VlRandomVar*> m_solveBeforeArrays;
    bool m_checkOnly = false;  // Set for randomize(null)
    bool m_spreadFailed = false;  // A solver failure cut this call's spreading short
    bool m_warnedSpreadFailed = false;  // Warned of a spreading cut short
    bool m_warnedSpreadBroke = false;  // Warned of a spreading that broke the solver
    // The pause of spreading after it broke the solver. A copy of the object spreads afresh.
    struct SpreadPause final {
        uint32_t skips = 0;  // Later calls that do not spread
        uint32_t length = 0;  // Calls the last break paused spreading for
        bool now = false;  // This call does not spread
        SpreadPause() = default;
        SpreadPause(const SpreadPause&) {}
        SpreadPause& operator=(const SpreadPause&) {
            skips = 0;
            length = 0;
            now = false;
            return *this;
        }
    };
    SpreadPause m_spreadPause;
    bool m_uniqueLazy = false;  // Uniqueness groups are solved lazily, see refineUnique
    // Members of null handles constraints may read, by solver name, with their source names
    std::vector<std::pair<std::string, std::string>> m_nullReads;
    // Why this randomize() fails without solving, e.g. a constraint reading one of them;
    // empty if it does not
    std::string m_failPending;
    const char* m_failFilename = nullptr;  // Where the cause is
    uint32_t m_failLinenum = 0;  // And line
    bool m_failWarned = false;  // The cause was reported where it was found
    bool m_sizeSolve = false;  // Set for the solve of array sizes before the final solve
    bool m_sizeSolved = false;  // The sizes are solved, so the final solve is next
    // Function argument variable solved in an earlier round (IEEE 1800-2023 18.5.11)
    struct FuncArgRound final {
        std::string name;  // Solver name of the variable
        int round;  // Solve round that solves it
        std::string pin;  // Constraint fixing its solved value, once its round is over
    };
    std::vector<FuncArgRound> m_funcArgRounds;  // Function argument variables
    int m_funcRound = 0;  // Current solve round
    int m_funcRoundLast = 0;  // Final solve round
    bool funcPreRound() const { return m_funcRound < m_funcRoundLast; }
    void keepRoundValues(const VlRandomVar& var);  // Keep var's value before a round sets it
    static void keepValues(const VlRandomVar& var, KeptValues& valuesr);
    void keepVars(KeptValues& valuesr) const;
    void setValues(const KeptValues& values) const;
    // The solver variables and constraints of the objects of rand class handles (see
    // merge_nested), by the handle's path: names added, and names disabled
    std::map<std::string, std::pair<std::vector<std::string>, std::vector<std::string>>> m_nested;
    bool m_nestedBusy = false;  // Merging the objects of rand class handles (see nested_busy)
    // First key of the unique arrays of merged randomizers (see merge_nested)
    static constexpr uint32_t s_mergedUniqueKey = 1U << 31;
    // While merging, the names of the variables registered here, by their storage
    std::unordered_map<const void*, std::string> m_nestedNames;
    // The name here of variable 'fromName' of a merged randomizer, registered if new
    std::string mergeVar(const VlRandomizer& from, const std::string& fromName,
                         const std::string& path, std::vector<std::string>& addedr);
    // Register the elements of array 'fromName' of a merged randomizer as of array 'name'
    void mergeArrayElements(const VlRandomizer& from, const std::string& fromName,
                            const std::string& name);
    // The name here of a variable of a merged randomizer
    static std::string renamedVar(const std::unordered_map<std::string, std::string>& renames,
                                  const std::string& name);
    bool isFrozenVar(const std::string& name,
                     const VlRandomVar& var) const;  // true if this var is currently frozen
    bool hasFrozenVar() const;  // true if any var is currently rand_mode(0)-frozen
    bool spreads() const;  // Whether this call spreads its solution
    // Remove from m_vars, into hiddenr, the frozen arrays of m_heldLookups no constraint of
    // this call names
    void hideUnnamedFrozen(std::map<std::string, std::shared_ptr<const VlRandomVar>>& hiddenr);

    // Structured domains emitted from the original constraint AST. Coordinates are
    // unsigned, with the sign bit flipped for signed variables, so order is monotone.
    struct FastRange final {
        QData lo;
        QData hi;
        QData weight;
        // Per value: the original :/ size dividing the weight, else 1. Range
        // mass: the original := size multiplying the weight, else 1; 0 is 2^64.
        QData scale;
    };
    using FastRanges = std::vector<FastRange>;
    struct FastConstraint final {
        void* datap;
        int width;
        bool isSigned;
        bool isSoft;
        bool isDist;
        bool rangeMass = false;  // IEEE 1800-2023 dist: each item weighs as a whole
        bool isEnum;  // This item supplies the complete enum domain
        FastRanges ranges;
        int viewLsb = 0;  // Constant extraction offset in physical storage
        int viewWidth = 0;  // Width before comparison/dist extension
        QData proposal = 0;  // Ordered coordinate of the original procedural draw
        bool hasProposal = false;
    };
    struct FastDomain final {
        const VlRandomVar* varp;
        int viewLsb = 0;
        int viewWidth = 0;
        bool isSigned = false;
        bool covered = false;
        QData pinMask = 0;
        QData pinBits = 0;
        bool pinConflict = false;
        FastRanges ranges;
        const FastConstraint* distp = nullptr;
    };
    // A scalar's values by its range constraints, to tie it to when spreading
    struct FastTarget final {
        FastRanges ranges;  // In the constraints' ordered coordinates
        int width;
        bool isSigned;
        QData count;  // Values in ranges
    };
    void fastTargets(std::unordered_map<const void*, FastTarget>& targetsr) const;
    static QData fastTargetValue(VlRNG& rngr, const FastTarget& target);
    std::vector<FastConstraint> m_fastConstraints;
    // A rand array whose elements its constraints read only one at a time, each against
    // constants, so they are sampled here rather than solved (see native_begin)
    struct NativeArray final {
        int width;  // Of its elements
        bool isSigned;
        std::vector<FastConstraint> items;  // Its constraints, in order, datap unused
        // Write each element from a sampler, or tell whether every element fits a domain
        std::function<void(const std::function<QData()>&)> fill;
        std::function<bool(const FastRanges&)> check;
    };
    std::unordered_map<const void*, NativeArray> m_nativeArrays;  // By its storage
    FastConstraint* m_nativeLastp = nullptr;  // The constraint native_range adds to
    // Variables of native arrays registered for every randomize(), as fixed-size ones are,
    // out of the solve until the next one sets up its constraints
    std::vector<std::pair<std::string, std::shared_ptr<const VlRandomVar>>> m_nativeHidden;
    std::vector<const void*> m_nativeOrder;  // Its keys, in the order registered
    bool m_fastDisabled = false;  // At least one original item cannot be represented
    static bool fastPinned(const FastConstraint& constraint);
    static bool fastView(FastDomain& domain);
    bool fastDomains(std::vector<FastDomain>& domains, std::unordered_map<void*, size_t>& indices);
    // Return -1 for fallback, 0 for an empty domain, 1 for a sampled solution.
    int nextFast(VlRNG& rngr);
    static FastRanges fastIntersect(const FastRanges& a, const FastRanges& b);
    static FastRanges fastUnion(FastRanges ranges);
    static bool solverSamplesOn();
    // A native array's domain and retained distribution, as nextFast forms a scalar's
    static void nativeDomain(const NativeArray& array, FastRanges& rangesr,
                             const FastConstraint*& distpr);
    void nativeFill(VlRNG& rngr);
    bool nativeCheck() const;
    template <typename T, size_t N_MaxSize>
    static T& nativeElem(VlQueue<T, N_MaxSize>& array, size_t index) {
        return array.atWrite(static_cast<int32_t>(index));
    }
    template <typename T, std::size_t N_Depth>
    static T& nativeElem(VlUnpacked<T, N_Depth>& array, size_t index) {
        return array[index];
    }
    template <typename T_Array>
    void nativeArray(T_Array& array, int width, bool isSigned) {
        const auto it = m_nativeArrays.find(&array);
        if (it != m_nativeArrays.end()) return;
        m_nativeOrder.push_back(&array);
        NativeArray& entry = m_nativeArrays[&array];
        entry.width = width;
        entry.isSigned = isSigned;
        T_Array* const arrayp = &array;
        entry.fill = [arrayp](const std::function<QData()>& sample) {
            const size_t size = arrayp->size();
            for (size_t i = 0; i < size; ++i) nativeElem(*arrayp, i) = sample();
        };
        entry.check = [arrayp, width, isSigned](const FastRanges& ranges) {
            const size_t size = arrayp->size();
            for (size_t i = 0; i < size; ++i) {
                QData key = static_cast<QData>(nativeElem(*arrayp, i)) & VL_MASK_Q(width);
                if (isSigned) key ^= QData{1} << (width - 1);
                if (std::none_of(ranges.begin(), ranges.end(), [key](const FastRange& range) {
                        return range.lo <= key && key <= range.hi;
                    })) {
                    return false;
                }
            }
            return true;
        };
    }
    static bool fastSample(VlRNG& rngr, const FastRanges& domain, const FastConstraint* distp,
                           QData& valuer);

    // PRIVATE METHODS
    void randomConstraint(std::ostream& os, VlRNG& rngr, int bits,
                          const std::vector<std::string>* layerVarsp = nullptr);
    // Fetch the model and write it into the registered variables.
    bool applyModel(VlSolverSession& sess);
    // The variable holding an array's size when the size is random, else nullptr
    const VlRandomVar* sizeVarp(const VlRandomVar& varr) const;
    // The element name a select of varr with these index terms names, as ArrayInfo names it
    bool elementName(const VlRandomVar& varr, std::vector<std::string> indices,
                     std::string& elementr) const;
    // Reads a (get-value) reply answering requested elements and variables, the arrays in
    // wholep asked whole. One of a value of a form not read sets *fallbackp, writing nothing
    bool parseModel(std::istream& is, size_t requested,
                    const std::unordered_set<std::string>* wholep = nullptr,
                    bool* fallbackp = nullptr);
    // Keep each lower 32-bit key word intact and pad to the stored key width.
    // Name of the element of struct array 'name' at 'indices' of 'idxWidths' bits
    static std::string structElementName(const std::string& name,
                                         const std::vector<IData>& indices,
                                         const std::vector<size_t>& idxWidths) {
        std::ostringstream oss;
        oss << name;
        for (size_t i = 0; i < indices.size(); ++i) {
            oss << '.' << std::hex << std::setw(int(idxWidths[i] / 4)) << std::setfill('0')
                << static_cast<int>(indices[i]);
        }
        return oss.str();
    }
    static std::string assocStructKeySuffix(const std::vector<size_t>& words, size_t idxWidth) {
        std::ostringstream oss;
        for (size_t i = 0; i < words.size(); ++i) {
            if (i) oss << std::setw(8) << std::setfill('0');
            oss << std::hex << static_cast<int>(words[i]);
        }
        std::string result = oss.str();
        result.insert(result.begin(), int(idxWidth / 4) - result.size(), '0');
        return result;
    }
    // Assert the maximal compatible soft-constraint set onto the open session.
    // Return SAT when processing succeeded; UNKNOWN or FAIL never drops a soft constraint.
    VlSolverStatus relaxSoftConstraints(VlSolverSession& sess);
    // Indices of the "__Va<N>" literals named by (get-unsat-assumptions).
    std::vector<int> readUnsatAssumptions(VlSolverSession& sess);
    bool reportUnsatSetup(VlSolverSession& sess, const std::vector<std::string>& uniqueExprs);
    void reportUnsatCore(VlSolverSession& sess);
    void warnUnsatConstraint(size_t n) const;
    using UniqueRanges = std::vector<std::pair<uint64_t, uint64_t>>;  // Keys, in order
    // The values each array of a uniqueness group, sorted names, may take: what all the domains
    // registered for it allow. False when an array has none, so may take any value
    bool uniqueAllowed(const std::vector<std::string>& names,
                       std::vector<UniqueRanges>& allowedr) const;
    // Whether a uniqueness group has more elements than values for them, in an array or in all
    bool uniqueDomainsUnsat() const;
    // For the solve of array sizes, bound the sizes of the arrays of each uniqueness group to
    // the values for them, each array and all together
    void addUniqueSizeBounds(std::vector<std::string>& exprs) const;
    void emitRandcExclusions(std::ostream& os) const;  // Emit randc exclusion constraints
    // Variables and elements of arrays whose values the solver sampler draws, see checkFree
    using FreeElements = std::vector<std::pair<const VlRandomVar*, int>>;
    FreeElements freeElements() const;
    VlSolverStatus checkFree(VlRNG& rngr, VlSolverSession& sess, const FreeElements& elements);
    void recordRandcValues();  // Record solved randc values for future exclusion
    size_t hashConstraints(const std::vector<std::string>& extras, bool randcOnly = false) const;
    bool nextRandomize(VlRNGReseeds& rngr, bool checkOnly, bool sizeSolve = false);
    bool nextSolve(VlRNGReseeds& rngr, bool checkOnly, bool sizeSolve);
    // "(distinct ...)" expression per unique-constrained array
    std::vector<std::string>
    buildUniqueExprs(std::vector<std::pair<uint32_t, uint64_t>>* lazyp) const;
    bool refineUnique(std::vector<std::pair<uint32_t, uint64_t>>& lazyr, int round,
                      std::vector<std::string>& exprsr, VlSolverSession& sess,
                      bool& refinedr) const;
    uint64_t solverBits() const;
    // Add constraints that the names of a variable registered under several have one value
    void addAliasExprs(std::vector<std::string>& exprsr) const;
    static std::string aliasExpr(const std::string& name, const std::string& otherName);
    void emitDefines(std::ostream& os) const;
    void emitDeclares(std::ostream& os, bool pinCurrent) const;
    void emitChainDefines(std::ostream& os) const;
    void emitAsserts(std::ostream& os, const std::vector<std::string>& extras, bool named) const;
    // A flat solve's logic, variables and constraints, and randc exclusions
    void emitFlat(std::ostream& os, const std::vector<std::string>& uniqueExprs) const;
    // Whether the constraints have constant arrays, outside the restricted logics
    bool usesConstArrays() const;
    // (set-logic logicp), after any option the solver needs for constant arrays, if
    // constArrays
    static void emitSetLogic(std::ostream& os, const char* logicp, bool constArrays);
    bool nextFlat(VlRNG& rngr, VlSolverSession& sess, const std::vector<std::string>& uniqueExprs);

    // --- UniGen2 (a near-uniform constrained randomization sampler) fields ---
    // Implementation based on the following paper:
    // "On Parallel Scalable Uniform SAT Witness Generation", Chakraborty et al.

    using Witness = std::map<std::string, std::map<int, std::string>>;  // One sampled solution

    // Sample one random solution. False if a sample couldn't be produced
    bool unigen2(VlRNG& rngr, VlSolverSession& sess, const std::vector<std::string>& uniqueExprs);
    // Find out how finely to cut the solution space, and what cell size to accept
    bool estimateParameters(VlSolverSession& sess, VlRNG& rngr);
    // Collect up to `bound` different solutions of whatever is asserted right now.
    // diversifyRngp adds a randomization step that spreads the solutions apart
    int bsat(VlSolverSession& sess, size_t bound, std::vector<Witness>& witnesses,
             VlRNG* diversifyRngp = nullptr);
    // Add `bits` random XOR equations, which cut the solution space into cells holding
    // roughly 1/2**bits of all the solutions
    void unigenXors(std::iostream& os, VlRNG& rngr, int bits);
    // Draw a cell and refill the batch of solutions from it
    bool generateSamples(VlSolverSession& sess, VlRNG& rngr);
    // Copy one solution into the SV variables
    void writeBackWitness(const Witness& witness);

    // UniGen2: sampling state
    struct Unigen2State final {
        std::vector<Witness> loThreshWitnesses;  // Consumable batch of solutions: loThresh random
                                                 // picks out of the cell BSAT enumerated
        std::vector<std::pair<std::string, int>> bsatOrder;  // (var, element) query order
        bool isLargeSpace = false;  // Large solution space (more than 61 * 2^10 solutions)
        // Below properties are what estimateParameters worked out, kept until the constraints
        // change so the expensive search is not repeated on every call.
        bool paramsValid = false;  // Whether the values below are set
        size_t paramHash = 0;  // Constraint set they were computed for
        int hashBits = 0;  // How many XOR equations to cut the space with
        int loThresh = 0;  // Smallest usable cell, and how many samples to take
        int hiThresh = 0;  // First cell size counted as too big
        uint64_t rngReseeds = 0;  // rngr.reseeds() as of the last call
        int lastSuccessI = -1;  // Hash-bit count that worked last time, -1 if none
    };
    Unigen2State m_ug2;

    // Bits [lsb, lsb + width) of element elem of a variable, steered by solveDiversity
    struct PinTerm final {
        const VlRandomVar* varp;  // Variable
        int elem;  // Element index, as for emitElement
        int lsb;  // Lowest bit
        int width;  // Number of bits
        int root;  // Index of the whole variable or element it is part of
        int value0 = 0;  // Lowest bit of the value it is pinned to
    };
    // Move the solution towards random values the constraints allow; uniqueExprsp, for a
    // flat solve, lets the solution be found again in a fresh session
    void solveDiversity(VlRNG& rngr, VlSolverSession& sess,
                        const std::set<std::string>* fixedp = nullptr,
                        const std::vector<std::string>* uniqueExprsp = nullptr);
    // Moves the current model's values of terms towards random ones (see solveDiversity);
    // true if the model current after it holds them, still to be read
    bool spreadTerms(VlRNG& rngr, VlSolverSession& sess, std::vector<PinTerm> terms,
                     const std::vector<std::string>* uniqueExprsp);
    // Find a random solution again in a fresh session, after spreading kept nothing
    void resolveFresh(VlRNG& rngr, VlSolverSession& sess,
                      const std::vector<std::string>& uniqueExprs, uint64_t limit);
    // Assume literals __Va<first>... (one per term) with keep, dropping conflicting ones until SAT
    bool assumeDropping(VlRNG& rngr, VlSolverSession& sess, const std::string& keep, int first,
                        const std::vector<PinTerm>& terms, std::vector<bool>& droppedr,
                        int& checksLeftr, std::vector<bool>* guessedp = nullptr,
                        std::vector<int>* slotIdsp = nullptr, int* satisfiedLeftp = nullptr);
    // Values of a (get-value) reply asking for terms, in order, each of its term's width and in
    // either SMT-LIB 2.6 literal notation
    bool readValues(VlSolverSession& sess, const std::vector<PinTerm>& terms,
                    std::vector<std::string>& valuesr);
    // Layers of the solve...before variables and parts of them in dependency order
    bool buildSolveLayers(std::vector<std::vector<std::string>>& layersr);
    // SMT logic for a flat or UniGen2 session
    const char* solverLogic() const;
    bool tablesNeed(uint8_t needs) const;  // Whether a table needs any of 'needs' (TableNeeds)
    // The variable or array element a solve...before name names, nullptr if none
    const VlRandomVar* solveBeforeVarp(const std::string& name);
    // Resolve a solve-before operand to its bits, false if it names none
    bool solveBeforeBits(const SolveBeforeRef& ref, SolveBeforeBits& bitsr);
    const char* phasedLogic() const;
    bool nextPhased(VlRNG& rngr, VlSolverSession& sess,
                    const std::vector<std::string>& uniqueExprs);
    bool solvePhases(VlRNG& rngr, VlSolverSession& sess,
                     const std::vector<std::vector<std::string>>& layers,
                     const std::vector<std::string>& uniqueExprs, bool& exhaustedr);
    bool solvePhaseValues(VlSolverSession& sess, VlRNG& rngr,
                          const std::vector<std::string>& layerVars,
                          std::map<std::string, std::string>& solvedValuesr);
    // Whether any of the variables is an array
    bool layerHasArray(const std::vector<std::string>& layerVars);
    // Whether to sample a phase, from how often its trials have been satisfiable; counts the
    // calls that skip sampling and restarts the counts when sampling is tried again
    bool sampleWorthwhile(const std::vector<std::string>& phaseVars);
    // Rejection-sample a phase's scalars from the kept solver base
    VlSolverStatus sampleLayer(VlSolverSession& sess, VlRNG& rngr,
                               const std::vector<std::string>& phaseVars,
                               std::map<std::string, std::string>* valuesp);
    // Phased solve: trials a kept base makes per phase before building a fresh one
    static constexpr int phaseSampleTries = 32;
    // Calls without trials before a phase whose trials rarely fit is sampled again
    static constexpr int phaseSampleRetry = 128;
    // Trials after which a phase's counts are halved
    static constexpr int phaseSampleWindow = 8 * phaseSampleTries;
    // How often a phase's trials were satisfiable, keyed by the phase's first variable
    struct PhaseSampleStats final {
        uint64_t tries = 0;  // Recent trials
        uint64_t accepts = 0;  // Satisfiable trials among them
        uint64_t skips = 0;  // Calls since the last trials that rebuilt the phase without them
    };
    std::unordered_map<std::string, PhaseSampleStats> m_phaseSampleStats;
    // The key a part of a variable or element is named by, or empty for another term
    std::string partTermKey(const std::string& term) const;
    // The variable or element a phase term names, with its key, or nullptr
    const VlRandomVar* phaseTermKey(const std::string& term, std::string& keyr) const;
    bool readPhaseValues(VlSolverSession& sess, const std::string& terms,
                         std::map<std::string, std::string>& solvedValuesr);
    bool parsePhaseValues(std::istream& is, const std::string& terms,
                          std::map<std::string, std::string>& solvedValuesr);
    // Record whether a constraint reads a member of a null handle
    void nullReadCheck(const std::string& constraint, const char* filename, uint32_t linenum);

public:
    // CONSTRUCTORS
    VlRandomizer() = default;
    ~VlRandomizer() = default;

    // METHODS
    /// Start one original, univariate constraint, bound to the actual SV storage.
    template <typename T>
    void fast_begin(T& var, int width, bool isSigned, bool isSoft, bool isDist, bool rangeMass,
                    bool isEnum, int viewLsb, int viewWidth) {
        m_fastConstraints.push_back(
            {&var, width, isSigned, isSoft, isDist, rangeMass, isEnum, {}});
        m_fastConstraints.back().viewLsb = viewLsb;
        m_fastConstraints.back().viewWidth = viewWidth;
    }
    /// Add an interval, its weight and the weight's scale to the current constraint.
    void fast_range(QData lo, QData hi, QData weight, QData scale) {
        if (lo <= hi && weight) {
            FastConstraint& constraint = m_fastConstraints.back();
            if (!scale && !constraint.rangeMass) {
                m_fastDisabled = true;  // An original :/ cardinality of 2^64
            } else {
                constraint.ranges.push_back({lo, hi, weight, scale});
            }
        }
    }
    /// Start one constraint of a native array's elements (see SolverScalarArrayVisitor),
    /// unless the solver samples
    template <typename T, size_t N_MaxSize>
    void native_begin(VlQueue<T, N_MaxSize>& array, int width, bool isSigned, bool isSoft,
                      bool isDist, bool rangeMass) {
        nativeBegin(array, width, isSigned, isSoft, isDist, rangeMass);
    }
    template <typename T, std::size_t N_Depth>
    void native_begin(VlUnpacked<T, N_Depth>& array, int width, bool isSigned, bool isSoft,
                      bool isDist, bool rangeMass) {
        nativeBegin(array, width, isSigned, isSoft, isDist, rangeMass);
    }
    template <typename T_Array>
    void nativeBegin(T_Array& array, int width, bool isSigned, bool isSoft, bool isDist,
                     bool rangeMass) {
        if (solverSamplesOn()) return;
        nativeArray(array, width, isSigned);
        for (auto it = m_vars.begin(); it != m_vars.end();) {
            if (it->second->VlRandomVar::datap(0) == &array) {
                m_nativeHidden.emplace_back(*it);
                it = m_vars.erase(it);
            } else {
                ++it;
            }
        }
        m_nativeArrays[&array].items.push_back(
            {nullptr, width, isSigned, isSoft, isDist, rangeMass, false, {}});
        m_nativeLastp = &m_nativeArrays[&array].items.back();
    }
    /// Add an interval, its weight and the weight's scale to the current native constraint
    void native_range(QData lo, QData hi, QData weight, QData scale) {
        if (m_nativeLastp && lo <= hi && weight)
            m_nativeLastp->ranges.push_back({lo, hi, weight, scale});
    }
    /// Whether the array's elements are sampled natively, not solved, in this randomize()
    template <typename T_Array>
    bool native_on(const T_Array& array) const {
        return m_nativeArrays.count(&array);
    }
    /// Record a single-range procedural pick at its original evaluation point.
    template <typename T>
    void fast_dist_pick(T& var, QData bits) {
        // Count original descriptors, including empty ones, before soft pruning.
        // Storage alone cannot identify which RHS produced a multi-dist pick.
        FastConstraint* pickp = nullptr;
        for (FastConstraint& constraint : m_fastConstraints) {
            if (!constraint.isDist || constraint.datap != &var) continue;
            if (pickp) return;
            pickp = &constraint;
        }
        if (!pickp) return;
        pickp->proposal = bits & VL_MASK_Q(pickp->viewWidth);
        if (pickp->isSigned) pickp->proposal ^= QData{1} << (pickp->viewWidth - 1);
        pickp->hasProposal = true;
    }
    /// Snapshot a state queue's membership set; duplicates never add probability.
    template <typename T, size_t N_MaxSize>
    void fast_queue(const VlQueue<T, N_MaxSize>& queue, bool exclude) {
        FastConstraint& constraint = m_fastConstraints.back();
        const QData mask = VL_MASK_Q(constraint.viewWidth);
        const QData sign = constraint.isSigned ? QData{1} << (constraint.viewWidth - 1) : 0;
        FastRanges ranges;
        ranges.reserve(queue.size());
        for (const T& value : queue) {
            const QData key = (static_cast<QData>(value) & mask) ^ sign;
            ranges.push_back({key, key, 1, 1});
        }
        ranges = fastUnion(std::move(ranges));
        if (!exclude) {
            constraint.ranges = std::move(ranges);
            return;
        }
        QData next = 0;
        for (const FastRange& range : ranges) {
            if (next < range.lo) constraint.ranges.push_back({next, range.lo - 1, 1, 1});
            if (range.hi == mask) return;
            next = range.hi + 1;
        }
        constraint.ranges.push_back({next, mask, 1, 1});
    }
    /// Keep the solver path when any original constraint item is unsupported.
    void fast_disable() { m_fastDisabled = true; }

    // Finds the next solution satisfying the constraints
    bool next(VlRNGReseeds& rngr);
    // Validate the constraints against the current runtime values of every
    // registered rand variable without picking new ones.
    bool next_check_only(VlRNGReseeds& rngr);
    /// Finds the sizes of the arrays for a final next(), without advancing randc cycles
    bool next_size(VlRNGReseeds& rngr);
    /// Keep the values a successful solve set, which restore_solution sets again after the
    /// basic randomization of the variables not solved, as that may overwrite them
    void keep_solution();
    /// Set the values keep_solution kept
    void restore_solution();
    /// Keep the values and randc cycles before a solve, for end_prior
    void keep_prior();
    /// Set the values and randc cycles keep_prior kept, unless ok
    void end_prior(bool ok);
    /// Continue the randc cycles of another randomizer, which solved for the same object
    void randc_history_from(const VlRandomizer& other) {
        m_randcUsedValues = other.m_randcUsedValues;
        m_randcConstraintHash = other.m_randcConstraintHash;
        m_sizeSolved = other.m_sizeSolved;
    }

    // ---  Process the key for associative array  ---

    // process_key: Handle integral keys (<= 32-bit)
    template <typename T_Key>
    typename std::enable_if<std::is_integral<T_Key>::value && (sizeof(T_Key) <= 4)>::type
    process_key(const T_Key& key, std::string& indexed_name, std::vector<size_t>& integral_index,
                const std::string& base_name, size_t& idx_width) {
        integral_index.push_back(static_cast<size_t>(key));
        indexed_name
            = base_name + "[" + std::to_string(integral_index[integral_index.size() - 1]) + "]";
        idx_width = sizeof(T_Key) * 8;
    }

    // process_key: Handle integral keys (> 32-bit), split into 2 x 32-bit segments
    template <typename T_Key>
    typename std::enable_if<std::is_integral<T_Key>::value && (sizeof(T_Key) > 4)>::type
    process_key(const T_Key& key, std::string& indexed_name, std::vector<size_t>& integral_index,
                const std::string& base_name, size_t& idx_width) {
        constexpr size_t segment_bits = 32;
        constexpr T_Key mask = (static_cast<T_Key>(1) << segment_bits) - 1;
        integral_index.push_back(static_cast<size_t>(key >> segment_bits));
        integral_index.push_back(static_cast<size_t>(key & mask));

        std::ostringstream hex_stream;
        hex_stream << std::hex << key;
        std::string index_string = hex_stream.str();
        index_string.erase(0, index_string.find_first_not_of('0'));
        index_string = index_string.empty() ? "0" : index_string;

        indexed_name = base_name + "[" + index_string + "]";

        idx_width = sizeof(T_Key) * 8;
    }

    // process_key: Handle wide keys (VlWide-like), segment is 32-bit per element
    template <typename T_Key>
    typename std::enable_if<VlIsVlWide<T_Key>::value>::type
    process_key(const T_Key& key, std::string& indexed_name, std::vector<size_t>& integral_index,
                const std::string& base_name, size_t& idx_width) {
        std::ostringstream hex_stream;
        for (size_t i = key.size(); i > 0; --i) {
            const size_t segment_value = key.at(i - 1);
            // Zero padded, so a zero segment is not dropped
            hex_stream << std::hex << std::setw(8) << std::setfill('0') << segment_value;
            integral_index.push_back(segment_value);
        }
        std::string index_string = hex_stream.str();
        index_string.erase(0, index_string.find_first_not_of('0'));
        index_string = index_string.empty() ? "0" : index_string;

        indexed_name = base_name + "[" + index_string + "]";
        idx_width = key.size() * 32;
    }

    // process_key: Handle string key, encoded as 128-bit hex
    template <typename T_Key>
    typename std::enable_if<std::is_same<T_Key, std::string>::value>::type
    process_key(const T_Key& key, std::string& indexed_name, std::vector<size_t>& integral_index,
                const std::string& base_name, size_t& idx_width) {
        // Convert the input string to its ASCII hexadecimal representation
        std::ostringstream oss;
        for (unsigned char c : key) {
            oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(c);
        }
        std::string hex_str = oss.str();
        // Ensure the hex string is exactly 128 bits (32 hex characters)
        hex_str = hex_str.size() > 32 ? hex_str.substr(0, 32)
                                      : std::string(32 - hex_str.size(), '0') + hex_str;

        // Split the hex string into 4 segments (32-bit per segment)
        integral_index.clear();
        for (size_t i = 0; i < hex_str.size(); i += 8) {
            integral_index.push_back(std::stoul(hex_str.substr(i, 8), nullptr, 16));
        }

        indexed_name = base_name + "["
                       + (hex_str.find_first_not_of('0') == std::string::npos
                              ? "0"
                              : hex_str.substr(hex_str.find_first_not_of('0')))
                       + "]";

        idx_width = 128;
    }

    // process_key: Unsupported key type fallback
    template <typename T_Key>
    typename std::enable_if<!std::is_integral<T_Key>::value
                            && !std::is_same<T_Key, std::string>::value
                            && !VlIsVlWide<T_Key>::value>::type
    process_key(const T_Key& key, std::string& indexed_name, std::vector<size_t>& integral_index,
                const std::string& base_name, size_t& idx_width) {
        VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                    "Unsupported: Only integral and string index of associative array is "
                    "supported currently.");
    }

    // Mark a variable as rand_mode-disabled: solver keeps it in m_vars
    // (so constraints still reference it) but skips write-back after solving.
    void set_var_disabled(const std::string& name) { m_disabledVars.insert(name); }
    // Clear disabled state for a variable
    void clear_var_disabled(const std::string& name) { m_disabledVars.erase(name); }

    // Drop the registered members of the elements of struct array name, so registering its
    // current elements does not keep members of elements that were removed or reallocated
    void clear_struct_arr(const std::string& name) {
        m_vars.erase(m_vars.lower_bound(name + "."), m_vars.lower_bound(name + "/"));
    }

    // ---  write_var to register variables  ---
    // Register scalar variable (non-struct, basic type)
    template <typename T>
    typename std::enable_if<!VlContainsCustomStruct<T>::value && !IsVlUnpacked<T>::value,
                            void>::type
    write_var(T& var, int width, const std::string& name, int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        // Registered again when reached through a member object that may have been replaced
        const auto it = m_vars.find(name);
        if (it != m_vars.end() && it->second->datap(0) == &var) return;
        // TODO: make_unique once VlRandomizer is per-instance not per-ref
        m_vars[name]
            = std::make_shared<const VlRandomVar>(name, width, &var, dimension, randmodeIdx);
    }

    // Register user-defined struct variable by recursively writing members
    template <typename T>
    typename std::enable_if<VlIsCustomStruct<T>::value, void>::type
    write_var(T& var, int width, const std::string& name, int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        modifyMembers(var, var.memberIndices(), name, randmodeIdx);
    }

    // Register queue of non-struct types
    template <typename T, size_t N_MaxSize>
    typename std::enable_if<!VlContainsCustomStruct<T>::value, void>::type
    write_var(VlQueue<T, N_MaxSize>& var, int width, const char* name, int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        if (native_on(var)) return;  // Sampled, not solved
        if (m_vars.find(name) == m_vars.end()) {
            m_vars[name] = std::make_shared<const VlRandomArrayVarTemplate<VlQueue<T, N_MaxSize>>>(
                name, width, &var, dimension, randmodeIdx);
        }
        if (dimension > 0) {
            m_index = 0;
            clear_arr_table(name);
            record_arr_table(var, name, dimension, {}, {});
        }
    }

    // Register queue of structs
    template <typename T, size_t N_MaxSize>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    write_var(VlQueue<T, N_MaxSize>& var, int width, const char* name, int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        clear_struct_arr(name);
        record_struct_arr(var, name, dimension, {}, {}, randmodeIdx);
    }
    // Register unpacked array of non-struct types
    template <typename T, std::size_t N_Depth>
    typename std::enable_if<!VlContainsCustomStruct<T>::value, void>::type
    write_var(VlUnpacked<T, N_Depth>& var, uint32_t width, const std::string& name,
              uint32_t dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        if (native_on(var)) return;  // Sampled, not solved
        if (m_vars.find(name) == m_vars.end()) {
            m_vars[name]
                = std::make_shared<const VlRandomArrayVarTemplate<VlUnpacked<T, N_Depth>>>(
                    name, width, &var, dimension, randmodeIdx);
        }

        if (dimension > 0) {
            m_index = 0;
            clear_arr_table(name);
            record_arr_table(var, name, dimension, {}, {});
        }
    }
    // Register unpacked array of structs
    template <typename T, std::size_t N_Depth>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    write_var(VlUnpacked<T, N_Depth>& var, int /*width*/, const char* name, int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        clear_struct_arr(name);
        record_struct_arr(var, name, dimension, {}, {}, randmodeIdx);
    }

    // Register associative array of non-struct types
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    typename std::enable_if<!VlContainsCustomStruct<T_Value>::value, void>::type
    write_var(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, int width, const char* name,
              int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        if (m_vars.find(name) == m_vars.end()) {
            std::vector<size_t> keyWidths;
            VlRandomAssocKeyWidths<VlAssocArray<T_Key, T_Value, T_KeyLess>>::push(keyWidths);
            m_vars[name] = std::make_shared<
                const VlRandomArrayVarTemplate<VlAssocArray<T_Key, T_Value, T_KeyLess>>>(
                name, width, &var, dimension, randmodeIdx, keyWidths);
        }
        if (dimension > 0) {
            m_index = 0;
            clear_arr_table(name);
            record_arr_table(var, name, dimension, {}, {});
        }
    }

    // Register associative array of structs
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    typename std::enable_if<VlContainsCustomStruct<T_Value>::value, void>::type
    write_var(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, int /*width*/, const char* name,
              int dimension,
              std::uint32_t randmodeIdx = std::numeric_limits<std::uint32_t>::max()) {
        clear_struct_arr(name);
        record_struct_arr(var, name, dimension, {}, {}, randmodeIdx);
    }

    // ---  Record Arrays: flat and struct  ---

    // Record a flat (non-class) element into the array variable table
    template <typename T>
    typename std::enable_if<!std::is_class<T>::value || VlIsVlWide<T>::value, void>::type
    record_arr_table(T& var, const std::string& name, int /*dimension*/,
                     std::vector<IData> indices, std::vector<size_t> idxWidths) {
        m_arr_vars[generateKey(name, m_index)]
            = std::make_shared<ArrayInfo>(name, &var, m_index, indices, idxWidths);
        ++m_index;
    }

    template <typename T>
    typename std::enable_if<!std::is_class<T>::value || VlIsVlWide<T>::value, void>::type
    update_arr_table(T& var, const std::string& name, int /*dimension*/) {
        const auto it = m_arr_vars.find(generateKey(name, m_index++));
        assert(it != m_arr_vars.end());
        const ArrayInfo& arrayInfo = *it->second;
        it->second = std::make_shared<const ArrayInfo>(arrayInfo.m_name, &var, arrayInfo.m_index,
                                                       arrayInfo.m_indices, arrayInfo.m_idxWidths);
    }

    // This is the "Sender" API for the generated code.
    // The elements to make distinct are taken from the array element table at
    // solve time, so a container resized by the solver is handled correctly.
    void rand_unique(const std::string& name, const uint32_t key) {
        m_uniqueArrays[key].insert(name);
    }
    // Start the values a hard constraint, registered next, allows every element of an array
    void unique_domain(const std::string& name, uint32_t width, bool isSigned) {
        m_uniqueDomains[name].push_back(UniqueDomain{m_constraints.size(), width, isSigned, {}});
        m_uniqueDomainName = name;
    }
    // Add values lo to hi, keys ordered from the least signed value, to the values started
    void unique_range(uint64_t lo, uint64_t hi) {
        m_uniqueDomains[m_uniqueDomainName].back().ranges.emplace_back(lo, hi);
    }

    // Recursively record all elements in an unpacked array
    template <typename T, std::size_t N_Depth>
    void record_arr_table(VlUnpacked<T, N_Depth>& var, const std::string& name, int dimension,
                          std::vector<IData> indices, std::vector<size_t> idxWidths) {
        if ((dimension > 0) && (N_Depth != 0)) {
            idxWidths.push_back(32);
            for (size_t i = 0; i < N_Depth; ++i) {
                const std::string indexed_name = name + "[" + std::to_string(i) + "]";
                indices.push_back(i);
                record_arr_table(var.operator[](i), indexed_name, dimension - 1, indices,
                                 idxWidths);
                indices.pop_back();
            }
        }
    }

    // Recursively update pointers to all elements in an unpacked array
    template <typename T, std::size_t N_Depth>
    void update_arr_table(VlUnpacked<T, N_Depth>& var, const std::string& name, int dimension) {
        assert(dimension > 0);
        for (size_t i = 0; i < N_Depth; ++i) {
            update_arr_table(var[i], name + "[" + std::to_string(i) + "]", dimension - 1);
        }
    }

    // Recursively record all elements in a queue
    template <typename T, size_t N_MaxSize>
    void record_arr_table(VlQueue<T, N_MaxSize>& var, const std::string& name, int dimension,
                          std::vector<IData> indices, std::vector<size_t> idxWidths) {
        if ((dimension > 0) && (var.size() != 0)) {
            idxWidths.push_back(32);
            for (size_t i = 0; i < var.size(); ++i) {
                const std::string indexed_name = name + "[" + std::to_string(i) + "]";
                indices.push_back(i);
                record_arr_table(var.atWrite(i), indexed_name, dimension - 1, indices, idxWidths);
                indices.pop_back();
            }
        }
    }

    // Recursively update pointers to all elements in a queue
    template <typename T, size_t N_MaxSize>
    void update_arr_table(VlQueue<T, N_MaxSize>& var, const std::string& name, int dimension) {
        assert(dimension > 0);
        for (size_t i = 0; i < var.size(); ++i) {
            update_arr_table(var.atWrite(i), name + "[" + std::to_string(i) + "]", dimension - 1);
        }
    }

    // Recursively record all elements in an associative array
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    void record_arr_table(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const std::string& name,
                          int dimension, std::vector<IData> indices,
                          std::vector<size_t> idxWidths) {
        if ((dimension > 0) && (var.size() != 0)) {
            for (auto it = var.begin(); it != var.end(); ++it) {
                const T_Key& key = it->first;
                const T_Value& value = it->second;

                std::string indexed_name;
                std::vector<size_t> integral_index;
                size_t idx_width = 0;

                process_key(key, indexed_name, integral_index, name, idx_width);

                // Update indices and widths
                idxWidths.push_back(idx_width);
                indices.insert(indices.end(), integral_index.begin(), integral_index.end());

                record_arr_table(var.atWrite(key), indexed_name, dimension - 1, indices,
                                 idxWidths);

                // Cleanup indices and widths
                idxWidths.pop_back();
                indices.resize(indices.size() - integral_index.size());
            }
        }
    }

    // Recursively update pointers to all elements in an associative array
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    void update_arr_table(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const std::string& name,
                          int dimension) {
        assert(dimension > 0);
        for (auto it = var.begin(); it != var.end(); ++it) {
            const T_Key& key = it->first;
            std::string indexed_name;
            std::vector<size_t> integral_index;
            size_t idx_width = 0;
            process_key(key, indexed_name, integral_index, name, idx_width);
            update_arr_table(var.atWrite(key), indexed_name, dimension - 1);
        }
    }

    // Register a single structArray element via write_var
    template <typename T>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    record_struct_arr(T& var, const std::string& name, int /*dimension*/,
                      const std::vector<IData>& indices, const std::vector<size_t>& idxWidths,
                      std::uint32_t randmodeIdx) {
        write_var(var, 1ULL, structElementName(name, indices, idxWidths), 1ULL, randmodeIdx);
    }

    template <typename T>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    update_struct_arr(T& var, const std::string& name) {
        update_var(var, name.c_str());
    }

    // Recursively process VlUnpacked of structs
    template <typename T, std::size_t N_Depth>
    void record_struct_arr(VlUnpacked<T, N_Depth>& var, const std::string& name, int dimension,
                           std::vector<IData> indices, std::vector<size_t> idxWidths,
                           std::uint32_t randmodeIdx) {
        if (dimension > 0 && N_Depth != 0) {
            constexpr size_t idx_width = 1 << VL_CLOG2_CE_Q(VL_CLOG2_CE_Q(N_Depth) + 1);
            idxWidths.push_back(idx_width);
            for (size_t i = 0; i < N_Depth; ++i) {
                indices.push_back(i);
                record_struct_arr(var.operator[](i), name, dimension - 1, indices, idxWidths,
                                  randmodeIdx);
                indices.pop_back();
            }
        }
    }

    template <typename T, std::size_t N_Depth>
    void update_struct_arr(VlUnpacked<T, N_Depth>& var, const std::string& name) {
        constexpr size_t idx_width = 1 << VL_CLOG2_CE_Q(VL_CLOG2_CE_Q(N_Depth) + 1);
        for (size_t i = 0; i < N_Depth; ++i) {
            std::ostringstream oss;
            oss << name << "." << std::hex << std::setw(int(idx_width / 4)) << std::setfill('0')
                << static_cast<int>(i);
            update_struct_arr(var[i], oss.str());
        }
    }

    // Recursively process VlQueue of structs
    template <typename T, size_t N_MaxSize>
    void record_struct_arr(VlQueue<T, N_MaxSize>& var, const std::string& name, int dimension,
                           std::vector<IData> indices, std::vector<size_t> idxWidths,
                           std::uint32_t randmodeIdx) {
        if ((dimension > 0) && (var.size() != 0)) {
            idxWidths.push_back(32);
            for (size_t i = 0; i < var.size(); ++i) {
                indices.push_back(i);
                record_struct_arr(var.atWrite(i), name, dimension - 1, indices, idxWidths,
                                  randmodeIdx);
                indices.pop_back();
            }
        }
    }

    template <typename T, size_t N_MaxSize>
    void update_struct_arr(VlQueue<T, N_MaxSize>& var, const std::string& name) {
        for (size_t i = 0; i < var.size(); ++i) {
            std::ostringstream oss;
            oss << name << "." << std::hex << std::setw(8) << std::setfill('0')
                << static_cast<int>(i);
            update_struct_arr(var.atWrite(i), oss.str());
        }
    }

    // Recursively process associative arrays of structs
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    void record_struct_arr(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const std::string& name,
                           int dimension, const std::vector<IData>& indices,
                           const std::vector<size_t>& idxWidths, std::uint32_t randmodeIdx) {
        if ((dimension > 0) && (!var.empty())) {
            for (auto it = var.begin(); it != var.end(); ++it) {
                const T_Key& key = it->first;
                const T_Value& value = it->second;

                std::string indexed_name;
                std::vector<size_t> integral_index;
                size_t idx_width = 0;

                process_key(key, indexed_name, integral_index, name, idx_width);
                const std::string result = assocStructKeySuffix(integral_index, idx_width);
                // After the indices of the dimensions outside, as named by the constraints
                record_struct_arr(var.atWrite(key),
                                  structElementName(name, indices, idxWidths) + "." + result,
                                  dimension - 1, {}, {}, randmodeIdx);
            }
        }
    }

    template <typename T_Key, typename T_Value, typename T_KeyLess>
    void update_struct_arr(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const std::string& name) {
        for (auto it = var.begin(); it != var.end(); ++it) {
            const T_Key& key = it->first;

            std::string indexed_name;
            std::vector<size_t> integral_index;
            size_t idx_width = 0;

            process_key(key, indexed_name, integral_index, name, idx_width);
            const std::string result = assocStructKeySuffix(integral_index, idx_width);
            update_struct_arr(var.atWrite(key), name + "." + result);
        }
    }

    // ---  Helper functions  ---

    // Helper: Register all members of a user-defined struct
    template <typename T, std::size_t... I>
    void modifyMembers(T& obj, std::index_sequence<I...>, const std::string& baseName,
                       std::uint32_t randmodeIdx) {
        // Use the indices to access each member via std::get
        const std::vector<std::string> names = obj.memberNames();
        const std::vector<const char*> domains = obj.memberEnumDomains();
        (void)std::initializer_list<int>{
            (write_var(std::get<I>(obj.getMembers(obj)), obj.memberWidth()[I],
                       (baseName + "." + names[I]).c_str(), obj.memberDimension()[I], randmodeIdx),
             domains[I] ? enum_domain(baseName + "." + names[I], domains[I]) : void(), 0)...};
    }

    template <typename T, std::size_t... I>
    void updateMembers(T& obj, std::index_sequence<I...>, const std::string& baseName) {
        (void)std::initializer_list<int>{
            (update_var(std::get<I>(obj.getMembers(obj)),
                        (baseName + "." + obj.memberNames()[I]).c_str()),
             0)...};
    }

    template <typename T>
    typename std::enable_if<!VlContainsCustomStruct<T>::value && !IsVlUnpacked<T>::value,
                            void>::type
    update_var(T& var, const char* name) {
        auto it = m_vars.find(name);
        assert(it != m_vars.end());
        it->second = std::make_shared<const VlRandomVar>(
            name, it->second->width(), &var, it->second->dimension(), it->second->randModeIdx());
    }

    template <typename T>
    typename std::enable_if<VlIsCustomStruct<T>::value, void>::type update_var(T& var,
                                                                               const char* name) {
        updateMembers(var, var.memberIndices(), name);
    }

    template <typename T, size_t N_MaxSize>
    typename std::enable_if<!VlContainsCustomStruct<T>::value, void>::type
    update_var(VlQueue<T, N_MaxSize>& var, const char* name) {
        auto it = m_vars.find(name);
        assert(it != m_vars.end());
        const int dimension = it->second->dimension();
        it->second = std::make_shared<const VlRandomArrayVarTemplate<VlQueue<T, N_MaxSize>>>(
            name, it->second->width(), &var, dimension, it->second->randModeIdx());
        m_index = 0;
        update_arr_table(var, name, dimension);
    }

    template <typename T, size_t N_MaxSize>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    update_var(VlQueue<T, N_MaxSize>& var, const char* name) {
        update_struct_arr(var, name);
    }

    template <typename T, std::size_t N_Depth>
    typename std::enable_if<!VlContainsCustomStruct<T>::value, void>::type
    update_var(VlUnpacked<T, N_Depth>& var, const char* name) {
        auto it = m_vars.find(name);
        assert(it != m_vars.end());
        const int dimension = it->second->dimension();
        it->second = std::make_shared<const VlRandomArrayVarTemplate<VlUnpacked<T, N_Depth>>>(
            name, it->second->width(), &var, dimension, it->second->randModeIdx());
        m_index = 0;
        update_arr_table(var, name, dimension);
    }

    template <typename T, std::size_t N_Depth>
    typename std::enable_if<VlContainsCustomStruct<T>::value, void>::type
    update_var(VlUnpacked<T, N_Depth>& var, const char* name) {
        update_struct_arr(var, name);
    }

    template <typename T_Key, typename T_Value, typename T_KeyLess>
    typename std::enable_if<!VlContainsCustomStruct<T_Value>::value, void>::type
    update_var(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const char* name) {
        auto it = m_vars.find(name);
        assert(it != m_vars.end());
        const int dimension = it->second->dimension();
        std::vector<size_t> keyWidths;
        VlRandomAssocKeyWidths<VlAssocArray<T_Key, T_Value, T_KeyLess>>::push(keyWidths);
        it->second = std::make_shared<
            const VlRandomArrayVarTemplate<VlAssocArray<T_Key, T_Value, T_KeyLess>>>(
            name, it->second->width(), &var, dimension, it->second->randModeIdx(), keyWidths);
        m_index = 0;
        update_arr_table(var, name, dimension);
    }

    template <typename T_Key, typename T_Value, typename T_KeyLess>
    typename std::enable_if<VlContainsCustomStruct<T_Value>::value, void>::type
    update_var(VlAssocArray<T_Key, T_Value, T_KeyLess>& var, const char* name) {
        update_struct_arr(var, name);
    }

    // Helper: Generate unique variable key from name and index
    static std::pair<std::string, int> generateKey(const std::string& name, int idx) {
        if (!name.empty() && name[0] == '\\') {
            const size_t space_pos = name.find(' ');
            return {space_pos != std::string::npos ? name.substr(0, space_pos) : name, idx};
        }
        const size_t bracket_pos = name.find('[');
        return {bracket_pos != std::string::npos ? name.substr(0, bracket_pos) : name, idx};
    }

    // Helper: Clear existing array element entries for a base name
    void clear_arr_table(const std::string& name) {
        for (int index = 0;; ++index) {
            const auto it = m_arr_vars.find(generateKey(name, index));
            if (it == m_arr_vars.end()) break;
            m_arr_vars.erase(it);
        }
    }

    // Name a new solver constant for the constraints, as the element index of an array
    // 'inside'. It is not a variable: never sampled, pinned or read back.
    std::string fresh_const();
    /// Make this randomize() fail without solving, for the reason 'msg' at filename:linenum,
    /// unless a reason is recorded already. 'warned' if the reason was reported already.
    void fail_pending(const std::string& msg, const char* filename, uint32_t linenum,
                      bool warned = false);
    /// Whether this randomize() fails for a reason fail_pending() recorded
    bool failed() const { return !m_failPending.empty(); }
    /// Whether randomize() may give the array 'name' the 'size' elements its constraints
    /// solved for, see VerilatedContext::randArrayMax. If not, warns, naming the array
    /// declared at filename:linenum, and makes this randomize() fail.
    bool array_size_ok(IData size, const char* name, const char* filename, uint32_t linenum);
    // varNames are the solver variables the constraint names, kept without copying until
    // clearConstraints(), so they must live that long (the generated code passes literals)
    void hard(std::string constraint, std::initializer_list<const char*> varNames = {},
              const char* filename = "", uint32_t linenum = 0, const char* source = "");
    // varNames are the solver variables a disable_soft() removes the constraint by
    void soft(std::string constraint, std::initializer_list<std::string> varNames,
              const char* filename = "", uint32_t linenum = 0, const char* source = "");
    // name is kept without copying until clearConstraints(), like hard()'s varNames, so it
    // must live that long (the generated code passes literals)
    void pin_var(const char* name, int width, uint64_t value) {
        std::string constraint = "(__Vbv (= "s + name + " (_ bv" + std::to_string(value) + " "
                                 + std::to_string(width) + ")))";
        hard(std::move(constraint), {name});
    }
    void disable_soft(const std::string& varName);
    // Add a hard constraint that applies only while variable varName is registered
    void pin_frozen(const std::string& varName, std::string&& constraint) {
        m_frozenPins.emplace_back(varName, std::move(constraint));
        m_pendingTablesHash = 0;
    }
    // Record that smtName, named name in the source, is a member of a null handle, which a
    // constraint added after reads in an evaluation error that fails the next solve (IEEE
    // 1800-2023 18.5.12), unless a guard keeps it out. Return smtName, standing in for it.
    std::string null_read(const std::string& name, const std::string& smtName);
    // What a table's values need of the solver, which the compiler finds in their text, as
    // solverLogic() reads it in a constraint's: an array constant, or another array term or a
    // product or quotient of variables
    enum TableNeeds : uint8_t { TABLE_CONST_ARRAY = 1, TABLE_ARRAY_TERMS = 2 };
    // Build an SMT function of the indexWidth-bit '?i' to valueWidth bits: the value of each
    // key, then the value of other keys, which table_end() returns the name of. It is defined in
    // every solver session until clearConstraints(), once for every equal one.
    void table_begin(int indexWidth, int valueWidth, bool positional, uint8_t needs);
    void table_entry(const std::string& key, std::string value);
    std::string table_end(const std::string& otherwise);
    // Name the tables of an object merged into 'into' (see merge_nested) apart from the tables
    // of 'into' and of the other objects merged into it
    void table_prefix_from(VlRandomizer& into);
    void clearConstraints();
    // The term of element 'index' of scalar array 'name' in a constraint: the element's
    // constant, or, for an index the array has no element at, a constant of its own
    const std::string& elemTerm(const std::string& name, IData index);
    // The term of the element of scalar array 'name' at index term 'index' the solver gives
    const std::string& elemChain(const std::string& name, const std::string& index);
    // Declare array 'name' element by element, see elemTerm
    void markScalar(const std::string& name) {
        const auto it = m_vars.find(name);
        if (it != m_vars.end()) it->second->scalar(true);
    }
    // The variable a term of a solver reply names: of an element of a scalar array, or the
    // array of a (select ...), whose indices are appended, or the term itself
    std::string termVarName(const std::string& term, std::vector<std::string>& indices) const;
    void clearAll();  // Clear both constraints and variables
    // Unregister the fields of the objects in a class handle array to register them again, once
    // after clearConstraints(): returns whether it did
    bool clear_elem_vars(const std::string& arrayName);
    // Unregister a variable
    void clear_var(const std::string& name) { m_vars.erase(name); }
    // Start solving in rounds, fixing each function argument variable after its round
    void func_round_start(int lastRound,
                          std::initializer_list<std::pair<const char*, int>> argRounds);
    // Fix the values solved by solvedr, and advance to the next round; false after the last
    bool func_round_next(const VlRandomizer& solvedr);
    // Whether the final round is being solved
    bool func_round_final() const { return !funcPreRound(); }
    // Stop solving in rounds; if they failed, set the values they changed back through the
    // variables solvedr, which solved the final round, registered
    void func_round_end(bool ok, const VlRandomizer& solvedr);
    // Whether the function argument variables are solved, so the call can be evaluated
    bool func_args_ready(std::initializer_list<const char*> names) const;
    void markRandc(const std::string& name);  // Mark variable as randc for cyclic tracking
    void markSizeVar(const std::string& name) { m_sizeVars.insert(name); }  // Of array size
    // Of an array whose element reads by a random index name it only while it is solved
    void markHeldLookup(const std::string& name) { m_heldLookups.insert(name); }
    /// Exclude the sizes the size variables hold from the next size solves of this call, as
    /// the solve of the elements failed with them. Returns true.
    bool exclude_sizes();
    /// Stop excluding sizes, as the call ends. Returns true.
    bool clear_size_exclusions() {
        m_sizeExclusions.clear();
        return true;
    }
    /// Whether an unsatisfied solve is reported, as it is not when the call tries other sizes
    /// after it. Returns true.
    bool quiet_unsat(bool flag) {
        m_quietUnsat = flag;
        return true;
    }
    /// Report why the constraints set up now, with the sizes excluded, are unsatisfied, as an
    /// unsatisfied solve does when not quiet. Returns true.
    bool report_unsat();
    /// Report why a call failed for another reason after tries of other sizes, whose
    /// unsatisfied constraints were not reported: the constraints set up now if they are
    /// unsatisfied, else that it failed. Returns true.
    bool report_retry_failure();
    /// Whether the last solve failed as its constraints are unsatisfied, not for another
    /// reason, as reading a member of a null handle
    bool unsat() const { return m_unsat; }
    /// Restrict variable name to its enum values: domain is a Bool term over '__Ve'
    void enum_domain(const std::string& name, const char* domain) { m_enumDomains[name] = domain; }
    /// Register solve-before ordering of bits [lsb, lsb + width) of variables or array
    /// elements, all bits if width is 0
    void solveBefore(const std::string& beforeName, IData beforeLsb, IData beforeWidth,
                     const std::string& afterName, IData afterLsb, IData afterWidth);
    void set_randmode(const VlQueue<CData>& randmode) { m_randmodep = &randmode; }
    // The solver variables and constraints of the object a rand class handle holds, of the
    // object's class (IEEE 1800-2023 18.5.2), set up in 'from', are solved with this
    // randomizer's. A variable named by 'path', the handle's path, prefixed to its name in
    // 'from', unless already registered here, as by a constraint of this randomizer's class.
    // A variable of 'from' with rand_mode off is disabled here.
    void merge_nested(const VlRandomizer& from, const std::string& path);
    // Remove what merge_nested() added for 'path', as its handle may hold another object
    void clear_nested(const std::string& path);
    // Whether merging the objects of rand class handles into this randomizer, so a cycle of
    // handles back to its object is not merged again
    bool nested_busy() const { return m_nestedBusy; }
    void set_nested_busy(bool flag);
    // Shared across all instances; consulted instead of m_randmodep for vars marked via
    // mark_var_static().
    void set_static_randmode(const VlQueue<CData>& randmode) { m_static_randmodep = &randmode; }
    void mark_var_static(const char* const name) { m_staticVars.insert(name); }
#ifdef VL_DEBUG
    void dump() const;
#endif
};

//=============================================================================

// Light wrapper for RNG used by std::randomize() to support scope-level randomization.
class VlStdRandomizer final : public VlRandomizer {
    // MEMBERS
    VlRNGReseeds m_rng;  // Random number generator

public:
    // CONSTRUCTORS
    VlStdRandomizer() = default;
    ~VlStdRandomizer() = default;

private:
    // Wide type specialization (>64 bits)
    template <typename T>
    typename std::enable_if<VlIsVlWide<T>::value, bool>::type
    basicStdRandomizationImpl(T& value, size_t width) {
        VL_RANDOM_RNG_W(m_rng, width, value);
        // Mask off garbage bits in last word
        const int words = VL_WORDS_I(width);
        const int bitsInLastWord = width & VL_SIZEBITS_I;
        if (bitsInLastWord) value.at(words - 1) &= VL_MASK_I(bitsInLastWord);
        return true;
    }

    // Scalar type specialization (<=64 bits)
    template <typename T>
    typename std::enable_if<!VlIsVlWide<T>::value, bool>::type
    basicStdRandomizationImpl(T& value, size_t width) {
        if (width <= 32) {
            value = VL_MASK_I(width) & VL_RANDOM_RNG_I(m_rng);
        } else {
            value = VL_MASK_Q(width) & VL_RANDOM_RNG_Q(m_rng);
        }
        return true;
    }

public:
    // Scalar/wide randomization
    template <typename T>
    bool basicStdRandomization(T& value, size_t width) {
        return basicStdRandomizationImpl(value, width);
    }

    // Unpacked array randomization
    template <typename T_Unpacked, std::size_t N_Depth>
    bool basicStdRandomization(VlUnpacked<T_Unpacked, N_Depth>& value, size_t width) {
        for (size_t i = 0; i < N_Depth; ++i) { basicStdRandomization(value.operator[](i), width); }
        return true;
    }

    // Queue/dynamic array randomization
    template <typename T_Value, size_t N_MaxSize>
    bool basicStdRandomization(VlQueue<T_Value, N_MaxSize>& value, size_t width) {
        for (int i = 0; i < value.size(); ++i) { basicStdRandomization(value.atWrite(i), width); }
        return true;
    }

    // Associative array randomization
    template <typename T_Key, typename T_Value, typename T_KeyLess>
    bool basicStdRandomization(VlAssocArray<T_Key, T_Value, T_KeyLess>& value, size_t width) {
        T_Key key;
        for (int exists = value.first(key); exists; exists = value.next(key)) {
            basicStdRandomization(value.atWrite(key), width);
        }
        return true;
    }
    bool next() { return VlRandomizer::next(m_rng); }
};

#endif  // Guard
