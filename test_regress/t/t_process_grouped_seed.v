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

// Procedures without timing run in one process here, which the first of them to end marks
// finished. The later ones still run in it, so draw from it however their calls are made
// (IEEE 1800-2023 18.14.1).

class Rand;
  rand int unsigned m_val;
endclass

class Forker;
  static bit s_forked;
  // Makes a process of its own for the fork
  static function void forkNone();
    fork
      s_forked = 1'b1;
    join_none
  endfunction
endclass

module t;
  process first;
  initial begin : first_procedure
    first = process::self();
  end

  string directState;
  string viaSelfState;
  initial begin : later_procedure
    process p;
    Rand r;
    p = process::self();
`ifdef VERILATOR
    // Runs in the process that the first procedure finished. This pins a known limit, that
    // these procedures run in one process, not a requirement of the standard
    `checkh(p == first, 1'b1);
    `checkh(first.status(), process::FINISHED);
`endif
    p.srandom(42);
    Forker::forkNone();
    r = new;
    directState = r.get_randstate();
    p.srandom(42);
    Forker::forkNone();
    // Makes this process current again
    p = process::self();
    r = new;
    viaSelfState = r.get_randstate();
  end

  final begin
    `checks(directState, viaSelfState);
    $write("*-* All Finished *-*\n");
  end
endmodule
