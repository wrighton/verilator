// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Build DPI protected C++ and SV
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

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3ProtectLib.h"

#include "V3Control.h"
#include "V3File.h"
#include "V3Hasher.h"
#include "V3InstrCount.h"
#include "V3String.h"
#include "V3Task.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// ProtectLib top-level visitor

class ProtectVisitor final : public VNVisitor {
    // TYPES
    struct InoutPorts final {
        AstVar* inp = nullptr;  // Resolved input value and original public port
        AstVar* outp = nullptr;  // Library drive value
        AstVar* enp = nullptr;  // Per-bit drive enable
    };

    // MEMBERS
    AstVFile* m_vfilep = nullptr;  // DPI-enabled Verilog wrapper
    AstCFile* m_cfilep = nullptr;  // C implementation of DPI functions
    // Verilog text blocks
    AstTextBlock* m_modPortsp = nullptr;  // Module port list
    AstTextBlock* m_comboPortsp = nullptr;  // Combo function port list
    AstTextBlock* m_seqPortsp = nullptr;  // Sequential function port list
    AstTextBlock* m_comboIgnorePortsp = nullptr;  // Combo ignore function port list
    AstTextBlock* m_comboDeclsp = nullptr;  // Combo signal declaration list
    AstTextBlock* m_seqDeclsp = nullptr;  // Sequential signal declaration list
    AstTextBlock* m_tmpDeclsp = nullptr;  // Temporary signal declaration list
    AstTextBlock* m_inoutDeclsp = nullptr;  // Lowered inout signals and tristate drivers
    AstTextBlock* m_hashValuep = nullptr;  // CPP hash value
    AstTextBlock* m_comboParamsp = nullptr;  // Combo function parameter list
    AstTextBlock* m_clkSensp = nullptr;  // Clock sensitivity list
    AstTextBlock* m_comboIgnoreParamsp = nullptr;  // Combo ignore parameter list
    AstTextBlock* m_seqParamsp = nullptr;  // Sequential parameter list
    AstTextBlock* m_nbAssignsp = nullptr;  // Non-blocking assignment list
    AstTextBlock* m_seqInitp = nullptr;  // The first update of clocks, if outputs need its results
    AstTextBlock* m_seqAssignsp = nullptr;  // Sequential assignment list
    AstTextBlock* m_comboAssignsp = nullptr;  // Combo assignment list
    // C text blocks
    AstTextBlock* m_cHashValuep = nullptr;  // CPP hash value
    AstTextBlock* m_cComboParamsp = nullptr;  // Combo function parameter list
    AstTextBlock* m_cComboInsp = nullptr;  // Combo input copy list
    AstTextBlock* m_cComboOutsp = nullptr;  // Combo output copy list
    AstTextBlock* m_cSeqParamsp = nullptr;  // Sequential parameter list
    AstTextBlock* m_cSeqClksp = nullptr;  // Sequential clock copy list
    AstTextBlock* m_settleDeclp = nullptr;  // Where the settle function is declared, if needed
    AstTextBlock* m_settleCallp = nullptr;  // Where the settle function is called, if needed
    AstTextBlock* m_cSettlep = nullptr;  // Where the settle function is defined, if needed
    AstTextBlock* m_settlePortsp = nullptr;  // Settle function's SV declaration ports
    AstTextBlock* m_cSettleParamsp = nullptr;  // Settle function's C parameters
    AstTextBlock* m_cSettleOutsp = nullptr;  // Settle function's output copies
    AstTextBlock* m_cSeqOutsp = nullptr;  // Sequential output copy list
    AstTextBlock* m_cIgnoreParamsp = nullptr;  // Combo ignore parameter list
    // With --vpi, the emitted names of the wrapper's ports and local signals
    std::unordered_set<std::string> m_usedNames;
    std::string m_vpiWritesName;  // Count of writes through the VPI into the library module
    std::string m_vpiWrittenName;  // Export counting them
    std::string m_initName = "init__V";  // Set at initial time
    std::string m_lastSeqName = "last_seq_seqnum__V";  // Sequence number of the update of clocks
    std::string m_seqNumName = "seq_seqnum__V";  // Same, at once
    std::string m_seqInitName = "seq_init__V";  // Set after the first update of clocks
    std::string m_seqFirstName = "seq_first__V";  // Set in the first update of clocks
    std::string m_settleName;  // Function settling the library before the first update of clocks
    AstTextBlock* m_selectp = nullptr;  // Results whichever update ran last
    AstTextBlock* m_seqFirstp = nullptr;  // Call of the settle function before the first update
    const string m_libName;
    const string m_topName;
    bool m_foundTop = false;  // Have seen the top module
    // True if the wrapper updates the clocks: the top module has sequential logic, or with --vpi,
    // for the update after a write through the VPI into it
    bool m_hasSeqUpdate = false;
    std::map<int, InoutPorts> m_inouts;  // Lowered ports grouped by original inout

