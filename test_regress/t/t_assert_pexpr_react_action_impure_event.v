// DESCRIPTION: Verilator: concurrent assertion action waiting on a condition with an impure
// expression
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The action of a property expression's attempt runs in the Reactive region, in a process of its
// own (IEEE 1800-2023 16.14.1), so it may wait; here at the negedge after each posedge, then on a
// wait condition that calls a function with a side effect (IEEE 1800-2023 9.4.3), which holds
// there.
module t (
    input clk
);

  int cyc = 0;
  int nres = 0;
  int ncall = 0;  // The side effect: checked only as a lower bound, not as a count
  always @(posedge clk) cyc <= cyc + 1;

  function automatic bit started(int c);
    ++ncall;
    return c != 0;
  endfunction

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    @(negedge clk) wait (started(cyc)) nres++;
  end

  always @(posedge clk) begin
    if (cyc == 21) begin
      // The actions of the posedges with sampled cyc 0..20 each resumed at the following negedge,
      // where cyc is 1..21
      if (nres < 1) `stop;
      if (ncall < nres) `stop;  // Each resumption evaluated started() (IEEE 1800-2023 9.4.3)
      `checkd(nres, 21);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
