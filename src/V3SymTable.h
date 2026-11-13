// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Symbol table
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

#ifndef VERILATOR_V3SYMTABLE_H_
#define VERILATOR_V3SYMTABLE_H_

#include "config_build.h"
#include "verilatedos.h"

#include "V3Ast.h"
#include "V3File.h"
#include "V3Global.h"
#include "V3String.h"

#include <algorithm>
#include <cstdarg>
#include <iomanip>
#include <map>
#include <memory>
#include <unordered_set>
#include <vector>

class VSymGraph;
class VSymEnt;

//######################################################################
// Symbol table

using VSymConstMap = std::unordered_set<const VSymEnt*>;

class VSymEnt final {
    // Symbol table that can have a "superior" table for resolving upper references
    // MEMBERS
    using IdNameMap = std::multimap<std::string, VSymEnt*>;
    // Most entries (variables, imported symbols) never get children, so only allocate on insert
    struct Names final {
        IdNameMap m_idName;  // Hash of variables by name
        std::unordered_set<std::string> m_idNameSimilar;  // Variables by name with same case
    };
    std::unique_ptr<Names> m_namesp;
    // Packages imported with 'import pkg::*', in import order. Per IEEE 1800-2023 26.3 their
    // symbols are only candidates, imported into the name map on first lookup, as copying
    // every symbol is O(package size) per importing scope.
    std::vector<const VSymEnt*> m_wildImportps;
    VSymGraph* const m_graphp;  // Graph that owns this entry
    AstNode* m_nodep;  // Node that entry belongs to
    VSymEnt* m_fallbackp = nullptr;  // Table "above" this in name scope, for fallback resolution
    VSymEnt* m_parentp = nullptr;  // Table that created this
    AstNodeModule* m_classOrPackagep = nullptr;  // Package node is in (for V3LinkDot, unused here)
    string m_symPrefix;  // String to prefix symbols with (for V3LinkDot, unused here)
    bool m_exported = true;  // Allow importing
    bool m_imported = false;  // Was imported
    bool m_wildImported = false;  // Was imported on lookup through a wildcard import
    bool m_importAmbiguous = false;  // Wildcard imported, but a different item of the same name
                                     // was also wildcard imported (IEEE 1800-2023 26.3)
    bool m_hidesWildcard = false;  // Declaration hides a wildcard imported item of the same name
    bool m_checkWildConflicts = true;  // Track names wildcard imported from multiple packages
    bool m_referenced = false;  // Found by a lookup, so a wildcard import actually imports it
    bool m_wildExported = false;  // Exported by a wildcard export, so only if m_referenced
    // Entry of the package that exported this by a wildcard export, which only exports it if
    // referenced in that package (IEEE 1800-2023 26.6)
    const VSymEnt* m_exportedWildcardp = nullptr;
    const VSymEnt* m_exporterp = nullptr;  // Package table of m_exportedWildcardp
#ifdef VL_DEBUG
    VL_DEFINE_DEBUG_FUNCTIONS;
#else
    static constexpr int debug() { return 0; }  // NOT runtime, too hot of a function
#endif
public:
    using const_iterator = IdNameMap::const_iterator;
    const IdNameMap& idNameMap() const {  // Read access only, as lazy-stored empty
        static const IdNameMap s_empty;
        return m_namesp ? m_namesp->m_idName : s_empty;
    }
    Names& namesWritable() {  // Going to insert, dynamically create if does not exist
        if (!m_namesp) m_namesp = std::make_unique<Names>();
        return *m_namesp;
    }
    const_iterator begin() const {
        const IdNameMap& nameMapr = idNameMap();
        return nameMapr.begin();
    }
    const_iterator end() const {
        const IdNameMap& nameMapr = idNameMap();
        return nameMapr.end();
    }

