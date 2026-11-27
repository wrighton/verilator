// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: AstNode hash computation
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

#include "V3PchAstMT.h"

#include "V3Hasher.h"

#include <functional>
#include <unordered_map>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Visitor that computes node hashes

// A function (AstCFunc or AstNodeFTask) is hashed where first reached, and its hash is part of the
// hash of what reaches it, e.g. a call. The functions reached from a node are hashed before the
// node, depth first with an explicit stack, as call chains can be deeper than recursion can go on
// the C++ stack. A first walk of each node records the functions it reaches that are not hashed
// yet, in the order hashing reaches them, and the node is walked again once they are hashed. The
// first walk hashes the node, except for what reaches those functions, so a node reaching only
// hashed functions is walked once.

class HasherVisitor final : public VNVisitorConst {
    // NODE STATE
    //  AstNode::user4() -> V3Hash.  Hash value of this node (hash of 0 is illegal)
    // VNUser4InUse     in V3Hasher.h

    // TYPES
    // Functions reached in order, and whether first reached there
    using Reaches = std::vector<std::pair<AstNode*, bool>>;

    // STATE
    V3Hash m_hash;  // Hash value accumulator
    const bool m_cacheInUser4;  // Use user4 to cache each V3Hash?
    std::set<AstNode*> m_visited;  // Functions reached, if not caching
    bool m_finding = false;  // In the first walk of a node, see above
    bool m_incomplete = false;  // Node being hashed reaches a function not hashed yet
    Reaches* m_reachesp = nullptr;  // Functions reached by the node being walked
    size_t m_reachIdx = 0;  // Index in 'm_reachesp' of next function reached, if not caching
    std::unordered_map<const AstNode*, V3Hash> m_funcHashes;  // Function hashes, if not caching

    // METHODS

    static bool isFunc(const AstNode* nodep) {
        return VN_IS(nodep, CFunc) || VN_IS(nodep, NodeFTask);
    }

    // Hash 'nodep', the start node, after the functions it reaches, see above
    void hashDepthFirst(AstNode* nodep) {
        struct Frame final {
            AstNode* nodep;  // Start node or function to hash
            Reaches reaches;  // Functions it reaches, see 'firstWalk'
            V3Hash hash;  // Its hash from the first walk, if 'reaches' is empty
            size_t next;  // Index of next function in 'reaches' to consider
        };
        std::vector<Frame> stack;
        if (!m_cacheInUser4 && isFunc(nodep)) m_visited.emplace(nodep);
        stack.emplace_back();
        stack.back().nodep = nodep;
        stack.back().hash = firstWalk(nodep, stack.back().reaches);
        stack.back().next = 0;
        while (!stack.empty()) {
            Frame& frame = stack.back();
            if (frame.next < frame.reaches.size()) {
                std::pair<AstNode*, bool>& reach = frame.reaches[frame.next++];
                AstNode* const funcp = reach.first;
                // Skip a function hashed already, or being hashed. The first walk marks it as
                // being hashed if caching.
                if (m_cacheInUser4 ? funcp->user4() != 0 : !m_visited.emplace(funcp).second) {
                    continue;
                }
                reach.second = true;
                stack.emplace_back();
                stack.back().nodep = funcp;
                stack.back().hash = firstWalk(funcp, stack.back().reaches);
                stack.back().next = 0;
                continue;
            }
            Frame done = std::move(frame);
            stack.pop_back();
            V3Hash hash = done.hash;
            if (!done.reaches.empty()) {
                VL_RESTORER(m_reachesp);
                m_reachesp = &done.reaches;
                m_reachIdx = 0;
                if (isFunc(done.nodep)) {
                    // Not marked as being hashed while hashing itself
                    if (m_cacheInUser4) done.nodep->user4(0);
                    hash = hashFunc(done.nodep);
                } else {
                    VL_RESTORER(m_hash);
                    iterateConst(done.nodep);
                    hash = m_hash;
                }
                UASSERT_OBJ(m_cacheInUser4 ? !m_incomplete : m_reachIdx == done.reaches.size(),
                            done.nodep, "Should reach only the functions found by the first walk");
            }
            if (!m_cacheInUser4 && isFunc(done.nodep)) m_funcHashes.emplace(done.nodep, hash);
            if (stack.empty()) {
                if (isFunc(done.nodep)) {
                    m_hash += hash;
                } else {
                    m_hash = hash;
                }
            }
        }
    }

