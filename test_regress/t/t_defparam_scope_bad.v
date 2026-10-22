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
  end
  if (1) begin : g
    parameter G = 1;  // Is a localparam
  end
endmodule

module t;
  sub u ();
  defparam u.blk.L = 2;  // Bad, localparam
  defparam u.blk.v = 2;  // Bad, variable
  defparam u.blk.Z = 2;  // Bad, not found
  defparam u.g.G = 2;  // Bad, localparam

  initial begin : tblk
    parameter P = 1;
  end
  defparam tblk.P = 2;  // Bad, not in an instance
endmodule
