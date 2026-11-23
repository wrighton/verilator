// DESCRIPTION: Verilator: Selective assertion control naming a local scope of the calling instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module sub #(
    parameter bit OFF = 0
);
  if (1) begin : chk_blk
    int failures = 0;
    initial begin
      #1;
      check :
      assert (1'b0)
      else failures++;
    end
  end
  // A relative name resolves from the calling instance, so only this instance's block
  // is selected (IEEE 1800-2023 20.11, 23.8)
  initial if (OFF) $assertoff(0, chk_blk);
endmodule

module t;
  bit clk;
  int cycle = 0;
  int procedural_failures = 0;
  always #1 clk = !clk;
  always @(negedge clk) ++cycle;
  process_check : assert property (@(posedge clk) cycle == 1)
  else procedural_failures++;
  initial $assertoff(0, process_check);
  always_ff @(posedge clk) if (cycle == 1) $asserton(0, process_check);

  sub #(.OFF(1)) a ();
  sub #(.OFF(0)) b ();
  initial begin
    #2;
    `checkd(a.chk_blk.failures, 0);
    `checkd(b.chk_blk.failures, 1);
    #4;
    `checkd(procedural_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