    // First walk of 'nodep', returning its hash if it reaches only hashed functions, and adding
    // the functions it reaches not hashed yet to 'reaches', see above
    V3Hash firstWalk(AstNode* nodep, Reaches& reaches) {
        VL_RESTORER(m_hash);
        VL_RESTORER(m_finding);
        VL_RESTORER(m_reachesp);
        VL_RESTORER(m_incomplete);
        m_finding = true;
        m_reachesp = &reaches;
        if (isFunc(nodep)) return hashFunc(nodep);
        iterateConst(nodep);
        return m_hash;
    }

    // Hash function 'nodep' itself
    V3Hash hashFunc(AstNode* nodep) {
        // When caching, a recursive call reaches a function being hashed with hash 1, set below.
        // A constant in the hash just ends the recursion; the function still has its own hash.
        if (AstCFunc* const funcp = VN_CAST(nodep, CFunc)) {
            return hashNodeAndIterate(funcp, HASH_DTYPE, HASH_CHILDREN, [this, funcp]() {  //
                if (m_cacheInUser4) funcp->user4(V3Hash{1}.value());
                m_hash += funcp->isLoose();
            });
        }
        AstNodeFTask* const ftaskp = VN_AS(nodep, NodeFTask);
        return hashNodeAndIterate(ftaskp, HASH_DTYPE, HASH_CHILDREN, [this, ftaskp]() {  //
            m_hash += ftaskp->name();
            if (m_cacheInUser4) ftaskp->user4(V3Hash{1}.value());
        });
    }

    // Reach function 'nodep' from the node being walked
    void reachFunc(AstNode* nodep) {
        if (m_cacheInUser4) {
            if (!nodep->user4()) {
                m_reachesp->emplace_back(nodep, false);
                m_incomplete = true;
            }
            m_hash += V3Hash{static_cast<uint32_t>(nodep->user4())};
            return;
        }
        if (m_finding) {
            m_reachesp->emplace_back(nodep, false);
            return;
        }
        // Without caching, a function hashes by name where reached again
        const std::pair<AstNode*, bool>& reach = m_reachesp->at(m_reachIdx++);
        UASSERT_OBJ(reach.first == nodep, nodep, "Should reach functions in the order found");
        m_hash += reach.second ? m_funcHashes.at(nodep) : V3Hash{nodep->name()};
    }

    V3Hash hashNodeAndIterate(AstNode* nodep, bool hashDType, bool hashChildren,
                              std::function<void()>&& f) {
        // See comments in hashFunc about this breaking recursion
        if (m_cacheInUser4 && nodep->user4()) {
            return V3Hash{static_cast<uint32_t>(nodep->user4())};
        } else {
            VL_RESTORER(m_hash);
            const bool outerIncomplete = m_incomplete;
            m_incomplete = false;
            // Reset accumulator
            m_hash = V3Hash{nodep->type().hash()};  // Node type
            f();  // Node-specific hash
            if (hashDType && nodep != nodep->dtypep())
                iterateConstNull(nodep->dtypep());  // Node dtype
            if (hashChildren) iterateChildrenConst(nodep);  // Children
            // Not cached when reaching a function not hashed yet, to hash again later
            if (m_cacheInUser4 && !m_incomplete) nodep->user4(m_hash.value());
            m_incomplete |= outerIncomplete;
            return m_hash;
        }
    }

    // VISITORS

    constexpr static bool HASH_DTYPE = true;
    constexpr static bool HASH_CHILDREN = true;

    // Each visitor below contributes to the hash any node-specific content
    // that is not dependent on either of the following, as these are
    // included by default by hashNode:
    // - Node type (as given by AstNode::type().hash())
    // - Node dtype (unless !hashDType)
    // - child nodes (unless !hashChildren)
    //
    // The hash must be stable, which means in particular it cannot rely on
    // pointer values, or any other value that might differ between separate
    // invocations of Verilator over the same design.
    //
    // Note there is a circularity problem where some child nodes can back
    // to their ancestral nodes via member pointers, which can lead to an
    // infinite traversal. To break this, nodes that are subject to such
    // referencing and represent code which can reasonably be assumed not to
    // be equivalent to any other code, are hashed either by name (e.g.:
    // AstNodeModule), or by unique identifier (e.g.: AstNodeUOrStructDType).

    //------------------------------------------------------------
    // AstNode - Warns to help find missing cases

