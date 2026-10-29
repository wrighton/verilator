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

  // Legal
  always @(s1) x = 1;
  always @(s_arg(s2)) x = 1;
  assert property (s_arg(s1) |-> b);
  assert property (p1);
  cover sequence (s_outer);
endmodule
