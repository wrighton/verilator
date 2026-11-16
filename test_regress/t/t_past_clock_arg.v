// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sampled value functions with an explicit clocking event argument (IEEE 1800-2023 16.9.3)
module t (
    input clk
);

  int cyc = 0;
  bit a = 0;
  bit rst = 1;
  bit [6:0] v = 7'd5;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[1];
    v <= v + 7'd3;
    if (cyc == 3) rst <= 0;
    if (cyc == 20) begin
      `checkd(rose_count, 5);
      `checkd(past_fails, 0);
      `checkd(disable_fails, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Sampled values at the most recent and previous posedge, starting from the
  // default sampled values
  bit tick_a = 0;
  bit tick2_a = 0;
  bit [6:0] tick_v = 7'd5;
  bit [6:0] tick2_v = 7'd5;
  always @(posedge clk) begin
    tick_a <= a;
    tick2_a <= tick_a;
    tick_v <= v;
    tick2_v <= tick_v;
  end

  // Evaluated between posedges, so only the explicit clock gives these results
  always @(negedge clk) begin
    `checkd($rose(a, @(posedge clk)), a && !tick_a);
    `checkd($fell(a, @(posedge clk)), !a && tick_a);
    `checkd($stable(v, @(posedge clk)), v == tick_v);
    `checkd($changed(v, @(posedge clk)), v != tick_v);
    `checkd($past(v, 1, , @(posedge clk)), tick_v);
    `checkd($past(v, 2, , @(posedge clk)), tick2_v);
    `checkd($past(v, , , @(posedge clk)), tick_v);
  end

  // Explicit clock in a procedure with a different clock
  always @(posedge clk) begin
    if (cyc > 1) `checkd($past(v, 1, , @(negedge clk)), v);
    if (cyc > 1) `checkd($stable(v, @clk), 1);
    `checkd($past($rose(a), 1, , @(posedge clk)), tick_a && !tick2_a);
  end

  int rose_count = 0;
  assert property (@(negedge clk) !$rose(a, @(posedge clk)))
  else rose_count++;

  int past_fails = 0;
  assert property (@(negedge clk) $past(v, 1, , @(posedge clk)) == tick_v)
  else past_fails++;

  // A sampled value function in a disable condition shall be explicitly clocked
  int disable_fails = 0;
  assert property (@(posedge clk) disable iff ($fell(rst, @(posedge clk))) cyc != 4)
  else disable_fails++;

endmodule