    // VISITORS
    void visit(AstNetlist* nodep) override {
        m_vfilep
            = new AstVFile{nodep->fileline(), v3Global.opt.makeDir() + "/" + m_libName + ".sv"};
        nodep->addFilesp(m_vfilep);
        m_cfilep
            = new AstCFile{nodep->fileline(), v3Global.opt.makeDir() + "/" + m_libName + ".cpp"};
        nodep->addFilesp(m_cfilep);
        iterateChildren(nodep);
    }

    void visit(AstNodeModule* nodep) override {
        if (!nodep->isTop()) {
            return;
        } else {
            UASSERT_OBJ(!m_foundTop, nodep, "Multiple root modules");
        }
        FileLine* const fl = nodep->fileline();
        // Need to know the existence of clk before createSvFile()
        m_hasSeqUpdate = checkIfClockExists(nodep) || v3Global.opt.vpi();
        // The wrapper's signals must not take the name of a port or another of them
        for (const AstNode* const stmtp : nodep->stmtspList()) {
            const AstVar* const varp = VN_CAST(stmtp, Var);
            if (!varp || !varp->isIO()) continue;
            m_usedNames.emplace(svPortName(varp));
            m_usedNames.emplace(AstNode::verilogIdent(varp->name() + "_combo__V"));
        }
        m_seqInitName = uniqueName(m_seqInitName);
        m_seqFirstName = uniqueName(m_seqFirstName);
        m_settleName = uniqueName(m_libName + "_protectlib_settle");
        m_seqNumName = uniqueName(m_seqNumName);
        if (v3Global.opt.vpi()) {
            // Nor the signals and functions --vpi adds, also to a top module without sequential
            // logic
            for (const std::string& name :
                 {std::string{"handle__V"}, std::string{"last_combo_seqnum__V"},
                  std::string{"protectlib_hash__V"}, m_libName + "_protectlib_check_hash",
                  m_libName + "_protectlib_create", m_libName + "_protectlib_combo_update",
                  m_libName + "_protectlib_seq_update", m_libName + "_protectlib_combo_ignore",
                  m_libName + "_protectlib_final"}) {
                m_usedNames.emplace(name);
            }
            m_vpiWritesName = uniqueName("vpi_writes__V");
            m_vpiWrittenName = uniqueName(m_libName + "_protectlib_vpi_written");
            m_initName = uniqueName(m_initName);
            m_lastSeqName = uniqueName(m_lastSeqName);
        }
        createSvFile(fl, nodep);
        createCppFile(fl);

        iterateChildren(nodep);

        restoreInouts();

        // cppcheck-suppress unreadVariable
        const V3Hash hash = V3Hasher::uncachedHash(m_cfilep);
        m_hashValuep->add(cvtToStr(hash.value()) + ";\n");
        m_cHashValuep->add(cvtToStr(hash.value()) + "U;\n");
        m_foundTop = true;
    }

    // 'base', or 'base' with a suffix, not the name of another port or signal of the wrapper
    std::string uniqueName(const std::string& base) {
        std::string name = base;
        for (int suffix = 1; !m_usedNames.emplace(AstNode::verilogIdent(name)).second; ++suffix) {
            name = base + "_" + std::to_string(suffix);
        }
        return name;
    }

    void addComment(AstTextBlock* txtp, FileLine* fl, const string& comment) {
        txtp->add(new AstComment{fl, comment});
    }

    void configSection(AstNodeModule* /*modp*/, AstTextBlock* txtp, FileLine* /*fl*/) {
        txtp->add("\n`ifdef VERILATOR\n");
        txtp->add("`verilator_config\n");

        // V3Control finds the module by its pretty name, see the module declaration below
        txtp->add("verilator_lib -module \""
                  + (v3Global.opt.hierChild()
                         ? V3OutFormatter::quoteNameControls(AstNode::prettyName(m_libName))
                         : m_libName)
                  + "\"\n");

        txtp->add("profile_data -hier-dpi \"" + m_libName + "_protectlib_combo_update\" -cost 64'd"
                  + std::to_string(v3Global.currentHierBlockCost()) + "\n");
        txtp->add("profile_data -hier-dpi \"" + m_libName + "_protectlib_seq_update\" -cost 64'd"
                  + std::to_string(v3Global.currentHierBlockCost()) + "\n");

        // Mark remaining NBA protectlib wrapper DPIs as non-hazardous by deliberately forwarding
        // them with non-zero cost.
        // Also, specify hierarchical workers for those tasks for scheduling.
        txtp->add("profile_data -hier-dpi \"" + m_libName
                  + "_protectlib_combo_ignore\" -cost 64'd1\n");
        txtp->add("profile_data -hier-dpi \"" + m_settleName + "\" -cost 64'd1\n");

        txtp->add("hier_workers -hier-dpi \"" + m_libName
                  + "_protectlib_combo_update\" -workers 16'd"
                  + std::to_string(V3Control::getHierWorkers(m_libName)) + "\n");
        txtp->add("hier_workers -hier-dpi \"" + m_libName
                  + "_protectlib_seq_update\" -workers 16'd"
                  + std::to_string(V3Control::getHierWorkers(m_libName)) + "\n");
        // No workers for combo_ignore
        txtp->add("`verilog\n");
        txtp->add("`endif\n");
    }

