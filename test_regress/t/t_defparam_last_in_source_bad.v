// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam value must be constant, also of a defparam another one later in the source text
// replaces

module leaf #(
    parameter int P = 0
);
endmodule

module mid;
  int rv;
  leaf x ();
  defparam x.P = rv;  // Bad, replaced by the defparam of t
endmodule

module other;
  leaf y ();
  defparam y.P = 5;
endmodule

module t;
  int tv;
  mid s ();
  defparam s.x.P = 47;
  other o ();
  defparam o.y.P = tv;  // Bad, replacing the defparam of other
endmodule
