// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A randomize() trying other sizes, whose last try fails for another reason than
// unsatisfied constraints, reports why (see t_randomize_size_retry_report.py)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Not satisfiable with any size allowed, so tries both
class Never;
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[3 : 4]};
    foreach (q[i]) if (i == 2) {
      q[i] > 10;
      q[i] < 5;
    }
  }
endclass

module t;
  initial begin
    automatic Never n = new;
    automatic int ok;
    ok = n.randomize();
    `checkd(ok, 0);
    `checkd(n.q.size(), 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
