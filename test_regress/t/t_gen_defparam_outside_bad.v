// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off DEFPARAM

module sub;
  parameter W = 0;
endmodule

module t;
  sub u ();
  if (1) begin : g
    sub u_in ();
    sub u_in2 ();
    sub u_in3 ();
    defparam u_in.W = 1;
    defparam t.g.u_in2.W = 2;
    defparam u.W = 3;  // Bad
    if (1) begin : h
      sub u_deep ();
      defparam u_deep.W = 4;
      defparam g.u_in.W = 5;  // Bad
    end
    defparam h.u_deep.W = 6;
  end
  for (genvar i = 0; i < 2; ++i) begin : gf
    sub u_for ();
    defparam u_for.W = i;
    defparam u.W = 7;  // Bad
  end
  defparam g.u_in3.W = 8;
endmodule
