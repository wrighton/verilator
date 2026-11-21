// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A sequence or property instance is not an expression (IEEE 1800-2023 16.8, 16.12)
module t (
  input clk
);
  logic a, b;
  default clocking @(posedge clk);
  endclocking
  global clocking @(posedge clk);
  endclocking

  sequence s1;
    a;
  endsequence
  sequence s2;
    a ##1 b;
  endsequence
  property p1;
    a |-> b;
  endproperty
  property p_arg(s);
    a |-> s;
  endproperty
  property p_local;
    logic v;
    (s1, v = b) |-> v;
  endproperty
  sequence s_bad;
    a ##1 (s1 == 1);
  endsequence
  sequence s_good;
    s1 ##1 s2 [*2];
  endsequence
  sequence s_clocked;
    @(posedge clk) s1 ##1 b;
  endsequence
  function automatic logic f(logic v);
    return v;
  endfunction

  // Illegal
  assert property (s1 + 1);
  assert property ($rose(s2));
  assert property (s2 == 1);
  assert property (~s1);
  assert property ($past(s1));
  assert property ($fell(s1));
  assert property ($stable(s1));
  assert property ($sampled(s1));
  assert property (b |-> (p1 != 0));
  assert property (s1 && b);
  assert property (s1 -> b);
  assert property ($rising_gclk(s2));
  assert property ($falling_gclk(s1));
  assert property ($future_gclk(s1));
  assert property ($steady_gclk(s1));
  assert property ($changing_gclk(s1));
  assert property (b ? s1 : s2);
  assert property (s1 inside {1'b1});
  assert property (f(s1));
  assert property (s_bad);

  // Legal
  assert property (not s2);
  assert property (s1 and s2);
  assert property (s1 or s2);
  assert property (s2 intersect (b ##1 a));
  assert property (s1 within s2);
  assert property (b throughout s2);
  assert property (s1 |-> s2);
  assert property (s1 implies p1);
  assert property (s1 iff s2);
  assert property (if (b) s1 else p1);
  assert property (s2 ##1 s1);
  cover sequence (s1 ##1 s2);
  assert property (p_arg(s2));
  assert property (s_good);
  assert property (s1 [*2] |-> s2);
  assert property (s1 [->1] |-> s2);
  assert property (s1 [=2] |-> s2);
  assert property (s_clocked);
  assert property (s1 until p1);
  assert property (s_eventually s2);
  assert property (always [1:2] s1);
  assert property (accept_on (b) s2);
  assert property (p_local);
  assert property (case (b) 1'b1: s1; default: p1; endcase);
endmodule
