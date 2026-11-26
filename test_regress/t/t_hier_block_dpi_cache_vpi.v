// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input [7:0] in,
    output [7:0] o,
    output [7:0] q
);
  // A force or deposit through the VPI here changes the input of the hierarchical block
  logic [7:0] drv  /*verilator forceable*/  /*verilator public_flat_rw*/;
  assign drv = in;
  sub u (
      .clk,
      .i(drv),
      .o,
      .q
  );
endmodule

module sub (
    input clk,
    input [7:0] i,
    output [7:0] o,
    output logic [7:0] q
);
  /*verilator hier_block*/
  // A write through the VPI here changes the state the outputs depend on, without an input
  logic [7:0] st  /*verilator public_flat_rw*/ = 8'h10;
  always_ff @(posedge clk) begin
    st <= st + 8'h1;
    q <= i;
  end
  assign o = i + st;
endmodule