    void dumpIterate(std::ostream& os, VSymConstMap& doneSymsr, const string& indent,
                     int numLevels, const string& searchName) const {
        os << indent << "+ " << std::left << std::setw(30) << ("'"s + searchName + "'"s)
           << std::setw(0) << std::right;
        os << "  se" << cvtToHex(this) << std::setw(0);
        os << "  fallb=se" << cvtToHex(m_fallbackp);
        if (m_imported || m_exported) {
            os << "  ";
            if (m_imported) os << "[I]";
            if (m_exported) os << "[E]";
        }
        if (m_symPrefix != "") os << "  symPrefix=" << m_symPrefix;
        if (nodep()) os << "  n=" << nodep();
        os << '\n';
        if (VL_UNCOVERABLE(!doneSymsr.insert(this).second)) {
            os << indent << "| ^ duplicate, so no children printed\n";  // LCOV_EXCL_LINE
        } else {
            for (const auto& itr : idNameMap()) {
                if (numLevels >= 1) {
                    itr.second->dumpIterate(os, doneSymsr, indent + "| ", numLevels - 1,
                                            itr.first);
                }
            }
            for (const VSymEnt* const pkgSymp : m_wildImportps) {
                os << indent << "| * wildcard import se" << cvtToHex(pkgSymp)
                   << "  n=" << cvtToHex(pkgSymp->nodep()) << '\n';
            }
        }
    }
    void dumpSelf(std::ostream& os, const string& indent = "", int numLevels = 1) const {
        VSymConstMap doneSyms;
        dumpIterate(os, doneSyms, indent, numLevels, "TOP");
    }

