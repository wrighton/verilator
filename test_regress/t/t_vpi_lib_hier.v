// DESCRIPTION: Verilator: VPI scope hierarchy of the instances of a library
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p;
  int pv  /*verilator public_flat_rw*/ = 5;
endpackage

module t (
    input clk
);
  int y0  /*verilator public_flat_rd*/;
  int y1  /*verilator public_flat_rd*/;
  int yg[2]  /*verilator public_flat_rd*/;
  int yw  /*verilator public_flat_rd*/;
  int yp  /*verilator public_flat_rd*/;
  sub u0 (
      .clk,
      .y(y0)
  );
`ifdef USE_LIB
  sub u1 (
`else
  // Another library, in a hierarchical build
  sub #(.N(2)) u1 (
`endif
      .clk,
      .y(y1)
  );
  for (genvar i = 0; i < 2; ++i) begin : GEN_SUB
    sub u (
        .clk,
        .y(yg[i])
    );
  end
  // A module with no public variable above an instance
  wrap w (
      .clk,
      .y(yw)
  );
  // A public module with no public variable above an instance, in a generate block
  for (genvar i = 0; i < 1; ++i) begin : GEN_RTL
    pub_wrap u_wrap_0 (
        .clk,
        .y(yp)
    );
  end
endmodule

// verilator lint_off UNOPTPUBLIC
module pub_wrap (
    input clk,
    output int y
);
  /*verilator public_module*/
  sub u_sub (
      .clk,
      .y
  );
endmodule
// verilator lint_on UNOPTPUBLIC

module wrap (
    input clk,
    output int y
);
  sub u (
      .clk,
      .y
  );
endmodule

`ifndef USE_LIB
module sub #(
    parameter int N = 1
) (
    input clk,
    output int y
);
  /*verilator hier_block*/
  int x  /*verilator public_flat_rw*/  /*verilator forceable*/ = N;
  int z;
  leaf l (
      .clk,
      .z
  );
  // Two levels with no public variable above one
  lvl1 u_l1 (.clk);
  always_ff @(posedge clk) y <= x + z - z + p::pv - p::pv;
endmodule

module lvl1 (
    input clk
);
  lvl2 u_l2 (.clk);
endmodule

module lvl2 (
    input clk
);
  int sig  /*verilator public_flat_rd*/ = 0;
  always_ff @(posedge clk) sig <= sig + 1;
endmodule

module leaf (
    input clk,
    output int z
);
  /*verilator hier_block*/
  int lv  /*verilator public_flat_rw*/ = 3;
  always_ff @(posedge clk) z <= lv;
endmodule
`endif
