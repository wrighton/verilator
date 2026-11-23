// DESCRIPTION: Verilator: VPI force of the ports of the instance of a library
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic clk,
    input logic [6:0] drv,
    input int sel,
    output logic [6:0] out1,
    output logic [6:0] out2,
    output logic [6:0] q1,
    output logic [6:0] q2,
    output logic [6:0] n1,
    output logic [6:0] n2,
    output logic [6:0] m1,
    output logic [6:0] m2,
    output logic [6:0] leaf1,
    output logic [6:0] leaf2,
    output logic [6:0] sm1,
    output logic [6:0] zc,
    output int tbo
);
  sub u1 (
      .clk,
      .i(drv),
      .sel,
      .vpi_writes__V(1),
      .o(out1),
      .q(q1),
      .n(n1),
      .m(m1),
      .o2(leaf1)
  );
  sub u2 (
      .clk,
      .i(~drv),
      .sel,
      .vpi_writes__V(2),
      .o(out2),
      .q(q2),
      .n(n2),
      .m(m2),
      .o2(leaf2)
  );

  // A flop sampling a combinational output of a library instance
  always_ff @(posedge clk) sm1 <= m1;

  // A library instance without a clock, fed from a flop
  logic [6:0] pflop;
  always_ff @(posedge clk) pflop <= drv;
  cmb c (
      .y(pflop),
      .z(zc)
  );

  // An export not related to the library instances
  int tbv = 0;
  export "DPI-C" function tb_set;
  function void tb_set(int v);
    tbv = v;
  endfunction
  assign tbo = tbv + 1;
endmodule

`ifndef USE_LIB
module sub (
    input logic clk  /*verilator public_flat_rw*/  /*verilator forceable*/,
    input logic [6:0] i  /*verilator public_flat_rw*/  /*verilator forceable*/,
    input int sel,
    // A port with the name of a signal of the library's wrapper, identifying the instance
    input int vpi_writes__V,
    output logic [6:0] o  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [6:0] q  /*verilator public_flat_rw*/,
    output logic [6:0] n  /*verilator public_flat_rw*/,
    output logic [6:0] m,
    output logic [6:0] o2
);
  /*verilator hier_block*/
  assign o = i;
  initial q = 0;
  initial n = 0;
  always @(posedge clk) begin
    n <= n + 1;
    q <= i;
  end
  logic [6:0] mem[0:3]  /*verilator public_flat_rw*/;
  initial for (int k = 0; k < 4; ++k) mem[k] = 7'(k + 1);
  assign m = mem[sel[1:0]];
  // A library without a clock within a library, in a hierarchical build
  leaf l (
      .i(~i),
      .j(sel[6:0]),
      .o(o2)
  );
  // Called at every evaluation of the instance
  int evalsReader  /*verilator public_flat_rw*/ = 0;
  import "DPI-C" function void sub_evaluated(
      input int id,
      input int unused
  );
  always_comb sub_evaluated(vpi_writes__V, evalsReader);
endmodule

module leaf (
    input logic [6:0] i  /*verilator public_flat_rw*/  /*verilator forceable*/,
    input logic [6:0] j,
    output logic [6:0] o
);
  /*verilator hier_block*/
  assign o = i ^ j;
endmodule
`endif

module cmb (
    input logic [6:0] y,
    output logic [6:0] z
);
  /*verilator hier_block*/
  logic [6:0] memc[0:3]  /*verilator public_flat_rw*/;
  initial for (int k = 0; k < 4; ++k) memc[k] = 7'(k + 9);
  assign z = memc[y[1:0]] + y;
endmodule
