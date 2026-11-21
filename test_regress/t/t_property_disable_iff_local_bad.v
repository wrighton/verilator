// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input rst,
    input a,
    input b,
    input c
);

  property p_bad;
    logic t;
    @(posedge clk) disable iff (t) (a, t = b) |=> c;  // BAD: local variable
  endproperty
  assert property (p_bad);

  property p_bad_expr;
    logic t;
    @(posedge clk) disable iff (rst || !t) (a, t = b) |=> (c == t);  // BAD: local variable
  endproperty
  assert property (p_bad_expr);

  // Ports and module variables are fine
  property p_ok(logic r);
    logic t;
    @(posedge clk) disable iff (r || rst) (a, t = b) |=> (c == t);
  endproperty
  assert property (p_ok(a));

endmodule
