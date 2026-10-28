// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ch_if #(
    parameter int W = 1
);
  logic [W-1:0] d;
endinterface

interface bus_if #(
    parameter int W = 1
);
  ch_if #(W) req ();
endinterface

module drv (
    interface g
);
  assign g.d = '1;
endmodule

module t;
  bus_if #(8) b ();
  drv u (.g(b.req));
endmodule