    // METHODS
    VSymEnt(VSymGraph* graphp, const VSymEnt* symp);  // Below
    VSymEnt(VSymGraph* graphp, AstNode* nodep);  // Below
    ~VSymEnt() {
        // Change links so we coredump if used
#ifdef VL_DEBUG
        m_nodep = reinterpret_cast<AstNode*>(1);
        m_fallbackp = reinterpret_cast<VSymEnt*>(1);
        m_parentp = reinterpret_cast<VSymEnt*>(1);
        m_classOrPackagep = reinterpret_cast<AstNodeModule*>(1);
#endif
    }
#if (defined(VL_DEBUG) || defined(VL_ALLOC_RANDOM_CHECKS)) && !defined(VL_LEAK_CHECKS)
    // For testing, leak so above destructor 1 assignments work
    void* operator new(size_t size) { return std::malloc(size); }
    void operator delete(void* objp, size_t size) {}
#endif
    void fallbackp(VSymEnt* entp) { m_fallbackp = entp; }
    VSymEnt* fallbackp() const { return m_fallbackp; }
    void parentp(VSymEnt* entp) { m_parentp = entp; }
    VSymEnt* parentp() const { return m_parentp; }
    // True if symp is a parent of this table, without going above stopp
    bool isEnclosedBy(const VSymEnt* symp, const VSymEnt* stopp) const {
        for (const VSymEnt* curp = this; curp != stopp; curp = curp->parentp()) {
            if (curp->parentp() == symp) return true;
        }
        return false;
    }
    void classOrPackagep(AstNodeModule* entp) { m_classOrPackagep = entp; }
    AstNodeModule* classOrPackagep() const { return m_classOrPackagep; }
    AstNode* nodep() const { return m_nodep; }
    string symPrefix() const { return m_symPrefix; }
    void symPrefix(const string& name) { m_symPrefix = name; }
    bool exported() const { return m_exported; }
    void exported(bool flag) { m_exported = flag; }
    bool imported() const { return m_imported; }
    void imported(bool flag) { m_imported = flag; }
    bool importAmbiguous() const { return m_importAmbiguous; }
    bool hidesWildcard() const { return m_hidesWildcard; }
    const VSymEnt* exportedWildcardp() const { return m_exportedWildcardp; }
    const VSymEnt* exporterp() const { return m_exporterp; }
    bool referenced() const { return m_referenced; }
    void hidesWildcard(bool flag) { m_hidesWildcard = flag; }
    VSymEnt* insert(const string& name, VSymEnt* entp) {
        UINFO(9, "     SymInsert se" << cvtToHex(this) << " '" << name << "' se" << cvtToHex(entp)
                                     << "  " << entp->nodep());
        const IdNameMap& nameMapr = idNameMap();
        if (name != "" && nameMapr.find(name) != nameMapr.end()) {
            // If didn't already report warning
            if (!V3Error::errorCount()) {  // LCOV_EXCL_START
                if (debug() >= 9 || V3Error::debugDefault())
                    dumpSelf(std::cout, "- err-dump: ", 1);
                entp->nodep()->v3fatalSrc("Inserting two symbols with same name: " << name);
            }  // LCOV_EXCL_STOP
        } else {
            namesWritable().m_idName.emplace(name, entp);
        }
        if (!name.empty() && name.find("__DOT__") == std::string::npos  // ignore hierarchical
            && checkSimilarname(entp->nodep())) {
            string lc = name;
            for (auto& c : lc) c = (char)tolower(c);
            namesWritable().m_idNameSimilar.insert(lc);
        }

        return entp;
    }
    void reinsert(const string& name, VSymEnt* entp) {
        IdNameMap& nameMap = namesWritable().m_idName;
        const auto it = nameMap.find(name);
        if (name != "" && it != nameMap.end()) {
            UINFO(9, "     SymReinsert se" << cvtToHex(this) << " '" << name << "' se"
                                           << cvtToHex(entp) << "  " << entp->nodep());
            it->second = entp;  // Replace
        } else {
            insert(name, entp);
        }
    }
    VSymEnt* findIdFlat(const string& name) {
        // Find identifier without looking upward through symbol hierarchy, as a reference.
        // Marks the entry referenced even if the lookup is not a reference, e.g. a duplicate
        // check, which only makes the wildcard export check (IEEE 1800-2023 26.6) more lenient
        VSymEnt* const symp = findIdFlatNoRef(name);
        if (symp) symp->m_referenced = true;
        return symp;
    }
    // Find identifier without looking upward, and without marking it referenced
    VSymEnt* findIdFlatNoRef(const string& name) {
        // First, scan this begin/end block or module for the name
        const IdNameMap& nameMapr = idNameMap();
        const auto it = nameMapr.find(name);
        UINFO(9, "     SymFind   se"
                     << cvtToHex(this) << " '" << name << "' -> "
                     << (it == nameMapr.end() ? "NONE"
                                              : "se" + cvtToHex(it->second)
                                                    + " n=" + cvtToHex(it->second->nodep())));
        if (it != nameMapr.end()) return it->second;
        // Then import it from a wildcard imported package
        return importWildCandidate(name);
    }
    // Whether name is, or on lookup would be, imported here through a wildcard import
    bool wildImportable(const string& name) const {
        const IdNameMap& nameMapr = idNameMap();
        const auto it = nameMapr.find(name);
        if (it != nameMapr.end()) return it->second->m_wildImported;
        for (const VSymEnt* const pkgSymp : m_wildImportps) {
            const IdNameMap& pkgNameMapr = pkgSymp->idNameMap();
            const auto pkgIt = pkgNameMapr.find(name);
            if (pkgIt != pkgNameMapr.end() && pkgIt->second->exported()) return true;
        }
        return false;
    }
    static bool checkSimilarname(const AstNode* nodep) {
        // Only declarations that can contribute a name to the netlist handed
        // to a backend tool.
        if (const AstVar* const varp = VN_CAST(nodep, Var)) {
            return !varp->isParam() && !varp->isGenVar();
        }
        return VN_IS(nodep, Cell)  //
               || VN_IS(nodep, NodeBlock)  //
               || VN_IS(nodep, GenBlock)  //
               || VN_IS(nodep, NodeFTask);
    }
    VSymEnt* findSimilarIdFlat(const string& name) const {
        // Find identifier without looking upward through symbol hierarchy
        // Were looking for symbols that are the same when compared without
        // caring about case, but that are not the same name
        if (name.find("__DOT__") != std::string::npos)  // ignore hierarchical equivalents
            return nullptr;
        string s = name;
        for (auto& c : s) c = (char)tolower(c);
        if (!m_namesp || !m_namesp->m_idNameSimilar.count(s)) return nullptr;
        for (const auto& itr : idNameMap()) {
            // Only report a declaration that is itself checked, otherwise we
            // might point at e.g. a localparam that merely sorts first
            if (!checkSimilarname(itr.second->nodep())) continue;
            // Not a wildcard import, which is only here if some lookup happened to import it
            if (itr.second->m_wildImported) continue;
            string t = itr.first;
            for (auto& c : t) c = (char)tolower(c);
            if (t == s && name != itr.first) return itr.second;
        }
        return nullptr;
    }
    VSymEnt* findIdFallback(const string& name) {
        // Find identifier looking upward through symbol hierarchy
        // First, scan this begin/end block or module for the name
        if (VSymEnt* const entp = findIdFlat(name)) return entp;
        // Then scan the upper begin/end block or module for the name
        if (m_fallbackp) return m_fallbackp->findIdFallback(name);
        return nullptr;
    }
    void candidateIdFlat(VSpellCheck* spellerp, const VNodeMatcher* matcherp,
                         bool includeType) const {
        // Suggest alternative symbol candidates without looking upward through symbol
        // hierarchy
        for (const auto& itr : idNameMap()) {
            candidateId(spellerp, matcherp, includeType, itr.second->nodep());
        }
        for (const VSymEnt* const pkgSymp : m_wildImportps) {
            for (const auto& itr : pkgSymp->idNameMap()) {
                if (itr.second->exported())
                    candidateId(spellerp, matcherp, includeType, itr.second->nodep());
            }
        }
    }
    void candidateIdFallback(VSpellCheck* spellerp, const VNodeMatcher* matcherp) const {
        // Suggest alternative symbol candidates with looking upward through symbol hierarchy
        // Note VSpellCheck wants the most important (closest) items pushed first
        candidateIdFlat(spellerp, matcherp, false);
        // Then suggest the upper begin/end block or module
        if (m_fallbackp) m_fallbackp->candidateIdFallback(spellerp, matcherp);
    }

private:
    static void candidateId(VSpellCheck* spellerp, const VNodeMatcher* matcherp, bool includeType,
                            const AstNode* itemp) {
        if (itemp && (!matcherp || matcherp->nodeMatch(itemp))) {
            if (includeType) {
                spellerp->pushCandidate(itemp->prettyName(), itemp->prettyTypeNameQ());
            } else {
                spellerp->pushCandidate(itemp->prettyName());
            }
        }
    }
    VSymEnt* newImportedSymbol(const VSymEnt* srcp, const VSymEnt* srcTablep) const {
        VSymEnt* const symp = new VSymEnt{m_graphp, srcp};
        symp->exported(false);  // Can't reimport an import without an export
        symp->imported(true);
        if (srcp->m_wildExported) {
            symp->m_exportedWildcardp = srcp;
            symp->m_exporterp = srcTablep;
        }
        return symp;
    }
    VSymEnt* importWildCandidate(const string& name) {
        // Import name from the first wildcard imported package that exports it
        for (const VSymEnt* const pkgSymp : m_wildImportps) {
            const IdNameMap& pkgNameMapr = pkgSymp->idNameMap();
            const auto pkgIt = pkgNameMapr.find(name);
            if (pkgIt == pkgNameMapr.end() || !pkgIt->second->exported()) continue;
            VSymEnt* const symp = insert(name, newImportedSymbol(pkgIt->second, pkgSymp));
            symp->m_wildImported = true;
            for (const VSymEnt* const otherp : m_wildImportps) checkWildImport(otherp, name, symp);
            return symp;
        }
        return nullptr;
    }
    // Update wildcard imported entry symp for package pkgSymp also wildcard imported
    void checkWildImport(const VSymEnt* pkgSymp, const string& name, VSymEnt* symp) const {
        const IdNameMap& pkgNameMapr = pkgSymp->idNameMap();
        const auto it = pkgNameMapr.find(name);
        if (it == pkgNameMapr.end() || !it->second->exported()) return;
        if (it->second->nodep() != symp->nodep()) {
            if (m_checkWildConflicts) symp->m_importAmbiguous = true;
        } else if (!it->second->m_wildExported) {
            // Also visible through this package, so not only through a wildcard export
            symp->m_exportedWildcardp = nullptr;
        }
    }
    void addWildImport(const VSymEnt* pkgSymp) {
        // Repeated imports of a package would only slow lookups that miss
        if (std::find(m_wildImportps.begin(), m_wildImportps.end(), pkgSymp)
            != m_wildImportps.end()) {
            return;
        }
        m_wildImportps.push_back(pkgSymp);
        // Names imported by earlier lookups are not looked up again
        for (const auto& itr : idNameMap()) {
            if (itr.second->m_wildImported) checkWildImport(pkgSymp, itr.first, itr.second);
        }
    }
    void importOneSymbol(const string& name, const VSymEnt* srcp, const VSymEnt* srcTablep,
                         bool honorExport) {
        if (honorExport && !srcp->exported()) return;
        // An explicit import hides a wildcard import, but not a declaration or other import
        const IdNameMap& nameMapr = idNameMap();
        const auto it = nameMapr.find(name);
        if (it == nameMapr.end() || it->second->m_wildImported) {
            reinsert(name, newImportedSymbol(srcp, srcTablep));
        } else if (it->second->nodep() == srcp->nodep() && !srcp->m_wildExported) {
            // Also visible by this import, so not only through a wildcard export
            it->second->m_exportedWildcardp = nullptr;
        }
    }
    void exportOneSymbol(const string& name, const VSymEnt* srcp, const VSymEnt* srcTablep,
                         bool wildcard) {
        // Export the declaration srcp, importing it if a wildcard import makes it a candidate,
        // through any package, per IEEE 1800-2023 26.6. Exporting a name that is not imported
        // is reported by V3LinkDot.
        if (!srcp->exported()) return;
        const IdNameMap& nameMapr = idNameMap();
        const auto it = nameMapr.find(name);
        if (it != nameMapr.end() && !it->second->m_wildImported) {
            if (it->second->nodep() == srcp->nodep()) {
                it->second->exported(true);
                // A named export makes the name available even if not referenced
                if (!wildcard) it->second->m_referenced = true;
            }
            return;
        }
        for (const VSymEnt* const pkgSymp : m_wildImportps) {
            const IdNameMap& pkgNameMapr = pkgSymp->idNameMap();
            const auto pkgIt = pkgNameMapr.find(name);
            if (pkgIt != pkgNameMapr.end() && pkgIt->second->exported()
                && pkgIt->second->nodep() == srcp->nodep()) {
                VSymEnt* const symp = newImportedSymbol(srcp, srcTablep);
                symp->exported(true);
                // A wildcard export only exports a candidate referenced here, also later
                symp->m_wildExported = wildcard;
                symp->m_referenced
                    = !wildcard || (it != nameMapr.end() && it->second->m_referenced);
                reinsert(name, symp);
                // A wildcard export, unlike a named one, does not pick this package's item
                if (wildcard) {
                    for (const VSymEnt* const otherp : m_wildImportps) {
                        checkWildImport(otherp, name, symp);
                    }
                }
                return;
            }
        }
    }

public:
    void importFromClass(const VSymEnt* srcp) {
        // Import tokens from source symbol table into this symbol table
        // Used for classes in early parsing only to handle "extends"

        // If an "extern foo" exists, then we can't import "foo" from the base class.
        // But ok for "extern foo" and "foo" to both come from base (so must check before
        // insert)
        std::unordered_set<std::string> haveExterns;
        for (const auto& itr : srcp->idNameMap()) {
            if (idNameMap().count("extern " + itr.first)) haveExterns.emplace(itr.first);
        }
        for (const auto& itr : srcp->idNameMap()) {
            if (!haveExterns.count(itr.first)) importOneSymbol(itr.first, itr.second, srcp, false);
        }
    }
    void importFromPackage(const VSymEnt* srcp, const string& id_or_star,
                           bool checkWildConflicts) {
        // Import tokens from source symbol table into this symbol table.
        // If !checkWildConflicts, a name wildcard imported from several packages is taken from
        // the first one, without marking it ambiguous.
        if (id_or_star != "*") {
            const IdNameMap& srcNameMapr = srcp->idNameMap();
            const auto it = srcNameMapr.find(id_or_star);
            if (it != srcNameMapr.end()) importOneSymbol(it->first, it->second, srcp, true);
        } else {
            if (!checkWildConflicts) m_checkWildConflicts = false;
            addWildImport(srcp);  // Symbols are imported on lookup, see findIdFlat
        }
    }
    void exportFromPackage(const VSymEnt* srcp, const string& id_or_star) {
        // Export tokens from source symbol table into this symbol table
        const IdNameMap& srcNameMapr = srcp->idNameMap();
        if (id_or_star != "*") {
            const auto it = vlstd::as_const(srcNameMapr).find(id_or_star);
            if (it != srcNameMapr.end()) exportOneSymbol(it->first, it->second, srcp, false);
        } else {
            for (const auto& itr : srcNameMapr) {
                exportOneSymbol(itr.first, itr.second, srcp, true);
            }
        }
    }
    void exportStarStar() {
        // Export *:*: Export all tokens from imported packages
        for (const VSymEnt* const pkgSymp : m_wildImportps) {
            for (const auto& itr : pkgSymp->idNameMap()) {
                // Import, so marked exported below, but not as a reference
                if (!idNameMap().count(itr.first)) importWildCandidate(itr.first);
            }
        }
        for (const auto& itr : idNameMap()) {
            VSymEnt* const symp = itr.second;
            if (!symp->exported()) symp->exported(true);
            // Only exported if referenced (IEEE 1800-2023 26.6)
            if (symp->m_wildImported) symp->m_wildExported = true;
        }
    }
    void importFromIface(const VSymEnt* srcp, bool onlyUnmodportable = false) {
        // Import interface tokens from source symbol table into this symbol table, recursively
        UINFO(9, "     importIf  se" << cvtToHex(this) << " from se" << cvtToHex(srcp));
        // Not for a modport, as only its items are visible through it; modport parameter and
        // type lookups fall back to the interface itself, which resolves its wildcard imports
        if (!onlyUnmodportable) {
            for (const VSymEnt* const pkgSymp : srcp->m_wildImportps) addWildImport(pkgSymp);
        }
        for (const auto& itr : srcp->idNameMap()) {
            const string& name = itr.first;
            VSymEnt* const subSrcp = itr.second;
            const AstVar* const varp = VN_CAST(subSrcp->nodep(), Var);
            if (!onlyUnmodportable || (varp && varp->isParam())) {
                VSymEnt* const subSymp = new VSymEnt{m_graphp, subSrcp};
                reinsert(name, subSymp);
                // And recurse to create children, except under an AstVar: an interface reference
                // may be of the interface being imported, so would recurse forever, and lookups
                // through it go to its own symbol or its interface, never this copy.
                if (!varp) subSymp->importFromIface(subSrcp);
            }
        }
    }
    string cellErrorScopes(const AstNode* lookp, string prettyName = "") {
        if (prettyName == "") prettyName = lookp->prettyName();
        string scopes;
        for (const auto& itr : idNameMap()) {
            const AstNode* const itemp = itr.second->nodep();
            if (VN_IS(itemp, Cell) || (VN_IS(itemp, Module) && VN_AS(itemp, Module)->isTop())) {
                if (scopes != "") scopes += ", ";
                scopes += AstNode::prettyName(itr.first);
            }
        }
        if (scopes == "") scopes = "<no instances found>";
        if (debug()) dumpSelf(std::cerr, "       KnownScope: ", 1);
        return V3Error::warnMore() + "... Known scopes under '" + prettyName + "': " + scopes
               + '\n';
    }
};

