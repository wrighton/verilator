// DESCRIPTION: Verilator: Assertion control through an interface port typed with an absent modport
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc (
    input logic clk
);
  a1 :
  assert property (@(posedge clk) 0);
  modport mp(input clk);
endinterface

// The absent modport is reported where the port is linked, before assertion control scopes are
// resolved; no assertion control error follows
module sub (
    ifc.nosuch p
);
  initial $assertoff(0, p.a1);
endmodule

module t;
  logic clk = 0;
  ifc i (.clk(clk));
  sub s (.p(i));
endmodule
