// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  logic a, b, d;

  property p_alw;
    always a;
  endproperty
  property p_impl;
    always (a |-> b);
  endproperty
  property p_wrap_impl;
    p_impl;
  endproperty
  property p_until;
    always (a until b);
  endproperty
  property p_seq;
    always (a ##1 b);
  endproperty

  // The body 'always p' is not reduced to p under another property operator
  assert property (@(posedge clk) not p_alw);
  assert property (@(posedge clk) d |-> p_impl);
  assert property (@(posedge clk) d |-> p_wrap_impl);
  assert property (@(posedge clk) d |-> p_until);
  assert property (@(posedge clk) d |-> p_seq);

endmodule
