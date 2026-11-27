// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Collect and print statistics
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

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Assert.h"

#include "V3Const.h"
#include "V3EmitCBase.h"
#include "V3Hash.h"
#include "V3SharedTmps.h"
#include "V3Stats.h"
#include "V3Task.h"
#include "V3UniqueNames.h"
#include "V3VNUserAllocator.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace {

class DefaultDisableLocalVisitor final : public VNVisitor {
    // STATE
    AstNode* m_scopep = nullptr;

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        nodep->defaultDisablep(nullptr);
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        nodep->defaultDisablep(nullptr);
        iterateChildren(nodep);
    }
    void visit(AstDefaultDisable* nodep) override {
        UASSERT_OBJ(nodep, m_scopep,
                    "default disable iff must be inside a module or generate block");
        AstDefaultDisable* defaultp = nullptr;
        if (const AstNodeModule* const modp = VN_CAST(m_scopep, NodeModule)) {
            defaultp = modp->defaultDisablep();
        } else {
            defaultp = VN_AS(m_scopep, GenBlock)->defaultDisablep();
        }
        if (VL_UNLIKELY(defaultp)) {
            nodep->v3error("Only one 'default disable iff' allowed per "
                           << (VN_IS(m_scopep, NodeModule) ? "module" : "generate block")
                           << " (IEEE 1800-2023 16.15)");
        } else if (AstNodeModule* const modp = VN_CAST(m_scopep, NodeModule)) {
            modp->defaultDisablep(nodep);
        } else {
            VN_AS(m_scopep, GenBlock)->defaultDisablep(nodep);
        }
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit DefaultDisableLocalVisitor(AstNetlist* nodep) { iterate(nodep); }
};

class DefaultDisablePropagateVisitor final : public VNVisitor {
    // STATE
    AstDefaultDisable* m_defaultDisablep = nullptr;

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        m_defaultDisablep = nodep->defaultDisablep();
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        if (!nodep->defaultDisablep()) nodep->defaultDisablep(m_defaultDisablep);
        m_defaultDisablep = nodep->defaultDisablep();
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit DefaultDisablePropagateVisitor(AstNetlist* nodep) { iterate(nodep); }
};

}  // namespace

void V3AssertCommon::collectDefaultDisable(AstNetlist* nodep) {
    { DefaultDisableLocalVisitor{nodep}; }
    { DefaultDisablePropagateVisitor{nodep}; }
}

AstClocking* V3AssertCommon::moduleDefaultClockingp(const AstNodeModule* modp) {
    // It applies to the whole module, also to items before its declaration (IEEE 1800-2023 14.12)
    for (AstNode* stmtp = modp->stmtsp(); stmtp; stmtp = stmtp->nextp()) {
        AstClocking* const clockingp = VN_CAST(stmtp, Clocking);
        if (clockingp && clockingp->isDefault()) return clockingp;
    }
    return nullptr;
}

// Add nodep to scopep, a module or generate block
static void addToScope(AstNode* scopep, AstNode* nodep) {
    if (AstGenBlock* const genBlockp = VN_CAST(scopep, GenBlock)) {
        // In a loop, to the body repeated at each iteration
        if (AstGenFor* const genForp = genBlockp->genforp()) {
            genForp->addItemsp(nodep);
        } else {
            genBlockp->addItemsp(nodep);
        }
    } else {
        VN_AS(scopep, NodeModule)->addStmtsp(nodep);
    }
}

// Add to scopep an internal cover sequence of schemaRefp running stmtp at each end point
// (IEEE 1800-2023 9.4.2.4)
static void addSequenceEndCover(FileLine* flp, AstNode* scopep, AstSchemaRef* schemaRefp,
                                AstNodeStmt* stmtp) {
    AstCover* const coverp = new AstCover{flp, new AstPropSpec{flp, nullptr, nullptr, schemaRefp},
                                          stmtp, VAssertType::CONCURRENT};
    coverp->isCoverSeq(true);
    coverp->isSeqEvent(true);
    // A concurrent assertion is in its own process, clocked by it in AssertVisitor
    addToScope(scopep, new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, coverp});
}

AstVar* V3AssertCommon::newSequenceEvent(FileLine* flp, AstNode* scopep, const string& name,
                                         AstSchemaRef* schemaRefp) {
    AstVar* const eventp = new AstVar{flp, VVarType::MODULETEMP, name,
                                      scopep->findBasicDType(VBasicDTypeKwd::EVENT)};
    eventp->lifetime(VLifetime::STATIC_EXPLICIT);
    addToScope(scopep, eventp);
    v3Global.setHasEvents();
    if (!schemaRefp) return eventp;
    addSequenceEndCover(flp, scopep, schemaRefp,
                        new AstFireEvent{flp, new AstVarRef{flp, eventp, VAccess::WRITE}, false});
    return eventp;
}

AstVar* V3AssertCommon::newSequenceEndCount(FileLine* flp, AstNode* scopep, const string& name,
                                            AstSchemaRef* schemaRefp) {
    // Not a temporary, so read as sampled in assertions. Wraps only after 2**32 end points
    // between two reads, far beyond any clock ratio.
    AstVar* const countp = new AstVar{flp, VVarType::VAR, name, scopep->findUInt32DType()};
    countp->lifetime(VLifetime::STATIC_EXPLICIT);
    addToScope(scopep, countp);
    if (!schemaRefp) return countp;
    addSequenceEndCover(flp, scopep, schemaRefp,
                        new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE},
                                      new AstAdd{flp, new AstVarRef{flp, countp, VAccess::READ},
                                                 new AstConst{flp, 1}}});
    return countp;
}

string V3AssertCommon::assertCtlGetCall(VAssertCtlQuery query, VAssertType type,
                                        VAssertDirectiveType directiveType) {
    // Template arguments let the runtime build the type/directive mask at C++ compile time.
    // Parenthesized, so the template comma cannot split an argument of an emitted macro.
    return "(vlSymsp->_vm_contextp__->assertCtlGet<"s + std::to_string(type) + ", "s
           + std::to_string(directiveType) + ">(VerilatedAssertCtlQuery::"s
           + assertCtlQueryName(query) + "))"s;
}

AstNodeExpr* V3AssertCommon::newAssertCtlGetp(FileLine* flp, VAssertCtlQuery query,
                                              VAssertType type, VAssertDirectiveType directiveType,
                                              AstVar* statep) {
    const int width = query == VAssertCtlQuery::KILL ? 32 : 1;
    AstCExpr* const globalp
        = new AstCExpr{flp, AstCExpr::Pure{}, assertCtlGetCall(query, type, directiveType), width};
    if (!statep) return globalp;
    v3Global.setHasAssertCtlReads();
    return new AstAssertCtlRead{flp, globalp, new AstVarRef{flp, statep, VAccess::READ}, query};
}

namespace {
// Ordered selector ordinals and minimum depths encode every scoped update to a
// state. States in the same concrete scope with equal masks and histories agree.
using AssertCtlHistory = std::vector<std::pair<size_t, int>>;
struct AssertCtlSignature final {
    const AstScope* scopep;
    uint32_t mask;
    AssertCtlHistory history;
    bool operator==(const AssertCtlSignature& other) const {
        return scopep == other.scopep && mask == other.mask && history == other.history;
    }
};
struct AssertCtlTableRow final {
    const AstVarScope* statep;
    int depth;
    uint32_t ordinal;
    bool operator==(const AssertCtlTableRow& other) const {
        return statep == other.statep && depth == other.depth && ordinal == other.ordinal;
    }
};
struct AssertCtlTableKey final {
    std::vector<AssertCtlTableRow> rows;
    std::vector<uint32_t> skips;
    bool overlay;
    bool operator==(const AssertCtlTableKey& other) const {
        return overlay == other.overlay && rows == other.rows && skips == other.skips;
    }
};
template <typename T>
uint32_t appendAssertCtlHash(uint32_t hash, T value) {
    const V3Hash seed{hash};
    return seed.operator+(value).value();
}

struct AssertCtlTableKeyHash final {
    size_t operator()(const AssertCtlTableKey& key) const {
        uint32_t hash = static_cast<uint32_t>(key.overlay);
        for (const AssertCtlTableRow& row : key.rows) {
            hash = appendAssertCtlHash(hash, row.statep);
            hash = appendAssertCtlHash(hash, row.depth);
            hash = appendAssertCtlHash(hash, row.ordinal);
        }
        for (uint32_t slot : key.skips) hash = appendAssertCtlHash(hash, slot);
        return hash;
    }
};
struct AssertCtlBoundTable final {
    AstVarScope* cachep = nullptr;
    AstCFunc* bindp = nullptr;
};
struct AssertCtlSignatureHash final {
    size_t operator()(const AssertCtlSignature& sig) const {
        uint32_t hash = appendAssertCtlHash(V3Hash{sig.scopep}.value(), sig.mask);
        for (const auto& entry : sig.history) {
            hash = appendAssertCtlHash(hash, static_cast<uint64_t>(entry.first));
            hash = appendAssertCtlHash(hash, entry.second);
        }
        return hash;
    }
};

// Each identical concrete selection shares one cache and one cold pointer binder.
class AssertCtlTableBindings final {
    AstNetlist* const m_rootp;  // Netlist owning the generated table type
    AstScope* const m_topScopep;  // Model scope storing all concrete table caches
    V3SharedTmps m_tables{"__VassertCtlTable", VVarType::MODULETEMP};  // Cache variables
    AstCDType* m_tableDtp = nullptr;  // Created with the first nonempty selection
    size_t m_entries = 0;  // Number of concrete targets in the unique tables
    size_t m_combined = 0;  // Calls binding a copy of the shared rows (see newCallp)
    // Concrete target sequence to its shared cache and binder.
    std::unordered_map<AssertCtlTableKey, AssertCtlBoundTable, AssertCtlTableKeyHash> m_bound;
    struct IndexedTable final {
        AssertCtlBoundTable binding;  // Model-owned shared cache and its binder
        std::unordered_map<const AstVarScope*, size_t> slots;  // Index by canonical state
        const AssertCtlTableKey* keyp = nullptr;  // Key retained by m_bound
        // Unbound copy of rows that include a forwarded block, for a caller selecting such a
        // block at a smaller depth than these rows do
        AstAssertCtlTarget* sourcep = nullptr;
    };
    // Index base rows once, then build each overlay without scanning the base again.
    std::unordered_map<const AstAssertCtlTargetSet*, IndexedTable> m_absolute;

    struct InputRow final {
        AssertCtlTableRow row;
        AstNodeVarRef* refp;
        bool forward;  // Handle of a hierarchical block, whose library adds its rows
    };

    template <typename T_Rebind>
    AssertCtlBoundTable bindingFor(FileLine* flp, AstAssertCtlTarget* targetsp,
                                   const T_Rebind& rebind, IndexedTable* outputp = nullptr,
                                   const IndexedTable* sharedp = nullptr) {
        std::unordered_map<const AstVarScope*, size_t> seen;
        std::vector<InputRow> inputs;
        AssertCtlTableKey key{{}, {}, sharedp != nullptr};
        for (AstAssertCtlTarget* const targetp : VNList<AstAssertCtlTarget>{targetsp}) {
            AstNodeVarRef* const refp = targetp->statep();
            if (!targetp->forward()) rebind(refp);
            const AstVarScope* const statep = refp->varScopep();
            const auto result = seen.emplace(statep, inputs.size());
            if (result.second) {
                inputs.push_back(
                    {{statep, targetp->depth(), outputp || sharedp ? targetp->ordinal() : 0},
                     refp,
                     targetp->forward()});
            } else {
                AssertCtlTableRow& row = inputs[result.first->second].row;
                row.depth = std::min(row.depth, targetp->depth());
                if (outputp || sharedp) row.ordinal = std::min(row.ordinal, targetp->ordinal());
            }
        }
        if (sharedp) {
            // The shared table already adds the rows of a block it forwards to at no larger depth
            inputs.erase(std::remove_if(inputs.begin(), inputs.end(),
                                        [&](const InputRow& input) {
                                            return input.forward
                                                   && sharedp->slots.count(input.row.statep);
                                        }),
                         inputs.end());
            for (InputRow& input : inputs) {
                const auto found = sharedp->slots.find(input.row.statep);
                if (found == sharedp->slots.end()) continue;
                const size_t slot = found->second;
                const AssertCtlTableRow& original = sharedp->keyp->rows[slot];
                input.row.depth = std::min(input.row.depth, original.depth);
                input.row.ordinal = std::min(input.row.ordinal, original.ordinal);
                key.skips.push_back(static_cast<uint32_t>(slot));
            }
            std::sort(key.skips.begin(), key.skips.end());
            std::sort(inputs.begin(), inputs.end(), [](const InputRow& a, const InputRow& b) {
                return a.row.ordinal < b.row.ordinal;
            });
        }
        // Forwarded rows follow all others at runtime, keeping the slots of the others
        std::stable_partition(inputs.begin(), inputs.end(),
                              [](const InputRow& input) { return !input.forward; });
        key.rows.reserve(inputs.size());
        for (const InputRow& input : inputs) key.rows.push_back(input.row);
        const auto table = m_bound.try_emplace(std::move(key));
        const AssertCtlTableKey& stored = table.first->first;
        AssertCtlBoundTable& binding = table.first->second;
        if (table.second) binding = newBinding(flp, stored, inputs);
        if (outputp) {
            outputp->keyp = &stored;  // Rehashing does not invalidate element references.
            for (size_t slot = 0; slot < inputs.size(); ++slot) {
                outputp->slots.emplace(inputs[slot].row.statep, slot);
            }
        }
        return binding;
    }

    AssertCtlBoundTable newBinding(FileLine* flp, const AssertCtlTableKey& key,
                                   const std::vector<InputRow>& rows) {
        if (!m_tableDtp) {
            m_tableDtp = new AstCDType{flp, "VlAssertCtlTable"};
            m_rootp->typeTablep()->addTypesp(m_tableDtp);
        }
        // The cache belongs to the model, not to the calling module or class.
        AstVarScope* const cachep = m_tables.make(flp, m_topScopep, m_tableDtp);
        cachep->varp()->noReset(true);
        cachep->varp()->isInternal(true);
        cachep->varp()->setIgnoreSchedWrite();
        AstCFunc* const bindp = new AstCFunc{
            flp, "__VbindAssertCtlTable_" + std::to_string(m_bound.size()), m_topScopep};
        bindp->isStatic(true);
        bindp->isLoose(true);
        bindp->slow(true);
        std::string args
            = EmitCUtil::symClassVar() + ", std::vector<VlAssertCtlTable::Target>& targets";
        if (key.overlay) args += ", std::vector<uint32_t>& skipped";
        bindp->argTypes(args);
        m_topScopep->addBlocksp(bindp);
        AstCStmt* const initp = new AstCStmt{flp, "targets = {\n"};
        for (const InputRow& input : rows) {
            if (input.forward) continue;
            initp->add("{&");
            initp->add(input.refp->unlinkFrBack());
            initp->add(", " + std::to_string(input.row.depth) + ", "
                       + std::to_string(input.row.ordinal) + "},\n");
        }
        initp->add("};\n");
        for (const InputRow& input : rows) {
            if (!input.forward) continue;
            // The library model of the block shares this context (see V3ProtectLib)
            initp->add(input.row.statep->scopep()->modp()->origName()
                       + "_protectlib_assert_ctl_targets(VL_CVT_Q_VP(");
            initp->add(input.refp->unlinkFrBack());
            initp->add("), targets, " + std::to_string(input.row.depth) + ", "
                       + std::to_string(input.row.ordinal) + ");\n");
        }
        if (key.overlay) {
            initp->add("skipped = {\n");
            for (uint32_t slot : key.skips) initp->add(std::to_string(slot) + ",\n");
            initp->add("};\n");
        }
        bindp->addStmtsp(initp);
        m_entries += key.rows.size();
        return {cachep, bindp};
    }

    static void appendBinding(AstCStmt* callp, const AssertCtlBoundTable& binding, bool overlay) {
        FileLine* const flp = callp->fileline();
        callp->add(", ");
        callp->add(new AstVarRef{flp, binding.cachep, VAccess::READWRITE});
        callp->add(", [&](std::vector<VlAssertCtlTable::Target>& targets");
        if (overlay) callp->add(", std::vector<uint32_t>& skipped");
        callp->add(") { ");
        AstCCall* const bindCallp = new AstCCall{flp, binding.bindp};
        bindCallp->dtypeSetVoid();
        bindCallp->argTypes(overlay ? "vlSymsp, targets, skipped" : "vlSymsp, targets");
        callp->add(bindCallp);
        callp->add("; }");
    }

    static bool reachesForwardSooner(const IndexedTable& shared, AstAssertCtlTarget* targetsp) {
        for (const AstAssertCtlTarget* const targetp : VNList<AstAssertCtlTarget>{targetsp}) {
            if (!targetp->forward()) continue;
            const auto found = shared.slots.find(targetp->statep()->varScopep());
            if (found != shared.slots.end()
                && targetp->depth() < shared.keyp->rows[found->second].depth) {
                return true;
            }
        }
        return false;
    }

public:
    AssertCtlTableBindings(AstNetlist* rootp, AstScope* topScopep)
        : m_rootp{rootp}
        , m_topScopep{topScopep} {}
    ~AssertCtlTableBindings() {
        for (const auto& entry : m_absolute) {
            if (AstAssertCtlTarget* const sourcep = entry.second.sourcep) {
                VL_DO_DANGLING(sourcep->deleteTree(), sourcep);
            }
        }
    }

    size_t size() const { return m_bound.size(); }
    size_t entries() const { return m_entries; }
    size_t combined() const { return m_combined; }

    // Binder of the sites of this hierarchical block, called by its library (see V3ProtectLib)
    template <typename T_Rebind>
    AstCFunc* newExportp(AstAssertCtlTargetSet* setp, const T_Rebind& rebind) {
        AstCFunc* const bindp = bindingFor(setp->fileline(), setp->targetsp(), rebind).bindp;
        bindp->entryPoint(true);
        return bindp;
    }

    template <typename T_Rebind>
    AstCStmt* newCallp(AstAssertCtlApply* applyp, const T_Rebind& rebind) {
        FileLine* const flp = applyp->fileline();
        AstCStmt* const callp = new AstCStmt{flp, "vlSymsp->_vm_contextp__->"};
        const IndexedTable* sharedp = nullptr;
        if (AstAssertCtlTargetSet* const setp = applyp->targetSetp()) {
            const auto shared = m_absolute.try_emplace(setp);
            IndexedTable& table = shared.first->second;
            if (shared.second && setp->targetsp()) {
                for (const AstAssertCtlTarget* const targetp : setp->targetspList()) {
                    if (!targetp->forward()) continue;
                    table.sourcep = setp->targetsp()->cloneTree(true);
                    break;
                }
                table.binding = bindingFor(flp, setp->targetsp(), rebind, &table);
            }
            if (table.binding.cachep) sharedp = &table;
        }
        // An overlay cannot replace the rows a forwarded block adds at runtime. A caller
        // selecting the block at a smaller depth instead applies all its rows as one table,
        // binding its own copy of the shared rows.
        if (sharedp && reachesForwardSooner(*sharedp, applyp->targetsp())) {
            applyp->addTargetsp(sharedp->sourcep->cloneTree(true));
            sharedp = nullptr;
            ++m_combined;
        }
        const bool mixed = sharedp && applyp->targetsp();
        const AssertCtlBoundTable local
            = applyp->targetsp() ? bindingFor(flp, applyp->targetsp(), rebind, nullptr, sharedp)
                                 : AssertCtlBoundTable{};
        if (!sharedp && !local.cachep) {
            callp->add("assertCtlValid(");
            callp->add(applyp->effectp()->unlinkFrBack());
            callp->add(");\n");
            return callp;
        }
        callp->add(mixed ? "assertCtlMixedTable(" : "assertCtlTable(");
        callp->add(applyp->effectp()->unlinkFrBack());
        callp->add(", ");
        callp->add(applyp->typesp()->unlinkFrBack());
        callp->add(", " + std::to_string(applyp->directives()) + ", ");
        callp->add(applyp->limitp()->unlinkFrBack());
        if (sharedp) appendBinding(callp, sharedp->binding, false);
        if (local.cachep) appendBinding(callp, local, mixed);
        callp->add(");\n");
        return callp;
    }
};
}  // namespace

void V3AssertCommon::bindControlQueries(AstNetlist* rootp) {
    // Scoped target writes identify the concrete states that a selector can reach.
    std::unordered_set<const AstVarScope*> selected;
    std::vector<AstVarScope*> selectedInOrder;
    std::vector<AstAssertCtlRead*> reads;
    std::vector<AstAssertCtlApply*> applies;
    std::vector<AstAssertCtlTarget*> uniqueLists;
    std::unordered_set<const AstAssertCtlTargetSet*> seenSets;
    const auto addTargets = [&](AstAssertCtlTarget* targetsp) {
        if (!targetsp) return;
        uniqueLists.push_back(targetsp);
        std::unordered_map<const AstVarScope*, AstAssertCtlTarget*> seen;
        std::vector<AstAssertCtlTarget*> duplicates;
        for (AstAssertCtlTarget* const targetp : VNList<AstAssertCtlTarget>{targetsp}) {
            AstVarScope* const statep = targetp->statep()->varScopep();
            UASSERT_OBJ(statep, targetp, "Unbound assertion control state");
            const auto target = seen.emplace(statep, targetp);
            if (!target.second) {
                AstAssertCtlTarget* const firstp = target.first->second;
                firstp->depth(std::min(firstp->depth(), targetp->depth()));
                firstp->ordinal(std::min(firstp->ordinal(), targetp->ordinal()));
                duplicates.push_back(targetp);
            } else if (!targetp->forward() && selected.emplace(statep).second) {
                selectedInOrder.push_back(statep);
            }
        }
        // Different scope paths can alias one instance. Apply each effect once per site.
        VNDeleter deleter;
        for (AstAssertCtlTarget* const targetp : duplicates) {
            VL_DO_DANGLING(deleter.pushDeletep(targetp->unlinkFrBack()), targetp);
        }
    };
    rootp->foreach([&](AstScope* scopep) {
        if (!scopep->blocksp()) return;
        scopep->blocksp()->foreachAndNext([&](AstAssertCtlApply* applyp) {
            applies.push_back(applyp);
            if (AstAssertCtlTargetSet* const setp = applyp->targetSetp()) {
                if (seenSets.emplace(setp).second) addTargets(setp->targetsp());
            }
            addTargets(applyp->targetsp());
        });
    });
    AstAssertCtlTargetSet* const exportp = rootp->assertCtlExportp();
    if (exportp && seenSets.emplace(exportp).second) addTargets(exportp->targetsp());
    rootp->foreach([&](AstAssertCtlRead* readp) { reads.push_back(readp); });
    // Matching component histories imply matching unions. Keeping components distinct
    // can retain separate state when two different histories happen to have equal unions.
    std::unordered_map<const AstVarScope*, AssertCtlHistory> histories;
    for (size_t i = 0; i < uniqueLists.size(); ++i) {
        const VNList<AstAssertCtlTarget> targets{uniqueLists[i]};
        for (const AstAssertCtlTarget* const targetp : targets) {
            if (targetp->forward()) continue;
            histories[targetp->statep()->varScopep()].emplace_back(i, targetp->depth());
        }
    }
    std::unordered_map<AssertCtlSignature, AstVarScope*, AssertCtlSignatureHash> groups;
    std::unordered_map<const AstVarScope*, AstVarScope*> canonical;
    std::vector<AstVarScope*> representatives;
    for (AstVarScope* const statep : selectedInOrder) {
        AssertCtlSignature signature{statep->scopep(), statep->varp()->assertCtlMask(),
                                     std::move(histories.at(statep))};
        const auto result = groups.emplace(std::move(signature), statep);
        canonical.emplace(statep, result.first->second);
        if (result.second) representatives.push_back(statep);
    }
    // If only some instances use a declaration, allocate their state once in the
    // root rather than adding a dead object to every instance of its module.
    struct StateCounts final {
        size_t declared = 0;
        size_t selected = 0;
    };
    std::unordered_map<const AstVar*, StateCounts> stateCounts;
    rootp->foreach([&](const AstVarScope* statep) {
        if (statep->varp()->assertCtlMask()) ++stateCounts[statep->varp()].declared;
    });
    for (const AstVarScope* const statep : representatives) ++stateCounts[statep->varp()].selected;
    V3SharedTmps concreteStates{"__VassertCtlState", VVarType::MODULETEMP};
    std::unordered_map<const AstVarScope*, AstVarScope*> replacements;
    AstScope* const topScopep = rootp->topScopep()->scopep();
    for (AstVarScope* const oldp : representatives) {
        AstVar* const varp = oldp->varp();
        const StateCounts& counts = stateCounts.at(varp);
        if (counts.declared == counts.selected) continue;
        AstVarScope* const newp = concreteStates.make(oldp->fileline(), topScopep, varp->dtypep());
        newp->varp()->assertCtlMask(varp->assertCtlMask());
        newp->varp()->isInternal(true);
        newp->varp()->setIgnoreSchedWrite();
        newp->varp()->lifetime(VLifetime::STATIC_EXPLICIT);
        replacements.emplace(oldp, newp);
    }
    const auto rebind = [&](AstNodeVarRef* refp) {
        AstVarScope* statep = canonical.at(refp->varScopep());
        const auto it = replacements.find(statep);
        if (it != replacements.end()) statep = it->second;
        refp->varp(statep->varp());
        refp->varScopep(statep);
    };
    // The assertion and violation nodes no longer own the state after query lowering.
    rootp->foreach([](AstNodeStmt* stmtp) { stmtp->controlVarp(nullptr); });
    VNDeleter deleter;
    for (AstAssertCtlRead* const readp : reads) {
        AstVarRef* const statep = readp->statep();
        AstNodeExpr* replacementp;
        if (!selected.count(statep->varScopep())) {
            replacementp = readp->globalp()->unlinkFrBack();
        } else {
            rebind(statep);
            AstCExpr* const exprp = new AstCExpr{readp->fileline(), AstCExpr::Pure{}};
            exprp->dtypeFrom(readp);
            exprp->add(statep->unlinkFrBack());
            exprp->add(".get(VerilatedAssertCtlQuery::"s + assertCtlQueryName(readp->query())
                       + ")");
            replacementp = exprp;
        }
        readp->replaceWith(replacementp);
        VL_DO_DANGLING(deleter.pushDeletep(readp), readp);
    }

    AssertCtlTableBindings tables{rootp, topScopep};
    for (AstAssertCtlApply* const applyp : applies) {
        applyp->replaceWith(tables.newCallp(applyp, rebind));
        VL_DO_DANGLING(deleter.pushDeletep(applyp), applyp);
    }
    if (exportp) {
        rootp->assertCtlExportFuncp(tables.newExportp(exportp, rebind));
        rootp->assertCtlExportp(nullptr);
    }
    std::vector<AstAssertCtlTargetSet*> sharedSets;
    rootp->foreach([&](AstAssertCtlTargetSet* setp) { sharedSets.push_back(setp); });
    const size_t sharedSetCount = sharedSets.size();
    for (AstAssertCtlTargetSet* const setp : sharedSets) {
        VL_DO_DANGLING(deleter.pushDeletep(setp->unlinkFrBack()), setp);
    }
    UASSERT_OBJ(!rootp->exists([](const AstNode* nodep) {
        return VN_IS(nodep, AssertCtlApply) || VN_IS(nodep, AssertCtlRead);
    }),
                rootp, "Assertion control binding left unresolved operations");
    if (v3Global.opt.stats()) {
        V3Stats::addStatSum("Assertions, Scoped selected sites", selected.size());
        V3Stats::addStatSum("Assertions, Scoped state instances", representatives.size());
        V3Stats::addStatSum("Assertions, Scoped tables", tables.size());
        V3Stats::addStatSum("Assertions, Scoped table entries", tables.entries());
        V3Stats::addStatSum("Assertions, Scoped combined forward tables", tables.combined());
        V3Stats::addStatSum("Assertions, Scoped target lists", uniqueLists.size());
        V3Stats::addStatSum("Assertions, Shared absolute target lists", sharedSetCount);
    }
}

bool V3AssertCommon::isSampledType(const AstNodeDType* dtypep) {
    // An integral or real type, a string, a class handle, or an unpacked, dynamic or queue array
    // or an unpacked structure of such types (IEEE 1800-2023 16.9.3).
    dtypep = dtypep->skipRefp();
    if (dtypep->isIntegralOrPacked() || dtypep->isDouble() || dtypep->isString()
        || VN_IS(dtypep, ClassRefDType)) {
        return true;
    }
    if (const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType)) {
        return isSampledType(arrayp->subDTypep());
    }
    if (const AstQueueDType* const arrayp = VN_CAST(dtypep, QueueDType)) {
        return isSampledType(arrayp->subDTypep());
    }
    if (const AstDynArrayDType* const arrayp = VN_CAST(dtypep, DynArrayDType)) {
        return isSampledType(arrayp->subDTypep());
    }
    const AstStructDType* const structp = VN_CAST(dtypep, StructDType);
    if (!structp) return false;
    for (const AstMemberDType* memberp = structp->membersp(); memberp;
         memberp = VN_AS(memberp->nextp(), MemberDType)) {
        if (!isSampledType(memberp->subDTypep())) return false;
    }
    return true;
}

bool V3AssertCommon::checkSvaValueLimit(AstNode* nodep, const AstConst* constp, const char* what) {
    // Temporal values can materialize as O(N) AST or state in later passes.
    // Leave headroom for a range ring's extra slot and V3Number's signed
    // `(bits + 31) / 32` word count.
    static constexpr unsigned SVA_VALUE_HARD_LIMIT
        = static_cast<unsigned>(std::numeric_limits<int>::max()) - 32U;
    const unsigned configuredLimit = static_cast<unsigned>(v3Global.opt.maxNumWidth());
    const unsigned limit = std::min(configuredLimit, SVA_VALUE_HARD_LIMIT);
    if (constp->num().fitsInUInt() && constp->toUInt() <= limit) return true;
    nodep->v3warn(E_UNSUPPORTED, "Unsupported: " << what << " exceeds implementation limit of "
                                                 << limit
                                                 << (configuredLimit <= SVA_VALUE_HARD_LIMIT
                                                         ? " (--max-num-width)"
                                                         : " (host arithmetic limit)"));
    return false;
}

// The bound of a cycle delay in a sequence, if a non-negative elaboration-time constant
static const AstConst* checkSvaDelayBound(AstNode* errp, AstNodeExpr* boundp, const char* what) {
    const AstConst* const constp = VN_CAST(boundp, Const);
    if (!constp || (constp->dtypep()->isSigned() && constp->num().isNegative())) {
        errp->v3error(what << " is not a non-negative elaboration-time constant"
                              " (IEEE 1800-2023 16.7)");
        return nullptr;
    }
    if (!V3AssertCommon::checkSvaValueLimit(errp, constp, "SVA cycle delay")) return nullptr;
    return constp;
}

// Fold the bounds of a cycle delay in a sequence, and return if they are valid, else report it
// on errp
static bool svaCycleDelayValid(const AstDelay* nodep, AstNode* errp) {
    V3Const::constifyParamsNoWarnEdit(nodep->lhsp());
    const AstConst* const minConstp = checkSvaDelayBound(
        errp, nodep->lhsp(), nodep->isRangeDelay() ? "Range delay minimum" : "Delay value");
    if (!nodep->rhsp() || nodep->isUnbounded()) return minConstp != nullptr;
    V3Const::constifyParamsNoWarnEdit(nodep->rhsp());
    const AstConst* const maxConstp
        = checkSvaDelayBound(errp, nodep->rhsp(), "Range delay maximum");
    if (!minConstp || !maxConstp) return false;
    if (maxConstp->toUInt() < minConstp->toUInt()) {
        errp->v3error("Range delay maximum must be >= minimum (IEEE 1800-2023 16.7)");
        return false;
    }
    return true;
}

void V3AssertCommon::checkSvaCycleDelay(AstDelay* nodep, AstNode* errp) {
    if (svaCycleDelayValid(nodep, errp)) return;
    // Make the delay valid, so later steps do not fail after the error
    FileLine* const flp = nodep->fileline();
    AstNodeExpr* const minp = nodep->lhsp();
    minp->replaceWith(new AstConst{flp, AstConst::BitFalseErroring{}});
    VL_DO_DANGLING(minp->deleteTree(), minp);
    if (nodep->rhsp() && !nodep->isUnbounded()) {
        AstNodeExpr* const maxp = nodep->rhsp();
        maxp->replaceWith(new AstConst{flp, AstConst::BitFalseErroring{}});
        VL_DO_DANGLING(maxp->deleteTree(), maxp);
    }
}

// Replace an invalid repetition count, so later steps do not fail, or expand it, after the error
static void replaceSvaRepCount(AstNodeExpr* countp) {
    countp->replaceWith(new AstConst{countp->fileline(), 1});
    VL_DO_DANGLING(countp->deleteTree(), countp);
}