    void visit(AstNode* nodep) override {
#if VL_DEBUG
        UINFO(0, "%Warning: Hashing node as AstNode: " << nodep);
#endif
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [=]() {});
    }

    //------------------------------------------------------------
    // AstNodeDType
    void visit(AstNodeArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->virtRefDTypep());
            m_hash += nodep->left();
            m_hash += nodep->right();
        });
    }
    void visit(AstNodeUOrStructDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, false, [this, nodep]() {  //
            m_hash += nodep->uniqueNum();
        });
    }
    void visit(AstParamTypeDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            m_hash += nodep->varType();
        });
    }
    void visit(AstMemberDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstDefImplicitDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->uniqueNum();
        });
    }
    void visit(AstAssocArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->virtRefDTypep());
            iterateConstNull(nodep->virtRefDType2p());
        });
    }
    void visit(AstBracketArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstDynArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstUnsizedArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstWildcardArrayDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstBasicDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->keyword();
            m_hash += nodep->numeric();
            m_hash += nodep->nrange().left();
            m_hash += nodep->nrange().right();
        });
    }
    void visit(AstCDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstConstDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstClassRefDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->classp());
        });
    }
    void visit(AstClosurePoolDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->subDTypep());
        });
    }
    void visit(AstIfaceRefDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->cellp());
        });
    }
    void visit(AstQueueDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->virtRefDTypep());
        });
    }
    void visit(AstRefDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->typedefp());
            iterateConstNull(nodep->refDTypep());
        });
    }
    void visit(AstStreamDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstVoidDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstEnumDType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, false, [this, nodep]() {  //
            m_hash += nodep->uniqueNum();
        });
    }

    //------------------------------------------------------------
    // AstNodeExpr
    void visit(AstNodeExpr* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstSel* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->widthConst();
        });
    }
    void visit(AstConst* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->num().toHash();
        });
    }
    void visit(AstNullCheck* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstCCast* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->size();
        });
    }
    void visit(AstVarRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            if (nodep->varScopep()) {
                iterateConstNull(nodep->varScopep());
            } else {
                iterateConstNull(nodep->varp());
                m_hash += nodep->selfPointer().asString();
            }
        });
    }
    void visit(AstVarXRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->varp());
            m_hash += nodep->dotted();
        });
    }
    void visit(AstMemberRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstSchemaRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstFScanF* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->text();
        });
    }
    void visit(AstSScanF* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->text();
        });
    }
    void visit(AstAddrOfCFunc* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->funcp());
        });
    }
    void visit(AstTriggered* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            for (const uint32_t index : nodep->indices()) m_hash += index;
        });
    }

    //------------------------------------------------------------
    // AstNodeStmt
    void visit(AstNodeStmt* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstNodeCCall* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->funcp());
        });
    }
    void visit(AstNbaEnqueue* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->funcp());
        });
    }
    void visit(AstCaseItem* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstNodeFTaskRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->taskp());
            iterateConstNull(nodep->classOrPackagep());
        });
    }
    void visit(AstCMethodHard* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->method();
        });
    }
    void visit(AstCAwait* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->sentreep());
        });
    }
    void visit(AstCLocalScope* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstCoverInc* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->declp());
        });
    }
    void visit(AstDisplay* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->displayType();
        });
    }
    void visit(AstMonitorOff* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->off();
        });
    }
    void visit(AstJumpGo* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, false, []() {});
    }
    void visit(AstNodeCoverOrAssert* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }

    //------------------------------------------------------------
    // AstNode direct descendants
    void visit(AstNodeRange* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstNodeModule* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, false, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstNodePreSel* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstClassExtends* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstForeachHeader* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstDefParam* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstArg* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstParseRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstClassOrPackageRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->classOrPackageNodep());
        });
    }
    void visit(AstSenItem* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->edgeType();
        });
    }
    void visit(AstSenTree* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstSFormatF* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->text();
        });
    }
    void visit(AstElabDisplay* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->displayType();
        });
    }
    void visit(AstNodeConsItem* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstConsArray* nodep) override {
        // Hash unpacked array values by element, so equal values hash the same whether or not
        // they use a default
        const AstUnpackArrayDType* const dtypep
            = VN_AS(nodep->dtypep()->skipRefp(), UnpackArrayDType);
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, /* hashChildren: */ false,
                                     [this, nodep, dtypep]() {
                                         const uint32_t size = dtypep->elementsConst();
                                         for (uint32_t n = 0; n < size; ++n) {  //
                                             iterateConstNull(nodep->valuep(n));
                                         }
                                     });
    }
    void visit(AstPragma* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->pragType();
        });
    }
    void visit(AstAttrOf* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->attrType();
        });
    }
    void visit(AstNodeFile* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstCFunc* nodep) override { reachFunc(nodep); }
    void visit(AstVar* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            m_hash += nodep->varType();
        });
    }
    void visit(AstScope* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, false, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->aboveScopep());
        });
    }
    void visit(AstVarScope* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            iterateConstNull(nodep->varp());
            iterateConstNull(nodep->scopep());
        });
    }
    void visit(AstEnumItem* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstTypedef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstTypedefFwd* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstActive* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            iterateConstNull(nodep->sentreep());
        });
    }
    void visit(AstCell* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->modp());
        });
    }
    void visit(AstCellInline* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN,
                                     [this, nodep]() { m_hash += nodep->name(); });
    }
    void visit(AstNodeFTask* nodep) override { reachFunc(nodep); }
    void visit(AstModport* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstModportVarRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->varp());
        });
    }
    void visit(AstModportFTaskRef* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->ftaskp());
        });
    }
    void visit(AstNodeProcedure* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstBegin* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
        });
    }
    void visit(AstFork* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->name();
            m_hash += nodep->joinType();
            m_hash += nodep->immediateStart();
            m_hash += nodep->capturesValues();
        });
    }
    void visit(AstPin* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            m_hash += nodep->pinNum();
        });
    }
    void visit(AstText* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->text();
        });
    }
    void visit(AstTextBlock* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->prefix();
            m_hash += nodep->separator();
            m_hash += nodep->suffix();
        });
    }
    void visit(AstCStmt* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstCStmtUser* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }
    void visit(AstCExpr* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstCExprUser* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }
    void visit(AstWith* nodep) override {
        m_hash += hashNodeAndIterate(nodep, HASH_DTYPE, HASH_CHILDREN, []() {});
    }

    // RTMD nodes do not hash their dtypep, as struct types hash by uniqueNum,
    // which would prevent sharing descriptors of cloned structs
    void visit(AstRtmdEnumItem* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            m_hash += nodep->value();
        });
    }
    void visit(AstRtmdMember* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            m_hash += nodep->lsb();
            iterateConstNull(nodep->rtmddtp());
        });
    }
    void visit(AstRtmdVarType* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->kind();
            m_hash += nodep->direction();
            iterateConstNull(nodep->rtmddtp());
        });
    }
    void visit(AstRtmdDTAtom* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->keyword();
            m_hash += nodep->isSigned();
        });
    }
    void visit(AstRtmdDTEnum* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->name();
            iterateConstNull(nodep->rtmddtp());
        });
    }
    void visit(AstRtmdDTPackedArray* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->left();
            m_hash += nodep->right();
            m_hash += nodep->isSigned();
            iterateConstNull(nodep->elemRtmddtp());
        });
    }
    void visit(AstRtmdDTPackedStruct* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->isSigned();
        });
    }
    void visit(AstRtmdDTPackedUnion* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {  //
            m_hash += nodep->isSigned();
        });
    }
    void visit(AstRtmdDTUnpackedArray* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, [this, nodep]() {
            m_hash += nodep->left();
            m_hash += nodep->right();
            iterateConstNull(nodep->elemRtmddtp());
        });
    }
    void visit(AstRtmdDTUnpackedStruct* nodep) override {
        m_hash += hashNodeAndIterate(nodep, false, HASH_CHILDREN, []() {});
    }

