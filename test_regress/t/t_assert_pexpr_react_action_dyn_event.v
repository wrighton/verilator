// DESCRIPTION: Verilator: concurrent assertion action waiting on an event of a class object
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The action of a property expression's attempt runs in the Reactive region, in a process of its
// own (IEEE 1800-2023 16.14.1), so it may wait; here on an event of a class object, which the
// negedge after each posedge triggers once the action is waiting.
module t (
    input clk
);

  class C;
    event e;
  endclass

  C c = new;
  int cyc = 0;
  int nres = 0, nfire = 0;
  always @(posedge clk) cyc <= cyc + 1;

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    @(c.e) nres++;
  end

  // Skip a clock initialization edge before the first posedge (a harness may start the clock at
  // X, then set it to 0), when no action is waiting yet
  always @(negedge clk) begin
    if (cyc != 0) begin
      ->c.e;
      nfire++;
    end
  end

  always @(posedge clk) begin
    if (cyc == 21) begin
      // The actions of the posedges with sampled cyc 0..20 each resumed at the following negedge
      if (nres < 1) `stop;
      `checkd(nfire, 21);
      `checkd(nres, 21);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
