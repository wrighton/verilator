// DESCRIPTION: Verilator: VPI force of the ports of library instances evaluated by threads
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic clk,
    input logic [6:0] drv,
    output logic [6:0] o1,
    output logic [6:0] q1,
    output logic [6:0] o2,
    output logic [6:0] q2
);
  sub u1 (
      .clk,
      .id(1),
      .i(drv),
      .o(o1),
      .q(q1)
  );
  sub u2 (
      .clk,
      .id(2),
      .i(~drv),
      .o(o2),
      .q(q2)
  );
endmodule

module sub (
    input logic clk,
    input int id,
    input logic [6:0] i,
    output logic [6:0] o  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [6:0] q
);
  /*verilator hier_block*/
  always @(posedge clk) q <= i;
  assign o = i;
  // Called at every evaluation of the instance, as it reads a variable written through the VPI
  int evalsReader  /*verilator public_flat_rw*/ = 0;
  import "DPI-C" function void sub_evaluated(
      input int id,
      input int unused
  );
  always_comb sub_evaluated(id, evalsReader);
endmodule
