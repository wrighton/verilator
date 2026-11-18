// DESCRIPTION: Verilator: Explicitly clocked sampled value functions in event expressions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The global clocking past sampled value functions are explicitly clocked and usable in
// procedural code (IEEE 1800-2023 16.9.4), so none of these infers a clock
module t;
  logic clk = 0;
  global clocking @(posedge clk);
  endclocking

  bit [2:0] cnt = 0;
  always @(posedge clk) cnt <= cnt + 3'd1;

  int rises = 0;
  int falls = 0;
  int stables = 0;
  int pasts = 0;
  always @(posedge clk iff $rose_gclk(cnt[1])) ++rises;
  always @(posedge clk iff $fell_gclk(cnt[1])) ++falls;
  always @(posedge clk iff $stable_gclk(cnt[1])) ++stables;
  always @(posedge clk iff $past_gclk(cnt[1])) ++pasts;

  // Reference from the value each tick reads before the counter's NBA; 0 is the default
  // sampled value of cnt[1] (16.5.1)
  int exp_rises = 0;
  int exp_falls = 0;
  int exp_stables = 0;
  int exp_pasts = 0;
  bit prev = 0;
  always @(posedge clk) begin
    if (cnt[1] && !prev) ++exp_rises;
    if (!cnt[1] && prev) ++exp_falls;
    if (cnt[1] == prev) ++exp_stables;
    if (prev) ++exp_pasts;
    prev <= cnt[1];
  end

  initial begin
    repeat (20) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
    end
    `checkd(exp_rises, 5);
    `checkd(exp_falls, 4);
    `checkd(exp_stables, 11);
    `checkd(exp_pasts, 9);
    `checkd(rises, exp_rises);
    `checkd(falls, exp_falls);
    `checkd(stables, exp_stables);
    `checkd(pasts, exp_pasts);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