//######################################################################
// Symbol tables

class VSymGraph final {
    // Collection of symbol tables
    // TYPES
    using SymStack = std::vector<VSymEnt*>;

    // MEMBERS
    VSymEnt* m_symRootp;  // Root symbol table
    SymStack m_symsp;  // All symbol tables, to cleanup

    // CONSTRUCTORS
    VL_UNCOPYABLE(VSymGraph);

    VL_DEFINE_DEBUG_FUNCTIONS;

public:
    explicit VSymGraph(AstNetlist* nodep) { m_symRootp = new VSymEnt{this, nodep}; }
    ~VSymGraph() {
        for (const VSymEnt* entp : m_symsp) delete entp;
    }

    // METHODS
    VSymEnt* rootp() const { return m_symRootp; }
    size_t importedCount() const {
        return std::count_if(m_symsp.begin(), m_symsp.end(),
                             [](const VSymEnt* const entp) { return entp->imported(); });
    }
    // Debug
    void dumpSelf(std::ostream& os, const string& indent = "") {
        VSymConstMap doneSyms;
        os << "SymEnt Dump:\n";
        m_symRootp->dumpIterate(os, doneSyms, indent, 9999, "$root");
        bool first = true;
        for (const auto& itr : m_symsp) {
            if (doneSyms.find(itr) == doneSyms.end()) {
                if (first) {
                    first = false;
                    os << "%%Warning: SymEnt Orphans:\n";
                }
                (itr)->dumpIterate(os, doneSyms, indent, 9999, "Orphan");
            }
        }
    }
    void dumpFilePrefixed(const string& nameComment) {
        if (dumpTreeLevel()) {
            const string filename = v3Global.debugFilename(nameComment) + ".txt";
            UINFO(2, "Dumping " << filename);
            const std::unique_ptr<std::ofstream> logp{V3File::new_ofstream(filename)};
            if (logp->fail()) v3fatal("Can't write file: " << filename);
            dumpSelf(*logp, "");
        }
    }

protected:
    friend class VSymEnt;
    void pushNewEnt(VSymEnt* entp) { m_symsp.push_back(entp); }
};

//######################################################################

inline VSymEnt::VSymEnt(VSymGraph* graphp, AstNode* nodep)
    : m_graphp{graphp}
    , m_nodep{nodep} {
    // No argument to set fallbackp, as generally it's wrong to set it in the new call,
    // Instead it needs to be set on a "findOrNew()" return, as it may have been new'ed
    // by an earlier search insertion.
    graphp->pushNewEnt(this);
}

inline VSymEnt::VSymEnt(VSymGraph* graphp, const VSymEnt* symp)
    : m_graphp{graphp}
    , m_nodep{symp->m_nodep}
    , m_fallbackp{symp->m_fallbackp}
    , m_parentp{symp->m_parentp}
    , m_classOrPackagep{symp->m_classOrPackagep}
    , m_exported{symp->m_exported}
    , m_imported{symp->m_imported} {
    graphp->pushNewEnt(this);
}

#endif  // guard