void V3AssertCommon::checkSvaRepetition(AstSConsRep* nodep, AstNode* errp, bool emptyOk) {
    if (VN_IS(nodep->maxCountp(), Unbounded)) {
        // A '$' actual argument (IEEE 1800-2023 16.8), as [*N:$]
        AstSConsRep* const newp
            = new AstSConsRep{nodep->fileline(), nodep->exprp()->unlinkFrBack(),
                              nodep->countp()->unlinkFrBack(), nullptr, true};
        newp->dtypeFrom(nodep);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        nodep = newp;
    }
    // The counts must be valid elaboration-time constants.
    V3Const::constifyParamsEdit(nodep->countp());
    const AstConst* minConstp = VN_CAST(nodep->countp(), Const);
    if (!minConstp) {
        errp->v3error("Consecutive repetition count must be constant expression"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (minConstp->toSInt() < 0) {
        errp->v3error("Consecutive repetition count must be non-negative"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (checkSvaValueLimit(errp, minConstp, "SVA repetition count")) {
        if (!nodep->unbounded() && !nodep->maxCountp() && minConstp->toSInt() < 1 && !emptyOk) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: [*0] consecutive repetition");
        }
    } else {
        minConstp = nullptr;  // Over the limit
    }
    if (!minConstp) replaceSvaRepCount(nodep->countp());
    if (!nodep->maxCountp()) return;
    V3Const::constifyParamsEdit(nodep->maxCountp());
    const AstConst* const maxConstp = VN_CAST(nodep->maxCountp(), Const);
    if (!maxConstp) {
        errp->v3error("Consecutive repetition max count must be constant"
                      " expression (IEEE 1800-2023 16.9.2)");
    } else if (minConstp && maxConstp->toSInt() < minConstp->toSInt()) {
        errp->v3error("Consecutive repetition max count must be >= min count"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (checkSvaValueLimit(errp, maxConstp, "SVA repetition count")) {
        if (maxConstp->toSInt() < 1 && !emptyOk) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: [*N:0] consecutive repetition"
                                        " with zero max count");
        }
        return;
    }
    // The min count is then at most 1 too
    replaceSvaRepCount(nodep->maxCountp());
    if (minConstp) replaceSvaRepCount(nodep->countp());
}

// Goto repetition [->N] or nonconsecutive repetition [=N], with the kind named in messages
template <typename T_Rep>
static void checkSvaGotoOrNonConsRep(T_Rep* nodep, const char* kind, AstNode* errp) {
    // Replace a non-constant count after reporting it, so later steps do not fail.
    if (!nodep->maxCountp()) {
        V3Const::constifyParamsNoWarnEdit(nodep->countp());
        const AstConst* const constp = VN_CAST(nodep->countp(), Const);
        if (!constp) {
            errp->v3error("Repetition count is not an elaboration-time constant"
                          " (IEEE 1800-2023 16.9.2)");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->dtypep()->isSigned() && constp->num().isNegative()) {
            errp->v3error("Repetition count must be non-negative"
                          " (IEEE 1800-2023 16.9.2)");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->num().mostSetBitP1() > 31) {
            errp->v3warn(
                E_UNSUPPORTED,
                "Unsupported: SVA repetition count exceeds implementation limit of 2147483647");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->isZero()) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: zero repetition count"
                                        " (IEEE 1800-2023 16.9.2)");
        }
        return;
    }
    // A '$' maximum is legal, but is not an expression to constify
    const bool unbounded = VN_IS(nodep->maxCountp(), Unbounded);
    // Accessors are re-fetched after constifyParamsEdit, as it can replace the node in-tree
    V3Const::constifyParamsEdit(nodep->countp());
    if (!unbounded) V3Const::constifyParamsEdit(nodep->maxCountp());
    const AstConst* const minConstp = VN_CAST(nodep->countp(), Const);
    const AstConst* const maxConstp = VN_CAST(nodep->maxCountp(), Const);
    if (!minConstp || (!maxConstp && !unbounded)) {
        errp->v3error(std::string{kind}
                      + " repetition range bounds must be constant expressions"
                        " (IEEE 1800-2023 16.9.2)");
        if (!minConstp) replaceSvaRepCount(nodep->countp());
        if (!maxConstp && !unbounded) replaceSvaRepCount(nodep->maxCountp());
    } else if (minConstp->toSInt() < 0) {
        errp->v3error(std::string{kind}
                      + " repetition range min count must be non-negative"
                        " (IEEE 1800-2023 16.9.2)");
        replaceSvaRepCount(nodep->countp());
        if (!unbounded) replaceSvaRepCount(nodep->maxCountp());
    } else if (unbounded) {
        // Only ever written in the body, as a '$' actual argument is checked when substituted
        nodep->maxCountp()->v3warn(E_UNSUPPORTED,
                                   "Unsupported: " << kind
                                                   << " repetition range with '$' maximum"
                                                      " (IEEE 1800-2023 16.9.2)");
    } else if (maxConstp->toSInt() < minConstp->toSInt()) {
        errp->v3error(std::string{kind}
                      + " repetition range max count must be >= min count"
                        " (IEEE 1800-2023 16.9.2)");
        replaceSvaRepCount(nodep->countp());
        replaceSvaRepCount(nodep->maxCountp());
    } else if (minConstp->isZero()) {
        errp->v3warn(E_UNSUPPORTED, "Unsupported: zero min count in "s + kind
                                        + " repetition range (IEEE 1800-2023 16.9.2)");
    }
}
void V3AssertCommon::checkSvaRepetition(AstSGotoRep* nodep, AstNode* errp) {
    checkSvaGotoOrNonConsRep(nodep, "Goto", errp);
}
void V3AssertCommon::checkSvaRepetition(AstSNonConsRep* nodep, AstNode* errp) {
    checkSvaGotoOrNonConsRep(nodep, "Nonconsecutive", errp);
}

void V3AssertCommon::checkSvaPastTicks(AstPast* nodep, AstNode* errp) {
    // The tick count must be a positive elaboration-time constant, else it is removed after
    // reporting it.
    V3Const::constifyParamsEdit(nodep->ticksp());  // ticksp may change
    const AstConst* const constp = VN_CAST(nodep->ticksp(), Const);
    if (!constp) {
        errp->v3error("$past tick value must be constant (IEEE 1800-2023 16.9.3)");
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (constp->toSInt() < 1) {
        constp->v3error("$past tick value must be >= 1 (IEEE 1800-2023 16.9.3)");
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (!checkSvaValueLimit(nodep, constp, "$past tick value")) {
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (constp->toSInt() > 10) {
        constp->v3warn(TICKCOUNT, "$past tick value of " << constp->toSInt()
                                                         << " may have a large performance cost");
    }
}

void V3AssertCommon::checkSvaAlwaysRange(AstPropAlways* nodep, AstNode* instp) {
    // Errors are reported on instp if given, else on the bound. After an error the bounds are
    // replaced with constants, so later steps do not fail.
    V3Const::constifyParamsEdit(nodep->loBoundp());  // loBoundp may change
    const bool hiUnbounded = VN_IS(nodep->hiBoundp(), Unbounded);
    if (!hiUnbounded) V3Const::constifyParamsEdit(nodep->hiBoundp());  // hiBoundp may change
    AstNode* const loErrp = instp ? instp : nodep->loBoundp();
    AstNode* const hiErrp = instp ? instp : nodep->hiBoundp();
    const AstConst* const loConstp = VN_CAST(nodep->loBoundp(), Const);
    const AstConst* const hiConstp = VN_CAST(nodep->hiBoundp(), Const);
    bool valid = false;
    if (!loConstp) {
        loErrp->v3error("always range low bound must be a constant expression"
                        " (IEEE 1800-2023 16.12.11)");
    } else if (loConstp->toSInt() < 0) {
        loErrp->v3error("always range low bound must be non-negative"
                        " (IEEE 1800-2023 16.12.11)");
    } else {
        valid = checkSvaValueLimit(loErrp, loConstp, "always range bound");
    }
    if (hiUnbounded && nodep->isStrong()) {
        // From a '$' actual argument (IEEE 1800-2023 16.8)
        hiErrp->v3error("s_always range must be bounded (IEEE 1800-2023 16.12.11)");
        valid = false;
    } else if (hiUnbounded) {
        // Weak always [m:$]
    } else if (!hiConstp) {
        hiErrp->v3error("always range high bound must be a constant expression"
                        " (IEEE 1800-2023 16.12.11)");
        valid = false;
    } else if (!checkSvaValueLimit(hiErrp, hiConstp, "always range bound")) {
        valid = false;
    } else if (loConstp && hiConstp->toSInt() < loConstp->toSInt()) {
        hiErrp->v3error("always range high bound must be >= low bound"
                        " (IEEE 1800-2023 16.12.11)");
        valid = false;
    }
    if (valid) return;
    for (AstNodeExpr* const boundp : {nodep->loBoundp(), nodep->hiBoundp()}) {
        if (VN_IS(boundp, Unbounded) && !nodep->isStrong()) continue;
        boundp->replaceWith(new AstConst{boundp->fileline(), AstConst::BitFalseErroring{}});
        VL_DO_DANGLING(boundp->deleteTree(), boundp);
    }
}

// Whether an action leaves itself by disable or jump
static bool actionLeavesItself(const AstNode* actionsp) {
    std::unordered_set<const AstNode*> blockps;  // What the action jumps in
    actionsp->foreachAndNext([&](const AstJumpBlock* blockp) { blockps.insert(blockp); });
    return actionsp->existsAndNext([&](const AstNode* np) {
        const AstJumpGo* const gop = VN_CAST(np, JumpGo);
        return VN_IS(np, Disable) || (gop && !blockps.count(gop->blockp()));
    });
}

// An action of a concurrent assertion that may suspend runs in a process of its own, so what
// runs it continues with other attempts and actions (IEEE 1800-2023 16.14.1). The conditions
// on the outcomes of attempts that gate actions, as newPassOnIf makes, are decided where they
// are, at once, and each action they gate runs in a process of its own.
AstNodeStmt* V3AssertCommon::newSpawnedAction(AstNodeStmt* actionsp) {
    // An action leaving itself stays in the process it leaves to
    if (!v3Global.opt.timing().isSetTrue() || !V3AssertCommon::procSuspends(actionsp)
        || actionLeavesItself(actionsp)) {
        return actionsp;
    }
    const auto isGatep = [](const AstNode* nodep) {
        const AstIf* const ifp = VN_CAST(nodep, If);
        return ifp && ifp->user1() && !V3AssertCommon::procSuspends(ifp->condp());
    };
    bool gated = false;
    for (AstNode* nodep = actionsp; nodep; nodep = nodep->nextp()) gated |= isGatep(nodep);
    if (!gated) {
        FileLine* const flp = actionsp->fileline();
        AstFork* const forkp = new AstFork{flp, VJoinType::JOIN_NONE};
        forkp->immediateStart(true);
        forkp->addForksp(new AstForkItem{flp, new AstBegin{flp, "", actionsp, true}});
        return forkp;
    }
    // Each gated action apart, and the statements between gates together
    AstNodeStmt* newsp = nullptr;
    AstNodeStmt* restsp = nullptr;
    while (actionsp) {
        AstNodeStmt* const nextp = VN_CAST(actionsp->nextp(), NodeStmt);
        if (nextp) nextp->unlinkFrBackWithNext();
        if (isGatep(actionsp)) {
            if (restsp) newsp = AstNode::addNext(newsp, newSpawnedAction(restsp));
            restsp = nullptr;
            AstIf* const gatep = VN_AS(actionsp, If);
            if (AstNodeStmt* const thensp = gatep->thensp()) {
                gatep->addThensp(newSpawnedAction(thensp->unlinkFrBackWithNext()));
            }
            newsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(newsp, gatep);
        } else {
            restsp = AstNode::addNext(restsp, actionsp);
        }
        actionsp = nextp;
    }
    if (restsp) newsp = AstNode::addNext(newsp, newSpawnedAction(restsp));
    return newsp;
}

// Whether the action of a concurrent assertion can run in the Reactive region, not in the
// process of its evaluation: it reads no automatic variable it does not declare, does not leave
// itself by disable or jump, has no named block, and reads no sampled value of a past tick
static bool actionRunsReactive(const AstNode* actionsp) {
    if (actionLeavesItself(actionsp)) return false;
    std::unordered_set<const AstVar*> ownps;  // What the action declares
    actionsp->foreachAndNext([&](const AstVar* varp) { ownps.insert(varp); });
    return !actionsp->existsAndNext([&](const AstNode* np) {
        if (const AstVarRef* const refp = VN_CAST(np, VarRef)) {
            return refp->varp()->lifetime().isAutomatic() && !ownps.count(refp->varp());
        }
        // A named block may be referenced by its name, also from a copy of the action
        if (const AstBegin* const beginp = VN_CAST(np, Begin)) {
            if (!beginp->name().empty()) return true;
        }
        // Sampled values of past ticks would read the registers of later ticks
        return VN_IS(np, Past) || VN_IS(np, Rose) || VN_IS(np, Fell) || VN_IS(np, Stable);
    });
}

// Find a timing control of a procedure

class AssertProcSuspendsVisitor final : public VNVisitorConst {
    bool m_suspends = false;  // Found one

    // The cycle delays of the property of an assertion in it are not its timing controls
    void visit(AstNodeCoverOrAssert*) override {}
    // A fork...join_none does not wait for the processes it starts
    void visit(AstFork* nodep) override {
        if (nodep->joinType().joinNone()) return;
        m_suspends = true;
    }
    // A task, unlike a function, may suspend its caller
    void visit(AstNodeFTaskRef* nodep) override {
        if (VN_IS(nodep->taskp(), Task)) m_suspends = true;
        if (!m_suspends) iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override {
        if (m_suspends) return;
        if (nodep->isTimingControl()) {
            m_suspends = true;
            return;
        }
        iterateChildrenConst(nodep);
    }

public:
    explicit AssertProcSuspendsVisitor(AstNode* stmtsp) { iterateAndNextConstNull(stmtsp); }
    bool suspends() const { return m_suspends; }
};

bool V3AssertCommon::procSuspends(AstNode* stmtsp) {
    return AssertProcSuspendsVisitor{stmtsp}.suspends();
}

// Return a new module temporary of the assertion's module
static AstVar* newReactiveTemp(const V3AssertReactive::Site& site, V3UniqueNames& names,
                               const char* namep) {
    FileLine* const flp = site.assertp->fileline();
    AstVar* const varp
        = new AstVar{flp, VVarType::MODULETEMP, names.get(namep), site.modp->findUInt32DType()};
    varp->isInternal(true);
    varp->lifetime(VLifetime::STATIC_EXPLICIT);
    varp->setIgnoreSchedWrite();
    site.modp->addStmtsp(varp);
    return varp;
}

V3AssertReactive::Runner& V3AssertReactive::runnerFor(const Site& site, V3UniqueNames& names) {
    std::vector<Runner>& runners = m_runners[site.containerp];
    for (Runner& runner : runners) {
        if (runner.clockp->sameTree(site.senTreep)) return runner;
    }
    FileLine* const flp = site.assertp->fileline();
    // Runs when an evaluation of the model notes an action pending, and runs what is pending
    // here, so costs nothing while nothing is pending. The note is in no variable, so is
    // unordered between threads, and moves freely with the evaluation (see newPendingNotep).
    AstSenTree* const senTreep
        = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_POSEDGE,
                                             new AstCExpr{flp, AstCExpr::Pure{},
                                                          "vlSymsp->__Vm_assertActionPending.load("
                                                          "std::memory_order_relaxed)",
                                                          1}}};
    AstIf* const bodyp = new AstIf{flp, new AstConst{flp, AstConst::BitFalse{}}};
    bodyp->branchPred(VBranchPred::BP_UNLIKELY);
    // Output of the time step's earlier regions, queued by multithreaded tasks, comes first
    if (v3Global.opt.mtasks()) {
        bodyp->addThensp(new AstCStmt{flp, "Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);"});
    }
    // Clear the note for the next evaluation, which the edge already took. No note is lost: the
    // Reactive region does not overlap the threads of the model's evaluation, so no evaluation
    // sets it while this runs, and one setting it later in the time step triggers this again.
    AstAlwaysReactive* const runnerp = new AstAlwaysReactive{
        flp, senTreep,
        new AstCStmt{
            flp, "vlSymsp->__Vm_assertActionPending.store(false, std::memory_order_relaxed);"}};
    runnerp->addStmtsp(bodyp);
    runners.push_back({runnerp, bodyp, site.senTreep->cloneTree(false), nullptr});
    ++m_statRunners;
    if (AstGenBlock* const genp = VN_CAST(site.containerp, GenBlock)) {
        genp->addItemsp(runnerp);
    } else {
        site.modp->addStmtsp(runnerp);
    }
    return runners.back();
}

V3AssertReactive::~V3AssertReactive() {
    for (const auto& it : m_runners) {
        for (const Runner& runner : it.second)
            VL_DO_DANGLING(runner.clockp->deleteTree(), runner.clockp);
    }
    V3Stats::addStatSum("Assertions, Reactive action runners", m_statRunners);
    V3Stats::addStatSum("Assertions, Reactive action kill checks", m_statKillChecks);
}

bool V3AssertReactive::mayKill() {
    // An assertion control of another model, as a hierarchical block, may also kill
    return v3Global.opt.hierChild() || !v3Global.opt.libCreate().empty()
           || v3Global.rootp()->exists([](const AstAssertCtl* ctlp) {
                  return ctlp->ctlType() == VAssertCtlType::KILL
                         || ctlp->ctlType() == VAssertCtlType::_TO_BE_EVALUATED;
              });
}

AstNodeExpr* V3AssertReactive::newKillCountp(const Site& site) {
    return V3AssertCommon::newAssertCtlGetp(site.assertp->fileline(), VAssertCtlQuery::KILL,
                                            site.assertp->userType(), site.assertp->directive(),
                                            site.assertp->controlVarp());
}

AstNodeStmt* V3AssertReactive::newPending(const Site& site, AstNodeStmt* actionsp,
                                          V3UniqueNames& names) {
    // Class processes run in the scope of their instance, not one of a module
    if (VN_IS(site.modp, Class) || !actionRunsReactive(actionsp)) return actionsp;
    FileLine* const flp = actionsp->fileline();
    // The action keeps the scope of the assertion, which V3Begin would have added
    if (!site.scope.empty()) {
        actionsp->foreachAndNext(
            [&](AstScopeName* namep) { namep->scopeAttr(site.scope + namep->scopeAttr()); });
    }
    Runner& runnerr = runnerFor(site, names);
    AstVar* const pendingp = newReactiveTemp(site, names, "Pending");
    // The $assertkill count at the first evaluation making an action pending, if one may kill
    AstVar* const killCountp = m_killChecks ? newReactiveTemp(site, names, "KillCount") : nullptr;
    const auto newKilledp = [&]() {
        return new AstNeq{flp, new AstVarRef{flp, killCountp, VAccess::READ}, newKillCountp(site)};
    };
    const auto newDropp = [&]() {
        return new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                             new AstConst{flp, 0}};
    };
    if (killCountp) {
        // Drop what is pending if an $assertkill came after its evaluation, before any action
        // runs, which may call one too
        ++m_statKillChecks;
        AstIf* const checkp = new AstIf{flp, newKilledp(), newDropp()};
        // Each assertion adds its check before its loop, so the first comes after the flush
        AstNode* const afterp = runnerr.lastCheckp ? runnerr.lastCheckp : runnerr.bodyp->thensp();
        if (afterp) {
            UASSERT_OBJ(afterp == runnerr.lastCheckp || VN_IS(afterp, CStmt), afterp,
                        "Action before the first $assertkill check");
            afterp->addNextHere(checkp);
        } else {
            runnerr.bodyp->addThensp(checkp);
        }
        runnerr.lastCheckp = checkp;
    }
    AstLoop* const loopp = new AstLoop{flp};
    loopp->addStmtsp(new AstLoopTest{flp, loopp, new AstVarRef{flp, pendingp, VAccess::READ}});
    loopp->addStmtsp(new AstAssign{
        flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
        new AstSub{flp, new AstVarRef{flp, pendingp, VAccess::READ}, new AstConst{flp, 1}}});
    loopp->addStmtsp(V3AssertCommon::newSpawnedAction(actionsp));
    runnerr.bodyp->addThensp(loopp);
    AstNodeExpr* const condp = runnerr.bodyp->condp()->unlinkFrBack();
    AstVarRef* const pendingRefp = new AstVarRef{flp, pendingp, VAccess::READ};
    if (VN_IS(condp, Const)) {
        VL_DO_DANGLING(condp->deleteTree(), condp);
        runnerr.bodyp->condp(pendingRefp);
    } else {
        runnerr.bodyp->condp(new AstLogOr{flp, condp, pendingRefp});
    }
    // pending++, noted for the runners
    AstNodeStmt* const stmtsp = new AstAssign{
        flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
        new AstAdd{flp, new AstVarRef{flp, pendingp, VAccess::READ}, new AstConst{flp, 1}}};
    // Noting it sets one value, from any thread, so may move like a display
    stmtsp->addNext(new AstCStmt{
        flp, "vlSymsp->__Vm_assertActionPending.store(true, std::memory_order_relaxed);",
        VCStmtType::ASSERT_ACTION_NOTE});
    if (killCountp) {
        // The first sets the count it is checked against; one after an $assertkill drops what
        // is pending before it
        AstIf* const armp
            = new AstIf{flp,
                        new AstLogOr{flp,
                                     new AstEq{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                               new AstConst{flp, 0}},
                                     newKilledp()},
                        newDropp()};
        armp->addThensp(new AstAssign{flp, new AstVarRef{flp, killCountp, VAccess::WRITE},
                                      newKillCountp(site)});
        return AstNode::addNext<AstNodeStmt, AstNodeStmt>(armp, stmtsp);
    }
    return stmtsp;
}

bool V3AssertCommon::refsSvaFormal(const AstNode* nodep) {
    return nodep->exists([](const AstNodeVarRef* refp) {
        const AstVar* const varp = refp->varp();
        if (!varp || !varp->isIO()) return false;
        const AstNode* const declp = varp->aboveLoopp();
        return VN_IS(declp, NodeSchema);
    });
}

AstNode* V3AssertCommon::checkSvaUnboundedActuals(
    AstNode* nodep, const std::unordered_map<const AstVar*, AstNodeExpr*>& portMap,
    AstNode* instp) {
    // A formal argument with a '$' actual argument may only be referenced as the maximum of a
    // cycle_delay_const_range_expression, of a cycle delay, an always, or a repetition, or as the
    // actual argument of a nested instance, which is checked when that is substituted (IEEE
    // 1800-2023 16.8). Run before the substitution, so that a '$' written in the body is not
    // mistaken for one from an actual argument.
    const bool anyUnbounded = std::any_of(portMap.begin(), portMap.end(), [](const auto& it) {
        return VN_IS(it.second, Unbounded);
    });
    if (!anyUnbounded) return nodep;
    std::unordered_set<const AstNode*> legalps;
    nodep->foreach([&](const AstDelay* delayp) {
        if (delayp->rhsp()) legalps.insert(delayp->rhsp());
    });
    nodep->foreach([&](const AstPropAlways* alwaysp) { legalps.insert(alwaysp->hiBoundp()); });
    nodep->foreach([&](const AstSConsRep* repp) { legalps.insert(repp->maxCountp()); });
    // Unlike a literal '$', which they do not support either
    std::unordered_set<const AstNode*> unsupps;
    nodep->foreach([&](const AstSGotoRep* repp) { unsupps.insert(repp->maxCountp()); });
    nodep->foreach([&](const AstSNonConsRep* repp) { unsupps.insert(repp->maxCountp()); });
    nodep->foreach([&](const AstSchemaRef* refp) {
        for (const AstArg* const argp : refp->argspList()) legalps.insert(argp->exprp());
    });
    std::vector<AstVarRef*> badps;
    nodep->foreach([&](AstVarRef* refp) {
        const auto it = portMap.find(refp->varp());
        if (it != portMap.end() && VN_IS(it->second, Unbounded) && !legalps.count(refp)) {
            AstNodeExpr* newp;
            if (unsupps.count(refp)) {
                instp->v3warn(E_UNSUPPORTED, "Unsupported: formal argument "
                                                 << refp->prettyNameQ()
                                                 << " with '$' actual argument as the maximum of a"
                                                    " goto or nonconsecutive repetition range");
                // Make the range its minimum, so later steps do not fail
                const AstSGotoRep* const gotop = VN_CAST(refp->backp(), SGotoRep);
                newp = (gotop ? gotop->countp() : VN_AS(refp->backp(), SNonConsRep)->countp())
                           ->cloneTreePure(false);
            } else {
                instp->v3error("Formal argument " << refp->prettyNameQ()
                                                  << " with '$' actual argument is used other"
                                                     " than as a range maximum (IEEE 1800-2023"
                                                     " 16.8)");
                newp = new AstConst{refp->fileline(), AstConst::BitFalseErroring{}};
            }
            // The body may be only the reference
            if (refp == nodep) {
                nodep = newp;
            } else {
                refp->replaceWith(newp);
            }
            badps.push_back(refp);
        }
    });
    for (AstVarRef* const refp : badps) VL_DO_DANGLING(refp->deleteTree(), refp);
    return nodep;
}

void V3AssertCommon::checkSvaInstanceConstants(AstNode* nodep, AstNode* instp) {
    // Check the cycle delays, repetition counts, always ranges and $past tick counts, now that
    // the formal arguments are replaced with the actual arguments (IEEE 1800-2023 16.8).
    // A delay still referencing a formal argument of an enclosing sequence or property is
    // checked when that is instanced. Collect first, as checking edits the delays.
    std::vector<AstDelay*> delayps;
    nodep->foreach([&](AstDelay* delayp) {
        if (!delayp->isCycleDelay() || refsSvaFormal(delayp->lhsp())) return;
        if (delayp->rhsp() && refsSvaFormal(delayp->rhsp())) return;
        delayps.push_back(delayp);
    });
    for (AstDelay* const delayp : delayps) checkSvaCycleDelay(delayp, instp);
    // Likewise repetitions and $past
    std::vector<AstNodeExpr*> exprps;
    nodep->foreach([&](AstNodeExpr* exprp) {
        const AstPast* const pastp = VN_CAST(exprp, Past);
        if (VN_IS(exprp, SConsRep) || VN_IS(exprp, SGotoRep) || VN_IS(exprp, SNonConsRep)
            || VN_IS(exprp, PropAlways) || (pastp && pastp->ticksp())) {
            if (!refsSvaFormal(exprp)) exprps.push_back(exprp);
        }
    });
    // Inner ones first, as checking an outer one may delete an invalid count holding them
    for (auto it = exprps.rbegin(); it != exprps.rend(); ++it) {
        AstNodeExpr* const exprp = *it;
        if (AstSConsRep* const repp = VN_CAST(exprp, SConsRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstSGotoRep* const repp = VN_CAST(exprp, SGotoRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstSNonConsRep* const repp = VN_CAST(exprp, SNonConsRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstPropAlways* const alwaysp = VN_CAST(exprp, PropAlways)) {
            checkSvaAlwaysRange(alwaysp, instp);
        } else {
            checkSvaPastTicks(VN_AS(exprp, Past), instp);
        }
    }
}

std::unordered_map<const AstVar*, AstVar*>
V3AssertCommon::newSvaLocalVars(const AstNodeSchema* schemap, AstNodeModule* modp,
                                V3UniqueNames& names) {
    std::unordered_map<const AstVar*, AstVar*> localVarMap;
    for (const AstNode* const declp : schemap->declspList()) {
        const AstVar* const varp = VN_CAST(declp, Var);
        if (!varp || varp->isIO()) continue;
        // An XTEMP stays one, see isMatchItem in V3AssertNfa
        const VVarType varType
            = varp->varType() == VVarType::XTEMP ? VVarType::XTEMP : VVarType::MODULETEMP;
        AstVar* const newVarp
            = new AstVar{varp->fileline(), varType, names.get(varp), varp->dtypep()};
        newVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        modp->addStmtsp(newVarp);
        localVarMap[varp] = newVarp;
    }
    return localVarMap;
}

AstNode* V3AssertCommon::relinkSvaInstanceBody(AstNode* bodyp, const AstSchemaRef* instp) {
    // A sequence or property may be instanced by a hierarchical name (IEEE 1800-2023 16.8,
    // 16.12). Its inlined body then refers to the declaring scope through the same path.
    const string dotted = instp->dotted();
    if (dotted.empty()) return bodyp;
    // Formal arguments and local variables, which are substituted by the caller
    std::unordered_set<const AstVar*> ownVarps;
    for (const AstNode* const declp : instp->schemap()->declspList()) {
        if (const AstVar* const varp = VN_CAST(declp, Var)) ownVarps.insert(varp);
    }
    // A hierarchical reference is downward if it starts at a scope in the declaring module.
    // Others are upward or absolute, so resolve the same from the instance.
    std::unordered_set<string> scopeNames;
    const AstNode* modp = instp->schemap();
    while (!VN_IS(modp, NodeModule)) modp = modp->backp();
    modp->foreach([&](const AstNode* nodep) {
        if (VN_IS(nodep, Cell) || VN_IS(nodep, NodeBlock) || VN_IS(nodep, GenBlock)
            || (VN_IS(nodep, Var) && VN_AS(nodep, Var)->isIfaceRef())) {
            scopeNames.insert(nodep->name());
        }
    });
    const auto relinkDotted = [&](const string& refDotted) {
        if (refDotted.empty()) return dotted;
        if (!scopeNames.count(refDotted.substr(0, refDotted.find('.')))) return refDotted;
        return dotted + "." + refDotted;
    };
    bodyp->foreach([&](AstVarXRef* refp) { refp->dotted(relinkDotted(refp->dotted())); });
    bodyp->foreach([&](AstNodeFTaskRef* refp) {
        if (!refp->classOrPackagep()) refp->dotted(relinkDotted(refp->dotted()));
    });
    bodyp->foreach([&](AstSchemaRef* refp) {
        if (!refp->classOrPackagep()) refp->dotted(relinkDotted(refp->dotted()));
    });
    bodyp->foreach([&](AstVarRef* refp) {
        if (refp->classOrPackagep() || ownVarps.count(refp->varp())) return;
        AstVarXRef* const xrefp
            = new AstVarXRef{refp->fileline(), refp->varp(), dotted, refp->access()};
        if (refp == bodyp) {
            bodyp = xrefp;
        } else {
            refp->replaceWith(xrefp);
        }
        VL_DO_DANGLING(refp->deleteTree(), refp);
    });
    return bodyp;
}

void V3AssertCommon::removeActualReductions(const std::vector<AstNodeExpr*>& actualps) {
    // V3Width reduces a reference to an untyped formal argument used as a boolean, as its type is
    // only known from the actual argument (IEEE 1800-2023 16.8). A sequence or property
    // instance is not an operand of a reduction, and for any other single-bit actual argument the
    // reduction is an identity.
    for (AstNodeExpr* const actualp : actualps) {
        AstRedOr* const redOrp = VN_CAST(actualp->firstAbovep(), RedOr);
        if (!redOrp || actualp->width() != 1) continue;
        redOrp->replaceWith(actualp->unlinkFrBack());
        VL_DO_DANGLING(redOrp->deleteTree(), redOrp);
    }
}

void V3AssertCommon::lowerSvaLocalVarInits(
    AstProperty* propp, AstPropSpec* bodyp,
    const std::unordered_map<const AstVar*, AstVar*>& localVarMap) {
    // A local variable is initialized at the start of each attempt (IEEE 1800-2023 16.10), but
    // its module variable is not. A read that is not after a match item assigning the variable
    // sees the initial value. Here only the reads in the consequent of an implication whose
    // antecedent is `(e, v = x)` are known to follow it; a read after a match item in the same
    // sequence, which V3AssertNfa lowers later, is conservatively reported too.
    const AstImplication* const implp = VN_CAST(bodyp->propp(), Implication);
    const AstExprStmt* const itemsp = implp ? VN_CAST(implp->lhsp(), ExprStmt) : nullptr;
    // V3LinkParse keeps the initializer of a local variable as its value
    for (AstNode* const declp : propp->declspList()) {
        AstVar* const localVarp = VN_CAST(declp, Var);
        if (!localVarp || localVarp->isIO() || !localVarp->valuep()) continue;
        V3Const::constifyParamsNoWarnEdit(localVarp->valuep());  // valuep may change
        AstNodeExpr* const initp = VN_AS(localVarp->valuep(), NodeExpr);
        const AstConst* const constp = VN_CAST(initp, Const);
        const AstVar* const varp = localVarMap.at(localVarp);
        std::vector<AstVarRef*> readps;
        bool assigned = false;
        bodyp->foreach([&](AstVarRef* refp) {
            if (refp->varp() != varp) return;
            if (refp->access().isReadOnly()) {
                readps.push_back(refp);
            } else {
                assigned = true;
            }
        });
        if (assigned) {
            std::unordered_set<const AstVarRef*> beforeps{readps.begin(), readps.end()};
            if (itemsp && itemsp->exists([&](const AstVarRef* refp) {
                    return refp->varp() == varp && refp->access().isWriteOrRW();
                })) {
                implp->rhsp()->foreach([&](const AstVarRef* refp) { beforeps.erase(refp); });
            }
            if (!beforeps.empty()) {
                initp->v3warn(E_UNSUPPORTED,
                              "Unsupported: initializer of a property local variable"
                              " assigned by a match item, read other than in the"
                              " consequent of an implication whose antecedent assigns"
                              " it (IEEE 1800-2023 16.10)");
            }
        } else if (constp) {
            for (AstVarRef* const refp : readps) {
                AstConst* const newp = new AstConst{refp->fileline(), constp->num()};
                newp->dtypeFrom(refp);
                refp->replaceWith(newp);
                VL_DO_DANGLING(refp->deleteTree(), refp);
            }  // LCOV_EXCL_LINE -- GCC exception cleanup branch
        } else if (!readps.empty()) {
            initp->v3warn(E_UNSUPPORTED, "Unsupported: non-constant initializer of a property"
                                         " local variable (IEEE 1800-2023 16.10)");
        }
    }
}

void V3AssertCommon::reducePlainAlways(AstPropSpec* specp) {
    // Equivalent when the property is attempted at every tick (IEEE 1800-2023 16.12.11).
    // Unlike under always, p may then contain property operators.
    AstPropAlways* const alwaysp = VN_CAST(specp->propp(), PropAlways);
    if (!alwaysp || !alwaysp->isPlainAlways()) return;
    alwaysp->replaceWith(alwaysp->propp()->unlinkFrBack());
    VL_DO_DANGLING(alwaysp->deleteTree(), alwaysp);
}

//######################################################################
// AssertInferClockVisitor
// Find the variables a procedure body uses other than in a clocking event or an assertion
// statement, which prevent inferring a clock from an event expression of the procedure's
// event control (IEEE 1800-2023 16.14.6). An event of the body counts as a clocking event, as
// does the clock that assertion lowering gives a sampled value function.

class AssertInferClockVisitor final : public VNVisitorConst {
    // STATE
    std::unordered_set<const AstVar*> m_usedVarps;  // Variables used in the body

    // VISITORS
    void visit(AstSenItem*) override {}
    void visit(AstNodeCoverOrAssert*) override {}
    void visit(AstVarRef* nodep) override { m_usedVarps.emplace(nodep->varp()); }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertInferClockVisitor(AstNode* stmtsp) { iterateAndNextConstNull(stmtsp); }
    ~AssertInferClockVisitor() override = default;
    // True if the body uses a variable of the expression
    bool usesVarOf(const AstNode* exprp) const {
        return exprp->exists(
            [&](const AstVarRef* refp) { return m_usedVarps.count(refp->varp()) != 0; });
    }
};

AstSenItem* V3AssertCommon::inferredClock(const AstAlways* alwaysp) {
    // The only event expression of the event control that is an edge event, possibly with iff,
    // or solely an event variable or clocking block, whose variables the procedure body does
    // not use (IEEE 1800-2023 16.14.6 c))
    if (!alwaysp->sentreep() || !alwaysp->stmtsp()) return nullptr;
    const AssertInferClockVisitor bodyUses{alwaysp->stmtsp()};
    AstSenItem* clockp = nullptr;
    for (AstSenItem* const itemp : alwaysp->sentreep()->sensespList()) {
        // A clocking block is an event variable here
        const bool isEvent = VN_IS(itemp->sensp(), NodeVarRef) && !itemp->condp()
                             && itemp->sensp()->dtypep()->isEvent();
        if (!itemp->edgeType().anEdge() && !isEvent) continue;
        if (bodyUses.usesVarOf(itemp->sensp())) continue;
        if (clockp) return nullptr;
        clockp = itemp;
    }
    return clockp;
}

//######################################################################
// AssertInferBlockVisitor
// Find a statement of a procedure body that prevents inferring a clock for the procedure: a
// blocking timing control, including a call of a task that blocks, or an event control
// (IEEE 1800-2023 16.14.6 a), b)). A timing control of a process forked without waiting for
// it, or of a nonblocking assignment, does not block. Neither does an assertion statement,
// whose actions run in a process of their own. In a task, only the blocking statements count.

class AssertInferBlockVisitor final : public VNVisitorConst {
    // STATE
    std::unordered_map<const AstNodeFTask*, bool>&
        m_taskBlocks;  // Whether calling each task blocks
    const bool m_inTask;  // In a task, not a procedure
    bool m_nonblocking = false;  // In a statement whose timing controls do not block
    const AstNode* m_blockerp = nullptr;  // The first statement found

    // METHODS
    bool taskBlocks(const AstNodeFTask* taskp) {
        // Insert false first, so recursive calls terminate
        if (!m_taskBlocks.emplace(taskp, false).second) return m_taskBlocks[taskp];
        const bool blocks
            = AssertInferBlockVisitor{m_taskBlocks, true, taskp->stmtsp()}.blockerp() != nullptr;
        m_taskBlocks[taskp] = blocks;
        return blocks;
    }

    // An event control, which prevents the inference also where it does not block
    void foundEventControl(const AstNode* nodep) {
        if (!m_inTask || !m_nonblocking) m_blockerp = nodep;
    }

    // VISITORS
    void visit(AstNodeCoverOrAssert*) override {}
    void visit(AstEventControl* nodep) override {
        if (!m_blockerp) foundEventControl(nodep);
    }
    void visit(AstFork* nodep) override {
        if (m_blockerp) return;
        VL_RESTORER(m_nonblocking);
        m_nonblocking |= nodep->joinType().joinNone();
        if (!m_nonblocking) m_blockerp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeAssign* nodep) override {
        if (m_blockerp) return;
        VL_RESTORER(m_nonblocking);
        m_nonblocking |= VN_IS(nodep, AssignDly);
        // An intra-assignment event control
        if (VN_IS(nodep->timingControlp(), SenTree)) foundEventControl(nodep);
        if (!m_blockerp && !m_nonblocking && nodep->isTimingControl()) m_blockerp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (m_blockerp) return;
        if (!m_nonblocking && VN_IS(nodep->taskp(), Task) && taskBlocks(nodep->taskp())) {
            m_blockerp = nodep;
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override {
        if (m_blockerp) return;
        if (!m_nonblocking && nodep->isTimingControl()) m_blockerp = nodep;
        iterateChildrenConst(nodep);
    }

public:
    // CONSTRUCTORS
    AssertInferBlockVisitor(std::unordered_map<const AstNodeFTask*, bool>& taskBlocks, bool inTask,
                            AstNode* stmtsp)
        : m_taskBlocks{taskBlocks}
        , m_inTask{inTask} {
        iterateAndNextConstNull(stmtsp);
    }
    ~AssertInferBlockVisitor() override = default;
    const AstNode* blockerp() const { return m_blockerp; }
};

const AstNode*
V3AssertCommon::inferenceBlockerp(const AstAlways* alwaysp,
                                  std::unordered_map<const AstNodeFTask*, bool>& taskBlocks) {
    return AssertInferBlockVisitor{taskBlocks, false, alwaysp->stmtsp()}.blockerp();
}

//######################################################################
// AssertActionXRefVisitor
// Find hierarchical references in an action to its variables whose first name the upward name
// resolution (IEEE 1800-2023 23.8) finds inside the action, so in the current instance: as a
// block enclosing the reference, or a child block of one or of the action. Other paths may
// leave the action and select another instance.

class AssertActionXRefVisitor final : public VNVisitorConst {
    // STATE
    std::unordered_set<const AstVar*> m_declVarps;  // Variables declared in the action
    // Names of the child blocks of each named block (nullptr: the action), through unnamed blocks
    std::unordered_map<const AstNodeBlock*, std::vector<std::string>> m_childNames;
    std::unordered_map<std::string, int> m_visibleNames;  // Count of first names found inside
    const AstNodeBlock* m_blockp = nullptr;  // Enclosing named block (nullptr: the action)
    bool m_collecting = true;  // Collecting m_childNames, else finding references
    std::vector<AstVarXRef*> m_xrefps;  // References found

    void showNames(const AstNodeBlock* blockp, int delta) {
        for (const std::string& name : m_childNames[blockp]) m_visibleNames[name] += delta;
    }

    // VISITORS
    void visit(AstNodeBlock* nodep) override {
        if (nodep->name().empty()) {
            iterateChildrenConst(nodep);
            return;
        }
        if (m_collecting) m_childNames[m_blockp].push_back(nodep->name());
        VL_RESTORER(m_blockp);
        m_blockp = nodep;
        if (!m_collecting) showNames(nodep, 1);
        iterateChildrenConst(nodep);
        if (!m_collecting) showNames(nodep, -1);
    }
    void visit(AstVarXRef* nodep) override {
        if (m_collecting || !m_declVarps.count(nodep->varp())) return;
        const std::string dotted = nodep->dotted();
        if (m_visibleNames[dotted.substr(0, dotted.find('.'))] > 0) m_xrefps.push_back(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertActionXRefVisitor(AstNodeStmt* actionp) {
        actionp->foreachAndNext([&](const AstVar* const varp) { m_declVarps.emplace(varp); });
        iterateAndNextConstNull(actionp);
        m_collecting = false;
        showNames(nullptr, 1);
        iterateAndNextConstNull(actionp);
    }
    ~AssertActionXRefVisitor() override = default;
    const std::vector<AstVarXRef*>& xrefps() const { return m_xrefps; }
};

// All executions of an action share its static variables, initialized once, and each has its
// own automatic variables (IEEE 1800-2023 6.21). So the clone refers to the original static
// declarations, and renames its automatic ones, which V3Begin may lift to the same scope.
AstNodeStmt* V3AssertCommon::cloneAction(AstNodeStmt* const actionp, V3UniqueNames& names) {
    // V3LinkDot finds hierarchical references again by name, which fails for a clone in
    // another scope, so these refer to their variable directly
    const AssertActionXRefVisitor xrefVisitor{actionp};
    for (AstVarXRef* const xrefp : xrefVisitor.xrefps()) {
        xrefp->replaceWithKeepDType(
            new AstVarRef{xrefp->fileline(), xrefp->varp(), xrefp->access()});
        VL_DO_DANGLING(xrefp->deleteTree(), xrefp);
    }
    AstNodeStmt* const clonep = actionp->cloneTree(true);
    std::unordered_map<const AstVar*, AstVar*> origVarps;  // Cloned to original static variable
    actionp->foreachAndNext([&](AstVar* const varp) {
        if (varp->lifetime().isStatic()) origVarps.emplace(varp->clonep(), varp);
    });
    std::vector<AstNode*> declps;  // Static declarations of the clone
    clonep->foreachAndNext([&](AstNode* const nodep) {
        if (AstNodeVarRef* const refp = VN_CAST(nodep, NodeVarRef)) {
            const auto it = origVarps.find(refp->varp());
            if (it != origVarps.end()) refp->varp(it->second);
        } else if (AstVar* const varp = VN_CAST(nodep, Var)) {
            if (origVarps.count(varp)) {
                declps.push_back(varp);
            } else {
                varp->name(names.get(varp->name()));
            }
        } else if (VN_IS(nodep, Typedef) || VN_IS(nodep, InitialStaticStmt)) {
            declps.push_back(nodep);
        }
    });
    for (AstNode* const nodep : declps) nodep->unlinkFrBack()->deleteTree();
    return clonep;
}

//######################################################################
// AssertDeFutureVisitor
// If any AstFuture, then move all non-future varrefs to be one cycle behind,
// see IEEE 1800-2023 16.9.4.

class AssertDeFutureVisitor final : public VNVisitor {
    // STATE - across all visitors
    AstNodeModule* const m_modp;  // Module future is underneath
    const AstFuture* m_futurep;  // First AstFuture found
    const unsigned m_pastNum;  // Prefix unique number for this module
    std::map<AstVar*, AstVar*> m_delayedVars;  // Old to delayed variable mapping
    std::map<AstVar*, AstVar*> m_delayedDisableVars;  // Same, in the disable condition
    // STATE - for current visit position (use VL_RESTORER)
    bool m_inFuture = false;  // Inside a future
    bool m_inDisable = false;  // Inside a disable condition
    bool m_inSampled = false;  // Inside a sampled value function
    bool m_unsupported = false;  // Printed unsupported

    // METHODS
    void unsupported(AstNode* nodep) {
        if (m_unsupported) return;
        m_unsupported = true;
        nodep->v3warn(E_UNSUPPORTED,
                      "Unsupported/illegal: Future value function used with expression with "
                          << nodep->prettyOperatorName());
    }
    // Return a new variable that each future clock tick loads with 'valuep'
    AstVar* newDelayedVar(const string& name, AstNodeExpr* valuep) {
        FileLine* const flp = valuep->fileline();
        AstAlways* const alwaysp = new AstAlways{flp, VAlwaysKwd::ALWAYS,
                                                 m_futurep->sentreep()->cloneTree(false), nullptr};
        m_modp->addStmtsp(alwaysp);
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, valuep->dtypep()};
        m_modp->addStmtsp(varp);
        AstVarRef* const writeRefp = new AstVarRef{flp, varp, VAccess::WRITE};
        writeRefp->user1(true);
        alwaysp->addStmtsp(new AstAssignDly{flp, writeRefp, valuep});
        return varp;
    }
    // VISITORS
    void visit(AstPropSpec* nodep) override {
        iterateAndNextNull(nodep->sensesp());
        {
            VL_RESTORER(m_inDisable);
            m_inDisable = true;
            iterateAndNextNull(nodep->disablep());
        }
        iterateAndNextNull(nodep->propp());
        iterateAndNextNull(nodep->matchCountp());
    }
    void visit(AstSampled* nodep) override {
        VL_RESTORER(m_inSampled);
        m_inSampled = true;
        iterateChildren(nodep);
    }
    void visit(AstFuture* nodep) override {
        // A disable condition is not a property or sequence expression, so leave a future value
        // function there for AssertVisitor to reject (IEEE 1800-2023 16.9.4)
        if (m_inDisable) return;
        VL_RESTORER(m_inFuture);
        m_inFuture = true;
        iterateChildren(nodep);
        // Done with the future, this subexpression is current-time
        nodep->replaceWith(nodep->exprp()->unlinkFrBack());
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (nodep->user1SetOnce()) return;
        if (m_inFuture || m_unsupported)
            return;  // Need user1 set above, don't process when Future is removed
        if (nodep->access().isWriteOrRW()) {
            unsupported(nodep);
            return;
        }
        // In the disable condition, other than in a sampled value function, the current value
        // (IEEE 1800-2023 16.12)
        const bool current = m_inDisable && !m_inSampled;
        std::map<AstVar*, AstVar*>& delayedVars = current ? m_delayedDisableVars : m_delayedVars;
        auto it = delayedVars.find(nodep->varp());
        AstVar* outvarp;
        if (it == delayedVars.end()) {
            AstNodeVarRef* const refp = nodep->cloneTree(false);
            refp->user1(true);
            // Sampled, as a derived clock may tick after an update (IEEE 1800-2023 16.9.4)
            AstNodeExpr* valuep = refp;
            if (!current) {
                valuep = new AstSampled{nodep->fileline(), refp, nodep->dtypep(), true};
            }
            outvarp = newDelayedVar((current ? "__VnotfutureDisable" : "__Vnotfuture")
                                        + cvtToStr(m_pastNum) + "_" + nodep->name(),
                                    valuep);
            delayedVars.emplace(nodep->varp(), outvarp);
        } else {
            outvarp = it->second;
        }
        AstVarRef* newp = new AstVarRef{nodep->fileline(), outvarp, VAccess::READ};
        newp->user1(true);
        UINFO(9, "DeFuture " << nodep << "  becomes " << newp);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstPExpr* nodep) override {
        // V3AssertPre lowered this operator to a forked process, which cannot be evaluated one
        // tick late; the rest of the visit then only strips the future value functions
        nodep->v3warn(E_UNSUPPORTED, "Unsupported: future sampled value function in a property"
                                     " with this temporal operator");
        m_unsupported = true;
        iterateChildren(nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override { unsupported(nodep); }
    void visit(AstMethodCall* nodep) override { unsupported(nodep); }
    void visit(AstNode* nodep) override {
        if (!nodep->isPure()) unsupported(nodep);
        iterateChildren(nodep);
    }

public:
    // CONSTRUCTORS
    explicit AssertDeFutureVisitor(AstNode* nodep, AstNodeModule* modp, unsigned pastNum)
        : m_modp{modp}
        , m_pastNum{pastNum} {
        // See if any Future before we process
        if (nodep->forall([&](const AstFuture* futurep) -> bool {
                m_futurep = futurep;
                return false;
            }))
            return;
        // Only concurrent assertions, which have a PropSpec, are lowered (IEEE 1800-2023 16.9.4)
        AstPropSpec* const specp = VN_AS(nodep, PropSpec);
        // UINFOTREE(9, nodep, "", "defuture-in");
        visit(specp);
        // UINFOTREE(9, nodep, "", "defuture-ou");
        // The attempt checked at a tick is the one from the previous tick, so disable the
        // first tick, which has no previous tick and no delayed values
        FileLine* const flp = specp->fileline();
        AstVar* const startedp = newDelayedVar("__VfutureStarted" + cvtToStr(m_pastNum),
                                               new AstConst{flp, AstConst::BitTrue{}});
        AstNodeExpr* disablep = new AstLogNot{flp, new AstVarRef{flp, startedp, VAccess::READ}};
        if (specp->disablep()) {
            disablep = new AstLogOr{flp, specp->disablep()->unlinkFrBack(), disablep};
        }
        specp->disablep(disablep);
    }
    ~AssertDeFutureVisitor() override = default;
};

//######################################################################
// An automatic variable of a block, task or function, whose sampled and past values are its
// current value (IEEE 1800-2023 16.5.1). Not a class property: its implicit automatic lifetime
// is that of its object.

static bool isProceduralAutomatic(const AstVar* varp) {
    return varp->lifetime().isAutomatic() && !varp->isClassMember();
}

//######################################################################
// AssertPastSplitVisitor
// The past value of an automatic variable is its current value (IEEE 1800-2023 16.5.1).
// Split a $past of an expression reading one, so the $past applies to each largest operand
// that reads no automatic variable.

class AssertPastSplitVisitor final : public VNVisitor {
    // TYPES
    struct Operand final {
        AstNodeExpr* nodep;  // The operand
        bool automatic;  // Reads a current value: an automatic variable or a const cast
        bool reads;  // Reads a variable
    };

    // STATE
    const AstPast* const m_pastp;  // The $past being split
    std::vector<Operand> m_operands;  // Operands of the expressions being visited, innermost last
    std::vector<AstPast*> m_newPastps;  // $past created around operands
    // Nested $past and their split expressions, replaced after the iteration, as replacing a node
    // during it visits its replacement again
    std::vector<std::pair<AstPast*, AstNodeExpr*>> m_splitPastps;
    AstNodeExpr* m_splitp = nullptr;  // The split expression, if split

    // METHODS
    // Apply the $past being split to an operand
    void applyPast(AstNodeExpr* nodep) {
        VNRelinker relinker;
        nodep->unlinkFrBack(&relinker);
        AstNodeExpr* const ticksp
            = m_pastp->ticksp() ? m_pastp->ticksp()->cloneTree(false) : nullptr;
        AstPast* const pastp
            = new AstPast{nodep->fileline(), nodep, ticksp, m_pastp->sentreep()->cloneTree(false)};
        pastp->dtypeFrom(nodep);
        relinker.relink(pastp);
        m_newPastps.push_back(pastp);
    }

    // VISITORS
    void visit(AstPast* nodep) override {
        // A nested $past is split first. Every operand it then reads the past of is one of the
        // $past it created, so this $past applies to those.
        const AssertPastSplitVisitor nested{nodep};
        if (AstNodeExpr* const newp = nested.m_splitp) {
            for (AstPast* const pastp : nested.m_newPastps) applyPast(pastp);
            m_splitPastps.emplace_back(nodep, newp);
            m_operands.push_back({newp, true, true});
            return;
        }
        m_operands.push_back({nodep, false, true});
    }
    void visit(AstNodeVarRef* nodep) override {
        m_operands.push_back({nodep, isProceduralAutomatic(nodep->varp()), true});
    }
    // The past value of a const cast is also its current value (IEEE 1800-2023 16.5.1)
    void visit(AstConstCast* nodep) override { m_operands.push_back({nodep, true, true}); }
    void visit(AstNodeExpr* nodep) override {
        const size_t first = m_operands.size();
        iterateChildren(nodep);
        const auto beginIt = m_operands.begin() + first;
        const bool automatic = std::any_of(
            beginIt, m_operands.end(), [](const Operand& operand) { return operand.automatic; });
        const bool reads = std::any_of(beginIt, m_operands.end(),
                                       [](const Operand& operand) { return operand.reads; });
        if (automatic) {
            std::for_each(beginIt, m_operands.end(), [this](const Operand& operand) {
                if (!operand.automatic && operand.reads) applyPast(operand.nodep);
            });
        }
        m_operands.erase(beginIt, m_operands.end());
        m_operands.push_back({nodep, automatic, reads});
    }
    // Operands below another node, such as a function argument, belong to the expression above
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

    void replaceSplit(AstPast* pastp, AstNodeExpr* splitp) {
        pastp->replaceWith(splitp);
        VL_DO_DANGLING(pushDeletep(pastp), pastp);
    }

    // CONSTRUCTORS
    explicit AssertPastSplitVisitor(AstPast* pastp)
        : m_pastp{pastp} {
        iterate(pastp->exprp());
        for (const auto& entry : m_splitPastps) replaceSplit(entry.first, entry.second);
        if (m_operands.front().automatic) m_splitp = pastp->exprp()->unlinkFrBack();
    }

public:
    ~AssertPastSplitVisitor() override = default;
    // Return the expression with the $past applied to its operands, or nullptr if it reads no
    // automatic variable
    static AstNodeExpr* split(AstPast* pastp) { return AssertPastSplitVisitor{pastp}.m_splitp; }
};

//######################################################################
// Default sampled values of checker formal arguments

class AssertCheckerFormals final {
    // A checker formal argument stands for its actual (IEEE 1800-2023 17.3), so its default
    // sampled value is that of the actual of each instance. The instances of a checker share its
    // module, so each other set of defaults gets a copy of the module.
    // STATE
    std::unordered_map<const AstVar*, AstConst*> m_defaults;  // Constant default of a formal
    size_t m_statCopies = 0;  // Statistic tracking
    // Copies of a checker for other defaults of its formals, beyond which they are unsupported
    static constexpr size_t MAX_COPIES = 16;

    // METHODS
    static AstNodeExpr* initialValuep(const AstVar* varp);
    static bool replaceByConstant(AstNodeExpr* nodep, AstNodeExpr* valuep);
    static void replaceElementByInitializer(AstArraySel* selp);
    static bool replaceByInitializer(AstNodeVarRef* refp);
    static bool isChecker(const AstNodeModule* modp) {
        const AstModule* const checkerp = VN_CAST(modp, Module);
        return checkerp && checkerp->isChecker();
    }
    static void deleteDefaults(const std::vector<AstConst*>& defaults) {
        for (AstConst* const constp : defaults)
            if (constp) constp->deleteTree();
    }
    AstConst* newActualDefault(const AstPin* pinp, const AstVar* portp) const;
    AstConst* newInstanceDefault(const AstCell* cellp, const AstVar* formalp) const;
    AstNodeModule* newCopy(AstNodeModule* modp, size_t group, const std::vector<AstCell*>& cellps);
    std::vector<AstCell*> specializeChecker(AstNodeModule* modp,
                                            const std::vector<AstCell*>& cellps);

public:
    // CONSTRUCTORS
    AssertCheckerFormals() = default;
    ~AssertCheckerFormals() {
        for (const auto& itr : m_defaults) itr.second->deleteTree();
    }
    // Give each set of the defaults of the formals of a checker read by $past its own copy of
    // the checker module, and record those defaults
    void specialize(AstNetlist* netlistp);
    // The default sampled value of a checker formal read by $past, if constant, else nullptr
    AstConst* defaultOf(const AstVar* varp) const {
        const auto it = m_defaults.find(varp);
        return it == m_defaults.end() ? nullptr : it->second;
    }
};

// Prepare one default sampled expression.
class DefaultSampledValueVisitor final : public VNVisitor {
    // STATE
    const AssertCheckerFormals* const m_formalsp;  // Defaults of checker formals

    // METHODS
    static AstNodeExpr* newTypeDefault(FileLine* flp, AstNodeDType* dtypep) {
        AstNodeDType* const skipDtp = dtypep->skipRefp();
        if (AstUnpackArrayDType* const arrayp = VN_CAST(skipDtp, UnpackArrayDType)) {
            return new AstConsArray{flp, arrayp, newTypeDefault(flp, arrayp->subDTypep())};
        }
        AstStructDType* const structp = VN_CAST(skipDtp, StructDType);
        if (structp && !structp->packed()) {
            AstConsStruct* const consp = new AstConsStruct{flp, structp};
            for (AstMemberDType* memberp = structp->membersp(); memberp;
                 memberp = VN_AS(memberp->nextp(), MemberDType)) {
                consp->addItemsp(new AstConsStructItem{flp, memberp,
                                                       newTypeDefault(flp, memberp->subDTypep())});
            }
            return consp;
        }
        AstConst* const constp = new AstConst{flp, AstConst::DTyped{}, dtypep};
        if (dtypep->isFourstate()) constp->num().setAllBitsX();
        constp->dtypep(dtypep);
        return constp;
    }
    // Whether a constant can have the default value of 'dtypep': not if it is, or has elements
    // or members of, a dynamically sized type or a class
    static bool hasConstant(const AstNodeDType* dtypep) {
        dtypep = dtypep->skipRefp();
        if (dtypep->isDynamicallySized() || VN_IS(dtypep, ClassRefDType)) return false;
        if (const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType)) {
            return hasConstant(arrayp->subDTypep());
        }
        const AstStructDType* const structp = VN_CAST(dtypep, StructDType);
        if (!structp) return true;
        for (const AstMemberDType* memberp = structp->membersp(); memberp;
             memberp = VN_AS(memberp->nextp(), MemberDType)) {
            if (!hasConstant(memberp->subDTypep())) return false;
        }
        return true;
    }
    static bool hasDefaultValue(const AstVar* varp) {
        return !varp->isParam()
               && (varp->isNet() || !varp->lifetime().isStatic() || !varp->hasUserInit());
    }
    static AstNodeExpr* selectFromp(AstNode* nodep) {
        if (AstNodeSel* const selp = VN_CAST(nodep, NodeSel)) return selp->fromp();
        if (AstSel* const selp = VN_CAST(nodep, Sel)) return selp->fromp();
        if (AstStructSel* const selp = VN_CAST(nodep, StructSel)) return selp->fromp();
        return nullptr;
    }
    void visitSelect(AstNodeExpr* nodep) {
        // A selection from a variable with its default value, or with an unknown index, has
        // the default value of the selected type (IEEE 1800-2023 7.4.6, 11.5.1). Replace the
        // whole selection: the variable may be unpacked, and a constant unknown index would
        // be rejected later.
        AstNodeExpr* basep = selectFromp(nodep);
        while (AstNodeExpr* const fromp = selectFromp(basep)) basep = fromp;
        const AstNodeVarRef* const refp = VN_CAST(basep, NodeVarRef);
        bool isDefault
            = refp && hasDefaultValue(refp->varp()) && !m_formalsp->defaultOf(refp->varp());
        // As for a whole variable, a selection with no constant keeps reading the variable
        if (isDefault && !hasConstant(nodep->dtypep())) return;
        if (!isDefault) {
            AstNodeExpr* selp = nodep;
            for (; selectFromp(selp); selp = selectFromp(selp)) {
                // The index of an AstNodeSel or AstSel; an AstStructSel has none
                AstNodeBiop* const biopp = VN_CAST(selp, NodeBiop);
                if (!biopp) continue;
                iterate(biopp->rhsp());
                const AstConst* const constp
                    = VN_CAST(V3Const::constifyEdit(biopp->rhsp()), Const);
                if (constp && constp->num().isAnyXZ()) isDefault = true;
            }
            iterate(selp);
        }
        if (isDefault) {
            nodep->replaceWith(newTypeDefault(nodep->fileline(), nodep->dtypep()));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
    }

    // VISITORS
    void visit(AstCMethodHard* nodep) override {
        if (nodep->method() == VCMethod::EVENT_IS_TRIGGERED) {
            nodep->replaceWith(new AstConst{nodep->fileline(), AstConst::BitFalse{}});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else {
            iterateChildren(nodep);
        }
    }
    void visit(AstNodeSel* nodep) override { visitSelect(nodep); }
    void visit(AstSel* nodep) override { visitSelect(nodep); }
    void visit(AstStructSel* nodep) override { visitSelect(nodep); }
    void visit(AstNodeVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        if (AstConst* const constp = m_formalsp->defaultOf(varp)) {
            AstConst* const newp = constp->cloneTree(false);
            newp->dtypeFrom(nodep);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (!hasDefaultValue(varp)) {
            // The value of its declaration initializer, not of a later write during
            // initialization (IEEE 1800-2023 16.5.1). V3LinkParse placed that initialization
            // just after a module variable. A connected input does not have the value of its
            // default. With X or Z, the value assigned depends on the X options. Otherwise the
            // variable is read when used, so may have a later value.
            if (varp->isParam() || varp->isNonOutput()) return;
            AstInitialStatic* const initp = VN_CAST(varp->nextp(), InitialStatic);
            if (!initp) return;
            AstAssign* const assignp = VN_AS(initp->stmtsp(), Assign);
            AstConst* const constp = VN_CAST(assignp->rhsp(), Const);
            if (!constp || constp->num().isAnyXZ()) return;
            UASSERT_OBJ(VN_AS(assignp->lhsp(), VarRef)->varp() == varp, nodep,
                        "Initialization of another variable");
            AstConst* const newp = constp->cloneTree(false);
            newp->dtypeFrom(nodep);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        // No constant may have its value, but before any process runs the variable has the
        // default value of its type
        if (!hasConstant(nodep->dtypep())) return;
        nodep->replaceWith(newTypeDefault(nodep->fileline(), nodep->dtypep()));
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    // The default sampled value of a past value is that of its expression, its value before
    // enough clock ticks (IEEE 1800-2023 16.9.3)
    void visit(AstPast* nodep) override {
        AstNodeExpr* const exprp = nodep->exprp()->unlinkFrBack();
        nodep->replaceWith(exprp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        iterate(exprp);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    DefaultSampledValueVisitor(AstNode* nodep, const AssertCheckerFormals* formalsp)
        : m_formalsp{formalsp} {
        iterate(nodep);
    }
};

AstNodeExpr* AssertCheckerFormals::initialValuep(const AstVar* varp) {
    // A parameter's value, or the declaration initializer that V3LinkParse placed just after
    // the variable
    if (varp->isParam()) return VN_CAST(varp->valuep(), NodeExpr);
    const AstInitialStatic* const initp = VN_CAST(varp->nextp(), InitialStatic);
    const AstAssign* const assignp = initp ? VN_CAST(initp->stmtsp(), Assign) : nullptr;
    return assignp ? assignp->rhsp() : nullptr;
}

bool AssertCheckerFormals::replaceByConstant(AstNodeExpr* nodep, AstNodeExpr* valuep) {
    AstConst* const constp = VN_CAST(valuep, Const);
    if (constp) {
        AstConst* const newp = constp->cloneTree(false);
        newp->dtypeFrom(nodep);
        nodep->replaceWith(newp);
        nodep->deleteTree();
    }
    return constp != nullptr;
}

void AssertCheckerFormals::replaceElementByInitializer(AstArraySel* selp) {
    // An element of an unpacked array variable with a constant index
    const AstNodeVarRef* const refp = VN_CAST(selp->fromp(), NodeVarRef);
    const AstConsArray* const consp
        = refp ? VN_CAST(initialValuep(refp->varp()), ConsArray) : nullptr;
    const AstConst* const indexp = VN_CAST(selp->bitp(), Const);
    if (consp && indexp) replaceByConstant(selp, consp->valuep(indexp->toUInt()));
}

bool AssertCheckerFormals::replaceByInitializer(AstNodeVarRef* refp) {
    return replaceByConstant(refp, initialValuep(refp->varp()));
}

AstConst* AssertCheckerFormals::newActualDefault(const AstPin* pinp, const AstVar* portp) const {
    // The default sampled value of the actual, in its own module
    AstNodeExpr* const actualp = VN_CAST(pinp->exprp(), NodeExpr);
    if (!actualp) return nullptr;
    AstNodeExpr* const exprp = actualp->cloneTreePure(false);
    AstSampled* const holderp = new AstSampled{exprp->fileline(), exprp, exprp->dtypep()};
    { DefaultSampledValueVisitor{holderp->exprp(), this}; }
    // A variable, or an element of one, keeps a constant initial value (16.5.1). Anything else
    // is not known to be constant.
    std::vector<AstArraySel*> selps;
    holderp->exprp()->foreach([&](AstArraySel* selp) { selps.push_back(selp); });
    for (AstArraySel* const selp : selps) replaceElementByInitializer(selp);
    std::vector<AstNodeVarRef*> refps;
    holderp->exprp()->foreach([&](AstNodeVarRef* refp) { refps.push_back(refp); });
    const bool constant = std::all_of(refps.begin(), refps.end(), replaceByInitializer);
    if (constant) V3Const::constifyEdit(holderp->exprp());
    AstConst* const constp = constant ? VN_CAST(holderp->exprp(), Const) : nullptr;
    // Only an actual of the width of the formal, which needs no conversion
    if (constp && constp->width() == portp->width()) {
        constp->unlinkFrBack();
        VL_DO_DANGLING(holderp->deleteTree(), holderp);
        return constp;
    }
    VL_DO_DANGLING(holderp->deleteTree(), holderp);
    return nullptr;
}

AstConst* AssertCheckerFormals::newInstanceDefault(const AstCell* cellp,
                                                   const AstVar* formalp) const {
    // An unconnected formal has its own default
    const AstPin* pinp = cellp->pinsp();
    while (pinp && pinp->modVarp() != formalp) pinp = VN_AS(pinp->nextp(), Pin);
    AstConst* const constp = pinp ? newActualDefault(pinp, formalp) : nullptr;
    if (pinp && !constp) {
        cellp->v3warn(EC_INFO, "Default sampled value of checker formal "
                                   << formalp->prettyNameQ() << " of instance "
                                   << cellp->prettyNameQ()
                                   << " is that of its type, as its actual has no constant one"
                                      " (IEEE 1800-2023 16.5.1).");
    }
    return constp;
}

AstNodeModule* AssertCheckerFormals::newCopy(AstNodeModule* modp, size_t group,
                                             const std::vector<AstCell*>& cellps) {
    // A copy of the checker module for these instances, which connect to its ports. The nodes
    // of the module point to their copies until the next clone.
    AstNodeModule* const copyp = modp->cloneTree(false);
    copyp->name(modp->name() + "__Vdef" + cvtToStr(group));
    modp->addNextHere(copyp);  // At the same level, to keep V3LinkLevel's order
    ++m_statCopies;
    for (AstCell* const cellp : cellps) {
        cellp->modp(copyp);
        for (AstPin* pinp = cellp->pinsp(); pinp; pinp = VN_AS(pinp->nextp(), Pin))
            if (pinp->modVarp()) pinp->modVarp(pinp->modVarp()->clonep());
    }
    return copyp;
}

std::vector<AstCell*>
AssertCheckerFormals::specializeChecker(AstNodeModule* modp, const std::vector<AstCell*>& cellps) {
    // Return the cells in the copies made
    std::vector<AstCell*> newCellps;
    // The formals read by $past, or passed to the checkers instantiated here, in the order of
    // their first read
    std::vector<const AstVar*> formalps;
    std::unordered_set<const AstVar*> seen;
    const auto addFormals = [&](const AstNode* nodep) {
        nodep->foreach([&](const AstNodeVarRef* refp) {
            const AstVar* const varp = refp->varp();
            if (varp->isIO() && varp->isNonOutput() && seen.emplace(varp).second) {
                formalps.push_back(varp);
            }
        });
    };
    modp->foreach([&](const AstPast* pastp) { addFormals(pastp->exprp()); });
    modp->foreach([&](const AstCell* cellp) {
        if (isChecker(cellp->modp())) addFormals(cellp);
    });
    // Group the instances by the defaults of those formals, in the order of first instance
    std::vector<std::vector<AstConst*>> groupDefaults;
    std::vector<std::vector<AstCell*>> groupCellps;
    std::unordered_map<std::string, size_t> groups;  // Group of each set of defaults
    for (AstCell* const cellp : cellps) {
        std::vector<AstConst*> defaults;
        std::string key;
        for (const AstVar* const formalp : formalps) {
            AstConst* const constp = newInstanceDefault(cellp, formalp);
            defaults.push_back(constp);
            key += (constp ? constp->num().ascii() : "-") + ",";
        }
        const auto pair = groups.emplace(key, groupCellps.size());
        if (pair.second) {
            groupDefaults.push_back(defaults);
            groupCellps.emplace_back();
        } else {
            deleteDefaults(defaults);
        }
        groupCellps[pair.first->second].push_back(cellp);
    }
    // The first group keeps the checker module, each other one gets a copy
    for (size_t group = 0; group < groupCellps.size(); ++group) {
        const std::vector<AstConst*>& defaults = groupDefaults[group];
        if (group > MAX_COPIES) {
            // Reported at the first instance with these defaults
            groupCellps[group].front()->v3warn(
                E_UNSUPPORTED, "Unsupported: instance of checker "
                                   << modp->prettyNameQ() << " with more than " << MAX_COPIES
                                   << " other sets of default sampled values of its formals,"
                                      " such as "
                                   << formalps.front()->prettyNameQ() << ".");
            deleteDefaults(defaults);
            continue;
        }
        AstNodeModule* const ownerp = group ? newCopy(modp, group, groupCellps[group]) : modp;
        if (group) ownerp->foreach([&](AstCell* cellp) { newCellps.push_back(cellp); });
        for (size_t i = 0; i < formalps.size(); ++i) {
            const AstVar* const varp = group ? formalps[i]->clonep() : formalps[i];
            if (defaults[i]) m_defaults.emplace(varp, defaults[i]);
        }
    }
    return newCellps;
}

void AssertCheckerFormals::specialize(AstNetlist* netlistp) {
    // V3LinkLevel sorted the modules by level, so a checker comes after the ones instantiating it,
    // whose copies are then already made. Copies have no instances recorded, so need no copies.
    std::unordered_map<const AstNodeModule*, std::vector<AstCell*>> cellps;
    const auto addCell = [&](AstCell* cellp) {
        if (isChecker(cellp->modp())) cellps[cellp->modp()].push_back(cellp);
    };
    netlistp->foreach(addCell);
    for (AstNodeModule* const modp : netlistp->modulespList()) {
        const auto it = cellps.find(modp);
        if (it == cellps.end() || modp->hierBlock()) continue;
        for (AstCell* const cellp : specializeChecker(modp, it->second)) addCell(cellp);
    }
    V3Stats::addStat("Assertions, checker copies for formal defaults", m_statCopies);
}

//######################################################################
// AssertTaskRunnersVisitor

// The tasks with a procedural concurrent assertion, the procedures and tasks calling them,
// directly or through other tasks, and the tasks those call: the code whose process may reach
// such an assertion, so has its flush points flush the pending instances of the process
// (IEEE 1800-2023 16.14.6.2)
class AssertTaskRunnersVisitor final : public VNVisitorConst {
    // STATE
    const AstNode* m_callerp = nullptr;  // Current procedure or task
    // Callers of each task, and tasks called by each procedure or task
    std::unordered_map<const AstNodeFTask*, std::vector<const AstNode*>> m_callerps;
    std::unordered_map<const AstNode*, std::vector<const AstNodeFTask*>> m_calleeps;
    std::vector<const AstNode*> m_workps;  // Runners yet to propagate to their callers
    std::unordered_set<const AstNode*>& m_runnerpsr;  // Result

    // VISITORS
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_callerp);
        m_callerp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_callerp);
        m_callerp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (m_callerp && nodep->taskp()) {
            m_callerps[nodep->taskp()].push_back(m_callerp);
            m_calleeps[m_callerp].push_back(nodep->taskp());
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeCoverOrAssert* nodep) override {
        if (!nodep->immediate() && VN_IS(m_callerp, NodeFTask)) m_workps.push_back(m_callerp);
        iterateChildrenConst(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // Linear in the netlist: each call is followed once
    AssertTaskRunnersVisitor(AstNetlist* nodep, std::unordered_set<const AstNode*>& runnerpsr)
        : m_runnerpsr{runnerpsr} {
        iterateConst(nodep);
        while (!m_workps.empty()) {
            const AstNode* const runnerp = m_workps.back();
            m_workps.pop_back();
            if (!m_runnerpsr.emplace(runnerp).second) continue;
            const AstNodeFTask* const taskp = VN_CAST(runnerp, NodeFTask);
            if (!taskp) continue;
            const auto it = m_callerps.find(taskp);
            if (it == m_callerps.end()) continue;
            for (const AstNode* const callerp : it->second) m_workps.push_back(callerp);
        }
        // A task such code calls runs in its process too, also when it calls none of those
        std::vector<const AstNode*> calleeWorkps{m_runnerpsr.begin(), m_runnerpsr.end()};
        while (!calleeWorkps.empty()) {
            const AstNode* const callerp = calleeWorkps.back();
            calleeWorkps.pop_back();
            const auto it = m_calleeps.find(callerp);
            if (it == m_calleeps.end()) continue;
            for (const AstNodeFTask* const calleep : it->second) {
                if (m_runnerpsr.emplace(calleep).second) calleeWorkps.push_back(calleep);
            }
        }
    }
};

//######################################################################
// AssertVisitor

class AssertVisitor final : public VNVisitor {
    // CONSTANTS
    static constexpr uint8_t ALL_ASSERT_TYPES
        = std::numeric_limits<std::underlying_type<VAssertType::en>::type>::max();

    // NODE STATE/TYPES
    // Cleared on netlist
    //  AstNode::user1()         -> bool.  True if processed
    //  AstAlways::user2p()      -> std::vector<AstVar*>. Delayed variables via 'm_delayed'
    //  AstNodeVarRef::user2()   -> bool.  True if shouldn't be sampled
    //  AstIf::user2()           -> bool.  True for assertOn() checks inserted in this pass
    //  AstNodeStmt::user3()     -> bool.  True for a wait of a PExpr attempt (abortWhenKilled)
    const VNUser1InUse m_user1InUse;
    const VNUser2InUse m_user2InUse;
    const VNUser3InUse m_user3InUse;
    VNUser2Allocator<AstAlways, std::vector<AstVar*>> m_delayed;

    // STATE
    AstNodeModule* m_modp = nullptr;  // Last module
    AssertCheckerFormals m_checkerFormals;  // Defaults of checker formals
    const AstNode* m_beginp = nullptr;  // Last AstBegin/AstGenBlock
    std::string m_genScope;  // Scope names of the named AstGenBlocks around, as V3Begin adds them
    unsigned m_modMonitorNum = 0;  // Module $monitor numbering
    AstVar* m_monitorNumVarp = nullptr;  // $monitor number variable
    AstVar* m_monitorNextVarp = nullptr;  // Last $monitor number given to an instance
    AstVar* m_monitorOffVarp = nullptr;  // $monitoroff variable
    AstVar* m_monitorPendingVarp = nullptr;  // $monitor display pending variable
    unsigned m_modPastNum = 0;  // Module past numbering
    unsigned m_modStrobeNum = 0;  // Module $strobe numbering
    AstNodeStmt* m_obsFlushp = nullptr;  // Clears the current process's pending deferred calls
    AstVar* m_obsDoneVarp = nullptr;  // Set when the outermost scope ends without a disable
    std::vector<AstNode*> m_obsWaitsp;  // Current process waits, flushed if it has pending calls
    bool m_inSpawnedFork = false;  // Under a fork...join_any or fork...join_none
    bool m_inForkBranch = false;  // In a fork branch, a process other than the procedure's
    bool m_inConcurrentAction = false;  // In an action of a concurrent assertion
    bool m_inlineAction = false;  // An action of the current assertion stays inline
    AstVar* m_matureEpochp = nullptr;  // Flushes of the current procedure's pending instances
    // Procedures and tasks whose process may reach a procedural concurrent assertion in a task
    std::unordered_set<const AstNode*> m_taskRunnerps;
    bool m_taskRunner = false;  // The current process may reach one
    bool m_taskMature = false;  // The current assertion, in a task, matures
    AstVar* m_taskPendingp = nullptr;  // Pending instances of tasks' assertions, by process
    AstVar* m_taskEpochp = nullptr;  // Flushes of processes with such pending instances
    AstVar* m_taskRootp = nullptr;  // Process running each disable wrapper's, see newTaskKeyp
    std::unordered_set<const AstForkItem*> m_keyedWrapperps;  // Done by keyDisableWrapper
    std::unordered_set<const AstVar*> m_pastVarps;  // Registers of sampled value functions
    AstVar* m_obsEventp = nullptr;  // Current module event to run deferred calls
    AstAlwaysReactive* m_obsReactivep = nullptr;  // Current module block running deferred calls
    AstAlwaysPostponed* m_finalPostponedp = nullptr;  // Current module block running final calls
    AstVar* m_actionEventp = nullptr;  // Current process's event to run queued PExpr actions
    AstAlwaysReactive* m_actionReactivep = nullptr;  // Block running them, beside the process
    std::vector<const AstBegin*> m_namedBeginps;  // Named blocks in the current process
    std::vector<AstVar*> m_disableCountps;  // Disable counts of the blocks around (V3LinkJump)
    AstNode* m_containerp = nullptr;  // Current module or generate block
    bool m_procSuspends = false;  // Current procedure may suspend
    V3AssertReactive m_reactive;  // Makes concurrent assertion actions run in Reactive
    bool m_inPExprFinal = false;  // In the end-of-simulation check of a PExpr
    AstBegin* m_pexprBodyp = nullptr;  // Body of the current PExpr, its attempt's process
    AstVar* m_strongPassOnp = nullptr;  // Strong property's active attempts started PassOn
    AstVar* m_strongFailOnp = nullptr;  // Strong property's active attempts started FailOn
    std::unordered_map<std::string, AstVar*> m_pexprStartVarps;  // Controls read at its start
    AstNodeProcedure* m_procedurep = nullptr;  // Current procedure
    // What the current always_comb reads outside the action blocks of immediate assertions
    std::unordered_set<const AstVar*> m_combReads;
    AstAlways* m_assertCoverp = nullptr;  // Process of the current concurrent assertion
    VDouble0 m_statCover;  // Statistic tracking
    VDouble0 m_statAsNotImm;  // Statistic tracking
    VDouble0 m_statAsImm;  // Statistic tracking
    VDouble0 m_statAsFull;  // Statistic tracking
    VDouble0 m_statPastVars;  // Statistic tracking
    VDouble0 m_statAssertOnCombined;  // Statistic tracking
    VDouble0 m_statAssertOnHoisted;  // Statistic tracking
    VDouble0 m_statViolationsDeferred;  // Statistic tracking
    VDouble0 m_statTaskMature;  // Statistic tracking
    bool m_inSampled = false;  // True inside a sampled expression
    bool m_inPast = false;  // True below a $past split for its automatic variables
    bool m_inRestrict = false;  // True inside restrict assertion
    AstNodeStmt* m_passsp = nullptr;  // Current pass statement
    AstNodeStmt* m_failsp = nullptr;  // Current fail statement
    // Pristine action clones for clauses that share the current assertion's action.
    std::unordered_map<const AstPExprClause*, AstNodeStmt*> m_clauseActionsp;
    AstNodeCoverOrAssert* m_assertp = nullptr;  // Current assertion
    int m_controlTempNum = 0;  // Assertion-control operand temporaries within a module
    using AssertCtlDepths = std::array<uint32_t, std::numeric_limits<uint32_t>::digits>;
    // Maximum statically possible depth by type/directive bit for each shared list.
    std::unordered_map<AstAssertCtlTargetSet*, AssertCtlDepths> m_sharedControlDepths;
    VDouble0 m_statLiftedCaseExprs;  // Count of purified case expressions
    VDouble0 m_statLiftedUniqueConds;  // Count of conditions and case items evaluated once
    AstNodeFTask* m_ftaskp = nullptr;  // Current function/task
    V3UniqueNames m_caseTempNames{"__VCase"};  // Unique names for case temporaries
    V3UniqueNames m_matchCountNames{"__VnfaRemainingMatchCount"};  // Match replay counter names
    V3UniqueNames m_obsNames{"__VassertObs"};  // Observed deferred assertion temp names
    V3UniqueNames m_actionNames{"__VassertAction"};  // Queued and cloned action temporaries
    // Key equality for the delayed value maps. AstNode::sameTree is not enough, as
    // AstVar::sameNode compares only names, and before V3Begin distinct variables in
    // different scopes (e.g. generate blocks) can have the same name.
    struct SameTreeAndVars final {
        static std::vector<const AstVar*> varps(const AstNode& node) {
            std::vector<const AstVar*> varps;
            node.foreach([&](const AstVarRef* refp) { varps.push_back(refp->varp()); });
            return varps;
        }
        template <typename T_Node>
        bool operator()(VNRef<T_Node> ar, VNRef<T_Node> br) const {
            return ar.get().sameTree(&br.get()) && varps(ar.get()) == varps(br.get());
        }
    };
    template <typename T_Node, typename T_Value>
    using SameTreeAndVarsMap
        = std::unordered_map<VNRef<T_Node>, T_Value, std::hash<VNRef<T_Node>>, SameTreeAndVars>;
    // Maps from (expression, senTree) to the AstAlways that computes its delayed values.
    SameTreeAndVarsMap<AstNodeExpr, SameTreeAndVarsMap<AstSenTree, AstAlways*>>
        m_modExpr2Sen2DelayedAlwaysp;
    // Source sampled-value history is initialized, unlike internal property-lowering history.
    SameTreeAndVarsMap<AstNodeExpr, SameTreeAndVarsMap<AstSenTree, AstAlways*>>
        m_modExpr2Sen2DefaultDelayedAlwaysp;
    // Map from delayed-value AstAlways to its last-sampling-tick time variable
    std::unordered_map<const AstAlways*, AstVar*> m_delayedAlways2TickTimep;

    // METHODS
    static VAssertCtlQuery assertPassOnQuery(bool vacuous) {
        return vacuous ? VAssertCtlQuery::PASS_VACUOUS : VAssertCtlQuery::PASS_NONVACUOUS;
    }
    static AstNodeExpr* assertOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                     VAssertDirectiveType directiveType) {
        // cppcheck-suppress missingReturn
        switch (directiveType) {
        case VAssertDirectiveType::INTRINSIC: return new AstConst{fl, AstConst::BitTrue{}};
        case VAssertDirectiveType::VIOLATION_CASE:
        case VAssertDirectiveType::VIOLATION_IF: {
            const bool enabled = directiveType == VAssertDirectiveType::VIOLATION_CASE
                                     ? v3Global.opt.assertCase()
                                     : v3Global.opt.assertOn();
            // If assertions are off, have constant propagation rip them out later
            // This allows syntax errors and such to be detected normally.
            if (!enabled) return new AstConst{fl, AstConst::BitFalse{}};
            // Unique/unique0/priority checks are controlled by their assertion type
            // (IEEE 1800-2023 Table 20-6), as assert directives; full_case/parallel_case
            // checks have no type and follow the global state.
            if (type != VAssertType::INTERNAL) {
                return V3AssertCommon::newAssertCtlGetp(fl, VAssertCtlQuery::ON, type,
                                                        VAssertDirectiveType::ASSERT, statep);
            }
            return new AstCExpr{fl, AstCExpr::Pure{}, "vlSymsp->_vm_contextp__->assertOn()", 1};
        }
        case VAssertDirectiveType::ASSERT:
        case VAssertDirectiveType::COVER:
        case VAssertDirectiveType::ASSUME: {
            if (v3Global.opt.assertOn()) {
                return V3AssertCommon::newAssertCtlGetp(fl, VAssertCtlQuery::ON, type,
                                                        directiveType, statep);
            }
            return new AstConst{fl, AstConst::BitFalse{}};
        }
        case VAssertDirectiveType::INTERNAL:
        case VAssertDirectiveType::RESTRICT: {
            if (v3Global.opt.assertOn()) {
                return new AstCExpr{fl, AstCExpr::Pure{}, "vlSymsp->_vm_contextp__->assertOn()",
                                    1};
            }
            return new AstConst{fl, AstConst::BitFalse{}};
        }
        }
        VL_UNREACHABLE;
    }

    static bool isControlled(VAssertDirectiveType directiveType) {
        return (static_cast<int>(directiveType)
                & (static_cast<int>(VAssertDirectiveType::ASSERT)
                   | static_cast<int>(VAssertDirectiveType::COVER)
                   | static_cast<int>(VAssertDirectiveType::ASSUME)));
    }
    static AstNodeExpr* assertPassOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                         VAssertDirectiveType directiveType, bool vacuous) {
        if (!isControlled(directiveType)) return new AstConst{fl, AstConst::BitTrue{}};
        if (!v3Global.opt.assertOn()) return new AstConst{fl, AstConst::BitFalse{}};
        return V3AssertCommon::newAssertCtlGetp(fl, assertPassOnQuery(vacuous), type,
                                                directiveType, statep);
    }
    static AstNodeExpr* assertFailOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                         VAssertDirectiveType directiveType) {
        if (!isControlled(directiveType)) return new AstConst{fl, AstConst::BitTrue{}};
        if (!v3Global.opt.assertOn()) return new AstConst{fl, AstConst::BitFalse{}};
        return V3AssertCommon::newAssertCtlGetp(fl, VAssertCtlQuery::FAIL_ON, type, directiveType,
                                                statep);
    }
    string assertDisplayMessage(const AstNode* nodep, const string& prefix, const string& message,
                                VDisplayType severity) {
        if (severity == VDisplayType::DT_ERROR || severity == VDisplayType::DT_FATAL) {
            return ("[%0t] "s + prefix + ": " + nodep->fileline()->filebasename() + ":"
                    + cvtToStr(nodep->fileline()->lineno()) + ": Assertion failed in %m"
                    + ((message != "") ? ": " : "") + message + "\n");
        }
        return ("[%0t] "s + prefix + ": " + nodep->fileline()->filebasename() + ":"
                + cvtToStr(nodep->fileline()->lineno()) + ": %m" + ((message != "") ? ": " : "")
                + message + "\n");
    }
    // Report a display in the Postponed region of what its static process cannot read: a
    // non-static class property, method or 'this', or an argument or automatic variable of a
    // task or function, which ends before the display
    void checkPostponedDisplay(const AstDisplay* nodep) const {
        nodep->fmtp()->foreach([&](const AstNodeExpr* exprp) {
            if (VN_IS(exprp, ThisRef)) {
                exprp->v3warn(E_UNSUPPORTED,
                              "Unsupported: " << nodep->verilogKwd() << " of 'this'.");
                return;
            }
            if (const AstFuncRef* const callp = VN_CAST(exprp, FuncRef)) {
                // A call of a non-static method without an object is of 'this'
                if (callp->taskp()->classMethod() && !callp->taskp()->isStatic()) {
                    callp->v3warn(E_UNSUPPORTED,
                                  "Unsupported: " << nodep->verilogKwd()
                                                  << " of non-static class method call "
                                                  << callp->prettyNameQ() << ".");
                }
                return;
            }
            const AstNodeVarRef* const refp = VN_CAST(exprp, NodeVarRef);
            if (!refp) return;
            const AstVar* const varp = refp->varp();
            if (varp->isClassMember() && !varp->lifetime().isStatic()) {
                refp->v3warn(E_UNSUPPORTED, "Unsupported: " << nodep->verilogKwd()
                                                            << " of non-static class property "
                                                            << refp->prettyNameQ() << ".");
            } else if (varp->isFuncLocal()) {
                UASSERT_OBJ(m_ftaskp, refp, "Task or function variable outside of it");
                // An argument has the lifetime of its task or function
                const bool automatic = varp->isIO() ? m_ftaskp->lifetime().isAutomatic()
                                                    : varp->lifetime().isAutomatic();
                if (automatic && nodep->displayType() == VDisplayType::DT_MONITOR) {
                    refp->v3error("Automatic variable "
                                  << refp->prettyNameQ()
                                  << " traced by $monitor, but it is deallocated when its task"
                                     " or function returns (IEEE 1800-2023 13.3.2).");
                } else if (automatic || varp->isIO()) {
                    refp->v3warn(E_UNSUPPORTED,
                                 "Unsupported: " << nodep->verilogKwd()
                                                 << " of argument or automatic variable "
                                                 << refp->prettyNameQ()
                                                 << " of a task or function.");
                }
            }
        });
    }
    void replaceDisplay(AstDisplay* nodep, const string& prefix) {
        nodep->fmtp()->text(
            assertDisplayMessage(nodep, prefix, nodep->fmtp()->text(), nodep->displayType()));
        nodep->displayType(VDisplayType::DT_WRITE);
        // cppcheck-suppress nullPointer
        AstNodeExpr* const timenewp = new AstTime{nodep->fileline(), m_modp->timeunit()};
        nodep->fmtp()->prependExprsp(timenewp);
        if (!nodep->fmtp()->scopeNamep() && nodep->fmtp()->formatScopeTracking()) {
            nodep->fmtp()->scopeNamep(new AstScopeName{nodep->fileline(), true});
        }
    }
    AstSampled* newSampledExpr(AstNodeExpr* nodep) {
        return new AstSampled{nodep->fileline(), nodep, nodep->dtypep(), true};
    }
    AstVarRef* newMonitorNumVarRefp(const AstNode* nodep, VAccess access) {
        if (!m_monitorNumVarp) {
            m_monitorNumVarp = new AstVar{nodep->fileline(), VVarType::MODULETEMP, "__VmonitorNum",
                                          nodep->findUInt32DType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorNumVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{nodep->fileline(), m_monitorNumVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstVarRef* newMonitorNextVarRefp(const AstNode* nodep, VAccess access) {
        if (!m_monitorNextVarp) {
            m_monitorNextVarp = new AstVar{nodep->fileline(), VVarType::MODULETEMP,
                                           "__VmonitorNext", nodep->findUInt32DType()};
            m_monitorNextVarp->setIgnoreSchedWrite();
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorNextVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{nodep->fileline(), m_monitorNextVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstVarRef* newMonitorOffVarRefp(const AstNode* nodep, VAccess access) {
        if (!m_monitorOffVarp) {
            m_monitorOffVarp = new AstVar{nodep->fileline(), VVarType::MODULETEMP, "__VmonitorOff",
                                          nodep->findBitDType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorOffVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{nodep->fileline(), m_monitorOffVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstVarRef* newMonitorPendingVarRefp(const AstNode* nodep, VAccess access) {
        FileLine* const flp = nodep->fileline();
        if (!m_monitorPendingVarp) {
            m_monitorPendingVarp = new AstVar{flp, VVarType::MODULETEMP, "__VmonitorPending",
                                              nodep->findBitDType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorPendingVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{flp, m_monitorPendingVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstAssign* newMonitorPendingSetp(const AstNode* nodep) {
        FileLine* const flp = nodep->fileline();
        return new AstAssign{flp, newMonitorPendingVarRefp(nodep, VAccess::WRITE),
                             new AstConst{flp, AstConst::BitTrue{}}};
    }
    // A module temporary is static; one copied when a process forks must be made automatic by
    // its caller, as the "Const" temporaries are
    static AstVar* newModuleTemp(FileLine* flp, const string& name, AstNodeDType* dtypep,
                                 AstNodeModule* ownerp) {
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, dtypep};
        varp->isInternal(true);
        varp->lifetime(VLifetime::STATIC_EXPLICIT);
        ownerp->addStmtsp(varp);
        return varp;
    }
    AstNodeStmt* newDeferredAssertFlush(FileLine* flp) const {
        return new AstDeferredAssertFlush{flp, m_obsFlushp->cloneTree(true)};
    }
    // Add the flushes of a process once it is known to have observed deferred assertions
    template <typename T_Scope>
    void addObsFlushes(T_Scope* scopep) {
        if (!m_obsFlushp) return;
        for (AstNode* const nodep : m_obsWaitsp) {
            if (AstEventControl* const controlp = VN_CAST(nodep, EventControl)) {
                addResumeFlush(controlp);
            } else if (AstWait* const waitp = VN_CAST(nodep, Wait)) {
                addResumeFlush(waitp);
            } else {  // AstWaitFork has no statements
                nodep->addNextHere(newDeferredAssertFlush(nodep->fileline()));
            }
        }
        // IEEE 1800-2023 16.4.4: Flush when the outermost scope was exited by a disable
        if (m_obsDoneVarp) {
            FileLine* const flp = scopep->fileline();
            // Clear for the next run of an always
            AstAssign* const clearp
                = new AstAssign{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::WRITE},
                                new AstConst{flp, AstConst::BitFalse{}}};
            scopep->addStmtsp(new AstIf{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::READ},
                                        clearp, newDeferredAssertFlush(flp)});
        }
        VL_DO_DANGLING(m_obsFlushp->deleteTree(), m_obsFlushp);
    }
    template <typename T_HasStmtsp>
    void addResumeFlush(T_HasStmtsp* nodep) const {
        if (!m_obsFlushp) return;
        if (nodep->stmtsp()) {
            nodep->stmtsp()->addHereThisAsNext(newDeferredAssertFlush(nodep->fileline()));
        } else {
            nodep->addStmtsp(newDeferredAssertFlush(nodep->fileline()));
        }
    }
    static AstQueueDType* newQueueDTypep(FileLine* flp, AstNodeDType* elemDTypep) {
        AstQueueDType* const queueDtp = new AstQueueDType{flp, elemDTypep, nullptr};
        v3Global.rootp()->typeTablep()->addTypesp(queueDtp);
        return queueDtp;
    }
    static AstNodeStmt* newQueuePush(FileLine* flp, AstVar* queuep, AstNodeExpr* valuep) {
        AstCMethodHard* const callp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::WRITE}, VCMethod::ARRAY_PUSH_BACK, valuep};
        callp->dtypeSetVoid();
        return callp->makeStmt();
    }
    static AstCMethodHard* newQueuePop(FileLine* flp, AstVar* queuep, AstNodeDType* elemDTypep) {
        AstCMethodHard* const callp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::READWRITE}, VCMethod::ARRAY_POP_FRONT};
        callp->dtypeFrom(elemDTypep);
        return callp;
    }
    void snapshotObservedExpr(AstNodeExpr* exprp, AstNodeStmt*& queuesp) {
        // Constants and, within the time step of the call, the time cannot change
        if (VN_IS(exprp, Const) || VN_IS(exprp, Time)) return;
        FileLine* const flp = exprp->fileline();
        AstNodeDType* const dtypep = exprp->dtypep();
        AstVar* const queuep
            = newModuleTemp(flp, m_obsNames.get("ValQueue"), newQueueDTypep(flp, dtypep), m_modp);
        queuep->setIgnoreSchedWrite();
        VNRelinker handle;
        AstNodeExpr* const oldp = exprp->unlinkFrBack(&handle);
        handle.relink(newQueuePop(flp, queuep, dtypep));
        queuesp = AstNode::addNext(queuesp, newQueuePush(flp, queuep, oldp));
        AstCMethodHard* const clearp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::WRITE}, VCMethod::DYN_CLEAR};
        clearp->dtypeSetVoid();
        m_obsFlushp = AstNode::addNext(m_obsFlushp, clearp->makeStmt());
    }
    void snapshotObservedSFormatArgs(AstSFormatF* fmtp, AstNodeStmt*& queuesp) {
        for (AstNodeExpr* const exprp : fmtp->exprspList()) {
            AstSFormatArg* const argp = VN_CAST(exprp, SFormatArg);
            snapshotObservedExpr(argp ? argp->exprp() : exprp, queuesp);
        }
    }
    static AstIf* newIfAssertOn(AstVar* statep, AstNodeStmt* bodyp,
                                VAssertDirectiveType directiveType,
                                VAssertType type = VAssertType::INTERNAL) {
        // Add an internal if to check assertions are on.
        // Don't make this an AND term, as it's unlikely to need to test this.
        FileLine* const fl = bodyp->fileline();

        AstNodeExpr* const condp = assertOnCond(statep, fl, type, directiveType);
        AstIf* const newp = new AstIf{fl, condp, bodyp};
        newp->isBoundsCheck(true);  // To avoid LATCH warning
        newp->user2(true);  // Mark as an assertOn() check
        return newp;
    }
    // Gate 'bodyp' by 'condp' as an assertion control check
    static AstIf* newIfControl(AstNodeExpr* condp, AstNodeStmt* bodyp) {
        AstIf* const newp = new AstIf{condp->fileline(), condp, bodyp};
        newp->isBoundsCheck(true);  // To avoid LATCH warning
        newp->user1(true);  // Don't assert/cover this if
        newp->user2(true);  // Mark as an assertOn() check
        return newp;
    }
    static AstNodeStmt* newIfAssertPassOn(AstVar* statep, AstNodeStmt* bodyp,
                                          VAssertDirectiveType directiveType, VAssertType type,
                                          bool vacuous) {
        // Add an internal if to check assertion passOn is enabled.
        // Don't make this an AND term, as it's unlikely to need to test this.
        return newIfControl(
            assertPassOnCond(statep, bodyp->fileline(), type, directiveType, vacuous), bodyp);
    }
    static AstNodeStmt* newIfAssertFailOn(AstVar* statep, AstNodeStmt* bodyp,
                                          VAssertDirectiveType directiveType, VAssertType type) {
        // Add an internal if to check assertion failOn is enabled.
        // Don't make this an AND term, as it's unlikely to need to test this.
        return newIfControl(assertFailOnCond(statep, bodyp->fileline(), type, directiveType),
                            bodyp);
    }

    static AstIf* assertCond(const AstNodeCoverOrAssert* nodep, AstNodeExpr* propp,
                             AstNodeStmt* passsp, AstNodeStmt* failsp) {
        AstIf* const ifp = new AstIf{nodep->fileline(), propp, passsp, failsp};
        // It's more LIKELY that we'll take the nullptr if clause
        // than the sim-killing else clause:
        ifp->branchPred(VBranchPred::BP_LIKELY);
        ifp->isBoundsCheck(true);  // To avoid LATCH warning
        return ifp;
    }

    AstNodeStmt* assertBody(const AstNodeCoverOrAssert* nodep, AstNode* propp, AstNodeStmt* passsp,
                            AstNodeStmt* failsp) {
        if (AstPExpr* const pexprp = VN_CAST(propp, PExpr)) {
            if (!v3Global.opt.timing().isSetTrue()) {
                nodep->v3warn(E_NOTIMING, "This property expression requires --timing");
                VL_DO_DANGLING(pushDeletep(pexprp), pexprp);
                return new AstBegin{nodep->fileline(), "", nullptr, false};
            }
            if (AstNodeStmt* const finalp = pexprp->finalp()) {
                // The final block executes in zero time (IEEE 1800-2023 9.2.3), so a timing
                // control there never resumes
                const AstNode* timingp = nullptr;
                finalp->exists([&](const AstNode* const np) {
                    if (!np->isTimingControl()) return false;
                    timingp = np;
                    return true;
                });
                if (timingp) {
                    timingp->v3warn(E_UNSUPPORTED,
                                    "Unsupported: Timing control in action block of a strong "
                                    "property, which also runs at end of simulation");
                    // Drop the whole property, its attempts too, as for a missing --timing: a
                    // property expression nested in them is not lowered for later passes
                    VL_DO_DANGLING(pushDeletep(pexprp), pexprp);
                    return new AstBegin{nodep->fileline(), "", nullptr, false};
                }
            }
            AstFork* const forkp = new AstFork{nodep->fileline(), VJoinType::JOIN_NONE};
            // The action uses the values of automatic variables when the assertion runs
            // (IEEE 1800-2023 16.14.6.1)
            forkp->capturesValues(true);
            forkp->addForksp(new AstForkItem{nodep->fileline(), pexprp->bodyp()->unlinkFrBack()});
            if (AstNodeStmt* const finalp = pexprp->finalp()) {
                // The end-of-simulation check runs action blocks in a final block, where an
                // NBA, legal in an action block, executes as a blocking assignment
                finalp->foreach([](AstAssignDly* const dlyp) {
                    FileLine* const newfl = new FileLine{dlyp->fileline()};
                    newfl->warnOff(V3ErrorCode::FINALDLY, true);
                    dlyp->fileline(newfl);
                });
                // A final block of its own, so an action suspending in it, by a task it calls,
                // does not stop the end-of-simulation checks of other assertions
                m_modp->addStmtsp(new AstFinal{m_modp->fileline(), finalp->unlinkFrBack()});
            }
            VL_DO_DANGLING2(pushDeletep(pexprp), pexprp, propp);
            return forkp;
        }

        return assertCond(nodep, VN_AS(propp, NodeExpr), passsp, failsp);
    }

    AstNodeStmt* newFireAssertUnchecked(const AstNodeStmt* nodep, const string& message,
                                        AstNodeExpr* exprsp = nullptr) {
        // Like newFireAssert() but omits the asserts-on check
        AstDisplay* const dispp
            = new AstDisplay{nodep->fileline(), VDisplayType::DT_ERROR, message, nullptr, nullptr};
        dispp->fmtp()->timeunit(m_modp->timeunit());
        AstNodeStmt* const bodysp = dispp;
        replaceDisplay(dispp, "%%Error");  // Convert to standard DISPLAY format
        if (exprsp) dispp->fmtp()->exprsp()->addNext(exprsp);
        if (v3Global.opt.stopFail()) bodysp->addNext(new AstStop{nodep->fileline(), false});
        return bodysp;
    }

    AstNodeStmt* newFireAssert(const AstNodeStmt* nodep, VAssertDirectiveType directiveType,
                               VAssertType assertType, const string& message,
                               AstNodeExpr* exprsp = nullptr) {
        AstNodeStmt* const bodysp = newFireAssertUnchecked(nodep, message, exprsp);
        AstIf* const ifp = newIfAssertOn(nodep->controlVarp(), bodysp, directiveType, assertType);
        // A unique, unique0 or priority violation report is pending until the Observed region,
        // flushed like an observed deferred assertion report (IEEE 1800-2023 12.4.2.1, 12.5.3.1).
        // It is made at once outside a procedure, so in a task or function, under a
        // fork...join_any or fork...join_none and in an action of a concurrent assertion, where
        // the process making it is not known, and in a final procedure, after which no Observed
        // region runs. A compiled out check is left to be removed.
        if (assertType != VAssertType::INTERNAL && !ifp->condp()->isZero()
            && v3Global.opt.timing().isSetTrue() && m_procedurep && !VN_IS(m_procedurep, Final)
            && !m_inSpawnedFork && !m_inConcurrentAction) {
            ++m_statViolationsDeferred;
            // Format the message at the check, so with its scope, time and values
            AstDisplay* const dispp = VN_AS(bodysp, Display);
            AstSFormatF* const fmtp = dispp->fmtp()->unlinkFrBack();
            dispp->fmtp(new AstSFormatF{fmtp->fileline(), "%s", true, fmtp});
            AstNodeStmt* queuesp = nullptr;
            snapshotObservedExpr(fmtp, queuesp);
            // Killed as an assert directive of its type, as assertOnCond controls it
            ifp->addThensp(newObservedDeferredCall(
                nodep->fileline(), ifp->thensp()->unlinkFrBackWithNext(), queuesp, assertType,
                VAssertDirectiveType::ASSERT, nodep->controlVarp()));
        }
        return ifp;
    }

    // Add a variable of state of the module, static in a class, whose processes are static
    void addStateVar(AstVar* varp) {
        if (VN_IS(m_modp, Class)) varp->lifetime(VLifetime::STATIC_EXPLICIT);
        m_modp->addStmtsp(varp);
    }
    AstVar* createDelayedVar(const std::string& name, AstAlways* alwaysp, AstNodeExpr* exprp,
                             AstNodeExpr* initp) {
        FileLine* const flp = exprp->fileline();
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, exprp->dtypep()};
        // TODO: this lifetime seems nonsene (can't have NBAs to automatics), but is as before
        varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        varp->isPastValue(true);
        addStateVar(varp);
        // Before enough clock ticks, $past returns the expression's default sampled value.
        if (initp) {
            m_modp->addStmtsp(new AstInitialStatic{
                flp, new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE}, initp}});
        }
        ++m_statPastVars;
        m_pastVarps.insert(varp);
        // Actually set the delayed value
        AstNodeExpr* const lhsp = new AstVarRef{flp, varp, VAccess::WRITE};
        AstAssignDly* const assignp = new AstAssignDly{flp, lhsp, exprp};
        alwaysp->prependStmtsp(assignp);
        return varp;
    }

    // The always block computing the delayed values, shared by identical expressions unless
    // 'ownHistory'
    AstAlways* getDelayedAlways(AstNodeExpr* exprp, AstNodeExpr* initp, AstSenTree* senTreep,
                                bool ownHistory) {
        auto& expr2Sen2Alwaysr
            = initp ? m_modExpr2Sen2DefaultDelayedAlwaysp : m_modExpr2Sen2DelayedAlwaysp;
        AstAlways* ownAlwaysp = nullptr;
        AstAlways*& alwayspr = ownHistory ? ownAlwaysp : expr2Sen2Alwaysr[*exprp][*senTreep];
        if (!alwayspr) {
            FileLine* const flp = exprp->fileline();
            // Create the always block that computes the delayed values
            alwayspr = new AstAlways{flp, VAlwaysKwd::ALWAYS, senTreep, nullptr};
            m_modp->addStmtsp(alwayspr);
            // Create the once-delayed variable
            const std::string name = "_Vpast_" + cvtToStr(m_modPastNum++) + "_1";
            AstVar* const varp = createDelayedVar(name, alwayspr, exprp, initp);
            // Add it to delayed variable vector
            m_delayed(alwayspr).emplace_back(varp);
        } else {
            // Reusing exiting, not needed
            VL_DO_DANGLING(pushDeletep(exprp), exprp);
            if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
        }
        return alwayspr;
    }

    AstNodeExpr* getPastValue(AstNodeExpr* exprp, AstNodeExpr* initp, AstSenTree* senTreep,
                              uint32_t ticks, bool ownHistory) {
        UASSERT_OBJ(ticks > 0, exprp, "Delay must be > 0");
        FileLine* const flp = exprp->fileline();
        AstAlways* const alwaysp = getDelayedAlways(
            exprp, initp ? initp->cloneTreePure(false) : nullptr, senTreep, ownHistory);
        AstNodeExpr* const resultp = pastValueRef(alwaysp, flp, ticks, initp);
        if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
        return resultp;
    }

    AstNodeExpr* pastValueRef(AstAlways* alwaysp, FileLine* flp, uint32_t ticks,
                              AstNodeExpr* initp) {
        std::vector<AstVar*>& delayedr = m_delayed(alwaysp);
        // Ensure the required delay exists
        while (delayedr.size() < ticks) {
            AstVar* const firstp = delayedr.front();
            FileLine* const varFlp = firstp->fileline();
            // Create once more delayed value
            std::string name = firstp->name();
            name.resize(name.size() - 1);
            name += std::to_string(delayedr.size() + 1);
            AstNodeExpr* const prevp = new AstVarRef{varFlp, delayedr.back(), VAccess::READ};
            AstVar* const varp = createDelayedVar(name, alwaysp, prevp,
                                                  initp ? initp->cloneTreePure(false) : nullptr);
            // Add it to delayed variable vector
            delayedr.emplace_back(varp);
        }
        // Return a reference to the appropriately delayed variable
        return new AstVarRef{flp, delayedr.at(ticks - 1), VAccess::READ};
    }

    // Time of the pipeline's last sampling tick, for end-of-simulation readers
    AstVar* getPastTickTimeVar(AstAlways* alwaysp) {
        AstVar*& varpr = m_delayedAlways2TickTimep[alwaysp];
        if (!varpr) {
            FileLine* const flp = alwaysp->fileline();
            varpr = new AstVar{flp, VVarType::MODULETEMP,
                               "_Vpast_" + cvtToStr(m_modPastNum++) + "_t",
                               m_modp->findUInt64DType()};
            addStateVar(varpr);
            AstNodeExpr* const timep = new AstCExpr{flp, "vlSymsp->_vm_contextp__->time()", 64};
            alwaysp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, varpr, VAccess::WRITE}, timep});
        }
        return varpr;
    }

    // Lower deferred action into a pending call with its input arguments snapshotted. Pending
    // calls run in the Reactive region, or for a final deferred assertion in the Postponed
    // region, unless a flush of their process clears them (IEEE 1800-2023 16.4.1).
    AstNodeStmt* newObservedDeferredAction(FileLine* flp, AstNodeStmt* actionsp,
                                           const AstNodeCoverOrAssert* assertp) {
        // The null statement of an 'else;', an empty implied block, has no call to defer
        const AstBegin* const beginp = VN_CAST(actionsp, Begin);
        if (beginp && beginp->implied() && !beginp->stmtsp()) return actionsp;
        if (!(actionsp->isOutputter() || VN_IS(actionsp, SFormat) || VN_IS(actionsp, StmtExpr))) {
            actionsp->v3error("Observed deferred immediate assertion action block must be a "
                              "single subroutine call (IEEE 1800-2023 16.4).");
            VL_DO_DANGLING(pushDeletep(actionsp), actionsp);
            return nullptr;
        }
        AstStmtExpr* const stmtexprp = VN_CAST(actionsp, StmtExpr);
        AstNodeFTaskRef* const refp
            = stmtexprp ? VN_CAST(stmtexprp->exprp(), NodeFTaskRef) : nullptr;
        if (!(VN_IS(actionsp, Display) || VN_IS(actionsp, SFormat) || VN_IS(actionsp, SystemT)
              || VN_IS(actionsp, Stop) || VN_IS(actionsp, Finish) || refp)) {
            actionsp->v3warn(E_UNSUPPORTED,
                             "Unsupported: Observed deferred immediate assertion action.");
            VL_DO_DANGLING(pushDeletep(actionsp), actionsp);
            return nullptr;
        }
        AstNodeStmt* queuesp = nullptr;
        if (AstDisplay* const displayp = VN_CAST(actionsp, Display)) {
            if (displayp->filep()) snapshotObservedExpr(displayp->filep(), queuesp);
            snapshotObservedSFormatArgs(displayp->fmtp(), queuesp);
        } else if (AstSFormat* const sformatp = VN_CAST(actionsp, SFormat)) {
            snapshotObservedSFormatArgs(sformatp->fmtp(), queuesp);
        } else if (AstSystemT* const systemp = VN_CAST(actionsp, SystemT)) {
            snapshotObservedExpr(systemp->lhsp(), queuesp);
        } else if (refp) {
            // Match actuals to formal ports, including named/default arguments
            const V3TaskConnects tconnects
                = V3Task::taskConnects(refp, refp->taskp()->declsp(), nullptr, false);
            for (const auto& tconnect : tconnects) {
                AstVar* const portp = tconnect.first;
                AstArg* const argp = tconnect.second;
                if (portp->isRef() || portp->isConstRef()) {
                    if (argp->exprp()->exists([](const AstNodeVarRef* varrefp) {
                            return varrefp->varp()->lifetime().isAutomatic()
                                   || varrefp->varp()->dtypep()->skipRefp()->isDynamicallySized();
                        })) {
                        argp->exprp()->v3error(
                            "Observed deferred immediate assertion ref action argument cannot "
                            "have automatic or dynamic storage (IEEE 1800-2023 16.4).");
                    }
                } else if (portp->isNonOutput()) {
                    snapshotObservedExpr(argp->exprp(), queuesp);
                } else {
                    argp->exprp()->v3error("Observed deferred immediate assertion action "
                                           "argument must be input, ref, or const ref "
                                           "(IEEE 1800-2023 16.4).");
                }
            }
        }
        return newObservedDeferredCall(flp, actionsp, queuesp, assertp->userType(),
                                       assertp->directive(), assertp->controlVarp());
    }
    // Make statements pending, appending what queues them to queuesp. A pending call made
    // before an $assertkill of its assertion, of the given types and control state, is not run
    // (IEEE 1800-2023 20.11).
    AstNodeStmt* newObservedDeferredCall(FileLine* flp, AstNodeStmt* callsp, AstNodeStmt* queuesp,
                                         VAssertType assertType,
                                         VAssertDirectiveType directiveType, AstVar* controlVarp) {
        // The calls run in a block of the module, so keep the scope of the named blocks, which
        // V3Begin would have added
        std::string scope = m_genScope;
        for (const AstBegin* const beginp : m_namedBeginps) scope += "__DOT__" + beginp->name();
        if (!scope.empty()) {
            callsp->foreachAndNext(
                [&](AstScopeName* namep) { namep->scopeAttr(scope + namep->scopeAttr()); });
        }
        AstVar* const pendingp
            = newModuleTemp(flp, m_obsNames.get("Pending"), m_modp->findUInt32DType(), m_modp);
        pendingp->setIgnoreSchedWrite();
        m_obsFlushp = AstNode::addNext(
            m_obsFlushp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                       new AstConst{flp, 0}});
        // Dropping a call made before a kill still removes its values from their queues
        AstNodeStmt* dropsp = nullptr;
        if (queuesp) {
            queuesp->foreachAndNext([&](const AstCMethodHard* pushp) {
                if (pushp->method() != VCMethod::ARRAY_PUSH_BACK) return;
                AstVar* const valQueuep = VN_AS(pushp->fromp(), VarRef)->varp();
                AstCMethodHard* const popp
                    = new AstCMethodHard{flp, new AstVarRef{flp, valQueuep, VAccess::READWRITE},
                                         VCMethod::DYN_POP_FRONT};
                popp->dtypeSetVoid();
                dropsp = AstNode::addNext(dropsp, popp->makeStmt());
            });
        }
        // The calls pending when a change of the $assertkill count of the assertion is first seen
        // were made before the kill, so are dropped. They are the first pending.
        AstVar* const killSeenp
            = newModuleTemp(flp, m_obsNames.get("KillSeen"), m_modp->findUInt32DType(), m_modp);
        killSeenp->setIgnoreSchedWrite();
        AstVar* const killedp
            = newModuleTemp(flp, m_obsNames.get("Killed"), m_modp->findUInt32DType(), m_modp);
        killedp->setIgnoreSchedWrite();
        m_obsFlushp = AstNode::addNext(
            m_obsFlushp,
            new AstAssign{flp, new AstVarRef{flp, killedp, VAccess::WRITE}, new AstConst{flp, 0}});
        const auto newKillCount = [&]() {
            AstNodeExpr* countp = V3AssertCommon::newAssertCtlGetp(
                flp, VAssertCtlQuery::KILL, assertType, directiveType, controlVarp);
            // A disable of a block around the call drops it as a kill does (IEEE 1800-2023 16.4.4)
            for (AstVar* const varp : m_disableCountps)
                countp = new AstAdd{flp, countp, new AstVarRef{flp, varp, VAccess::READ}};
            return countp;
        };
        const auto newKillCheck = [&]() {
            AstNodeStmt* const stmtsp
                = new AstAssign{flp, new AstVarRef{flp, killedp, VAccess::WRITE},
                                new AstVarRef{flp, pendingp, VAccess::READ}};
            stmtsp->addNext(
                new AstAssign{flp, new AstVarRef{flp, killSeenp, VAccess::WRITE}, newKillCount()});
            return new AstIf{
                flp, new AstNeq{flp, newKillCount(), new AstVarRef{flp, killSeenp, VAccess::READ}},
                stmtsp};
        };
        queuesp = AstNode::addNext(queuesp, newKillCheck());
        dropsp = AstNode::addNext(static_cast<AstNodeStmt*>(new AstAssign{
                                      flp, new AstVarRef{flp, killedp, VAccess::WRITE},
                                      new AstSub{flp, new AstVarRef{flp, killedp, VAccess::READ},
                                                 new AstConst{flp, 1}}}),
                                  dropsp);
        callsp = new AstIf{flp, new AstVarRef{flp, killedp, VAccess::READ}, dropsp, callsp};
        queuesp = AstNode::addNext(
            queuesp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                   new AstAdd{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                              new AstConst{flp, 1}}});
        AstNodeProcedure* runnerp;
        if (assertType == VAssertType::FINAL_DEFERRED_IMMEDIATE) {
            if (!m_finalPostponedp) {
                m_finalPostponedp = new AstAlwaysPostponed{flp, nullptr};
                m_modp->addStmtsp(m_finalPostponedp);
            }
            runnerp = m_finalPostponedp;
        } else {
            if (!m_obsEventp) {
                m_obsEventp = newModuleTemp(flp, m_obsNames.get("Event"),
                                            m_modp->findBasicDType(VBasicDTypeKwd::EVENT), m_modp);
                v3Global.setHasEvents();
                v3Global.setUsesTiming();
                m_obsReactivep = new AstAlwaysReactive{
                    flp,
                    new AstSenTree{flp,
                                   new AstSenItem{flp, VEdgeType::ET_EVENT,
                                                  new AstVarRef{flp, m_obsEventp, VAccess::READ}}},
                    nullptr};
                m_obsReactivep->deferredReports(true);
                m_modp->addStmtsp(m_obsReactivep);
            }
            runnerp = m_obsReactivep;
            queuesp = AstNode::addNext(
                queuesp,
                new AstFireEvent{flp, new AstVarRef{flp, m_obsEventp, VAccess::WRITE}, false});
        }

        AstLoop* const reactLoopp = new AstLoop{flp};
        reactLoopp->addStmtsp(
            new AstLoopTest{flp, reactLoopp, new AstVarRef{flp, pendingp, VAccess::READ}});
        reactLoopp->addStmtsp(new AstAssign{
            flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
            new AstSub{flp, new AstVarRef{flp, pendingp, VAccess::READ}, new AstConst{flp, 1}}});
        reactLoopp->addStmtsp(callsp);
        // Every report pending when its region runs has matured, also if an action run before it
        // kills its assertion, so the checks come before any of the calls
        AstIf* const checkp = newKillCheck();
        if (runnerp->stmtsp()) {
            runnerp->stmtsp()->addHereThisAsNext(checkp);
        } else {
            runnerp->addStmtsp(checkp);
        }
        runnerp->addStmtsp(reactLoopp);
        return queuesp;
    }

    // Return the variable holding the value of 'condp' at the start of the current PExpr's
    // attempt, which the assertion controls apply to (IEEE 1800-2023 20.11)
    AstVar* getPExprStartVarp(const std::string& key, AstNodeExpr* condp) {
        AstVar*& varpr = m_pexprStartVarps[key];
        if (varpr) {
            VL_DO_DANGLING(pushDeletep(condp), condp);
            return varpr;
        }
        FileLine* const flp = condp->fileline();
        varpr = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Start"), condp->dtypep()};
        varpr->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        m_pexprBodyp->addDeclsp(varpr);
        AstAssign* const initp
            = new AstAssign{flp, new AstVarRef{flp, varpr, VAccess::WRITE}, condp};
        // Every PExpr body V3AssertPre creates has statements other than clauses (see the census
        // in the PExpr lowerings), which stay while V3Assert visits it
        AstNode* const stmtsp = m_pexprBodyp->stmtsp();
        UASSERT_OBJ(stmtsp, m_pexprBodyp, "Empty PExpr body");
        stmtsp->addHereThisAsNext(initp);
        return varpr;
    }
    // The Kill count of the current assertion
    AstNodeExpr* newKillCountp(FileLine* flp) const {
        return V3AssertCommon::newAssertCtlGetp(flp, VAssertCtlQuery::KILL, m_assertp->userType(),
                                                m_assertp->directive(), m_assertp->controlVarp());
    }
    // A Kill aborts an executing attempt (IEEE 1800-2023 20.11): after each wait of the attempt
    // of 'nodep' (marked by user3), end it if killed since its start, so it evaluates nothing
    // further.
    void abortWhenKilled(AstPExpr* nodep) {
        AstBegin* const bodyp = nodep->bodyp();
        FileLine* const flp = bodyp->fileline();
        AstVar* const killp = getPExprStartVarp("kill", newKillCountp(flp));
        AstNodeStmt* const stmtsp = bodyp->stmtsp();
        UASSERT_OBJ(stmtsp, bodyp, "Empty PExpr body");
        AstJumpBlock* const blockp = new AstJumpBlock{flp, stmtsp->unlinkFrBackWithNext()};
        bodyp->addStmtsp(blockp);
        std::vector<AstNodeStmt*> waitps;
        blockp->foreach([&](AstNodeStmt* stmtp) {
            if (stmtp->user3()) waitps.push_back(stmtp);
            stmtp->user3(false);  // Not for an enclosing PExpr
        });
        for (AstNodeStmt* const waitp : waitps) {
            waitp->addNextHere(new AstIf{
                flp, new AstNeq{flp, new AstVarRef{flp, killp, VAccess::READ}, newKillCountp(flp)},
                new AstJumpGo{flp, blockp}});
        }
        if (nodep->finalp()) dropKilledAtFinal(nodep);
    }
    // The end-of-simulation check of a strong property checks the attempts V3AssertPre records
    // as active, in an associative array by process, or a count, which the check reads first.
    // The attempts executing at a Kill are aborted (IEEE 1800-2023 20.11), and aborted attempts
    // do not retire themselves, so once the Kill count differs from that of the attempts
    // recorded, they are all dropped, at the start of the next attempt or of the check.
    void dropKilledAtFinal(AstPExpr* nodep) {
        AstBegin* const finalp = VN_AS(nodep->finalp(), Begin);
        FileLine* const flp = finalp->fileline();
        const AstAssign* const countp = VN_CAST(finalp->stmtsp(), Assign);
        UASSERT_OBJ(countp, finalp, "Expected the count of the active attempts first");
        AstNodeStmt* clearp = nullptr;
        AstVar* activep = nullptr;
        if (const AstCMethodHard* const sizep = VN_CAST(countp->rhsp(), CMethodHard)) {
            UASSERT_OBJ(sizep->method() == VCMethod::ASSOC_SIZE, sizep, "Expected a size");
            activep = VN_AS(sizep->fromp(), VarRef)->varp();
            AstCMethodHard* const callp = new AstCMethodHard{
                flp, new AstVarRef{flp, activep, VAccess::WRITE}, VCMethod::ASSOC_CLEAR};
            callp->dtypeSetVoid();
            clearp = callp->makeStmt();
        } else {
            activep = VN_AS(countp->rhsp(), VarRef)->varp();
            clearp
                = new AstAssign{flp, new AstVarRef{flp, activep, VAccess::WRITE},
                                new AstConst{flp, AstConst::WidthedValue{}, activep->width(), 0}};
        }
        AstVar* const epochp
            = newModuleTemp(flp, m_actionNames.get("Epoch"), m_modp->findUInt32DType(), m_modp);
        const auto newDropIfp = [&](bool update) {
            AstIf* const ifp = new AstIf{
                flp,
                new AstNeq{flp, new AstVarRef{flp, epochp, VAccess::READ}, newKillCountp(flp)},
                clearp->cloneTree(false)};
            for (AstVar* const countp : {m_strongPassOnp, m_strongFailOnp}) {
                ifp->addThensp(new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE},
                                             new AstConst{flp, AstConst::WidthedValue{}, 32, 0}});
            }
            if (update) {
                ifp->addThensp(new AstAssign{flp, new AstVarRef{flp, epochp, VAccess::WRITE},
                                             newKillCountp(flp)});
            }
            return ifp;
        };
        AstNodeStmt* const blockp = nodep->bodyp()->stmtsp();
        blockp->addHereThisAsNext(newDropIfp(true));
        finalp->stmtsp()->addHereThisAsNext(newDropIfp(false));
        // Count the recorded attempts by the controls at their start, where V3AssertPre records
        // and retires them
        const VAssertDirectiveType directive = m_assertp->directive();
        const VAssertType type = m_assertp->userType();
        AstVar* const passStartp = getPExprStartVarp(
            "pass0", assertPassOnCond(m_assertp->controlVarp(), flp, type, directive, false));
        AstVar* const failStartp = getPExprStartVarp(
            "fail", assertFailOnCond(m_assertp->controlVarp(), flp, type, directive));
        const auto newCountp = [&](bool inc) {
            AstNodeStmt* stmtsp = nullptr;
            for (AstVar* const countp : {m_strongPassOnp, m_strongFailOnp}) {
                AstNodeExpr* const onep = new AstConst{flp, AstConst::WidthedValue{}, 32, 1};
                AstNodeExpr* const valuep
                    = inc ? static_cast<AstNodeExpr*>(
                                new AstAdd{flp, new AstVarRef{flp, countp, VAccess::READ}, onep})
                          : new AstSub{flp, new AstVarRef{flp, countp, VAccess::READ}, onep};
                stmtsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                    stmtsp,
                    new AstIf{
                        flp,
                        new AstVarRef{flp, countp == m_strongPassOnp ? passStartp : failStartp,
                                      VAccess::READ},
                        new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE}, valuep}});
            }
            return stmtsp;
        };
        std::vector<AstNodeStmt*> recordps;
        std::vector<AstNodeStmt*> retireps;
        blockp->foreach([&](AstNodeStmt* stmtp) {
            if (const AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
                const AstAssocSel* const selp = VN_CAST(assignp->lhsp(), AssocSel);
                const AstVarRef* const refp
                    = VN_CAST(selp ? selp->fromp() : assignp->lhsp(), VarRef);
                if (!refp || refp->varp() != activep) return;
                if (selp || VN_IS(assignp->rhsp(), Add)) recordps.push_back(stmtp);
                if (VN_IS(assignp->rhsp(), Sub)) retireps.push_back(stmtp);
            } else if (const AstStmtExpr* const exprp = VN_CAST(stmtp, StmtExpr)) {
                const AstCMethodHard* const methodp = VN_CAST(exprp->exprp(), CMethodHard);
                if (methodp && methodp->method() == VCMethod::ASSOC_ERASE
                    && VN_AS(methodp->fromp(), VarRef)->varp() == activep) {
                    retireps.push_back(stmtp);
                }
            }
        });
        UASSERT_OBJ(!recordps.empty(), nodep, "Expected the record of a strong attempt");
        for (AstNodeStmt* const stmtp : recordps) stmtp->addNextHere(newCountp(true));
        for (AstNodeStmt* const stmtp : retireps) stmtp->addNextHere(newCountp(false));
        VL_DO_DANGLING(pushDeletep(clearp), clearp);
    }
    // Whether an action is left where it is, rather than queued (see newQueuedAction)
    static bool actionStaysInline(AstNodeStmt* actionsp) {
        std::unordered_set<const AstVar*> ownps;  // What the action declares
        actionsp->foreachAndNext([&](const AstVar* varp) { ownps.insert(varp); });
        // Automatic inputs of an action shall not be modified (IEEE 1800-2023 16.14.6.1), leave
        // such an action where V3Fork reports it
        if (actionsp->existsAndNext([&](const AstVarRef* refp) {
                return refp->access().isWriteOrRW() && refp->varp()->lifetime().isAutomatic()
                       && !ownps.count(refp->varp());
            })) {
            return true;
        }
        // Also leave an action jumping out of itself, e.g. disabling a block of the process
        std::unordered_set<const AstJumpBlock*> blockps;  // What the action contains
        actionsp->foreachAndNext([&](const AstJumpBlock* blockp) { blockps.insert(blockp); });
        return actionsp->existsAndNext([&](const AstNode* np) {
            const AstJumpGo* const gop = VN_CAST(np, JumpGo);
            return VN_IS(np, Disable) || (gop && !blockps.count(gop->blockp()));
        });
    }
    // Run the actions of the current concurrent assertion in the Reactive region, see
    // V3AssertReactive
    AstNodeStmt* newReactiveAction(const AstNodeCoverOrAssert* assertp, AstSenTree* senTreep,
                                   AstNodeStmt* actionsp) {
        // A procedure that may suspend may evaluate it in a later time step
        if (m_procSuspends) return actionsp;
        std::string scope;
        for (const AstBegin* const beginp : m_namedBeginps) scope += "__DOT__" + beginp->name();
        return m_reactive.newPending({assertp, m_modp, m_containerp, senTreep, scope}, actionsp,
                                     m_actionNames);
    }

    // Queue the action of a PExpr clause, run in the Reactive region (IEEE 1800-2023 4.4.2.6).
    // Return what queues it, at the decision of the attempt. An entry of the queue holds the
    // values of the automatic variables it reads (IEEE 1800-2023 16.14.6.1).
    AstNodeStmt* newQueuedAction(FileLine* flp, AstNodeStmt* actionsp) {
        // Without timing, assertBody rejects the PExpr
        if (!v3Global.opt.timing().isSetTrue()) return actionsp;
        // A sequence event control resumes its waiters from the cover action, and without
        // coverage the cover statement is deleted
        const AstCover* const coverp = VN_CAST(m_assertp, Cover);
        if (coverp && (coverp->isSeqEvent() || !v3Global.opt.coverageUser())) return actionsp;
        if (actionStaysInline(actionsp)) {
            m_inlineAction = true;
            return actionsp;
        }
        std::unordered_set<const AstVar*> ownps;  // What the action declares
        actionsp->foreachAndNext([&](const AstVar* varp) { ownps.insert(varp); });
        // Queued from the process of the attempt, a fork of the process of the assertion
        const auto newTemp = [&](const string& name, AstNodeDType* dtypep) {
            return newModuleTemp(flp, m_actionNames.get(name), dtypep, m_modp);
        };
        if (!m_actionEventp) {
            m_actionEventp = newTemp("Event", m_modp->findBasicDType(VBasicDTypeKwd::EVENT));
            v3Global.setHasEvents();
            m_actionReactivep = new AstAlwaysReactive{
                flp,
                new AstSenTree{flp,
                               new AstSenItem{flp, VEdgeType::ET_EVENT,
                                              new AstVarRef{flp, m_actionEventp, VAccess::READ}}},
                nullptr};
            // Beside the process of the assertion, in the scope of its generate blocks
            queuesAnchorp()->addNextHere(m_actionReactivep);
        }
        // The process running an entry, which first takes its values from the queues
        AstBegin* const instancep = new AstBegin{flp, "", nullptr, true};
        AstNodeStmt* queuesp = nullptr;
        std::unordered_map<AstVar*, AstVar*> valueps;
        actionsp->foreachAndNext([&](AstVarRef* refp) {
            AstVar* const varp = refp->varp();
            if (!varp->lifetime().isAutomatic() || ownps.count(varp)) return;
            AstVar*& valuepr = valueps[varp];
            if (!valuepr) {
                // Push the value at the decision, pop it in the entry's process
                AstNodeDType* const dtypep = varp->dtypep();
                AstVar* const queuep = newTemp("Queue", newQueueDTypep(flp, dtypep));
                queuep->setIgnoreSchedWrite();
                AstVarRef* const readp = new AstVarRef{flp, varp, VAccess::READ};
                readp->user2(1);
                queuesp = AstNode::addNext(queuesp, newQueuePush(flp, queuep, readp));
                valuepr = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Value"), dtypep};
                valuepr->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                instancep->addDeclsp(valuepr);
                instancep->addStmtsp(new AstAssign{flp,
                                                   new AstVarRef{flp, valuepr, VAccess::WRITE},
                                                   newQueuePop(flp, queuep, dtypep)});
            }
            refp->varp(valuepr);
        });
        // The action keeps the scope of the assertion, under the named blocks of its process,
        // which V3Begin would have added
        std::string scope;
        for (const AstBegin* const beginp : m_namedBeginps) scope += "__DOT__" + beginp->name();
        if (!scope.empty()) {
            actionsp->foreachAndNext(
                [&](AstScopeName* namep) { namep->scopeAttr(scope + namep->scopeAttr()); });
        }
        instancep->addStmtsp(actionsp);
        // Each entry is run by a process of its own, starting in the Reactive region
        AstFork* const forkp = new AstFork{flp, VJoinType::JOIN_NONE};
        forkp->immediateStart(true);
        forkp->addForksp(new AstForkItem{flp, instancep});
        // Run every pending entry
        AstVar* const pendingp = newTemp("Pending", m_modp->findUInt32DType());
        pendingp->setIgnoreSchedWrite();
        AstLoop* const loopp = new AstLoop{flp};
        loopp->addStmtsp(new AstLoopTest{flp, loopp, new AstVarRef{flp, pendingp, VAccess::READ}});
        loopp->addStmtsp(new AstAssign{
            flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
            new AstSub{flp, new AstVarRef{flp, pendingp, VAccess::READ}, new AstConst{flp, 1}}});
        loopp->addStmtsp(forkp);
        m_actionReactivep->addStmtsp(loopp);
        queuesp = AstNode::addNext(
            queuesp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                   new AstAdd{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                              new AstConst{flp, 1}}});
        return AstNode::addNext(
            queuesp,
            new AstFireEvent{flp, new AstVarRef{flp, m_actionEventp, VAccess::WRITE}, false});
    }

    // The type of a handle of a process, or of an array indexed by one
    static AstNodeDType* newProcessDTypep(FileLine* flp) {
        AstClass* const classp = v3Global.rootp()->stdPackageProcessp();
        AstClassRefDType* const dtypep = new AstClassRefDType{flp, classp, nullptr};
        dtypep->classOrPackagep(classp);
        v3Global.rootp()->typeTablep()->addTypesp(dtypep);
        return dtypep;
    }
    static AstAssocArrayDType* newProcessAssocDTypep(FileLine* flp, AstNodeDType* valuep) {
        AstAssocArrayDType* const dtypep
            = new AstAssocArrayDType{flp, valuep, newProcessDTypep(flp)};
        dtypep->dtypep(dtypep);
        v3Global.rootp()->typeTablep()->addTypesp(dtypep);
        return dtypep;
    }
    // A count, or other value, by process, of what all tasks' assertions share
    static AstVar* newTaskCountp(FileLine* flp, const char* name,
                                 AstNodeDType* valueDtp = nullptr) {
        AstPackage* const unitp = v3Global.rootp()->dollarUnitPkgp();
        if (!valueDtp) valueDtp = v3Global.rootp()->typeTablep()->findUInt32DType();
        AstVar* const varp
            = new AstVar{flp, VVarType::MODULETEMP, name, newProcessAssocDTypep(flp, valueDtp)};
        varp->isInternal(true);
        varp->lifetime(VLifetime::STATIC_EXPLICIT);
        varp->setIgnoreSchedWrite();
        unitp->addStmtsp(varp);
        return varp;
    }
    static AstVarRef* newUnitRefp(FileLine* flp, AstVar* varp, VAccess access) {
        AstVarRef* const refp = new AstVarRef{flp, varp, access};
        refp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return refp;
    }
    // The process whose instances the code running now queues and flushes: std::process::self(),
    // or for a disable wrapper of V3LinkJump, which runs part of its enclosing process, that
    // process
    AstNodeExpr* newTaskKeyp(FileLine* flp) {
        AstNetlist* const rootp = v3Global.rootp();
        AstCMethodHard* const existsp
            = new AstCMethodHard{flp, newUnitRefp(flp, m_taskRootp, VAccess::READ),
                                 VCMethod::ASSOC_EXISTS, rootp->stdPackageProcessSelfp(flp)};
        existsp->dtypeSetBit();
        return new AstCond{flp, existsp,
                           new AstAssocSel{flp, newUnitRefp(flp, m_taskRootp, VAccess::READ),
                                           rootp->stdPackageProcessSelfp(flp)},
                           rootp->stdPackageProcessSelfp(flp)};
    }
    // The count of the process, that of newTaskKeyp unless given
    AstAssocSel* newTaskCountSelp(FileLine* flp, AstVar* varp, VAccess access,
                                  AstNodeExpr* processp = nullptr) {
        if (!processp) processp = newTaskKeyp(flp);
        return new AstAssocSel{flp, newUnitRefp(flp, varp, access), processp};
    }
    // Whether a process, given by a handle, is still running: a pending instance of a process
    // killed, e.g. by 'disable fork', has no process to mature in
    static AstNodeExpr* newProcessLivep(FileLine* flp, AstNodeExpr* processp) {
        AstClass* const classp = v3Global.rootp()->stdPackageProcessp();
        AstFunc* statusp = nullptr;
        for (AstNode* const itemp : classp->memberspList()) {
            if (itemp->name() == "status") statusp = VN_AS(itemp, Func);
        }
        UASSERT_OBJ(statusp, classp, "'std::process::status' should be found");
        AstMethodCall* const callp = new AstMethodCall{flp, processp, statusp->name()};
        callp->taskp(statusp);
        callp->classOrPackagep(classp);
        callp->dtypeFrom(statusp);
        // std::process::KILLED
        const AstEnumDType* const enump = VN_AS(statusp->dtypep()->skipRefToEnump(), EnumDType);
        const AstEnumItem* killedp = nullptr;
        for (const AstEnumItem* const itemp : enump->itemspList()) {
            if (itemp->name() == "KILLED") killedp = itemp;
        }
        UASSERT_OBJ(killedp, enump, "'std::process::KILLED' should be found");
        return new AstNeq{flp, callp, VN_AS(killedp->valuep(), Const)->cloneTree(false)};
    }
    // Have newTaskKeyp give, in a disable wrapper, the process running the code enclosing it.
    // The entry is erased after the wrapper's join, so it remains only when the enclosing
    // process is killed while the wrapper runs: one entry per such kill.
    void keyDisableWrapper(AstFork* forkp, AstForkItem* wrapperp) {
        FileLine* const flp = forkp->fileline();
        AstNetlist* const rootp = v3Global.rootp();
        const auto newVarp = [&](const char* name) {
            AstVar* const varp = new AstVar{flp, VVarType::BLOCKTEMP, name, newProcessDTypep(flp)};
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            varp->funcLocal(m_ftaskp);
            varp->isInternal(true);
            return varp;
        };
        AstVar* const parentp = newVarp("__VassertTaskParent");
        AstVar* const selfp = newVarp("__VassertTaskWrapper");
        AstBegin* const beginp = new AstBegin{flp, "", nullptr, true};
        beginp->addDeclsp(parentp);
        beginp->addDeclsp(selfp);
        VNRelinker relinker;
        forkp->unlinkFrBack(&relinker);
        beginp->addStmtsp(
            new AstAssign{flp, new AstVarRef{flp, parentp, VAccess::WRITE}, newTaskKeyp(flp)});
        beginp->addStmtsp(forkp);
        AstCMethodHard* const erasep
            = new AstCMethodHard{flp, newUnitRefp(flp, m_taskRootp, VAccess::WRITE),
                                 VCMethod::ASSOC_ERASE, new AstVarRef{flp, selfp, VAccess::READ}};
        erasep->dtypeSetVoid();
        beginp->addStmtsp(erasep->makeStmt());
        relinker.relink(beginp);
        AstNodeStmt* const setsp = new AstAssign{flp, new AstVarRef{flp, selfp, VAccess::WRITE},
                                                 rootp->stdPackageProcessSelfp(flp)};
        setsp->addNext(
            new AstAssign{flp,
                          new AstAssocSel{flp, newUnitRefp(flp, m_taskRootp, VAccess::WRITE),
                                          new AstVarRef{flp, selfp, VAccess::READ}},
                          new AstVarRef{flp, parentp, VAccess::READ}});
        if (AstNodeStmt* const stmtsp = wrapperp->stmtsp()) {
            stmtsp->addHereThisAsNext(setsp);
        } else {
            wrapperp->addStmtsp(setsp);
        }
    }
    // At a flush point of a process that may reach an assertion in a task, flush the process's
    // pending instances of such assertions (IEEE 1800-2023 16.14.6.2)
    AstNodeStmt* newTaskFlushp(FileLine* flp) {
        if (!m_taskPendingp) {
            m_taskPendingp = newTaskCountp(flp, "__VassertTaskPending");
            m_taskEpochp = newTaskCountp(flp, "__VassertTaskEpoch");
            m_taskRootp = newTaskCountp(flp, "__VassertTaskRoot", newProcessDTypep(flp));
        }
        AstCMethodHard* const existsp
            = new AstCMethodHard{flp, newUnitRefp(flp, m_taskPendingp, VAccess::READ),
                                 VCMethod::ASSOC_EXISTS, newTaskKeyp(flp)};
        existsp->dtypeSetBit();
        AstNodeExpr* const incp
            = new AstAdd{flp, newTaskCountSelp(flp, m_taskEpochp, VAccess::READ),
                         new AstConst{flp, AstConst::WidthedValue{}, 32, 1}};
        return new AstIf{
            flp, existsp,
            new AstAssign{flp, newTaskCountSelp(flp, m_taskEpochp, VAccess::WRITE), incp}};
    }
    // Whether a procedural concurrent assertion in a task matures as in a procedure (see the
    // decision in visitAssertionIterate): an assert, not lowered by V3AssertNfa, outside a fork
    // branch and an action, with timing and its actions queued, in a task of a module or
    // interface, not a class method or an exported task (IEEE 1800-2023 16.14.6)
    bool taskAssertionMatures(AstNodeCoverOrAssert* nodep) const {
        AstAssert* const assertp = VN_CAST(nodep, Assert);
        if (!assertp || nodep->nfaLowered() || m_inForkBranch || m_inConcurrentAction
            || !v3Global.opt.timing().isSetTrue() || !v3Global.rootp()->stdPackageProcessp()
            || m_ftaskp->classMethod() || m_ftaskp->dpiExport() || VN_IS(m_modp, Package)) {
            return false;
        }
        return !(nodep->passsp() && actionStaysInline(nodep->passsp()))
               && !(assertp->failsp() && actionStaysInline(assertp->failsp()));
    }
    // The block beside which the queues of the current assertion run
    AstNode* queuesAnchorp() const {
        if (m_assertCoverp) return m_assertCoverp;
        if (m_procedurep) return m_procedurep;
        return m_ftaskp;
    }

    // A procedural concurrent assertion queues a pending instance at its statement, with the
    // values of its automatic inputs, and the instance matures in the Observed region unless a
    // flush point of its process, or a Kill, flushes it before (IEEE 1800-2023 16.14.6, 20.11).
    // A matured instance begins its attempt there if its leading clock occurred in the time
    // step, else at the next one. 'beginsp' is the attempt's begin, 'clockp' its leading clock.
    // Return what queues the instance.
    AstNodeStmt* newMatureInstance(AstNodeCoverOrAssert* nodep, AstNodeStmt* beginsp,
                                   AstSenTree* clockp) {
        FileLine* const flp = nodep->fileline();
        AstNodeDType* const u32p = m_modp->findUInt32DType();
        AstNodeDType* const u64p = m_modp->findUInt64DType();
        const auto newStatic = [&](const string& name, AstNodeDType* dtypep) {
            AstVar* const varp = newModuleTemp(flp, m_actionNames.get(name), dtypep, m_modp);
            varp->setIgnoreSchedWrite();
            return varp;
        };
        const auto rd = [&](AstVar* varp) { return new AstVarRef{flp, varp, VAccess::READ}; };
        const auto wr = [&](AstVar* varp) { return new AstVarRef{flp, varp, VAccess::WRITE}; };
        const auto incp = [&](AstVar* varp, int delta) -> AstNodeStmt* {
            AstNodeExpr* const onep
                = new AstConst{flp, AstConst::WidthedValue{}, varp->width(), 1};
            AstNodeExpr* const valuep
                = delta > 0 ? static_cast<AstNodeExpr*>(new AstAdd{flp, rd(varp), onep})
                            : new AstSub{flp, rd(varp), onep};
            return new AstAssign{flp, wr(varp), valuep};
        };
        // The values of the sampled value functions at the clock, as the attempt may begin
        // after their registers updated (IEEE 1800-2023 16.9.3)
        std::vector<AstVarRef*> pastRefps;
        beginsp->foreach([&](AstVarRef* refp) {
            // Already sampled only if wrapped itself: the node before a list element, as of an
            // unsigned format argument, is its preceding sibling, not its parent
            const AstSampled* const sampledp = VN_CAST(refp->backp(), Sampled);
            if (refp->access().isReadOnly() && m_pastVarps.count(refp->varp())
                && !(sampledp && sampledp->exprp() == refp)) {
                pastRefps.push_back(refp);
            }
        });
        for (AstVarRef* const refp : pastRefps) {
            VNRelinker handle;
            refp->unlinkFrBack(&handle);
            AstSampled* const sampledp = newSampledExpr(refp);
            sampledp->user1(1);
            handle.relink(sampledp);
            v3Global.setHasSampled();
        }
        // The automatic inputs, with their values at the statement (IEEE 1800-2023 16.14.6.1)
        std::unordered_set<const AstVar*> declps;
        beginsp->foreach([&](const AstVar* varp) { declps.insert(varp); });
        std::vector<AstVar*> inputps;
        std::unordered_map<AstVar*, std::vector<AstVarRef*>> refps;
        beginsp->foreach([&](AstVarRef* refp) {
            AstVar* const varp = refp->varp();
            if (!varp->lifetime().isAutomatic() || declps.count(varp) || m_pastVarps.count(varp)) {
                return;
            }
            std::vector<AstVarRef*>& varRefps = refps[varp];
            if (varRefps.empty()) inputps.push_back(varp);
            varRefps.push_back(refp);
        });
        // The flushes of the process (IEEE 1800-2023 16.14.6.2), see addObsFlushes; in a task,
        // of the calling process, see newTaskFlushp
        if (m_ftaskp) {
            UASSERT_OBJ(m_taskPendingp, nodep, "Task with no flush points");
        } else if (!m_matureEpochp) {
            m_matureEpochp = newStatic("FlushEpoch", u32p);
            m_obsFlushp = AstNode::addNext(m_obsFlushp, incp(m_matureEpochp, 1));
        }
        AstVar* const eventp
            = newStatic("MatureEvent", m_modp->findBasicDType(VBasicDTypeKwd::EVENT));
        v3Global.setHasEvents();
        AstVar* const pendingp = newStatic("Pending", u32p);
        AstVar* const maturedp = newStatic("Matured", u32p);
        AstVar* const epochQp = newStatic("EpochQueue", newQueueDTypep(flp, u32p));
        AstVar* const killQp = newStatic("KillQueue", newQueueDTypep(flp, u32p));
        AstVar* const clkQp = newStatic("ClockQueue", newQueueDTypep(flp, u64p));
        AstVar* const epochp = newStatic("Epoch", u32p);
        AstVar* const killp = newStatic("Kill", u32p);
        AstVar* const clkCountp = newStatic("ClockCount", u64p);
        AstVar* const clkTimep = newStatic("ClockTime", u64p);
        // Never occurred
        m_modp->addStmtsp(new AstInitialStatic{
            flp,
            new AstAssign{flp, wr(clkTimep),
                          new AstNot{flp, new AstConst{flp, AstConst::WidthedValue{}, 64, 0}}}});
        const auto newTimep
            = [&]() { return new AstCExpr{flp, "vlSymsp->_vm_contextp__->time()", 64}; };
        // At the statement
        AstNodeStmt* queuesp = nullptr;
        // Matured, kept for the clock
        AstNodeStmt* keepsp = nullptr;
        // Flushed
        AstNodeStmt* dropsp = nullptr;
        // Begun
        AstBegin* const beginp = new AstBegin{flp, "", nullptr, true};
        for (AstVar* const varp : inputps) {
            AstNodeDType* const dtypep = varp->dtypep();
            AstVar* const pendQp = newStatic("PendQueue", newQueueDTypep(flp, dtypep));
            AstVar* const matQp = newStatic("MatQueue", newQueueDTypep(flp, dtypep));
            queuesp = AstNode::addNext(queuesp, newQueuePush(flp, pendQp, rd(varp)));
            keepsp = AstNode::addNext(keepsp,
                                      newQueuePush(flp, matQp, newQueuePop(flp, pendQp, dtypep)));
            dropsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                dropsp, newQueuePop(flp, pendQp, dtypep)->makeStmt());
            AstVar* const copyp
                = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Input"), dtypep};
            copyp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            beginp->addDeclsp(copyp);
            beginp->addStmtsp(new AstAssign{flp, wr(copyp), newQueuePop(flp, matQp, dtypep)});
            for (AstVarRef* const refp : refps[varp]) {
                refp->varp(copyp);
                // Its value at the statement, not a sample
                if (AstSampled* const sampledp = VN_CAST(refp->backp(), Sampled)) {
                    if (sampledp->exprp() == refp) {
                        sampledp->replaceWith(refp->unlinkFrBack());
                        VL_DO_DANGLING(pushDeletep(sampledp), sampledp);
                    }
                }
            }
        }
        AstNodeDType* const processDtp = m_ftaskp ? newProcessDTypep(flp) : nullptr;
        AstVar* const processQp
            = m_ftaskp ? newStatic("ProcessQueue", newQueueDTypep(flp, processDtp)) : nullptr;
        AstVar* const processp = m_ftaskp ? newStatic("Process", processDtp) : nullptr;
        if (m_ftaskp) {
            // The process's count of flushes, and its pending instances
            queuesp = AstNode::addNext(queuesp, newQueuePush(flp, processQp, newTaskKeyp(flp)));
            queuesp = AstNode::addNext(
                queuesp,
                newQueuePush(flp, epochQp, newTaskCountSelp(flp, m_taskEpochp, VAccess::READ)));
            queuesp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                queuesp,
                new AstAssign{flp, newTaskCountSelp(flp, m_taskPendingp, VAccess::WRITE),
                              new AstAdd{flp, newTaskCountSelp(flp, m_taskPendingp, VAccess::READ),
                                         new AstConst{flp, AstConst::WidthedValue{}, 32, 1}}});
        } else {
            queuesp = AstNode::addNext(queuesp, newQueuePush(flp, epochQp, rd(m_matureEpochp)));
        }
        queuesp = AstNode::addNext(queuesp, newQueuePush(flp, killQp, newKillCountp(flp)));
        queuesp = AstNode::addNext(queuesp, incp(pendingp, 1));
        queuesp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
            queuesp, new AstFireEvent{flp, wr(eventp), false});
        // Mature the pending instances
        AstLoop* const matureLoopp = new AstLoop{flp};
        matureLoopp->addStmtsp(new AstLoopTest{flp, matureLoopp, rd(pendingp)});
        matureLoopp->addStmtsp(incp(pendingp, -1));
        if (m_ftaskp) {
            matureLoopp->addStmtsp(
                new AstAssign{flp, wr(processp), newQueuePop(flp, processQp, processDtp)});
        }
        matureLoopp->addStmtsp(new AstAssign{flp, wr(epochp), newQueuePop(flp, epochQp, u32p)});
        matureLoopp->addStmtsp(new AstAssign{flp, wr(killp), newQueuePop(flp, killQp, u32p)});
        keepsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
            keepsp,
            new AstIf{flp, new AstEq{flp, rd(clkTimep), newTimep()},
                      newQueuePush(flp, clkQp,
                                   new AstSub{flp, rd(clkCountp),
                                              new AstConst{flp, AstConst::WidthedValue{}, 64, 1}}),
                      newQueuePush(flp, clkQp, rd(clkCountp))});
        keepsp = AstNode::addNext(keepsp, incp(maturedp, 1));
        AstNodeExpr* const flushesp
            = m_ftaskp ? static_cast<AstNodeExpr*>(
                             newTaskCountSelp(flp, m_taskEpochp, VAccess::READ, rd(processp)))
                       : rd(m_matureEpochp);
        AstNodeExpr* keepCondp = new AstLogAnd{flp, new AstEq{flp, rd(epochp), flushesp},
                                               new AstEq{flp, rd(killp), newKillCountp(flp)}};
        if (m_ftaskp)
            keepCondp = new AstLogAnd{flp, newProcessLivep(flp, rd(processp)), keepCondp};
        matureLoopp->addStmtsp(new AstIf{flp, keepCondp, keepsp, dropsp});
        if (m_ftaskp) {
            // A process with no pending instance left keeps no count
            const auto countp = [&](AstVar* varp, VAccess access) {
                return newTaskCountSelp(flp, varp, access, rd(processp));
            };
            matureLoopp->addStmtsp(
                new AstAssign{flp, countp(m_taskPendingp, VAccess::WRITE),
                              new AstSub{flp, countp(m_taskPendingp, VAccess::READ),
                                         new AstConst{flp, AstConst::WidthedValue{}, 32, 1}}});
            AstNodeStmt* erasesp = nullptr;
            for (AstVar* const varp : {m_taskPendingp, m_taskEpochp}) {
                AstCMethodHard* const erasep
                    = new AstCMethodHard{flp, newUnitRefp(flp, varp, VAccess::WRITE),
                                         VCMethod::ASSOC_ERASE, rd(processp)};
                erasep->dtypeSetVoid();
                erasesp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(erasesp, erasep->makeStmt());
            }
            matureLoopp->addStmtsp(
                new AstIf{flp,
                          new AstEq{flp, countp(m_taskPendingp, VAccess::READ),
                                    new AstConst{flp, AstConst::WidthedValue{}, 32, 0}},
                          erasesp});
        }
        // Begin the matured instances whose leading clock occurred since they matured, in
        // their order
        AstQueueSel* const frontp
            = new AstQueueSel{flp, rd(clkQp), new AstConst{flp, AstConst::WidthedValue{}, 32, 0}};
        AstLoop* const beginLoopp = new AstLoop{flp};
        beginLoopp->addStmtsp(new AstLoopTest{
            flp, beginLoopp,
            new AstLogAnd{flp, rd(maturedp), new AstLt{flp, frontp, rd(clkCountp)}}});
        beginLoopp->addStmtsp(incp(maturedp, -1));
        beginLoopp->addStmtsp(newQueuePop(flp, clkQp, u64p)->makeStmt());
        beginp->addStmtsp(beginsp);
        // In a process of its own, with its own copies of the inputs
        AstFork* const beginForkp = new AstFork{flp, VJoinType::JOIN_NONE};
        beginForkp->immediateStart(true);
        beginForkp->addForksp(new AstForkItem{flp, beginp});
        beginLoopp->addStmtsp(beginForkp);
        AstSenTree* const senTreep
            = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_EVENT, rd(eventp)}};
        senTreep->addSensesp(clockp->sensesp()->cloneTree(true));
        AstAlwaysObserved* const runnerp = new AstAlwaysObserved{flp, senTreep, matureLoopp};
        runnerp->addStmtsp(beginLoopp);
        // The occurrences of the leading clock
        AstAlways* const clockAlwaysp
            = new AstAlways{flp, VAlwaysKwd::ALWAYS, clockp, incp(clkCountp, 1)};
        clockAlwaysp->addStmtsp(new AstAssign{flp, wr(clkTimep), newTimep()});
        queuesAnchorp()->addNextHere(runnerp);
        queuesAnchorp()->addNextHere(clockAlwaysp);
        return newIfAssertOn(nodep->controlVarp(), queuesp, nodep->directive(), nodep->userType());
    }

    // The action lists of a concurrent assertion that run in a process of their own: a jump that
    // V3LinkJump made to a block outside them cannot leave that process. The loop exit after a
    // $finish in a loop of the procedure only ends that loop, so it is dropped and the $finish
    // stays; any other such jump is reported as unsupported. A cover deleted without coverage
    // takes its actions along, so it is left alone.
    void dropOutwardActionJumps(AstNodeCoverOrAssert* nodep) {
        const AstCover* const coverp = VN_CAST(nodep, Cover);
        if (coverp && !coverp->isSeqEvent() && !v3Global.opt.coverageUser()) return;
        // Only for concurrent assertions; an AstAssertIntrinsic is always immediate
        UASSERT_OBJ(!nodep->immediate(), nodep, "Immediate assertion");
        AstNode* failsp = nullptr;
        if (AstAssert* const assertp = VN_CAST(nodep, Assert)) failsp = assertp->failsp();
        std::unordered_set<const AstJumpBlock*> innerps;
        std::vector<AstJumpGo*> gops;
        for (AstNode* const listp : {failsp, static_cast<AstNode*>(nodep->passsp())}) {
            for (AstNode* np = listp; np; np = np->nextp()) {
                np->foreach([&](const AstJumpBlock* blockp) { innerps.insert(blockp); });
            }
        }
        for (AstNode* const listp : {failsp, static_cast<AstNode*>(nodep->passsp())}) {
            for (AstNode* np = listp; np; np = np->nextp()) {
                np->foreach([&](AstJumpGo* gop) {
                    if (!innerps.count(gop->blockp())) gops.push_back(gop);
                });
            }
        }
        for (AstJumpGo* const gop : gops) {
            // As V3LinkJump visit(AstFinish) adds it, and nothing else does: next to the
            // $finish, with the $finish's own file line, to the jump block around the loop (which
            // V3Width may have converted from a foreach)
            const AstFinish* const finishp = VN_CAST(gop->backp(), Finish);
            const bool finishExit
                = finishp && finishp->nextp() == gop && gop->fileline() == finishp->fileline();
            if (finishExit) {
                // Never the head of a list, it follows its $finish
                VL_DO_DANGLING(pushDeletep(gop->unlinkFrBack()), gop);
                continue;
            }
            gop->v3warn(E_UNSUPPORTED, "Unsupported: control transfer out of a concurrent"
                                       " assertion action block, which runs in a process of"
                                       " its own");
            // Keep the action list non-empty
            gop->replaceWith(new AstBegin{gop->fileline(), "", nullptr, true});
            VL_DO_DANGLING(pushDeletep(gop), gop);
        }
    }

    // Collect the variables 'nodep' reads outside the action blocks of immediate assertions
    static void collectNonActionReads(AstNode* nodep, std::unordered_set<const AstVar*>& readsr) {
        for (; nodep; nodep = nodep->nextp()) {
            const AstNodeVarRef* const refp = VN_CAST(nodep, NodeVarRef);
            if (refp && refp->access().isReadOrRW()) readsr.emplace(refp->varp());
            const AstNodeCoverOrAssert* const assertp = VN_CAST(nodep, NodeCoverOrAssert);
            if (assertp && assertp->immediate()) {
                collectNonActionReads(assertp->propp(), readsr);
                continue;
            }
            collectNonActionReads(nodep->op1p(), readsr);
            collectNonActionReads(nodep->op2p(), readsr);
            collectNonActionReads(nodep->op3p(), readsr);
            collectNonActionReads(nodep->op4p(), readsr);
        }
    }
    void visitAssertionIterate(AstNodeCoverOrAssert* nodep, AstNodeStmt* failsp) {
        FileLine* const flp = nodep->fileline();
        const bool obsDeferred = nodep->userType() == VAssertType::OBSERVED_DEFERRED_IMMEDIATE;
        // A final deferred assertion runs its action immediately without --timing, in a task or
        // function or under a fork, sharing no queue between processes, and in a final
        // procedure, after which no Postponed region runs (IEEE 1800-2023 9.2.3)
        const bool deferred = obsDeferred
                              || (nodep->userType() == VAssertType::FINAL_DEFERRED_IMMEDIATE
                                  && v3Global.opt.timing().isSetTrue() && !m_ftaskp
                                  && !m_inSpawnedFork && !VN_IS(m_procedurep, Final));
        if (obsDeferred && (!v3Global.opt.timing().isSetTrue() || m_ftaskp || m_inSpawnedFork)) {
            if (v3Global.opt.timing().isSetFalse()) {
                nodep->v3warn(E_NOTIMING,
                              "Observed deferred immediate assertion requires --timing");
            } else if (!v3Global.opt.timing().isSetTrue()) {
                nodep->v3warn(E_NEEDTIMINGOPT,
                              "Use --timing or --no-timing to specify how observed deferred "
                              "immediate assertions should be handled");
            } else {
                // Under fork...join_any/join_none, instances of a branch may run at once, but
                // would share one queue
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Observed deferred immediate assertion in "
                                  << (m_ftaskp ? "a task or function."
                                               : "fork...join_any or fork...join_none."));
            }
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        if (m_beginp && nodep->name() == "") nodep->name(m_beginp->name());
        // What an immediate assertion's action block reads does not wake an always_comb
        // (IEEE 1800-2023 9.2.2.2.1), so mark its references for V3Sched. A variable the
        // always_comb also reads elsewhere stays a sensitivity, even if an optimization removes
        // that read, so is not marked.
        if (nodep->immediate()) {
            for (AstNode* const actionsp :
                 {static_cast<AstNode*>(failsp), static_cast<AstNode*>(nodep->passsp())}) {
                if (!actionsp) continue;
                actionsp->foreachAndNext([this](AstNodeVarRef* refp) {
                    if (!m_combReads.count(refp->varp())) refp->inAssertAction(true);
                });
                actionsp->foreachAndNext(
                    [](AstNodeFTaskRef* refp) { refp->inAssertAction(true); });
            }
        }
        VL_RESTORER(m_inlineAction);
        m_inlineAction = false;
        VL_RESTORER(m_taskMature);
        m_taskMature = false;
        // The waits of a concurrent assertion's attempts and actions are not those of the
        // process, so not its flush points
        struct WaitsIsolation final {
            std::vector<AstNode*>& m_waitsr;  // The process's waits
            std::vector<AstNode*> m_saved;  // Those before the assertion
            const bool m_on;  // Isolating
            WaitsIsolation(std::vector<AstNode*>& waitsr, bool on)
                : m_waitsr{waitsr}
                , m_on{on} {
                if (m_on) std::swap(m_saved, m_waitsr);
            }
            ~WaitsIsolation() {
                if (m_on) std::swap(m_saved, m_waitsr);
            }
        };
        const WaitsIsolation waitsIsolation{m_obsWaitsp, !nodep->immediate()};
        // A const cast takes its value when a procedural concurrent assertion is queued, at its
        // statement (IEEE 1800-2023 16.14.6.1). The attempt gets its own copy (see V3Fork), and
        // so does each entry of its queued actions (see newQueuedAction).
        // Inner casts first, so an outer one reads their copies. A cast of variables declared
        // in the assertion, e.g. in an action block, only has their values there.
        // Those of a concurrent assertion in an action block are its own.
        std::vector<AstConstCast*> castps;  // In post-order, so inner ones first
        const std::function<void(AstNode*)> collect = [&](AstNode* np) {
            for (; np; np = np->nextp()) {
                const AstNodeCoverOrAssert* const assertp = VN_CAST(np, NodeCoverOrAssert);
                if (assertp && !assertp->immediate()) continue;
                collect(np->op1p());
                collect(np->op2p());
                collect(np->op3p());
                collect(np->op4p());
                if (AstConstCast* const castp = VN_CAST(np, ConstCast)) castps.push_back(castp);
            }
        };
        collect(nodep->op1p());
        collect(nodep->op2p());
        collect(nodep->op3p());
        collect(nodep->op4p());
        std::unordered_set<const AstVar*> localps;
        nodep->foreach([&](const AstVar* varp) { localps.insert(varp); });
        for (AstConstCast* const castp : castps) {
            AstNodeExpr* const exprp = castp->lhsp();
            const bool local = exprp->exists([&](const AstNode* np) {
                const AstNodeVarRef* const refp = VN_CAST(np, NodeVarRef);
                return VN_IS(np, LambdaArgRef) || (refp && localps.count(refp->varp()));
            });
            // Otherwise visit(AstConstCast) takes the current value of the expression
            if (!m_procedurep || nodep->immediate() || local) continue;
            FileLine* const castFlp = castp->fileline();
            AstVar* const varp
                = newModuleTemp(castFlp, m_actionNames.get("Const"), exprp->dtypep(), m_modp);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            nodep->addHereThisAsNext(new AstAssign{
                castFlp, new AstVarRef{castFlp, varp, VAccess::WRITE}, exprp->unlinkFrBack()});
            castp->replaceWith(new AstVarRef{castFlp, varp, VAccess::READ});
            VL_DO_DANGLING(pushDeletep(castp), castp);
        }

        // Only a concurrent assertion has a property or sequence expression, so visit(AstFuture)
        // rejects future value functions in immediate assertions and $cast (IEEE 1800-2023 16.9.4)
        if (!nodep->immediate()) AssertDeFutureVisitor{nodep->propp(), m_modp, m_modPastNum++};

        // A $past in an action, lowered below, keeps it inline, see actionRunsReactive
        const auto hasPast = [](const AstNode* actionsp) {
            return actionsp
                   && actionsp->existsAndNext([](const AstNode* np) { return VN_IS(np, Past); });
        };
        const AstAssert* const failAssertp = VN_CAST(nodep, Assert);
        const bool passPast = hasPast(nodep->passsp());
        const bool failPast = failAssertp && hasPast(failAssertp->failsp());
        iterateAndNextNull(nodep->sentreep());
        {
            // The actions of a concurrent assertion run in a process of their own, so its
            // nested assertions are not of the procedure's process
            VL_RESTORER(m_inConcurrentAction);
            m_inConcurrentAction |= !nodep->immediate();
            if (AstAssert* const assertp = VN_CAST(nodep, Assert)) {
                iterateAndNextNull(assertp->failsp());
            } else if (AstAssertIntrinsic* const assertp = VN_CAST(nodep, AssertIntrinsic)) {
                iterateAndNextNull(assertp->failsp());
            } else {
                // Called only for an Assert, AssertIntrinsic or Cover (visit(AstRestrict) has its
                // own iteration)
                iterateAndNextNull(VN_AS(nodep, Cover)->coverincsp());
            }
            iterateAndNextNull(nodep->passsp());
        }
        AstSenTree* sentreep = nodep->sentreep();
        AstSenTree* procClockp = nullptr;  // Leading clock of a procedural assertion
        // Clocking the actions of a concurrent assertion, not a property expression, whose
        // process runs its actions
        AstSenTree* actionSenTreep = nullptr;
        if (nodep->immediate()) {
            UASSERT_OBJ(!sentreep, nodep, "Immediate assertions don't have sensitivity");
        } else {
            UASSERT_OBJ(sentreep, nodep, "Concurrent assertions must have sensitivity");
            // Explicit inline clock differs from the enclosing always: hoist
            // and warn. To support this need queue of asserts to activate.
            if (m_procedurep && !nodep->senFromAlways()) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Procedural concurrent assertion with"
                              " clocking event inside always (IEEE 1800-2023 16.14.6)");
                // Its actions move with it, out of the procedure
                dropOutwardActionJumps(nodep);
                // Leave an empty statement, so a block of the procedure whose only statement
                // this was keeps a body (V3LinkJump's disable target wrapper expects one)
                nodep->replaceWith(new AstBegin{flp, "", nullptr, true});
                m_procedurep->addNext(
                    new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, nodep});
                return;  // Later iterate will pick up
            }
            // A task is not a process. An assertion in it that matures is queued by the
            // process calling the task (see newMatureInstance), else it gets its own beside the
            // task.
            if (m_ftaskp) {
                m_taskMature = taskAssertionMatures(nodep);
                // Outside the task, its variables are out of scope, other than the automatic
                // ones of the assertion's own blocks, and those whose value an instance that
                // matures takes when queued
                std::unordered_set<const AstVar*> ownps;
                nodep->foreach([&](const AstVar* varp) {
                    if (varp->lifetime().isAutomatic()) ownps.emplace(varp);
                });
                const AstVarRef* localRefp = nullptr;
                nodep->exists([&](const AstVarRef* refp) {
                    const AstVar* const varp = refp->varp();
                    if (varp->isFuncLocal() && !ownps.count(varp)
                        && !(m_taskMature && varp->lifetime().isAutomatic())) {
                        localRefp = refp;
                    }
                    return localRefp != nullptr;
                });
                if (localRefp && m_taskMature) {
                    localRefp->v3warn(E_UNSUPPORTED,
                                      "Unsupported: Procedural concurrent assertion in a task "
                                      "referencing a static variable of the task "
                                          << localRefp->varp()->prettyNameQ()
                                          << " (IEEE 1800-2023 16.14.6).");
                    VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
                    return;
                }
                if (localRefp) {
                    localRefp->v3warn(E_UNSUPPORTED,
                                      "Unsupported: Procedural concurrent assertion in a task "
                                      "referencing a variable of the task "
                                          << localRefp->varp()->prettyNameQ()
                                          << " (IEEE 1800-2023 16.14.6).");
                    VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
                    return;
                }
            }
            if (m_ftaskp && !m_taskMature) {
                // Its actions move with it, out of the task
                dropOutwardActionJumps(nodep);
                // As above, for a block under a fork item in the task
                nodep->replaceWith(new AstBegin{flp, "", nullptr, true});
                m_ftaskp->addNextHere(
                    new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, nodep});
                return;  // Later iterate will pick up
            }
            sentreep->unlinkFrBack();
            const AstPropSpec* const specp = VN_CAST(nodep->propp(), PropSpec);
            const AstNode* propp = specp ? specp->propp() : nodep->propp();
            if (const AstSampled* const sampledp = VN_CAST(propp, Sampled)) {
                propp = sampledp->exprp();
            }
            if (!VN_IS(propp, PExpr)) actionSenTreep = sentreep;
            if (m_procedurep || m_ftaskp) {
                procClockp = sentreep;
                sentreep = nullptr;
            }
        }
        // The attempt of a property expression runs in a forked process (assertBody), with its
        // actions
        if (!nodep->immediate() && v3Global.opt.timing().isSetTrue()) {
            const AstPropSpec* const specp = VN_CAST(nodep->propp(), PropSpec);
            const AstNode* propp = specp ? specp->propp() : nodep->propp();
            // V3AssertPre samples the whole property; visit(AstSampled) removes that later
            if (const AstSampled* const sampledp = VN_CAST(propp, Sampled)) {
                propp = sampledp->exprp();
            }
            if (VN_IS(propp, PExpr)) dropOutwardActionJumps(nodep);
        }
        //
        const string& message = nodep->name();
        AstNodeStmt* passsp = nodep->passsp();
        const AstNodeStmt* defaultFailsp = nullptr;  // Fail action made here, if no action
        if (passsp) passsp->unlinkFrBackWithNext();
        if (AstAssert* const assertp = VN_CAST(nodep, Assert)) {
            failsp = assertp->failsp();
        } else if (AstAssertIntrinsic* const assertp = VN_CAST(nodep, AssertIntrinsic)) {
            failsp = assertp->failsp();
        }
        if (failsp) failsp->unlinkFrBackWithNext();

        bool selfDestruct = false;
        bool passspGated = false;
        const AstCover* const coverp = VN_CAST(nodep, Cover);
        // A sequence event control is not an assertion directive; no assertion control
        const bool seqEvent = coverp && coverp->isSeqEvent();
        if (coverp) {
            ++m_statCover;
            if (seqEvent) {
                // Keep the event-fire action, with no coverage bucket
            } else if (!v3Global.opt.coverageUser()) {
                selfDestruct = true;
            } else {
                // V3Coverage assigned us a bucket to increment.
                AstCoverInc* const covincp = VN_AS(coverp->coverincsp(), CoverInc);
                UASSERT_OBJ(covincp, coverp, "Missing AstCoverInc under assertion");
                covincp->unlinkFrBackWithNext();  // next() might have  AstAssign for trace
                if (message != "") covincp->declp()->comment(AstNode::prettyName(message));
                // IEEE 1800-2023 16.4.2: Deferred coverage is flushed like a pending report
                AstNodeStmt* creditsp = covincp;
                if (deferred) {
                    creditsp = newObservedDeferredCall(flp, covincp, nullptr, nodep->userType(),
                                                       nodep->directive(), nodep->controlVarp());
                    if (passsp) passsp = newObservedDeferredAction(flp, passsp, nodep);
                }
                if (passsp && actionSenTreep && !nodep->nfaLowered() && !passPast) {
                    passsp = newReactiveAction(nodep, actionSenTreep, passsp);
                }
                if (passsp) {
                    passsp = newIfAssertPassOn(nodep->controlVarp(), passsp, nodep->directive(),
                                               nodep->userType(),
                                               /*vacuous=*/false);
                    passspGated = true;
                    passsp = AstNode::addNext(creditsp, passsp);
                } else {
                    passsp = creditsp;
                }
            }
        } else if (VN_IS(nodep, Assert) || VN_IS(nodep, AssertIntrinsic)) {
            if (nodep->immediate()) {
                ++m_statAsImm;
            } else {
                ++m_statAsNotImm;
            }
            if (!failsp) {
                failsp = newFireAssertUnchecked(
                    nodep, VN_IS(nodep, AssertIntrinsic) ? "'$cast' failed." : "'assert' failed.");
                defaultFailsp = failsp;
            }
            if (deferred) {
                if (passsp) passsp = newObservedDeferredAction(flp, passsp, nodep);
                if (failsp) failsp = newObservedDeferredAction(flp, failsp, nodep);
            }
        } else {
            nodep->v3fatalSrc("Unknown node type");
        }

        VL_RESTORER(m_passsp);
        VL_RESTORER(m_failsp);
        VL_RESTORER(m_assertp);
        m_passsp = passsp;
        m_failsp = failsp;
        m_assertp = nodep;
        {
            VL_RESTORER_CLEAR(m_clauseActionsp);
            // Queue construction rewrites captured references. Make copies before any clause
            // takes the original action, which owns the shared static declarations.
            bool usedPass = false;
            bool usedFail = false;
            nodep->propp()->foreach([&](const AstPExprClause* const clausep) {
                AstNodeStmt* const actionp = clausep->pass() ? passsp : failsp;
                if (!actionp) return;
                bool& used = clausep->pass() ? usedPass : usedFail;
                if (used) {
                    m_clauseActionsp.emplace(clausep,
                                             V3AssertCommon::cloneAction(actionp, m_actionNames));
                }
                used = true;
            });
            iterate(nodep->propp());
            for (const auto& entry : m_clauseActionsp) pushDeletep(entry.second);
        }

        AstNode* propExprp;
        AstNodeExpr* disablep = nullptr;
        AstNodeExpr* matchCountp = nullptr;
        if (AstPropSpec* const specp = VN_CAST(nodep->propp(), PropSpec)) {
            propExprp = specp->propp()->unlinkFrBack();
            if (specp->disablep()) disablep = specp->disablep()->unlinkFrBack();
            matchCountp = specp->matchCountp();
        } else {
            propExprp = nodep->propp()->unlinkFrBack();
        }
        // A procedural concurrent assertion matures in the Observed region, see
        // newMatureInstance, unless it is lowered by V3AssertNfa, in a fork branch or an action
        // of a concurrent assertion, processes other than the procedure's, without timing, or
        // has an action that stays inline; in a task, as decided by taskAssertionMatures
        const bool isPExpr = VN_IS(propExprp, PExpr);
        bool mature = procClockp && VN_IS(nodep, Assert) && !nodep->nfaLowered() && !m_inForkBranch
                      && !m_inConcurrentAction && (!m_ftaskp || m_taskMature) && !seqEvent
                      && !selfDestruct && v3Global.opt.timing().isSetTrue();
        if (mature && isPExpr) mature = !m_inlineAction;
        if (mature && !isPExpr) {
            mature
                = !(passsp && actionStaysInline(passsp)) && !(failsp && actionStaysInline(failsp));
            // Its actions run in the Reactive region (IEEE 1800-2023 4.4.2.6)
            if (mature && passsp) passsp = newQueuedAction(flp, passsp);
            if (mature && failsp) failsp = newQueuedAction(flp, failsp);
        }
        UASSERT_OBJ(!m_taskMature || mature, nodep, "Task assertion expected to mature");
        if (m_taskMature) ++m_statTaskMature;
        // Otherwise those of a clocked assertion run in the Reactive region from a process on
        // its clock. V3AssertNfa made those of what it lowered so already, except a default.
        if (!mature && actionSenTreep && !coverp) {
            if (passsp && !nodep->nfaLowered() && !passPast) {
                passsp = newReactiveAction(nodep, actionSenTreep, passsp);
            }
            if (failsp && (!nodep->nfaLowered() || failsp == defaultFailsp) && !failPast) {
                failsp = newReactiveAction(nodep, actionSenTreep, failsp);
            }
        }
        bool passspAlreadyGated = false;
        if (passsp && VN_IS(passsp, If)) passspAlreadyGated = VN_AS(passsp, If)->user1();
        if (passsp && !passspGated && !passspAlreadyGated && !VN_IS(propExprp, PExpr)
            && !seqEvent) {
            passsp = newIfAssertPassOn(nodep->controlVarp(), passsp, nodep->directive(),
                                       nodep->userType(),
                                       /*vacuous=*/false);
        }
        if (failsp && !VN_IS(propExprp, PExpr) && !nodep->failsGated()) {
            failsp = newIfAssertFailOn(nodep->controlVarp(), failsp, nodep->directive(),
                                       nodep->userType());
        }
        // Also one left where it is
        if (!nodep->immediate() && !isPExpr) {
            if (passsp) passsp = V3AssertCommon::newSpawnedAction(passsp);
            if (failsp) failsp = V3AssertCommon::newSpawnedAction(failsp);
        }
        if (coverp && matchCountp && passsp) {
            // Convert the match count into a loop that decrements a temporary variable until it
            // reaches zero.
            matchCountp->unlinkFrBack();
            AstVar* const remainingp = new AstVar{
                flp, VVarType::MODULETEMP, m_matchCountNames.get(""), matchCountp->dtypep()};
            remainingp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(remainingp);
            AstNodeStmt* const replaysp
                = new AstAssign{flp, new AstVarRef{flp, remainingp, VAccess::WRITE}, matchCountp};
            AstLoop* const loopp = new AstLoop{flp};
            loopp->addStmtsp(
                new AstLoopTest{flp, loopp, new AstVarRef{flp, remainingp, VAccess::READ}});
            loopp->addStmtsp(passsp);
            loopp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, remainingp, VAccess::WRITE},
                              new AstSub{flp, new AstVarRef{flp, remainingp, VAccess::READ},
                                         new AstConst{flp, AstConst::WidthedValue{},
                                                      remainingp->dtypep()->width(), 1}}});
            replaysp->addNext(loopp);
            passsp = replaysp;
        }
        // A discarded cover runs no action, so also not at the end of simulation.
        if (selfDestruct) {
            if (AstPExpr* const pexprp = VN_CAST(propExprp, PExpr)) {
                if (pexprp->finalp()) pushDeletep(pexprp->finalp()->unlinkFrBack());
            }
        }
        AstNodeStmt* bodysp = assertBody(nodep, propExprp, passsp, failsp);
        // A matured attempt begins at once, in the Observed region
        if (mature) {
            if (AstFork* const forkp = VN_CAST(bodysp, Fork)) forkp->immediateStart(true);
        }
        if (disablep) bodysp = new AstIf{flp, new AstLogNot{flp, disablep}, bodysp};
        if (mature) {
            bodysp = newMatureInstance(nodep, bodysp, procClockp);
            procClockp = nullptr;
        } else if (!seqEvent && !nodep->nfaLowered()) {
            // V3AssertNfa gates the start of each attempt, as Off leaves the attempts already
            // executing (IEEE 1800-2023 20.11)
            bodysp = newIfAssertOn(nodep->controlVarp(), bodysp, nodep->directive(),
                                   nodep->userType());
        }
        if (procClockp) VL_DO_DANGLING(pushDeletep(procClockp), procClockp);
        bodysp->foreach([](AstNodeVarRef* nodep) {
            nodep->fileline()->modifyWarnOff(V3ErrorCode::SYNCASYNCNET, true);
        });

        if (passsp && !passsp->backp()) VL_DO_DANGLING(pushDeletep(passsp), passsp);
        if (failsp && !failsp->backp()) VL_DO_DANGLING(pushDeletep(failsp), failsp);

        // Install it
        if (selfDestruct) {
            // Delete it after making the tree.  This way we can tell the user
            // if it wasn't constructed nicely or has other errors without needing --coverage.
            VL_DO_DANGLING(bodysp->deleteTree(), bodysp);
            if (sentreep) VL_DO_DANGLING(sentreep->deleteTree(), sentreep);
            nodep->unlinkFrBack();
        } else {
            if (sentreep) {
                // The process of the concurrent assertion is clocked by it
                UASSERT_OBJ(m_assertCoverp, nodep, "Concurrent assertion not in its process");
                m_assertCoverp->keyword(VAlwaysKwd::ALWAYS);
                m_assertCoverp->sentreep(sentreep);
            }
            nodep->replaceWith(bodysp);
        }
        // Bye
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    bool isEmptyStmt(AstNode* nodep) {
        if (!nodep) return true;
        if (AstBegin* const beginp = VN_CAST(nodep, Begin)) {
            if (beginp->declsp()) return false;
            for (AstNode* const stmtp : beginp->stmtspList()) {
                if (!isEmptyStmt(stmtp)) return false;
            }
            return true;
        }
        return false;
    }

    // VISITORS
    void visit(AstIf* nodep) override {
        if (!nodep->user1SetOnce()) {
            if (nodep->uniquePragma() || nodep->unique0Pragma() || nodep->priorityPragma()) {
                const bool priority = nodep->priorityPragma();
                // A unique or unique0 if evaluates all its conditions (IEEE 1800-2023 12.4.2).
                // If one has a side effect, evaluate each once, in order, for the check and the
                // statement.
                bool lift = false;
                for (const AstIf* ifp = nodep; !priority && ifp; ifp = VN_CAST(ifp->elsesp(), If))
                    lift |= !ifp->condp()->isPure();
                AstIf* ifp = nodep;
                AstIf* lastifp = nodep;
                AstNodeExpr* propp = nullptr;
                bool hasDefaultElse = false;
                do {
                    // If this statement ends with 'else if', then nextIf will point to the
                    // nextIf statement.  Otherwise it will be null.
                    AstIf* const nextifp = VN_CAST(ifp->elsesp(), If);
                    iterateAndNextNull(ifp->condp());
                    if (lift) {
                        ++m_statLiftedUniqueConds;
                        liftExpr(nodep, ifp->condp());
                    }

                    // Recurse into the true case.
                    iterateAndNextNull(ifp->thensp());

                    // If the last else is not an else if, recurse into that too.
                    if (ifp->elsesp() && !nextifp) {  //
                        iterateAndNextNull(ifp->elsesp());
                    }

                    // Build a bitmask of the true predicates
                    if (!priority) {
                        AstNodeExpr* const predp = ifp->condp()->cloneTreePure(false);
                        if (propp) {
                            propp = new AstConcat{nodep->fileline(), predp, propp};
                        } else {
                            propp = predp;
                        }
                    }

                    // Record if this ends with an 'else' that does not have an if.  An else
                    // holding only CoverIncs is one V3Coverage added; a source 'else ;' still
                    // holds an empty begin.
                    if (!nextifp) {
                        for (const AstNode* const stmtp : ifp->elsespList()) {
                            if (!VN_IS(stmtp, CoverInc)) {
                                hasDefaultElse = true;
                                break;
                            }
                        }
                    }

                    lastifp = ifp;
                    ifp = nextifp;
                } while (ifp);

                const bool allow_none = nodep->unique0Pragma();

                // A priority if is violated when no condition is true, so when it reaches its end
                // without an 'else'. Report there, as it evaluates its conditions in order up to
                // the first true one (IEEE 1800-2023 12.4.2).
                if (priority) {
                    if (!hasDefaultElse) {
                        lastifp->addElsesp(newFireAssert(nodep, VAssertDirectiveType::VIOLATION_IF,
                                                         VAssertType::PRIORITY,
                                                         "'priority if' statement violated"));
                    }
                    return;
                }

                // Empty case means no property
                if (!propp) propp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};

                // Note: if this ends with an 'else', then we don't need to validate that one of
                // the predicates evaluates to true.
                AstNodeExpr* const okp
                    = (allow_none || hasDefaultElse)
                          ? static_cast<AstNodeExpr*>(new AstOneHot0{nodep->fileline(), propp})
                          : static_cast<AstNodeExpr*>(new AstOneHot{nodep->fileline(), propp});
                const VAssertType assertType
                    = nodep->uniquePragma() ? VAssertType::UNIQUE : VAssertType::UNIQUE0;
                AstIf* const checkifp
                    = new AstIf{nodep->fileline(), new AstLogNot{nodep->fileline(), okp},
                                newFireAssert(nodep, VAssertDirectiveType::VIOLATION_IF,
                                              assertType, "'unique if' statement violated")};
                checkifp->isBoundsCheck(true);  // To avoid LATCH warning
                checkifp->branchPred(VBranchPred::BP_UNLIKELY);
                // The statement runs also after a violation (IEEE 1800-2023 12.4.2)
                nodep->replaceWith(checkifp);
                checkifp->addNextHere(nodep);
                return;
            }
        }

        iterateChildren(nodep);

        if (nodep->user2()) {
            // Combine consecutive assertOn checks if possible
            if (AstIf* const backp = VN_CAST(nodep->backp(), If)) {
                if (backp->nextp() == nodep  //
                    && backp->user2()  //
                    && backp->condp()->sameTree(nodep->condp())) {
                    ++m_statAssertOnCombined;
                    backp->addThensp(nodep->thensp()->unlinkFrBackWithNext());
                    nodep->unlinkFrBack();
                    VL_DO_DANGLING(pushDeletep(nodep), nodep);
                    return;
                }
            }
            // Combine nested assertOn checks if possible
            if (nodep->thensp() && !nodep->thensp()->nextp() && isEmptyStmt(nodep->elsesp())) {
                AstIf* const checkp = VN_CAST(nodep->thensp(), If);
                if (checkp  //
                    && checkp->user2()  //
                    && checkp->condp()->sameTree(nodep->condp())) {
                    ++m_statAssertOnCombined;
                    nodep->addThensp(checkp->thensp()->unlinkFrBackWithNext());
                    VL_DO_DANGLING(pushDeletep(checkp->unlinkFrBack()), checkp);
                    return;
                }
            }
            return;
        }

        // Swap assertOn check with single statement 'if' statement to bubble up for combining
        // Note we can't just swap the conditions as they two Ifs have different flags,
        // so swapping the Ifs themeselves then swapping back the bodies.
        if (nodep->condp()->isPure()) {
            if (nodep->thensp() && !nodep->thensp()->nextp() && isEmptyStmt(nodep->elsesp())) {
                AstIf* const checkp = VN_CAST(nodep->thensp(), If);
                if (checkp && checkp->user2()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(checkp->unlinkFrBack());
                    nodep->addThensp(checkp->thensp()->unlinkFrBackWithNext());
                    checkp->addThensp(nodep);
                    return;
                }
            }
            if (nodep->elsesp() && !nodep->elsesp()->nextp() && isEmptyStmt(nodep->thensp())) {
                AstIf* const checkp = VN_CAST(nodep->elsesp(), If);
                if (checkp && checkp->user2()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(checkp->unlinkFrBack());
                    nodep->addElsesp(checkp->thensp()->unlinkFrBackWithNext());
                    checkp->addThensp(nodep);
                    return;
                }
            }
        }
    }

    // Evaluate an expression of a statement once, before the statement, into a temporary that
    // the statement, and the checks that read the expression again, read instead
    void liftExpr(AstNodeStmt* stmtp, AstNodeExpr* exprp) {
        FileLine* const fl = exprp->fileline();
        AstVar* const varp
            = new AstVar{fl, VVarType::BLOCKTEMP, m_caseTempNames.get(stmtp), exprp->dtypep()};
        exprp->replaceWith(new AstVarRef{fl, varp, VAccess::READ});
        stmtp->addHereThisAsNext(
            new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE}, exprp});
        if (m_ftaskp) {
            varp->funcLocal(true);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_ftaskp->prependDeclsp(varp);
        } else {
            m_modp->prependStmtsp(varp);
        }
        VIsCached::clearCacheTree();
    }

    // A unique, unique0 or parallel case compares the expression with all its items (IEEE
    // 1800-2023 12.5.3). If an item expression has a side effect, evaluate each item expression
    // once, in order, for the check and the statement, after the case expression, which is
    // evaluated first, unless 'exprLifted' says it already is.
    void liftCaseItems(AstCase* nodep, bool exprLifted) {
        std::vector<AstNodeExpr*> exprps;  // Item expressions, and the bounds of ranges
        for (const AstCaseItem* const itemp : nodep->itemspList()) {
            for (AstNodeExpr* const icondp : itemp->condspList()) {
                if (const AstInsideRange* const rcondp = VN_CAST(icondp, InsideRange)) {
                    exprps.push_back(rcondp->lhsp());
                    exprps.push_back(rcondp->rhsp());
                } else {
                    exprps.push_back(icondp);
                }
            }
        }
        if (std::all_of(exprps.begin(), exprps.end(),
                        [](AstNodeExpr* exprp) { return exprp->isPure(); })) {
            return;
        }
        // An item expression could change what the case expression reads
        if (!exprLifted && !VN_IS(nodep->exprp(), Const)) {
            ++m_statLiftedUniqueConds;
            liftExpr(nodep, nodep->exprp());
        }
        m_statLiftedUniqueConds += exprps.size();
        for (AstNodeExpr* const exprp : exprps) liftExpr(nodep, exprp);
    }

    //========== Case assertions
    void visit(AstCase* nodep) override {
        // Introduce temporary variable for AstCase if needed - it is done here and not in V3Case
        // because this phase is before V3Scope and V3Case is not. Doing it before V3Scope ensures
        // that V3Scope will take care of a scope creation
        // We also need to do it before V3Begin, co that pragmas like `unique0` also work correctly
        const bool exprLifted = !nodep->exprp()->isPure();
        if (exprLifted) {
            ++m_statLiftedCaseExprs;
            liftExpr(nodep, nodep->exprp());
        }
        iterateChildren(nodep);
        if (!nodep->user1SetOnce()) {
            bool has_default = false;
            for (AstCaseItem* const itemp : nodep->itemspList()) {
                if (itemp->isDefault()) has_default = true;
            }
            const AstNodeDType* exprDtypep = nodep->exprp()->dtypep()->skipRefp();

            VAssertType assertType = VAssertType::INTERNAL;
            if (nodep->priorityPragma()) {
                assertType = VAssertType::PRIORITY;
            } else if (nodep->uniquePragma()) {
                assertType = VAssertType::UNIQUE;
            } else if (nodep->unique0Pragma()) {
                assertType = VAssertType::UNIQUE0;
            }

            string valFmt;
            if (exprDtypep->isIntegralOrPacked())
                valFmt = " for '" + cvtToStr(exprDtypep->widthMin()) + "'h%X'";
            if (nodep->fullPragma() || nodep->priorityPragma()) {
                // Need to add a default if there isn't one already
                ++m_statAsFull;
                if (!has_default) {
                    nodep->addItemsp(new AstCaseItem{
                        nodep->fileline(), nullptr /*DEFAULT*/,
                        newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                      nodep->pragmaString() + ", but non-match found" + valFmt,
                                      valFmt.empty() ? nullptr
                                                     : nodep->exprp()->cloneTreePure(false))});
                }
            }
            if (nodep->parallelPragma() || nodep->uniquePragma() || nodep->unique0Pragma()) {
                // Need to check that one, and only one of the case items match at any moment
                // If there's a default, we allow none to match, else exactly one must match
                ++m_statAsFull;
                if (!has_default && !nodep->itemsp()) {
                    // Not parallel, but harmlessly so.
                } else {
                    liftCaseItems(nodep, exprLifted);
                    AstNodeExpr* propp = nullptr;
                    for (AstCaseItem* const itemp : nodep->itemspList()) {
                        AstNodeExpr* itembitp = nullptr;
                        for (AstNodeExpr* const icondp : itemp->condspList()) {
                            AstNodeExpr* onep;
                            if (AstInsideRange* const rcondp = VN_CAST(icondp, InsideRange)) {
                                onep = rcondp->newAndFromInside(
                                    nodep->exprp()->cloneTreePure(true),
                                    rcondp->lhsp()->cloneTreePure(true),
                                    rcondp->rhsp()->cloneTreePure(true), true);
                            } else if (icondp->width() != nodep->exprp()->width()) {
                                // A case inside item of its own width (see V3Width)
                                onep = AstNodeBiop::newTypedCompare(
                                    VNType::EqWild, itemp->fileline(),
                                    nodep->exprp()->cloneTreePure(false),
                                    icondp->cloneTreePure(false));
                            } else if (nodep->casex() || nodep->casez() || nodep->caseInside()) {
                                onep = AstEqWild::newTyped(itemp->fileline(),
                                                           nodep->exprp()->cloneTreePure(false),
                                                           icondp->cloneTreePure(false));
                            } else {
                                onep = AstEq::newTyped(icondp->fileline(),
                                                       nodep->exprp()->cloneTreePure(false),
                                                       icondp->cloneTreePure(false));
                            }
                            // OR together all conditions within the same case item
                            if (onep) {
                                if (itembitp) {
                                    itembitp = new AstOr{icondp->fileline(), onep, itembitp};
                                } else {
                                    itembitp = onep;
                                }
                            }
                        }
                        if (itembitp) {
                            if (propp) {
                                propp = new AstConcat{itemp->fileline(), itembitp, propp};
                            } else {
                                propp = itembitp;
                            }
                        }
                    }
                    // Empty case means no property
                    if (!propp) propp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
                    const bool allow_none = has_default || nodep->unique0Pragma();
                    // The following assertion looks as below.
                    // if (!$onehot(propp)) begin
                    //     if (propp == '0) begin if (!allow_none) $error("none match"); end
                    //     else $error("multiple match");
                    // end
                    AstNodeExpr* const ohotp = new AstOneHot{nodep->fileline(), propp};
                    AstConst* const zerop = new AstConst{
                        nodep->fileline(), AstConst::WidthedValue{}, propp->width(), 0};
                    AstIf* const ohotIfp
                        = new AstIf{nodep->fileline(), new AstLogNot{nodep->fileline(), ohotp}};
                    AstIf* const zeroIfp = new AstIf{
                        nodep->fileline(),
                        new AstEq{nodep->fileline(), propp->cloneTreePure(false), zerop}};
                    AstNodeExpr* const exprp = nodep->exprp();
                    const string pragmaStr = nodep->pragmaString();
                    if (!allow_none)
                        zeroIfp->addThensp(
                            newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                          pragmaStr + ", but none matched" + valFmt,
                                          valFmt.empty() ? nullptr : exprp->cloneTreePure(false)));
                    zeroIfp->addElsesp(
                        newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                      pragmaStr + ", but multiple matches found" + valFmt,
                                      valFmt.empty() ? nullptr : exprp->cloneTreePure(false)));
                    ohotIfp->addThensp(zeroIfp);
                    ohotIfp->isBoundsCheck(true);  // To avoid LATCH warning
                    ohotIfp->branchPred(VBranchPred::BP_UNLIKELY);
                    nodep->addNotParallelp(ohotIfp);
                }
            }
        }
    }

    void visit(AstFuture* nodep) override {
        nodep->v3error("Future sampled value function called outside property or sequence "
                       "expression (IEEE 16.9.4)");
        nodep->replaceWith(new AstConst{nodep->fileline(), 0});
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    //========== Past
    // True if sentreep has an event that fires in the Observed region
    static bool isObservedEventClock(const AstSenTree* sentreep) {
        // Compiler-made events, of clocking blocks and sequences (the only MODULETEMP events
        // at this stage), fire in the Observed region
        for (const AstSenItem* itemp = sentreep->sensesp(); itemp;
             itemp = VN_AS(itemp->nextp(), SenItem)) {
            const AstNodeVarRef* const refp = itemp->varrefp();
            if (refp && refp->varp()->varType() == VVarType::MODULETEMP
                && refp->varp()->isEvent()) {
                return true;
            }
        }
        return false;
    }

    void visit(AstPast* nodep) override {
        // Checked before the expression is rewritten into its history
        if (reportNonStaticProperty(nodep->exprp())) {
            nodep->replaceWith(
                new AstConst{nodep->fileline(), AstConst::DTyped{}, nodep->dtypep()});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        // When clocked in the Observed region, the history of a nested sampled value function
        // would already be updated in the time step
        if (isObservedEventClock(nodep->sentreep())
            && nodep->exprp()->exists([](const AstPast*) { return true; })) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: sampled value function clocked by a"
                                         " clocking block or sequence event, of an expression"
                                         " with a nested sampled value function");
            nodep->replaceWith(
                new AstConst{nodep->fileline(), AstConst::DTyped{}, nodep->dtypep()});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        VL_RESTORER(m_inPast);
        if (!nodep->propertyTiming()) {
            // A $past below another one was already split with it
            if (!m_inPast) {
                if (AstNodeExpr* const newp = AssertPastSplitVisitor::split(nodep)) {
                    nodep->replaceWith(newp);
                    VL_DO_DANGLING(pushDeletep(nodep), nodep);
                    m_inPast = true;
                    iterate(newp);
                    return;
                }
            }
            m_inPast = true;
            nodep->initp(nodep->exprp()->cloneTreePure(false));
            { DefaultSampledValueVisitor{nodep->initp(), &m_checkerFormals}; }
        }
        AstNodeExpr* const initp = nodep->initp() ? nodep->initp()->unlinkFrBack() : nullptr;
        iterateChildren(nodep);
        uint32_t ticks = 1;
        if (nodep->ticksp()) {
            UASSERT_OBJ(VN_IS(nodep->ticksp(), Const), nodep,
                        "Expected constant ticks, checked in V3Width");
            ticks = VN_AS(nodep->ticksp(), Const)->toUInt();
        }
        UASSERT_OBJ(ticks >= 1, nodep, "0 tick should have been checked in V3Width");
        AstNodeExpr* const exprp = newSampledExpr(nodep->exprp()->unlinkFrBack());
        AstSenTree* const senTreep = nodep->sentreep()->unlinkFrBack();
        AstNodeExpr* inp = nullptr;
        // Deliberately emitted for every ftask $past; calls outside final take the normal stage
        if (VN_IS(m_procedurep, Final) || m_ftaskp) {
            // A sampling-tick finish reads one stage deeper (IEEE 1800-2023 16.9.3).
            FileLine* const flp = nodep->fileline();
            AstAlways* const alwaysp
                = getDelayedAlways(exprp, initp ? initp->cloneTreePure(false) : nullptr, senTreep,
                                   nodep->ownHistory());
            AstNodeExpr* const betweenTicksp = pastValueRef(alwaysp, flp, ticks, initp);
            AstNodeExpr* const onTickp = pastValueRef(alwaysp, flp, ticks + 1, initp);
            if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
            AstNodeExpr* const onTickCondp = new AstLogAnd{
                flp, new AstCExpr{flp, "vlSymsp->_vm_contextp__->executingFinal()", 1},
                new AstEq{flp, new AstVarRef{flp, getPastTickTimeVar(alwaysp), VAccess::READ},
                          new AstCExpr{flp, "vlSymsp->_vm_contextp__->finishPendingTime()", 64}}};
            AstCond* const condp = new AstCond{flp, onTickCondp, onTickp, betweenTicksp};
            condp->dtypeFrom(onTickp);
            inp = condp;
        } else {
            inp = getPastValue(exprp, initp, senTreep, ticks, nodep->ownHistory());
        }
        nodep->replaceWith(inp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    //========== Move $sampled down to read-only variables
    // Report a sampled value of a non-static class property, as sampled values and their
    // history are static, so not of each object. Return whether reported.
    static bool reportNonStaticProperty(const AstNode* exprp) {
        bool reported = false;
        exprp->foreach([&](const AstNodeVarRef* refp) {
            const AstVar* const varp = refp->varp();
            if (varp->isClassMember() && !varp->lifetime().isStatic()) {
                refp->v3warn(E_UNSUPPORTED,
                             "Unsupported: sampled value of non-static class property "
                                 << refp->prettyNameQ() << ".");
                reported = true;
            }
        });
        return reported;
    }
    void visit(AstSampled* nodep) override {
        if (nodep->user1()) return;
        reportNonStaticProperty(nodep->exprp());
        VL_RESTORER(m_inSampled);
        {
            m_inSampled = true;
            iterateChildren(nodep);
        }
        if (nodep->timed()) {
            // Kept for V3ActiveTop and V3Sampled
            nodep->user1(1);
            v3Global.setHasSampled();
            return;
        }
        if (nodep->exprp()) {
            nodep->replaceWith(nodep->exprp()->unlinkFrBack());
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        // Sampled values of automatic variables are their current values (IEEE 1800-2023 16.5.1)
        if (m_inSampled && !nodep->user2() && !nodep->varp()->isTemp()
            && !isProceduralAutomatic(nodep->varp())) {
            if (!nodep->access().isReadOnly()) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Write to variable in sampled expression");
            } else {
                VNRelinker relinkHandle;
                nodep->unlinkFrBack(&relinkHandle);
                AstSampled* const newp = newSampledExpr(nodep);
                relinkHandle.relink(newp);
                newp->user1(1);
                v3Global.setHasSampled();
            }
        }
    }
    // Don't sample sensitivities
    void visit(AstSenItem* nodep) override {
        VL_RESTORER(m_inSampled);
        m_inSampled = false;
        iterateChildren(nodep);
    }
    void visit(AstPExprClause* nodep) override {
        AstNodeStmt* stmtsp = nodep->pass() ? m_passsp : m_failsp;
        const auto it = m_clauseActionsp.find(nodep);
        if (it != m_clauseActionsp.end()) {
            stmtsp = it->second;
            m_clauseActionsp.erase(it);
        }
        if (stmtsp) {
            stmtsp->foreachAndNext([](AstNodeVarRef* const refp) {
                // References inside action blocks shouldn't be implicitly sampled
                // m_passsp/m_failsp have been already visited once and refs explicitly sampled
                // are handled already
                refp->user2(1);
            });
        }
        const AstCover* const coverp = VN_CAST(m_assertp, Cover);
        FileLine* const clauseFlp = nodep->fileline();
        if (stmtsp && m_inPExprFinal && m_strongPassOnp) {
            // The end-of-simulation check of a strong property checks attempts, which all have
            // the same outcome there, so act for as many as started with it enabled
            // (IEEE 1800-2023 20.11)
            AstVar* const countp = nodep->pass() ? m_strongPassOnp : m_strongFailOnp;
            AstIf* const ifp = newIfControl(
                new AstNeq{clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::READ},
                           new AstConst{clauseFlp, AstConst::WidthedValue{}, 32, 0}},
                new AstAssign{
                    clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::WRITE},
                    new AstSub{clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::READ},
                               new AstConst{clauseFlp, AstConst::WidthedValue{}, 32, 1}}});
            ifp->addThensp(stmtsp);
            stmtsp = ifp;
        } else if (stmtsp && (m_inPExprFinal || (coverp && coverp->isSeqEvent()))) {
            // The end-of-simulation check runs in a final block, and the attempts of a sequence
            // event control are not assertion attempts, so both keep the controls applying now
            if (nodep->pass()) {
                stmtsp
                    = newIfAssertPassOn(m_assertp->controlVarp(), stmtsp, m_assertp->directive(),
                                        m_assertp->userType(), nodep->vacuous());
            } else {
                stmtsp = newIfAssertFailOn(m_assertp->controlVarp(), stmtsp,
                                           m_assertp->directive(), m_assertp->userType());
            }
        } else if (stmtsp) {
            // The controls apply to attempts starting after them; one already executing is not
            // affected, unless killed (IEEE 1800-2023 20.11). A cover statement controls its
            // own pass action inside, see visitAssertionIterate.
            FileLine* const flp = nodep->fileline();
            const VAssertDirectiveType directive = m_assertp->directive();
            const VAssertType type = m_assertp->userType();
            if (VN_IS(m_assertp, Cover)) {
                for (AstNode* np = stmtsp; np; np = np->nextp()) {
                    AstIf* const ifp = VN_CAST(np, If);
                    if (!ifp || !ifp->user2()) continue;  // Only the assertOn() check
                    pushDeletep(ifp->condp()->unlinkFrBack());
                    ifp->condp(new AstVarRef{
                        flp,
                        getPExprStartVarp("pass0", assertPassOnCond(m_assertp->controlVarp(), flp,
                                                                    type, directive, false)),
                        VAccess::READ});
                }
            }
            AstVar* const enablep
                = nodep->pass()
                      ? getPExprStartVarp(nodep->vacuous() ? "pass1" : "pass0",
                                          assertPassOnCond(m_assertp->controlVarp(), flp, type,
                                                           directive, nodep->vacuous()))
                      : getPExprStartVarp("fail", assertFailOnCond(m_assertp->controlVarp(), flp,
                                                                   type, directive));
            AstVar* const killp = getPExprStartVarp("kill", newKillCountp(flp));
            stmtsp = newQueuedAction(flp, stmtsp);
            stmtsp = newIfControl(new AstVarRef{flp, enablep, VAccess::READ}, stmtsp);
            stmtsp = newIfControl(
                new AstEq{flp, new AstVarRef{flp, killp, VAccess::READ}, newKillCountp(flp)},
                stmtsp);
        }
        if (stmtsp) {
            nodep->replaceWith(stmtsp);
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstConstCast* nodep) override {
        // Only the expression, whose sampled value is its current value (IEEE 1800-2023 16.5.1)
        AstNodeExpr* const lhsp = nodep->lhsp()->unlinkFrBack();
        nodep->replaceWith(lhsp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        lhsp->foreach([](AstNodeVarRef* refp) { refp->user2(1); });
        iterate(lhsp);
    }
    void visit(AstPExpr* nodep) override {
        if (m_inRestrict) {
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
        } else {
            VL_RESTORER(m_strongPassOnp);
            VL_RESTORER(m_strongFailOnp);
            m_strongPassOnp = nullptr;
            m_strongFailOnp = nullptr;
            const AstCover* const seqCoverp = VN_CAST(m_assertp, Cover);
            if (nodep->finalp() && !nodep->user1() && !(seqCoverp && seqCoverp->isSeqEvent())) {
                FileLine* const flp = nodep->fileline();
                for (AstVar** const varpp : {&m_strongPassOnp, &m_strongFailOnp}) {
                    *varpp = newModuleTemp(flp, m_actionNames.get("StrongOn"),
                                           m_modp->findUInt32DType(), m_modp);
                }
            }
            {
                VL_RESTORER(m_pexprBodyp);
                VL_RESTORER_CLEAR(m_pexprStartVarps);
                m_pexprBodyp = nodep->bodyp();
                // The waits of the attempt itself: not of action blocks added in its place, which
                // a Kill does not abort once started, nor of other processes in it
                const std::function<void(AstNode*)> findWaits = [&](AstNode* np) {
                    for (; np; np = np->nextp()) {
                        if (VN_IS(np, PExpr) || VN_IS(np, Fork) || VN_IS(np, NodeExpr)) continue;
                        if (VN_IS(np, EventControl) || VN_IS(np, Delay)) np->user3(true);
                        findWaits(np->op1p());
                        findWaits(np->op2p());
                        findWaits(np->op3p());
                        findWaits(np->op4p());
                    }
                };
                // Once, though the PExpr may be visited again
                const bool first = !nodep->user1SetOnce();
                if (first) findWaits(nodep->bodyp()->stmtsp());
                iterateAndNextNull(nodep->bodyp());
                const AstCover* const coverp = VN_CAST(m_assertp, Cover);
                if (first && (!coverp || !coverp->isSeqEvent())) abortWhenKilled(nodep);
            }
            VL_RESTORER(m_inPExprFinal);
            m_inPExprFinal = true;
            iterateAndNextNull(nodep->finalp());
        }
    }

    //========== Statements
    void visit(AstDisplay* nodep) override {
        iterateChildren(nodep);
        // Replace the special types with standard text
        if (nodep->displayType() == VDisplayType::DT_INFO) {
            replaceDisplay(nodep, "-Info");
        } else if (nodep->displayType() == VDisplayType::DT_WARNING) {
            replaceDisplay(nodep, "%%Warning");
        } else if (nodep->displayType() == VDisplayType::DT_ERROR) {
            replaceDisplay(nodep, "%%Error");
        } else if (nodep->displayType() == VDisplayType::DT_FATAL) {
            replaceDisplay(nodep, "%%Fatal");
        } else if (nodep->displayType() == VDisplayType::DT_MONITOR) {
            checkPostponedDisplay(nodep);
            nodep->displayType(VDisplayType::DT_DISPLAY);
            FileLine* const fl = nodep->fileline();

            // Each instance numbers its $monitor when first invoked, so that the call of one
            // instance is told from the same call in another instance. No process waits on the
            // numbers, so their writes are not scheduled, as they would make a calling
            // always_comb circular.
            AstVar* const idVarp = newModuleTemp(fl, "__VmonitorId" + cvtToStr(m_modMonitorNum++),
                                                 nodep->findUInt32DType(), m_modp);
            idVarp->setIgnoreSchedWrite();
            const auto newIdRefp
                = [&](VAccess access) { return new AstVarRef{fl, idVarp, access}; };
            // "__VmonitorIdN != 0 && __VmonitorNum == __VmonitorIdN" selects this call
            const auto newActivep = [&]() {
                return new AstLogAnd{fl,
                                     new AstNeq{fl, newIdRefp(VAccess::READ), new AstConst{fl, 0}},
                                     new AstEq{fl, newIdRefp(VAccess::READ),
                                               newMonitorNumVarRefp(nodep, VAccess::READ)}};
            };
            // Where $monitor was we do "if (__VmonitorIdN == 0) __VmonitorIdN = ++__VmonitorNext;
            // __VmonitorNum = __VmonitorIdN; __VmonitorPending = '1;", so it is displayed when
            // invoked
            AstIf* const numberp = new AstIf{
                fl, new AstEq{fl, newIdRefp(VAccess::READ), new AstConst{fl, 0}},
                new AstAssign{fl, newMonitorNextVarRefp(nodep, VAccess::WRITE),
                              new AstAdd{fl, newMonitorNextVarRefp(nodep, VAccess::READ),
                                         new AstConst{fl, 1}}}};
            numberp->addThensp(new AstAssign{fl, newIdRefp(VAccess::WRITE),
                                             newMonitorNextVarRefp(nodep, VAccess::READ)});
            AstNodeStmt* const newsetp = numberp;
            newsetp->addNext(new AstAssign{fl, newMonitorNumVarRefp(nodep, VAccess::WRITE),
                                           newIdRefp(VAccess::READ)});
            newsetp->addNext(newMonitorPendingSetp(nodep));
            nodep->replaceWith(newsetp);
            // Add "always @(args) if (<this call>) __VmonitorPending = '1;"
            AstSenItem* monSenItemsp = nullptr;
            if (AstNode* const monExprsp = nodep->fmtp()->exprsp()) {
                monExprsp->foreachAndNext([&](AstVarRef* varrefp) {
                    AstSenItem* const senItemp
                        = new AstSenItem{fl, VEdgeType::ET_CHANGED,
                                         // Clone so get VarRef or VarXRef as needed
                                         varrefp->cloneTree(false)};
                    monSenItemsp = AstNode::addNextNull(monSenItemsp, senItemp);
                });
            }
            if (monSenItemsp) {
                AstIf* const setIfp = new AstIf{fl, newActivep(), newMonitorPendingSetp(nodep)};
                AstSenTree* const monSenTreep = new AstSenTree{fl, monSenItemsp};
                m_modp->addStmtsp(new AstAlways{fl, VAlwaysKwd::ALWAYS, monSenTreep, setIfp});
            }
            // Display once at the end of the time step (IEEE 1800-2023 21.2.3), like $strobe:
            // "always_postponed if (__VmonitorPending && <this call>) begin
            //    __VmonitorPending = '0; if (!__VmonitorOff) $display(...); end"
            AstNodeExpr* const pendingp
                = new AstLogAnd{fl, newMonitorPendingVarRefp(nodep, VAccess::READ), newActivep()};
            AstNodeExpr* const onp = new AstLogNot{fl, newMonitorOffVarRefp(nodep, VAccess::READ)};
            AstIf* const onIfp = new AstIf{fl, onp, nodep};
            onIfp->isBoundsCheck(true);  // To avoid LATCH warning
            AstAssign* const clearp
                = new AstAssign{fl, newMonitorPendingVarRefp(nodep, VAccess::WRITE),
                                new AstConst{fl, AstConst::BitFalse{}}};
            AstIf* const ifp = new AstIf{fl, pendingp, clearp};
            ifp->addThensp(onIfp);
            ifp->isBoundsCheck(true);  // To avoid LATCH warning
            ifp->branchPred(VBranchPred::BP_UNLIKELY);
            m_modp->addStmtsp(new AstAlwaysPostponed{fl, ifp});
        } else if (nodep->displayType() == VDisplayType::DT_STROBE) {
            checkPostponedDisplay(nodep);
            nodep->displayType(VDisplayType::DT_DISPLAY);
            // Need one-shot
            FileLine* const fl = nodep->fileline();
            AstVar* const varp
                = new AstVar{fl, VVarType::MODULETEMP, "__Vstrobe" + cvtToStr(m_modStrobeNum++),
                             nodep->findBitDType()};
            addStateVar(varp);
            // Where $strobe was we do "__Vstrobe = '1;"
            AstAssign* const newsetp = new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                                     new AstConst{fl, AstConst::BitTrue{}}};
            nodep->replaceWith(newsetp);
            // Add "always_comb if (__Vstrobe) begin $display(...); __Vstrobe = '0; end"
            AstNodeStmt* const stmtsp = nodep;
            AstIf* const ifp = new AstIf{fl, new AstVarRef{fl, varp, VAccess::READ}, stmtsp};
            ifp->isBoundsCheck(true);  // To avoid LATCH warning
            ifp->branchPred(VBranchPred::BP_UNLIKELY);
            AstNode* const newp = new AstAlwaysPostponed{fl, ifp};
            stmtsp->addNext(new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                          new AstConst{fl, AstConst::BitFalse{}}});
            m_modp->addStmtsp(newp);
        }
    }
    void visit(AstMonitorOff* nodep) override {
        FileLine* const flp = nodep->fileline();
        AstAssign* const newp
            = new AstAssign{flp, newMonitorOffVarRefp(nodep, VAccess::WRITE),
                            new AstConst{flp, AstConst::BitTrue{}, nodep->off()}};
        // $monitoron displays immediately (IEEE 1800-2023 21.2.3)
        if (!nodep->off()) newp->addNext(newMonitorPendingSetp(nodep));
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstEventControl* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstWait* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstWaitFork* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstDisableTargetBody* nodep) override {
        iterateChildren(nodep);
        // V3LinkJump wraps only the body of a process's outermost scope. Running to its end
        // means the scope was not disabled.
        if (m_obsFlushp) {
            FileLine* const flp = nodep->fileline();
            m_obsDoneVarp
                = newModuleTemp(flp, m_obsNames.get("Done"), m_modp->findBitDType(), m_modp);
            m_obsDoneVarp->setIgnoreSchedWrite();
            nodep->addStmtsp(new AstAssign{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::WRITE},
                                           new AstConst{flp, AstConst::BitTrue{}}});
        }
        UASSERT_OBJ(nodep->stmtsp(), nodep, "V3LinkJump wraps only a non-empty body");
        nodep->addNextHere(nodep->stmtsp()->unlinkFrBackWithNext());
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }
    void visit(AstFork* nodep) override {
        iterateAndNextNull(nodep->declsp());
        iterateAndNextNull(nodep->stmtsp());
        VL_RESTORER(m_inSpawnedFork);
        m_inSpawnedFork |= !nodep->joinType().join();
        AstForkItem* wrapperp = nullptr;
        for (AstForkItem* const branchp : nodep->forkspList()) {
            // V3LinkJump's wrapper runs part of the enclosing process
            if (branchp->disableWrapper()) {
                iterate(branchp);
                wrapperp = branchp;
                continue;
            }
            // IEEE 1800-2023 9.3.2: Each branch is a separate process
            VL_RESTORER(m_inForkBranch);
            m_inForkBranch = true;
            VL_RESTORER(m_obsFlushp);
            VL_RESTORER(m_obsDoneVarp);
            VL_RESTORER_CLEAR(m_obsWaitsp);
            m_obsFlushp = m_taskRunner ? newTaskFlushp(branchp->fileline()) : nullptr;
            m_obsDoneVarp = nullptr;
            iterate(branchp);
            addObsFlushes(branchp);
        }
        if (wrapperp && m_taskRunner && m_keyedWrapperps.emplace(wrapperp).second) {
            keyDisableWrapper(nodep, wrapperp);
        }
    }
    // A fork branch is a process of its own, which also suspends if its own statements may
    void visit(AstForkItem* nodep) override {
        VL_RESTORER(m_procSuspends);
        if (!nodep->disableWrapper()) {
            m_procSuspends = m_procSuspends || V3AssertCommon::procSuspends(nodep->stmtsp());
        }
        iterateChildren(nodep);
    }
    void visit(AstAssert* nodep) override {  //
        visitAssertionIterate(nodep, nodep->failsp());
    }
    AstVar* newControlArgp(AstNodeExpr* exprp, AstBegin* beginp) {
        AstVar* const varp
            = new AstVar{exprp->fileline(), VVarType::BLOCKTEMP,
                         "__VassertCtlArg" + std::to_string(m_controlTempNum++), exprp->dtypep()};
        // A concurrent action can be hoisted out of its enclosing task.
        if (m_ftaskp && !m_inConcurrentAction) {
            varp->funcLocal(true);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_ftaskp->addDeclsp(varp);
        } else {
            // Procedural operands execute without yielding. Module-owned storage
            // must not pretend to be an automatic enclosing-fork variable.
            varp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(varp);
        }
        beginp->addStmtsp(new AstAssign{
            exprp->fileline(), new AstVarRef{exprp->fileline(), varp, VAccess::WRITE}, exprp});
        return varp;
    }
    static AstCStmt* newControlCallp(FileLine* flp, AstVar* controlp, AstVar* typesp,
                                     VAssertDirectiveType directives) {
        AstCStmt* const stmtp = new AstCStmt{flp, "vlSymsp->_vm_contextp__->assertCtl("};
        stmtp->add(new AstVarRef{flp, controlp, VAccess::READ});
        stmtp->add(", ");
        stmtp->add(new AstVarRef{flp, typesp, VAccess::READ});
        stmtp->add(", " + std::to_string(directives) + ");\n");
        return stmtp;
    }
    static AstConst* newControlLevelConstp(FileLine* flp, AstVar* levelp, uint32_t value) {
        AstConst* const constp = new AstConst{flp, AstConst::DTyped{}, levelp->dtypep()};
        constp->num().setLong(value);
        return constp;
    }
    static AstNodeExpr* newControlDepthLimitp(FileLine* flp, AstVar* levelp) {
        constexpr uint32_t unlimited = std::numeric_limits<uint32_t>::max();
        const auto newLevelRef = [&]() { return new AstVarRef{flp, levelp, VAccess::READ}; };
        const auto newLimitConst = [&](uint32_t value) {
            return new AstConst{flp, AstConst::WidthedValue{}, 32, value};
        };
        AstNodeExpr* allp = new AstEq{flp, newLevelRef(), newControlLevelConstp(flp, levelp, 0)};
        AstNodeExpr* limitp = newLevelRef();
        if (levelp->width() > 32) {
            allp = new AstLogOr{
                flp, allp,
                new AstGt{flp, newLevelRef(), newControlLevelConstp(flp, levelp, unlimited)}};
            limitp = new AstSel{flp, limitp, 0, 32};
        }
        AstNodeExpr* const narrowedp = limitp;
        limitp = new AstCond{flp, allp, newLimitConst(unlimited), narrowedp};
        limitp->dtypeFrom(narrowedp);
        if (levelp->isSigned()) {
            limitp = new AstCond{
                flp, new AstLtS{flp, newLevelRef(), newControlLevelConstp(flp, levelp, 0)},
                newLimitConst(0), limitp};
        }
        return limitp;
    }
    void pruneTargets(AstAssertCtlTarget* targetsp, uint32_t limit, uint32_t mask) {
        for (AstAssertCtlTarget* const targetp : VNList<AstAssertCtlTarget>{targetsp}) {
            const AstVar* const statep = targetp->statep()->varp();
            // A forwarded block may hold sites of any type
            if (static_cast<uint32_t>(targetp->depth()) >= limit
                || (statep && !targetp->forward() && !(statep->assertCtlMask() & mask))) {
                VL_DO_DANGLING(pushDeletep(targetp->unlinkFrBack()), targetp);
            }
        }
    }
    void pruneControlTargets(AstAssertCtl* nodep) {
        AstAssertCtlArgs* const argsp = nodep->argsp();
        const AstConst* const levelp = VN_CAST(argsp->levelp(), Const);
        const AstConst* const typesp = VN_CAST(nodep->assertTypesp(), Const);
        constexpr uint32_t unlimited = std::numeric_limits<uint32_t>::max();
        uint32_t limit = unlimited;
        if (levelp && !levelp->num().isOpaque() && !levelp->num().isFourState()
            && levelp->width() <= 32) {
            if (levelp->isSigned() && levelp->toSInt() < 0) {
                limit = 0;
            } else if (!levelp->num().isEqZero()) {
                limit = levelp->toUInt();
            }
        }
        uint32_t mask = unlimited;
        if (!nodep->assertTypesp()
            || (typesp && !typesp->num().isOpaque() && !typesp->num().isFourState()
                && typesp->width() <= 32)) {
            const uint32_t types = typesp ? typesp->toUInt() : ALL_ASSERT_TYPES;
            mask = 0;
            for (unsigned bit = 0; bit < std::numeric_limits<uint8_t>::digits; ++bit) {
                if (types & (uint32_t{1} << bit)) {
                    mask |= static_cast<uint32_t>(nodep->directiveTypes())
                            << (VAssertDirectiveType::MASK_WIDTH * bit);
                }
            }
        }
        pruneTargets(argsp->targetsp(), limit, mask);
        for (AstAssertCtlTargetSet* const setp : argsp->setspList()) {
            pruneTargets(setp->targetsp(), limit, mask);
        }
        if (AstAssertCtlTargetSet* const setp = argsp->sharedp()) {
            AssertCtlDepths& depths = m_sharedControlDepths[setp];
            for (size_t bit = 0; bit < depths.size(); ++bit) {
                if (mask & (uint32_t{1} << bit)) depths[bit] = std::max(depths[bit], limit);
            }
        }
    }
    AstNodeStmt* newScopedControlp(AstAssertCtl* nodep) {
        pruneControlTargets(nodep);
        FileLine* const flp = nodep->fileline();
        AstAssertCtlArgs* const argsp = nodep->argsp();
        AstBegin* const beginp = new AstBegin{flp, "", nullptr, true};
        // Evaluate effect, types and levels once in source order, even for an empty selection.
        AstVar* const controlp = newControlArgp(nodep->controlTypep()->unlinkFrBack(), beginp);
        AstVar* const typesp
            = newControlArgp(nodep->assertTypesp() ? nodep->assertTypesp()->unlinkFrBack()
                                                   : new AstConst{flp, ALL_ASSERT_TYPES},
                             beginp);
        AstNodeExpr* levelExprp
            = argsp->levelp() ? argsp->levelp()->unlinkFrBack() : new AstConst{flp, 0};
        if (levelExprp->width() < 32) {
            if (levelExprp->isSigned()) {
                levelExprp = new AstExtendS{flp, levelExprp, 32};
                levelExprp->dtypeSetBitSized(32, VSigning::SIGNED);
            } else {
                levelExprp = new AstExtend{flp, levelExprp, 32};
            }
        }
        AstVar* const levelp = newControlArgp(levelExprp, beginp);
        AstAssertCtlApply* const applyp = new AstAssertCtlApply{
            flp,
            new AstVarRef{flp, controlp, VAccess::READ},
            new AstVarRef{flp, typesp, VAccess::READ},
            newControlDepthLimitp(flp, levelp),
            nodep->directiveTypes(),
            argsp->targetsp() ? argsp->targetsp()->unlinkFrBackWithNext() : nullptr};
        applyp->targetSetp(argsp->sharedp());
        if (argsp->setsp()) {
            AstAssertCtlPlan* const planp
                = new AstAssertCtlPlan{flp, argsp->setsp()->unlinkFrBackWithNext()};
            v3Global.rootp()->addMiscsp(planp);
            applyp->planp(planp);
        }
        v3Global.setHasAssertCtlReads();
        if (argsp->scoped()) {
            beginp->addStmtsp(applyp);
        } else {
            // A zero level with no explicit scopes is an operation on the context.
            beginp->addStmtsp(new AstIf{
                flp,
                new AstEq{flp, new AstVarRef{flp, levelp, VAccess::READ},
                          newControlLevelConstp(flp, levelp, 0)},
                newControlCallp(flp, controlp, typesp, nodep->directiveTypes()), applyp});
        }
        return beginp;
    }
    void visit(AstAssertCtl* nodep) override {
        iterateChildren(nodep);

        bool assertTypeConst = true;
        if (!nodep->assertTypesp()) {
            nodep->assertTypes(VAssertType{ALL_ASSERT_TYPES});
        } else if (const AstConst* const assertTypesp = VN_CAST(nodep->assertTypesp(), Const)) {
            nodep->assertTypes(VAssertType{assertTypesp->toSInt()});
        } else {
            assertTypeConst = false;
        }

        bool controlTypeConst = false;
        if (const AstConst* const constp = VN_CAST(nodep->controlTypep(), Const)) {
            nodep->ctlType(constp->toSInt());
            controlTypeConst = true;
        }
        if (controlTypeConst
            && (nodep->ctlType() < VAssertCtlType::LOCK
                || nodep->ctlType() > VAssertCtlType::VACUOUS_OFF)) {
            nodep->unlinkFrBack();
            nodep->v3error("Bad $assertcontrol control_type '"
                           << cvtToStr(static_cast<int>(nodep->ctlType()))
                           << "' (IEEE 1800-2023 Table 20-5)");
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (assertTypeConst && nodep->assertTypes() != ALL_ASSERT_TYPES
            && nodep->assertTypes().containsAny(VAssertType::UNIQUE | VAssertType::UNIQUE0
                                                | VAssertType::PRIORITY)
            && (!controlTypeConst || nodep->ctlType() > VAssertCtlType::KILL)) {
            // Violation checks are only enabled by the On/Off state; pass and fail action
            // controls would be silently ignored
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: assert control of unique, unique0 or"
                                         " priority checks with this control_type");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        bool directiveTypeConst = true;
        if (!nodep->directiveTypesp()) {
            nodep->directiveTypes(VAssertDirectiveType::ASSERT | VAssertDirectiveType::ASSUME
                                  | VAssertDirectiveType::COVER);
        } else if (const AstConst* const directiveTypesp
                   = VN_CAST(nodep->directiveTypesp(), Const)) {
            nodep->directiveTypes(VAssertDirectiveType{directiveTypesp->toSInt()});
        } else {
            directiveTypeConst = false;
        }
        if (!directiveTypeConst) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: non-const assert directive type expression");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }

        if (nodep->argsp()) {
            nodep->replaceWith(newScopedControlp(nodep));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        FileLine* const fl = nodep->fileline();
        UINFO(9, "Generating assertctl for a module: " << m_modp);
        AstCStmt* const newp = new AstCStmt{fl};
        newp->add("vlSymsp->_vm_contextp__->assertCtl(");
        newp->add(nodep->controlTypep()->unlinkFrBack());
        newp->add(", ");
        if (nodep->assertTypesp()) {
            newp->add(nodep->assertTypesp()->unlinkFrBack());
        } else {
            newp->add(std::to_string(ALL_ASSERT_TYPES));
        }
        newp->add(", " + std::to_string(nodep->directiveTypes()) + ");\n");
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstAssertIntrinsic* nodep) override {  //
        visitAssertionIterate(nodep, nodep->failsp());
    }
    void visit(AstCover* nodep) override {  //
        visitAssertionIterate(nodep, nullptr);
    }
    void visit(AstRestrict* nodep) override {
        VL_RESTORER(m_inRestrict);
        m_inRestrict = true;
        iterateChildren(nodep);
        // IEEE says simulator ignores these
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }

    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_controlTempNum);
        m_controlTempNum = 0;
        VL_RESTORER_COPY(m_obsNames);
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsEventp);
        VL_RESTORER(m_obsReactivep);
        VL_RESTORER(m_finalPostponedp);
        VL_RESTORER_COPY(m_actionNames);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER(m_containerp);
        VL_RESTORER(m_modPastNum);
        VL_RESTORER(m_modStrobeNum);
        VL_RESTORER(m_modMonitorNum);
        VL_RESTORER_CLEAR(m_modExpr2Sen2DelayedAlwaysp);
        VL_RESTORER_CLEAR(m_modExpr2Sen2DefaultDelayedAlwaysp);
        VL_RESTORER_CLEAR(m_delayedAlways2TickTimep);
        m_modp = nodep;
        m_containerp = nodep;
        m_modPastNum = 0;
        m_obsNames.reset();
        m_obsFlushp = nullptr;
        m_obsEventp = nullptr;
        m_obsReactivep = nullptr;
        m_finalPostponedp = nullptr;
        m_actionNames.reset();
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        m_modStrobeNum = 0;
        m_modMonitorNum = 0;
        iterateChildren(nodep);
    }
    void visit(AstAlways* nodep) override {
        if (nodep->keyword() != VAlwaysKwd::ASSERT_COVER) {
            visit(static_cast<AstNodeProcedure*>(nodep));
            return;
        }
        // The process of a concurrent assertion, not a procedural context. The assertion clocks
        // it, or it goes with the assertion. Its action blocks have no flush point (IEEE
        // 1800-2023 16.4.2), so the flushes of deferred assertions in them are not added.
        VL_RESTORER(m_assertCoverp);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER_CLEAR(m_namedBeginps);
        VL_RESTORER(m_procSuspends);
        m_procSuspends = false;
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsDoneVarp);
        VL_RESTORER_CLEAR(m_obsWaitsp);
        m_assertCoverp = nodep;
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        m_obsFlushp = nullptr;
        m_obsDoneVarp = nullptr;
        iterateChildren(nodep);
        if (m_obsFlushp) VL_DO_DANGLING(m_obsFlushp->deleteTree(), m_obsFlushp);
        if (nodep->keyword() == VAlwaysKwd::ASSERT_COVER) {
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
        }
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_procedurep);
        VL_RESTORER_CLEAR(m_combReads);
        VL_RESTORER(m_matureEpochp);
        m_matureEpochp = nullptr;
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsDoneVarp);
        VL_RESTORER_CLEAR(m_obsWaitsp);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER_CLEAR(m_namedBeginps);
        VL_RESTORER(m_procSuspends);
        VL_RESTORER(m_taskRunner);
        m_procedurep = nodep;
        const AstAlways* const combp = VN_CAST(nodep, Always);
        if (combp && combp->userComb()) collectNonActionReads(nodep->stmtsp(), m_combReads);
        m_procSuspends = V3AssertCommon::procSuspends(nodep->stmtsp());
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        m_taskRunner = m_taskRunnerps.count(nodep);
        if (m_taskRunner) {
            m_obsFlushp = AstNode::addNext(m_obsFlushp, newTaskFlushp(nodep->fileline()));
        }
        AstBegin* const scopep = VN_CAST(nodep->stmtsp(), Begin);
        iterateChildren(nodep);
        // IEEE 1800-2023 16.4.2: The process resumes from its event control, or was declared by
        // an always_comb or always_latch and is resumed due to a transition on one of its
        // dependent signals.
        if (AstAlways* const alwaysp = VN_CAST(nodep, Always)) {
            if (alwaysp->stmtsp()
                && (alwaysp->sentreep() || alwaysp->keyword() == VAlwaysKwd::ALWAYS_COMB
                    || alwaysp->keyword() == VAlwaysKwd::ALWAYS_LATCH)) {
                addResumeFlush(alwaysp);
            }
        }
        addObsFlushes(scopep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_ftaskp);
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsDoneVarp);
        VL_RESTORER_CLEAR(m_obsWaitsp);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER(m_taskRunner);
        m_ftaskp = nodep;
        m_obsDoneVarp = nullptr;
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        // Its flush points are those of the calling process
        m_taskRunner = m_taskRunnerps.count(nodep);
        m_obsFlushp = m_taskRunner ? newTaskFlushp(nodep->fileline()) : nullptr;
        iterateChildren(nodep);
        if (m_taskRunner) addObsFlushes(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        // This code is needed rather than a visitor in V3Begin,
        // because V3Assert is called before V3Begin
        VL_RESTORER(m_beginp);
        VL_RESTORER(m_containerp);
        VL_RESTORER_COPY(m_genScope);
        m_beginp = nodep;
        m_containerp = nodep;
        if (!nodep->name().empty()) m_genScope += "__DOT__" + nodep->name();
        iterateChildren(nodep);
    }
    void visit(AstBegin* nodep) override {
        // This code is needed rather than a visitor in V3Begin,
        // because V3Assert is called before V3Begin
        VL_RESTORER(m_beginp);
        m_beginp = nodep;
        if (!nodep->name().empty()) m_namedBeginps.push_back(nodep);
        if (nodep->disableCountp()) m_disableCountps.push_back(nodep->disableCountp());
        iterateChildren(nodep);
        if (nodep->disableCountp()) m_disableCountps.pop_back();
        if (!nodep->name().empty()) m_namedBeginps.pop_back();
        // If the body is a single assertOn check, bubble it up for combining
        if (!nodep->declsp()) {
            if (AstIf* const ifp = VN_CAST(nodep->stmtsp(), If)) {
                if (ifp->user2() && !ifp->nextp()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(ifp->unlinkFrBack());
                    nodep->addStmtsp(ifp->thensp()->unlinkFrBackWithNext());
                    ifp->addThensp(nodep);
                }
            }
        }
    }

    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertVisitor(AstNetlist* nodep) {
        m_checkerFormals.specialize(nodep);
        if (v3Global.opt.timing().isSetTrue() && nodep->stdPackageProcessp()) {
            AssertTaskRunnersVisitor{nodep, m_taskRunnerps};
        }
        iterate(nodep);
        for (const auto& item : m_sharedControlDepths) {
            for (AstAssertCtlTarget* const targetp : item.first->targetspList()) {
                const AstVar* const statep = targetp->statep()->varp();
                const uint32_t mask = targetp->forward() ? ~0U : statep->assertCtlMask();
                const auto depth = static_cast<uint32_t>(targetp->depth());
                bool selected = false;
                for (size_t bit = 0; bit < item.second.size(); ++bit) {
                    if ((mask & (uint32_t{1} << bit)) && depth < item.second[bit]) {
                        selected = true;
                        break;
                    }
                }
                if (!selected) VL_DO_DANGLING(pushDeletep(targetp->unlinkFrBack()), targetp);
            }
        }
    }
    ~AssertVisitor() override {
        V3Stats::addStat("Assertions, assert non-immediate statements", m_statAsNotImm);
        V3Stats::addStat("Assertions, assert immediate statements", m_statAsImm);
        V3Stats::addStat("Assertions, cover statements", m_statCover);
        V3Stats::addStat("Assertions, full/parallel case", m_statAsFull);
        V3Stats::addStat("Assertions, $past variables", m_statPastVars);
        V3Stats::addStat("Assertions, assertOn checks combined", m_statAssertOnCombined);
        V3Stats::addStat("Assertions, procedural in tasks matured", m_statTaskMature);
        V3Stats::addStat("Assertions, assertOn checks hoisted", m_statAssertOnHoisted);
        V3Stats::addStat("Assertions, deferred violation reports", m_statViolationsDeferred);
        V3Stats::addStat("Assertions, lifted impure case expressions", m_statLiftedCaseExprs);
        V3Stats::addStat("Assertions, lifted unique conditions", m_statLiftedUniqueConds);
        // Rewrites can change purity, e.g. by compiling out assertion statements with --no-assert
        VIsCached::clearCacheTree();
    }
};

//######################################################################
// Top Assert class

void V3Assert::assertAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { AssertVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("assert", 0, dumpTreeEitherLevel() >= 3);
}
