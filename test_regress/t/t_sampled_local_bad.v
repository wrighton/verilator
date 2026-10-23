// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input a,
    input b
);

  property p_bad;
    logic t;
    (a, t = b) |=> $rose(t) && $fell(t) && $stable(t) && $changed(t);  // BAD: local variable
  endproperty
  assert property (@(posedge clk) p_bad);

  property p_bad_past;
    logic [1:0] t;
    (a, t = {b, b}) |=> $past(t[0]) || ($sampled(t + 1) == 0);  // BAD: local variable
  endproperty
  assert property (@(posedge clk) p_bad_past);

  // Ports and module signals are fine, as is a local variable outside the function
  property p_ok(logic r);
    logic t;
    (a, t = b) |=> $rose(r) && $past(b) == t;
  endproperty
  assert property (@(posedge clk) p_ok(a));

endmodule
