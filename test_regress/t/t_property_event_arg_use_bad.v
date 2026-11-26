// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk;
  bit a;

  // A formal with an event expression actual is only referenced as a clocking event
  property p_expr(ev, x);
    @(posedge clk) x == ev;
  endproperty
  property p_iff(event ev, logic x);
    @(ev iff a) x;
  endproperty
  assert property (p_expr(posedge clk, a));
  assert property (p_iff(posedge clk, a));
endmodule
