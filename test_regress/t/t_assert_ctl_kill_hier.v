// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An $assertkill ends the attempts in flight of the assertions of a hierarchical block
// (IEEE 1800-2023 20.11)
module sub (
    input clk,
    input a,
    output int passes
);
  /*verilator hier_block*/
  initial passes = 0;
  assert property (@(posedge clk) a |-> ##2 1'b1) ++passes;
endmodule

module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire a = cyc % 3 == 0;
  int passes;
  sub u_sub (
      .clk(clk),
      .a(a),
      .passes(passes)
  );
  initial $assertvacuousoff;
  // Test: killed between ticks, each time with one attempt in flight
  always @(negedge clk) begin
    if (cyc == 7 || cyc == 14) begin
      $assertkill;
      $asserton;
    end
  end
  always @(negedge clk) begin
    if (cyc == 30) begin
      // Of the attempts of ticks 0, 3, ..., 27, those of ticks 6 and 12 are killed
      `checkd(passes, 8);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
