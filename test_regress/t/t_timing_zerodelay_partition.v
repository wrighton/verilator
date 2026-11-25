// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Clocked processes triggered in a time step run before the processes resumed from a #0
// delay in it, and only the processes interacting with these need to run before them

module t;
  logic clk = 1'b0;
  int cyc = 0;

  // Written with a blocking assignment by a clocked process, read after a #0
  int blk = 0;
  always @(posedge clk) blk = cyc;
  // Computed from it, read after a #0
  int blk_inc;
  assign blk_inc = blk + 1;

  // Written after a #0, read by a clocked process
  int late = 0;
  int seen = 0;
  always @(posedge clk) seen <= late;

  // Written after a #0, triggering a clocked process
  logic clk2 = 1'b0;
  int ticks2 = 0;
  always @(posedge clk2) ticks2 <= ticks2 + 1;

  // Unrelated to the #0
  int acc[8];
  for (genvar i = 0; i < 8; ++i) begin : g
    initial acc[i] = 0;
    always @(posedge clk) acc[i] <= acc[i] + i;
  end

  int blk_after = 0;
  int blk_inc_after = 0;
  always @(posedge clk) begin
    #0;
    blk_after = blk;
    blk_inc_after = blk_inc;
    late = cyc + 100;
    clk2 = ~clk2;
  end

  initial begin
    repeat (8) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      ++cyc;
      `checkd(blk_after, cyc - 1);
      `checkd(blk_inc_after, cyc);
      `checkd(seen, cyc == 1 ? 0 : cyc + 98);
      `checkd(ticks2, (cyc + 1) / 2);
      for (int i = 0; i < 8; ++i) `checkd(acc[i], i * cyc);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
