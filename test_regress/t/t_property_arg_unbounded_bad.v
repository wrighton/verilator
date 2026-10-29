// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A formal argument with a '$' actual argument may only be a cycle delay range maximum
// (IEEE 1800-2023 16.8)
module t (
  input clk
);
  logic a, b;
  int x;

  property p_expr(r);
    @(posedge clk) a |-> x == r;
  endproperty
  property p_min(r);
    @(posedge clk) a |-> ##[r:3] b;
  endproperty
  property p_delay(r);
    @(posedge clk) a |-> ##r b;
  endproperty
  property p_nest(r);
    p_expr(r);
  endproperty
  property p_s_always(r);
    a |=> s_always [0:r] b;
  endproperty
  sequence s_only(r);
    r;
  endsequence

  assert property (p_expr($));
  assert property (p_min($));
  assert property (p_delay($));
  assert property (p_nest($));
  assert property (@(posedge clk) p_s_always($));
  assert property (@(posedge clk) s_only($));
  assert property (@(posedge clk) a |-> s_only($));
endmodule
