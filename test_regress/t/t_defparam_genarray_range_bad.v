// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 1;
endmodule

// The same path from each instance of the module containing the defparam (IEEE 1800-2023 23.6)
module cfg;
  defparam g[1].u.P = 30;
  defparam g[1].u.P = 3;  // The same, so reported once
endmodule

module has2;
  for (genvar i = 0; i < 2; ++i) begin : g
    sub u ();
  end
  cfg c ();
endmodule

module has1;
  for (genvar i = 0; i < 1; ++i) begin : g
    sub u ();
  end
  cfg c ();  // Bad, no iteration 1 here
endmodule

module loop #(
    parameter int N = 1
);
  for (genvar i = 0; i < N; ++i) begin : g
    sub u ();
  end
  defparam g[1].u.P = 4;  // Bad in l1, no iteration 1 there
endmodule

// From $root, the same instance from each instance, so reported once
module rootcfg;
  defparam $root.t.a.g[2].u.P = 5;
endmodule

// From the top module, likewise
module topcfg;
  defparam t.a.g[3].u.P = 6;
endmodule

module t;
  rootcfg rc1 ();
  rootcfg rc2 ();
  topcfg tc1 ();
  topcfg tc2 ();
  has2 a ();
  has1 b ();
  loop #(.N(2)) l2 ();
  loop #(.N(1)) l1 ();
  for (genvar i = 0; i < 2; ++i) begin : g
    sub u ();
  end
  defparam g[2].u.P = 2;  // Bad, outside the loop's range
endmodule
