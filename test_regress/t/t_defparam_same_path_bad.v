// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam value must be constant, also of a defparam a later one by the same path in its
// scope replaces

module leaf #(
    parameter int P = 0
);
endmodule

module mid;
  leaf x ();
endmodule

// Of an instance not under the scope
module other;
  int ov;
  defparam t.s.x.P = ov;  // Bad
  defparam t.s.x.P = 47;
endmodule

// Of an instance in a generate loop iteration
module sel;
  int sv;
  defparam t.g[1].s.x.P = sv;  // Bad
  defparam t.g[1].s.x.P = 47;
endmodule

module t;
  int rv;
  mid s ();
  defparam s.x.P = rv;  // Bad
  defparam s.x.P = 47;
  other o ();
  for (genvar i = 0; i < 2; ++i) begin : g
    mid s ();
  end
  sel e ();
endmodule
