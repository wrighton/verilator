// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// An imported task whose exports suspend, here in another model, does not use the process
// that was current when it started, which may be gone once it resumes (IEEE 1800-2023 18.14.1).
// Run with the address sanitizer.

module a;
  // Needs a process, but keeps no handle to it past this evaluation
  function automatic void seedSelf();
    process p = process::self();
    p.srandom(42);
  endfunction
  initial seedSelf();

  import "DPI-C" context function void a_save_scope();
  import "DPI-C" context task a_imp();
  export "DPI-C" task a_wait;
  task a_wait();
    #1;
  endtask
  initial begin
    a_save_scope();
    // Calls an export of model b taking a process, which waits in a_wait
    a_imp();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module b;
  import "DPI-C" context function void b_save_scope();
  initial b_save_scope();
  import "DPI-C" context task b_imp();
  export "DPI-C" task b_task;
  process taken;
  task b_task();
    taken = process::self();
    b_imp();
  endtask
endmodule