    void hashComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Checks to make sure the .sv wrapper and library agree");
    }

    void initialComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Creates an instance of the library module at initial-time");
        addComment(txtp, fl, "(one for each instance in the user's design)");
    }

    void comboComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Updates all non-clock inputs and retrieves the results");
    }

    void seqComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Updates all clocks and retrieves the results");
    }

    void comboIgnoreComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Need to convince some simulators that the input to the module");
        addComment(txtp, fl, "must be evaluated before evaluating the clock edge");
    }

    void finalComment(AstTextBlock* txtp, FileLine* fl) {
        addComment(txtp, fl, "Evaluates the library module's final process");
    }

    void createSvFile(FileLine* fl, AstNodeModule* modp) {
        // Comments
        AstTextBlock* const txtp = new AstTextBlock{fl};
        addComment(txtp, fl, "Wrapper module for DPI protected library");
        addComment(txtp, fl,
                   "This module requires lib" + m_libName + ".a or lib" + m_libName
                       + ".so to work");
        addComment(txtp, fl,
                   "See instructions in your simulator for how"
                   " to use DPI libraries\n");

        // Module declaration
        // Wrapper ranges preserve the original RTL, including intentional ascending ranges.
        txtp->add("/*verilator lint_save*/\n");
        txtp->add("/*verilator lint_off ASCRANGE*/\n");
        // A hierarchical child's library is its encoded module name, a user's is kept as given
        const string libIdent
            = v3Global.opt.hierChild() ? AstNode::verilogIdent(m_libName) : m_libName;
        m_modPortsp = new AstTextBlock{fl, "module " + libIdent + " (\n", ", ", ");\n\n"};
        txtp->add(m_modPortsp);

        // Timescale
        if (v3Global.opt.hierChild() && v3Global.rootp()->timescaleSpecified()) {
            // Emit timescale for hierarchical Verilation if input HDL specifies timespec
            txtp->add("timeunit "s + modp->timeunit().ascii() + ";\n");
            txtp->add("timeprecision "s + +v3Global.rootp()->timeprecision().ascii() + ";\n");
        } else {
            addComment(txtp, fl,
                       "Precision of submodule"
                       " (commented out to avoid requiring timescale on all modules)");
            addComment(txtp, fl, "timeunit "s + v3Global.rootp()->timeunit().ascii() + ";");
            addComment(txtp, fl,
                       "timeprecision "s + v3Global.rootp()->timeprecision().ascii() + ";\n");
        }

        // DPI declarations
        hashComment(txtp, fl);
        txtp->add("import \"DPI-C\" function void " + m_libName
                  + "_protectlib_check_hash(int protectlib_hash__V);\n\n");
        initialComment(txtp, fl);
        txtp->add("import \"DPI-C\" function chandle " + m_libName
                  + "_protectlib_create(string scope__V);\n\n");
        comboComment(txtp, fl);
        m_comboPortsp = new AstTextBlock{fl,  //
                                         "import \"DPI-C\" function longint unsigned " + m_libName
                                             + "_protectlib_combo_update(\n",  //
                                         ", ",  //
                                         ");\n\n"};
        m_comboPortsp->add("chandle handle__V\n");
        txtp->add(m_comboPortsp);
        seqComment(txtp, fl);
        if (m_hasSeqUpdate) {
            m_seqPortsp = new AstTextBlock{fl,  //
                                           "import \"DPI-C\" function longint unsigned "
                                               + m_libName + "_protectlib_seq_update(\n",  //
                                           ", ",  //
                                           ");\n\n"};
            m_seqPortsp->add("chandle handle__V\n");
            txtp->add(m_seqPortsp);
            m_settleDeclp = new AstTextBlock{fl};
            txtp->add(m_settleDeclp);
        }
        comboIgnoreComment(txtp, fl);
        m_comboIgnorePortsp = new AstTextBlock{fl,  //
                                               "import \"DPI-C\" function void " + m_libName
                                                   + "_protectlib_combo_ignore(\n",  //
                                               ", ",  //
                                               ");\n\n"};
        m_comboIgnorePortsp->add("chandle handle__V\n");
        txtp->add(m_comboIgnorePortsp);

        finalComment(txtp, fl);
        txtp->add("import \"DPI-C\" function void " + m_libName
                  + "_protectlib_final(chandle handle__V);\n\n");

        // Local variables
        // Avoid tracing handle, as it is not a stable value, so breaks wavediff
        // Likewise other internals aren't interesting to the user
        txtp->add("// verilator tracing_off\n");

        txtp->add("chandle handle__V;\n");
        txtp->add("time last_combo_seqnum__V;\n");
        if (v3Global.opt.vpi()) {
            // Written by the export, called after a write through the VPI into the library
            // module, so the update below sees a change of this instance alone
            txtp->add("export \"DPI-C\" function " + m_vpiWrittenName + ";\n");
            txtp->add("int " + m_vpiWritesName + " = 0;\n");
            txtp->add("function void " + m_vpiWrittenName + "();\n");
            txtp->add(/**/ m_vpiWritesName + " = " + m_vpiWritesName + " + 1;\n");
            txtp->add("endfunction\n");
        }
        if (m_hasSeqUpdate) {
            txtp->add("time " + m_lastSeqName + ";\n");
            txtp->add("time " + m_seqNumName + ";\n");
            txtp->add("bit " + m_initName + " = 1'b0;\n");
        }
        txtp->add("\n");

        m_comboDeclsp = new AstTextBlock{fl};
        txtp->add(m_comboDeclsp);
        m_seqDeclsp = new AstTextBlock{fl};
        txtp->add(m_seqDeclsp);
        m_tmpDeclsp = new AstTextBlock{fl};
        txtp->add(m_tmpDeclsp);
        m_inoutDeclsp = new AstTextBlock{fl};
        txtp->add(m_inoutDeclsp);

        // CPP hash value
        addComment(txtp, fl, "Hash value to make sure this file and the corresponding");
        addComment(txtp, fl, "library agree");
        m_hashValuep = new AstTextBlock{
            fl, "localparam int protectlib_hash__V /*verilator public_flat_rd*/ = 32'd", "", "\n"};
        txtp->add(m_hashValuep);

        // Initial
        txtp->add("initial begin\n");
        txtp->add(m_libName + "_protectlib_check_hash(protectlib_hash__V);\n");
        txtp->add("if (handle__V == null) handle__V = " + m_libName
                  + "_protectlib_create"
                    "($sformatf(\"%m\"));\n");
        if (m_hasSeqUpdate) txtp->add(m_initName + " = 1'b1;\n");
        txtp->add("end\n\n");

        // Combinatorial process
        addComment(txtp, fl, "Combinatorially evaluate changes to inputs");
        txtp->add("always_comb begin\n");
        m_comboParamsp = new AstTextBlock{fl,  //
                                          "last_combo_seqnum__V = " + m_libName
                                              + "_protectlib_combo_update(\n",  //
                                          ",\n",  //
                                          "\n);\n"};
        m_comboParamsp->add("handle__V");
        txtp->add(m_comboParamsp);
        txtp->add("end\n\n");

        // Sequential process
        if (m_hasSeqUpdate) {
            addComment(txtp, fl, "Evaluate clock edges");
            m_clkSensp = new AstTextBlock{fl, "always @(", " or ", ")"};
            m_clkSensp->add(m_initName);
            // Also after a write through the VPI into the library module, updating all inputs
            if (v3Global.opt.vpi()) m_clkSensp->add(m_vpiWritesName);
            txtp->add(m_clkSensp);
            txtp->add(" begin\n");
            m_comboIgnoreParamsp
                = new AstTextBlock{fl,  //
                                   m_libName + "_protectlib_combo_ignore(\n", ",\n", "\n);\n"};
            m_comboIgnoreParamsp->add("handle__V");
            txtp->add(m_comboIgnoreParamsp);
            m_settleCallp = new AstTextBlock{fl};
            txtp->add(m_settleCallp);
            m_seqParamsp = new AstTextBlock{
                fl, m_seqNumName + " = " + m_libName + "_protectlib_seq_update(\n", ",\n",
                "\n);\n" + m_lastSeqName + " <= " + m_seqNumName + ";\n"};
            m_seqParamsp->add("handle__V");
            txtp->add(m_seqParamsp);
            m_nbAssignsp = new AstTextBlock{fl};
            txtp->add(m_nbAssignsp);
            m_seqInitp = new AstTextBlock{fl};
            txtp->add(m_seqInitp);
            txtp->add("end\n\n");
        }

        // Select between combinatorial and sequential results
        addComment(txtp, fl, "Select between combinatorial and sequential results");
        txtp->add("always_comb begin\n");
        if (m_hasSeqUpdate) {
            txtp->add("if (" + m_lastSeqName + " > last_combo_seqnum__V) begin\n");
            m_seqAssignsp = new AstTextBlock{fl};
            txtp->add(m_seqAssignsp);
            txtp->add("end else begin\n");
            m_comboAssignsp = new AstTextBlock{fl};
            txtp->add(m_comboAssignsp);
            txtp->add("end\n");
            m_selectp = new AstTextBlock{fl};
            txtp->add(m_selectp);
        } else {
            m_comboAssignsp = new AstTextBlock{fl};
            txtp->add(m_comboAssignsp);
        }
        txtp->add("end\n\n");

        // Final
        txtp->add("final " + m_libName + "_protectlib_final(handle__V);\n\n");

        txtp->add("endmodule\n");
        txtp->add("/*verilator lint_restore*/\n");

        configSection(modp, txtp, fl);

        m_vfilep->tblockp(txtp);
    }

    void castPtr(FileLine* /*fl*/, AstTextBlock* txtp) {
        txtp->add(m_topName
                  + "_container* const handlep__V = "  // LCOV_EXCL_LINE  // lcov bug
                    "static_cast<"
                  + m_topName + "_container*>(vhandlep__V);\n");
    }

    void createCppFile(FileLine* fl) {
        // Comments
        AstTextBlock* const txtp = new AstTextBlock{fl};
        addComment(txtp, fl, "Wrapper functions for DPI protected library\n");

        // Includes
        txtp->add("#include \"" + m_topName + ".h\"\n");
        txtp->add("#include \"verilated_dpi.h\"\n\n");
        txtp->add("#include <cstdio>\n");
        txtp->add("#include <cstdlib>\n\n");

        // Verilated module plus sequence number
        addComment(txtp, fl, "Container class to house verilated object and sequence number");
        txtp->add("class " + m_topName + "_container: public " + m_topName + " {\n");
        txtp->add("public:\n");
        txtp->add("unsigned long long m_seqnum = 0;\n");
        if (v3Global.opt.vpi()) {
            txtp->add("void (*m_vpiWriteCbp)(VerilatedSyms*) = nullptr;\n");
            txtp->add("VerilatedSyms* m_vpiWriteSymsp = nullptr;\n");
        }
        txtp->add(m_topName + "_container(const char* scopep__V):\n");
        txtp->add(m_topName + "(Verilated::threadContextp(), scopep__V, false) {}\n");
        txtp->add("};\n\n");

        // Extern C
        txtp->add("extern \"C\" {\n\n");

        // Hash check
        hashComment(txtp, fl);
        txtp->add("void " + m_libName
                  + "_protectlib_check_hash"
                    "(int protectlib_hash__V) {\n");
        m_cHashValuep = new AstTextBlock{fl, "const int expected_hash__V = ", "", ""};
        txtp->add(m_cHashValuep);
        txtp->add(/**/ "if (protectlib_hash__V != expected_hash__V) {\n");
        txtp->add(/****/ "fprintf(stderr, \"%%Error: cannot use " + m_libName
                  + " library, "
                    "Verliog (%u) and library (%u) hash values do not "
                    "agree\\n\", protectlib_hash__V, expected_hash__V);\n");
        txtp->add(/****/ "std::exit(EXIT_FAILURE);\n");
        txtp->add(/**/ "}\n");
        txtp->add("}\n\n");

        // Delete
        txtp->add("void " + m_libName + "_protectlib_delete(void* vhandlep__V) {\n");
        txtp->add(/**/ "VL_DO_DANGLING(delete static_cast<" + m_topName
                  + "_container*>(vhandlep__V), vhandlep__V);\n");
        txtp->add("}\n\n");

        // Initial
        initialComment(txtp, fl);
        // A Verilator model using the library creates the library model with the VPI scope
        // above its instance. Without VPI, the library model has no VPI scopes to add.
        txtp->add("void* " + m_libName
                  + "_protectlib_create_under(const char* scopep__V, const VerilatedScope* "
                  + (v3Global.opt.vpi() ? "abovep__V" : "/*abovep__V*/") + ") {\n");
        txtp->add(/**/ m_topName + "_container* const handlep__V = new " + m_topName
                  + "_container{scopep__V};\n");
        if (v3Global.opt.vpi()) txtp->add(/**/ "handlep__V->__VvpiAttach(abovep__V);\n");
        txtp->add(/**/ "return handlep__V;\n");
        txtp->add("}\n\n");
        // A library model created otherwise, as in another simulator, has its VPI scopes at the
        // top level, and is deleted with its context, as the model using the library deletes
        // only the library models it created
        txtp->add("void* " + m_libName + "_protectlib_create(const char* scopep__V) {\n");
        txtp->add(/**/ "void* const handlep__V = " + m_libName
                  + "_protectlib_create_under(scopep__V, nullptr);\n");
        txtp->add(/**/ "static_cast<" + m_topName
                  + "_container*>(handlep__V)->contextp()->addEndContextCb(" + m_libName
                  + "_protectlib_delete, handlep__V);\n");
        txtp->add(/**/ "return handlep__V;\n");
        txtp->add("}\n\n");

        if (v3Global.opt.vpi()) {
            addComment(txtp, fl, "Has the model using the library evaluate this instance again,");
            addComment(txtp, fl, "after a write through the VPI into its model");
            txtp->add("static void " + m_libName + "_protectlib_vpi_write(void* vhandlep__V) {\n");
            castPtr(fl, txtp);
            txtp->add(/**/ "handlep__V->m_vpiWriteCbp(handlep__V->m_vpiWriteSymsp);\n");
            addComment(txtp, fl, "That model may itself be an instance of a library");
            txtp->add(/**/ "const VerilatedSyms* const symsp__V = handlep__V->m_vpiWriteSymsp;\n");
            txtp->add(/**/ "if (symsp__V->__Vm_vpiWriteCbp) "
                           "symsp__V->__Vm_vpiWriteCbp(symsp__V->__Vm_vpiWriteCbDatap);\n");
            txtp->add("}\n\n");
            addComment(txtp, fl,
                       "Called by a Verilator model using the library with the function");
            addComment(txtp, fl,
                       "of the instance that has it evaluate the instance again, or with");
            addComment(txtp, fl, "none when that model is deleted");
            txtp->add(
                "void " + m_libName
                + "_protectlib_on_vpi_write(void* vhandlep__V, void (*cbp__V)(VerilatedSyms*), "
                  "VerilatedSyms* symsp__V) {\n");
            castPtr(fl, txtp);
            txtp->add(/**/ "handlep__V->m_vpiWriteCbp = cbp__V;\n");
            txtp->add(/**/ "handlep__V->m_vpiWriteSymsp = symsp__V;\n");
            txtp->add(/**/ "if (cbp__V) {\n");
            txtp->add(/****/ "handlep__V->__VvpiOnWrite(" + m_libName
                      + "_protectlib_vpi_write, handlep__V);\n");
            txtp->add(/**/ "} else {\n");
            txtp->add(/****/ "handlep__V->__VvpiOnWrite(nullptr, nullptr);\n");
            txtp->add(/**/ "}\n");
            txtp->add("}\n\n");
        }

        // Updates
        comboComment(txtp, fl);
        m_cComboParamsp = new AstTextBlock{
            fl, "unsigned long long " + m_libName + "_protectlib_combo_update(\n", ",\n",
            "\n) {\n"};
        m_cComboParamsp->add("void* vhandlep__V");
        txtp->add(m_cComboParamsp);
        m_cComboInsp = new AstTextBlock{fl};
        castPtr(fl, m_cComboInsp);
        txtp->add(m_cComboInsp);
        txtp->add("handlep__V->eval();\n");
        m_cComboOutsp = new AstTextBlock{fl};
        txtp->add(m_cComboOutsp);
        txtp->add("return handlep__V->m_seqnum++;\n");
        txtp->add("}\n\n");

        if (m_hasSeqUpdate) {
            seqComment(txtp, fl);
            m_cSeqParamsp = new AstTextBlock{
                fl, "unsigned long long " + m_libName + "_protectlib_seq_update(\n", ",\n",
                "\n) {\n"};
            m_cSeqParamsp->add("void* vhandlep__V");
            txtp->add(m_cSeqParamsp);
            m_cSeqClksp = new AstTextBlock{fl};
            castPtr(fl, m_cSeqClksp);
            txtp->add(m_cSeqClksp);
            txtp->add("handlep__V->eval();\n");
            m_cSeqOutsp = new AstTextBlock{fl};
            txtp->add(m_cSeqOutsp);
            txtp->add("return handlep__V->m_seqnum++;\n");
            txtp->add("}\n\n");
            m_cSettlep = new AstTextBlock{fl};
            txtp->add(m_cSettlep);
        }

        comboIgnoreComment(txtp, fl);
        m_cIgnoreParamsp = new AstTextBlock{
            fl, "void " + m_libName + "_protectlib_combo_ignore(\n", ",\n", "\n)\n{ }\n\n"};
        m_cIgnoreParamsp->add("void* vhandlep__V");
        txtp->add(m_cIgnoreParamsp);

        // Final
        finalComment(txtp, fl);
        txtp->add("void " + m_libName + "_protectlib_final(void* vhandlep__V) {\n");
        castPtr(fl, txtp);
        txtp->add(/**/ "handlep__V->final();\n");
        txtp->add("}\n\n");

        txtp->add("}\n");
        m_cfilep->tblockp(txtp);
    }

    void visit(AstVar* nodep) override {
        if (!nodep->isIO()) return;
        if (restoreInout(nodep)) {
            InoutPorts& ports = m_inouts[nodep->libInoutId()];
            if (nodep->isInput()) {
                ports.inp = nodep;
            } else if (nodep->libInoutEnable()) {
                ports.enp = nodep;
            } else {
                ports.outp = nodep;
            }
        }
        if (nodep->direction() == VDirection::INPUT) {
            if (nodep->isPrimaryClock()) {
                UASSERT_OBJ(m_hasSeqUpdate, nodep, "checkIfClockExists() didn't find this clock");
                handleClock(nodep);
            } else {
                handleDataInput(nodep);
            }
        } else {
            // Ref ports were rejected during linking, and tristate lowering split all inouts.
            UASSERT_OBJ(nodep->direction() == VDirection::OUTPUT, nodep,
                        "Unexpected library port direction");
            handleOutput(nodep);
        }
    }

    void visit(AstNode*) override {}

    string cInputConnection(AstVar* varp) {
        return V3Task::assignDpiToInternal("handlep__V->" + varp->name(), varp);
    }

    // The wrapper's module ports are connected by name, so they must use the user's
    // names rather than the hashed form of long names used internally
    static string svPortName(const AstVar* varp) {
        return AstNode::verilogIdent(VName::dehash(varp->name()));
    }

    static AstVar* newSvPortVar(AstVar* varp) {
        AstVar* const newVarp = varp->cloneTree(false);
        newVarp->name(VName::dehash(varp->name()));
        return newVarp;
    }

    void handleClock(AstVar* varp) {
        handleInput(varp);
        m_seqPortsp->add(varp->cloneTree(false));
        if (m_hasSeqUpdate) {
            const std::string pname = svPortName(varp);
            m_seqParamsp->add(pname);
            m_clkSensp->add(pname);
        }
        m_cSeqParamsp->add(varp->dpiArgType(true, false));
        m_cSeqClksp->add(cInputConnection(varp));
    }

    void handleDataInput(AstVar* varp) {
        handleInput(varp);
        m_comboPortsp->add(varp->cloneTree(false));
        m_comboParamsp->add(svPortName(varp));
        m_comboIgnorePortsp->add(varp->cloneTree(false));
        if (m_hasSeqUpdate) m_comboIgnoreParamsp->add(svPortName(varp));
        m_cComboParamsp->add(varp->dpiArgType(true, false));
        m_cComboInsp->add(cInputConnection(varp));
        m_cIgnoreParamsp->add(varp->dpiArgType(true, false));
        if (v3Global.opt.vpi() && m_hasSeqUpdate) {
            // The update of the clocks updates all inputs, as it follows writes through the VPI
            m_seqPortsp->add(varp->cloneTree(false));
            m_seqParamsp->add(svPortName(varp));
            m_cSeqParamsp->add(varp->dpiArgType(true, false));
            m_cSeqClksp->add(cInputConnection(varp));
        }
    }

    static bool restoreInout(const AstVar* varp) {
        return varp->libInoutId() && !v3Global.opt.pinsInoutEnables();
    }

    void handleInput(AstVar* varp) {
        AstVar* const portp = newSvPortVar(varp);
        if (restoreInout(varp)) {
            portp->direction(VDirection::INOUT);
            portp->varType(VVarType::WIRE);
        }
        m_modPortsp->add(portp);
    }

    void restoreInouts() {
        for (const auto& entry : m_inouts) {
            const InoutPorts& ports = entry.second;
            UASSERT_OBJ(ports.inp && ports.outp && ports.enp, m_vfilep,
                        "Incomplete lowered library inout");
            const string in = svPortName(ports.inp);
            const string out = ports.outp->verilogIdent();
            const string en = ports.enp->verilogIdent();
            std::vector<std::pair<int, int>> dimensions;
            const AstNodeDType* dtypep = ports.inp->dtypep()->skipRefp();
            while (const AstNodeArrayDType* const arrayp = VN_CAST(dtypep, NodeArrayDType)) {
                // V3Slice currently rejects lowered unpacked inouts before this pass.
                // TODO: Support unpacked inouts once V3Slice supports their lowered form.
                UASSERT_OBJ(!VN_IS(arrayp, UnpackArrayDType), ports.inp,
                            "Unpacked library inout should have been rejected by V3Slice");
                dimensions.emplace_back(arrayp->lo(), arrayp->hi());
                dtypep = arrayp->subDTypep()->skipRefp();
            }
            const AstBasicDType* const basicp = dtypep->basicp();
            UASSERT_OBJ(basicp, ports.inp, "Library inout must have a packed integral type");
            if (basicp->isRanged()) dimensions.emplace_back(basicp->lo(), basicp->hi());
            if (dimensions.empty()) {
                m_inoutDeclsp->add("assign " + in + " = " + en + " ? " + out + " : 1'bz;\n");
            } else {
                string lhs = in;
                string rhsEn = en;
                string rhsOut = out;
                for (size_t dim = 0; dim < dimensions.size(); ++dim) {
                    const string index
                        = "__VlibInout" + cvtToStr(entry.first) + "_" + cvtToStr(dim);
                    const int low = dimensions[dim].first;
                    const int high = dimensions[dim].second;
                    const int size = high - low + 1;
                    m_inoutDeclsp->add("for (genvar " + index + " = 0; " + index + " < "
                                       + cvtToStr(size) + "; ++" + index + ") begin\n");
                    const string select = "[" + cvtToStr(low) + " + " + index + "]";
                    lhs += select;
                    rhsEn += select;
                    rhsOut += select;
                }
                m_inoutDeclsp->add("assign " + lhs + " = " + rhsEn + " ? " + rhsOut
                                   + " : 1'bz;\n");
                for (size_t dim = 0; dim < dimensions.size(); ++dim) m_inoutDeclsp->add("end\n");
            }
        }
    }

    static void addLocalVariable(AstTextBlock* textp, const AstVar* varp, const string& name) {
        textp->add(new AstVar{varp->fileline(), VVarType::VAR, name, varp->dtypep()});
    }

    // The name of a local signal of the wrapper for an output
    std::string localName(const AstVar* varp, const char* suffixp) {
        return uniqueName(varp->name() + suffixp);
    }

    // Create the function that settles the library module before the first clock update and
    // returns its outputs, and its call
    void newSettle(FileLine* fl) {
        m_seqDeclsp->add("bit " + m_seqInitName + ";\n");
        m_seqDeclsp->add("bit " + m_seqFirstName + ";\n");
        m_seqInitp->add(m_seqInitName + " <= 1'b1;\n");
        m_settlePortsp = new AstTextBlock{
            fl, "import \"DPI-C\" function void " + m_settleName + "(\n", ", ", ");\n\n"};
        m_settlePortsp->add("chandle handle__V\n");
        m_settleDeclp->add(m_settlePortsp);
        m_seqFirstp
            = new AstTextBlock{fl, "if (!" + m_seqFirstName + ") begin\n" + m_settleName + "(\n",
                               ",\n", "\n);\n" + m_seqFirstName + " = 1'b1;\nend\n"};
        m_seqFirstp->add("handle__V");
        m_settleCallp->add(m_seqFirstp);
        m_cSettleParamsp = new AstTextBlock{fl, "void " + m_settleName + "(\n", ",\n", "\n) {\n"};
        m_cSettleParamsp->add("void* vhandlep__V");
        m_cSettlep->add(m_cSettleParamsp);
        castPtr(fl, m_cSettlep);
        m_cSettlep->add("handlep__V->eval();\n");
        m_cSettleOutsp = new AstTextBlock{fl};
        m_cSettlep->add(m_cSettleOutsp);
        m_cSettlep->add("}\n\n");
    }

    void handleOutput(AstVar* const varp) {
        // Restored inout drivers are local signals and retain their internal names.
        const std::string portName = restoreInout(varp) ? varp->verilogIdent() : svPortName(varp);
        const std::string comboLocal = varp->name() + "_combo__V";
        const std::string seqLocal = m_hasSeqUpdate ? localName(varp, "_seq__V") : "";
        const std::string tmpLocal = m_hasSeqUpdate ? localName(varp, "_tmp__V") : "";
        const std::string comboName = AstNode::verilogIdent(comboLocal);
        const std::string seqName = AstNode::verilogIdent(seqLocal);
        const std::string tmpName = AstNode::verilogIdent(tmpLocal);
        if (restoreInout(varp)) {
            AstVar* const localp = varp->cloneTree(false);
            localp->direction(VDirection::NONE);
            m_inoutDeclsp->add(localp);
        } else {
            m_modPortsp->add(newSvPortVar(varp));
        }
        // An output the combinational update cannot change comes from the clock update alone, so
        // it does not depend on the data inputs
        const bool combo = !m_hasSeqUpdate || !varp->isPrimaryRegOut();
        // Until the first NBA of the clock update's results, such an output has its value in the
        // library settled before the first clock update, its initial value, so the parent has it
        // at time zero like the combinational results
        // A function of the inputs alone is current after either update, so it comes from the
        // latest one at once, and from the clock update alone if a function of the clocks alone
        const bool inputsOnly = m_hasSeqUpdate && varp->isPrimaryCombOut();
        std::string seqAssign = portName + " = " + seqName + ";\n";
        if (inputsOnly) {
            seqAssign = portName + " = " + tmpName + ";\n";
            if (combo) {
                seqAssign = "if (" + m_seqNumName + " > last_combo_seqnum__V) " + seqAssign
                            + "else " + portName + " = " + comboName + ";\n";
            }
        } else if (!combo) {
            if (!m_seqFirstp) newSettle(varp->fileline());
            const std::string firstLocal = localName(varp, "_first__V");
            addLocalVariable(m_seqDeclsp, varp, firstLocal);
            m_settlePortsp->add(varp->cloneTree(false));
            m_seqFirstp->add(AstNode::verilogIdent(firstLocal));
            m_cSettleParamsp->add(varp->dpiArgType(true, false));
            m_cSettleOutsp->add(V3Task::assignInternalToDpi(varp, true, "", "", "handlep__V->")
                                + "\n");
            seqAssign = "if (" + m_seqInitName + ") " + portName + " = " + seqName + "; else "
                        + portName + " = " + AstNode::verilogIdent(firstLocal) + ";\n";
        }
        if (combo) {
            m_comboPortsp->add(varp->cloneTree(false));
            m_comboParamsp->add(comboName);
            addLocalVariable(m_comboDeclsp, varp, comboLocal);
            m_cComboParamsp->add(varp->dpiArgType(true, false));
            m_cComboOutsp->add(V3Task::assignInternalToDpi(varp, true, "", "", "handlep__V->")
                               + "\n");
        }
        if (m_hasSeqUpdate) {
            m_seqPortsp->add(varp->cloneTree(false));
            m_seqParamsp->add(tmpName);
            addLocalVariable(m_tmpDeclsp, varp, tmpLocal);
            if (!inputsOnly) {
                addLocalVariable(m_seqDeclsp, varp, seqLocal);
                m_nbAssignsp->add(seqName + " <= " + tmpName + ";\n");
            }
            m_cSeqParamsp->add(varp->dpiArgType(true, false));
            m_cSeqOutsp->add(V3Task::assignInternalToDpi(varp, true, "", "", "handlep__V->")
                             + "\n");
        }
        if (combo && !inputsOnly) {
            if (m_hasSeqUpdate) m_seqAssignsp->add(seqAssign);
            m_comboAssignsp->add(portName + " = " + comboName + ";\n");
        } else {
            m_selectp->add(seqAssign);
        }
    }

    static bool checkIfClockExists(const AstNodeModule* modp) {
        for (const AstNode* const stmtp : modp->stmtspList()) {
            if (const AstVar* const varp = VN_CAST(stmtp, Var)) {
                if (varp->direction() == VDirection::INPUT && varp->isPrimaryClock()) {
                    return true;
                }
            }
        }
        return false;
    }

public:
    explicit ProtectVisitor(AstNode* nodep)
        : m_libName{v3Global.opt.libCreate()}
        , m_topName{v3Global.opt.prefix()} {
        iterate(nodep);
    }
};

//######################################################################
// ProtectLib class functions

void V3ProtectLib::protect() {
    UINFO(2, __FUNCTION__ << ":");
    ProtectVisitor{v3Global.rootp()};
}
