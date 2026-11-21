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

// A process without a process object of its own that calls a task that suspends does not
// draw, once resumed, from a static process that a handle keeps (IEEE 1800-2023 18.14.1)

class Rand;
  rand int unsigned m_val;
endclass

class Waiter;
  static task waitOne();
    #1;
  endtask
endclass

module t;
  process kept;
  string keptState;
  initial begin
    kept = process::self();
    kept.srandom(42);
    keptState = kept.get_randstate();
  end

  int randomize_result;
  initial begin
    Rand r;
    Waiter::waitOne();
    r = new;
    randomize_result = r.randomize();
  end

  final begin
    `checks(kept.get_randstate(), keptState);
    `checkh(randomize_result, 1);
    $write("*-* All Finished *-*\n");
  end
endmodule
