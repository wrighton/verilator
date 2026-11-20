// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process without a process object of its own that calls a task that suspends does not,
// once resumed, use the process that was current when it started, which may be gone by then
// (IEEE 1800-2023 18.14.1). Run with the address sanitizer.

class Rand;
  rand int unsigned m_val;
endclass

class Waiter;
  static task waitOne();
    #1;
  endtask
endclass

module t;
  // Needs a process, but keeps no handle to it past this evaluation
  function automatic void seedSelf();
    process p = process::self();
    p.srandom(42);
  endfunction
  initial seedSelf();

  int randomize_result;
  initial begin
    Rand r;
    Waiter::waitOne();
    r = new;
    randomize_result = r.randomize();
  end

  final begin
    `checkh(randomize_result, 1);
    $write("*-* All Finished *-*\n");
  end
endmodule
