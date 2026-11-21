// DESCRIPTION: Verilator: Verilog Test module
//
// Parameter values, referring into a generate block or circularly, of instances
// reached by hierarchical interface port actuals: still the usual errors, as
// when not reached, not internal errors.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface bus_if #(
    parameter int W = 7
);
  logic [W-1:0] data;
endinterface

module relay #(
    parameter int K = 1
) (
    bus_if src
);
  bus_if #(.W(K)) out ();
endmodule

module sink (
    bus_if bus
);
endmodule

module holder;
  bus_if b ();
  if (1) begin : g
    logic [30:0] data;
  end
  relay #(.K($bits(g.data))) r (.src(b));
endmodule

module circular;
  localparam int A = $bits(t.c.B);
  localparam int B = A;
  bus_if b ();
  relay #(.K(A)) r (.src(b));
endmodule

module t;
  bus_if b ();
  if (1) begin : g
    logic [30:0] data;
  end
  sink s (.bus(r.out));
  relay #(.K($bits(g.data))) r (.src(b));
  sink s2 (.bus(h.r.out));
  holder h ();
  sink s3 (.bus(c.r.out));
  circular c ();
endmodule