public:
    // CONSTRUCTORS
    explicit HasherVisitor(AstNode* nodep)
        : m_cacheInUser4{true} {
        hashDepthFirst(nodep);
    }
    class Uncached {};
    HasherVisitor(const AstNode* nodep, Uncached)
        : m_cacheInUser4{false} {
        hashDepthFirst(const_cast<AstNode*>(nodep));
    }
    V3Hash finalHash() const { return m_hash; }
    ~HasherVisitor() override = default;
};

//######################################################################
// V3Hasher methods

V3Hash V3Hasher::operator()(AstNode* nodep) const {
    if (!nodep->user4()) HasherVisitor{nodep};
    return V3Hash{static_cast<uint32_t>(nodep->user4())};
}

V3Hash V3Hasher::rehash(AstNode* nodep) const {
    nodep->user4(0);
    { HasherVisitor{nodep}; }
    return V3Hash{static_cast<uint32_t>(nodep->user4())};
}

V3Hash V3Hasher::uncachedHash(const AstNode* nodep) {
    const HasherVisitor visitor{nodep, HasherVisitor::Uncached{}};
    return visitor.finalHash();
}

//######################################################################
// This is used by the std::hash specialization for VNRef.
// Declared separately to avoid a circular header dependency.

size_t V3HasherUncachedHash(const AstNode& node) {
    return static_cast<size_t>(V3Hasher::uncachedHash(&node).value());
}
