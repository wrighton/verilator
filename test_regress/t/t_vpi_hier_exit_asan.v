// DESCRIPTION: Verilator: VPI hierarchical model torn down with the default context at exit
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter int W = 8
) (
    input logic clk,
    output logic [W-1:0] q
);
  /*verilator hier_block*/
  logic [W-1:0] cnt  /*verilator public_flat_rd*/ = '0;
  always_ff @(posedge clk) cnt <= cnt + 1'b1;
  assign q = cnt;
endmodule

module t (
    input logic clk,
    output logic [7:0] q0,
    output logic [7:0] q1
);
  sub u0 (
      .clk(clk),
      .q(q0)
  );
  sub u1 (
      .clk(clk),
      .q(q1)
  );
endmodule
