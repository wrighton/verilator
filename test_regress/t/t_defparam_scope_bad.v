// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  initial begin : blk
    localparam L = 1;
    int v;
    v = L;
    begin : inner
      v = 2;
    end
  end
  if (1) begin : g
    parameter G = 1;  // Is a localparam
  end
endmodule

module sub_ports #(
    parameter W = 1
);
  initial begin : blk
    parameter P = 1;  // Is a localparam, as the module has a parameter port list
  end
endmodule

module t;
  sub u ();
  sub_ports up ();
  defparam u.blk.L = 2;  // Bad, localparam
  defparam u.blk.v = 2;  // Bad, variable
  defparam u.blk.inner = 2;  // Bad, block
  defparam u.blk.Z = 2;  // Bad, not found
  defparam u.g.G = 2;  // Bad, localparam
  defparam u.blk.v.P = 2;  // Bad, not an instance
  defparam up.blk.P = 2;  // Bad, localparam
endmodule
