// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An export runs in the process of the import calling it, or, called directly from C, in a
// process of its own. Once it returns, the caller's process is current again, unless the export
// ended it, and later draws do not come from another process's RNG (IEEE 1800-2023 18.14.1).

class Rand;
  rand int unsigned m_val;
endclass

module t;
  int casesDone = 0;

  // An export called directly from C keeps its process
  process retained;
  string retainedState;
  export "DPI-C" function sv_retain_self;
  function void sv_retain_self();
    retained = process::self();
    retainedState = retained.get_randstate();
  endfunction

  import "DPI-C" context function void c_save_scope();
  import "DPI-C" function int c_current_restored();

  initial begin : direct_from_c
    Rand r;
    int randomize_result;
    c_save_scope();
`ifdef VERILATOR
    $c("{ void c_call_export_directly(); c_call_export_directly(); }");
    r = new;
    randomize_result = r.randomize();
    `checkh(randomize_result, 1);
    `checkh(c_current_restored(), 1);
    `checks(retained.get_randstate(), retainedState);
`endif
    ++casesDone;
  end

  // An export called from an import kills a child of a fork that another process joins, which
  // resumes the joiner; the joiner then kills the importing process
  process importer;
  process joinedChild;
  string importerState;
  initial begin : joiner
    fork
      begin
        joinedChild = process::self();
        #10;
      end
    join
    importer.kill();
  end

  export "DPI-C" function sv_kill_joined_child;
  function void sv_kill_joined_child();
    joinedChild.kill();
  endfunction
  import "DPI-C" context function void c_kill_joined_child();

  initial begin : imports_kill
    Rand r;
    int randomize_result;
    #1;
    importer = process::self();
    importer.srandom(42);
    importerState = importer.get_randstate();
    c_kill_joined_child();
    // Statements after the kill should not run (IEEE 1800-2023 9.7); if they do, they must not
    // draw from the killed process
    r = new;
    randomize_result = r.randomize();
  end

  initial begin : importer_not_current
    #2;
`ifdef VERILATOR
    // Whether the joiner runs within kill() is up to the implementation (IEEE 1800-2023 4.7)
    `checkh(importer.status(), process::KILLED);
    `checks(importer.get_randstate(), importerState);
`endif
    ++casesDone;
  end

  initial begin
    #5;
    `checkh(casesDone, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
