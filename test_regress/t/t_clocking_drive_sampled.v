// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Synchronous drives whose value uses sampled value functions with their own clock, compared
// with nonblocking assignments of the same values
module t;
  bit clk = 0;
  always #1 clk = ~clk;
  global clocking @(posedge clk);
  endclocking

  int cyc = 0;
  logic a = 0;
  logic o_rose, o_rose_gclk, o_stable_gclk, o_past_gclk;
  logic ref_rose, ref_rose_gclk, ref_stable_gclk, ref_past_gclk;
  clocking cb @(posedge clk);
    output o_rose, o_rose_gclk, o_stable_gclk, o_past_gclk;
  endclocking

  always @(posedge clk) begin
    cb.o_rose <= $rose(a, clk);
    cb.o_rose_gclk <= $rose_gclk(a);
    cb.o_stable_gclk <= $stable_gclk(a);
    cb.o_past_gclk <= $past_gclk(a);
    ref_rose <= $rose(a, clk);
    ref_rose_gclk <= $rose_gclk(a);
    ref_stable_gclk <= $stable_gclk(a);
    ref_past_gclk <= $past_gclk(a);
  end

  int rises = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[1];
    if (cyc > 2) begin
      `checkd(o_rose, ref_rose);
      `checkd(o_rose_gclk, ref_rose_gclk);
      `checkd(o_stable_gclk, ref_stable_gclk);
      `checkd(o_past_gclk, ref_past_gclk);
      if (o_rose_gclk) ++rises;
    end
    if (cyc == 20) begin
      `checkd(rises, 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
