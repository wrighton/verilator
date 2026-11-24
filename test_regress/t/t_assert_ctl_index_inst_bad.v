// DESCRIPTION: Verilator: Assertion control scope index reading module instance parameters
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar i = 0; i < 4; ++i) begin : g
    initial check : assert (1'b1);
  end
  sub #(.P(2)) s ();
  initial begin : ctl
    // A constant expression names no parameter through a module instance
    // (IEEE 1800-2023 A.8.4, 11.2.1)
    $assertoff(0, g[s.P]);
    $assertoff(0, g[s.P - 1]);
    $assertoff(0, g[s.si.P]);
  end
  ifc #(.P(7)) i7 ();
  ifc #(.P(3)) i3 ();
  wp #(.P(3)) w3 ();
  wp #(.P(5)) w5 ();
  // A local interface instance's parameter, other than by its direct name in module code
  initial begin : ctl_qualified
    $assertoff(0, g[t.i7.P]);
    $assertoff(0, g[$root.t.i7.P]);
  end
  class C;
    task off();
      $assertoff(0, g[i7.P]);
      $assertoff(0, g[i3.Q]);
    endtask
  endclass
endmodule

// Shared by instances under different parents, so a value found upward differs per instance
module um;
  for (genvar i = 0; i < 8; ++i) begin : g
    initial check : assert (1'b1);
  end
  initial begin : ctl
    $assertoff(0, g[gbw.LQ + 1]);
    $assertoff(0, g[gbw.LQ]);
    $assertoff(0, g[i7.P]);
  end
endmodule

module wp #(
    parameter int P = 0
);
  if (1) begin : gbw
    localparam int LQ = P + 1;
  end
  um u ();
endmodule

module sub #(
    parameter int P = 0
);
  ifc #(.P(P)) si ();
endmodule

interface ifc #(
    parameter int P = 0
);
  localparam int Q = P + 1;
endinterface
