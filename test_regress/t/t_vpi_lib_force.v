// DESCRIPTION: Verilator: VPI force of the ports of the instance of a library
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic [7:0] drv,
    output logic [7:0] out,
    output logic [7:0] out2
);
  sub u (
      .i(drv),
      .o(out),
      .o2(out2)
  );
endmodule

`ifndef USE_LIB
module sub (
    input logic [7:0] i  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [7:0] o  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [7:0] o2
);
  /*verilator hier_block*/
  assign o = i;
  // A library within a library, in a hierarchical build
  leaf l (
      .i(~i),
      .o(o2)
  );
endmodule

module leaf (
    input logic [7:0] i  /*verilator public_flat_rw*/  /*verilator forceable*/,
    output logic [7:0] o
);
  /*verilator hier_block*/
  assign o = i;
endmodule
`endif
