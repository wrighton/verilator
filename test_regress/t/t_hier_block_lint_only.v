// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A run not Verilating the hierarchical blocks reads their ports as any module's

module leaf (
    input logic [7:0] i,
    output logic [7:0] o
);
  /*verilator hier_block*/
  assign o = i;
endmodule

module t (
    input logic [7:0] in,
    output logic [7:0] out
);
  logic [7:0] w;
  leaf u_leaf (
      .i(in),
      .o(w)
  );
  assign out = u_leaf.o;
endmodule
