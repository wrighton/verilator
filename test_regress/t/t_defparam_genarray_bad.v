// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 1;
endmodule

module t;
  sub u ();
  for (genvar i = 0; i < 2; ++i) begin : g
    sub u ();
    defparam g[1].u.P = 3;  // Bad, changes a parameter outside the other iteration
  end
  if (1) begin : g_if
    sub u ();
  end
  defparam g[1:0].u.P = 2;  // Bad, range select
  defparam g_if[0].u.P = 2;  // Bad, select of a generate block that is not a loop
  defparam u[0].P = 2;  // Bad, select of an instance that is not an array
  defparam g.u.P = 2;  // Bad, generate loop without a select
endmodule
