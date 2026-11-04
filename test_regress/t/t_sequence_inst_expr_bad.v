// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sequence and property instances are only legal in sequence or property expressions, and a
// sequence instance in an event control (IEEE 1800-2023 16.8, 16.12)
module t (
    input clk
);
  logic a, b, x;

  default clocking @(posedge clk);
  endclocking

  sequence s1;
    a;
  endsequence
  sequence s2;
    a ##1 b;
  endsequence
  sequence s_outer;
    s2 ##1 a;
  endsequence
  sequence s_arg(q);
    q ##1 a;
  endsequence
  property p1;
    a |-> b;
  endproperty

  initial x = s1;
  initial if (s2) x = 1;
  initial x = s_outer;
  initial s1;
  initial x = p1;
  initial p1;
  initial assert (s1);
  always @(p1) x = 0;
  function bit f;
    return s_arg(b);
  endfunction
  // A function first widthed from an assertion
  assert property (g());
  function bit g;
    return s_arg(a);
  endfunction
  // A disable iff or abort condition is an expression
  assert property (disable iff (s2) a);
  assert property (disable iff (!s1) a);
  assert property (disable iff (b || p1) a);
  property p_dis;
    disable iff (s_arg(b)) a;
  endproperty
  assert property (p_dis);
  assert property (accept_on (s1) a);
  assert property (sync_reject_on (p1) a);
  sub u_sub (.clk);

  // Legal
  always @(s1) x = 1;
  always @(s1 iff b) x = 1;
  always @(s_arg(s2)) x = 1;
  assert property (s_arg(s1) |-> b);
  assert property (p1);
  cover sequence (s_outer);
  assert property (disable iff (b) s1);
  assert property (accept_on (b) s1);
endmodule

module sub (
    input clk
);
  logic a;
  sequence s1;
    a;
  endsequence
  default disable iff (s1);
endmodule
