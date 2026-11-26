// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  sequence s_pkg(x);
    x ##1 s_pkg(x);
  endsequence
endpackage

interface ifc (
    input clk
);
  logic a;
  sequence s_ifc;
    a ##1 s_ifc;
  endsequence
endinterface

module t (
    input clk
);
  logic a, b;
  ifc i (.clk);

  // BAD: A named sequence shall not depend on itself (IEEE 1800-2023 16.8)
  sequence s_self;
    a ##1 s_self;
  endsequence
  assert property (@(posedge clk) s_self);

  // BAD: Also when never instantiated
  sequence s_unused;
    a ##1 s_unused;
  endsequence

  // BAD: Through another sequence
  sequence s1;
    @(posedge clk) (a ##1 s2);
  endsequence
  sequence s2;
    @(posedge clk) (b ##1 s1);
  endsequence
  assert property (s1);

  // BAD: Through the actual argument of an instance
  sequence s_pass(x);
    x ##1 b;
  endsequence
  sequence s_arg;
    a ##1 s_pass(s_arg);
  endsequence
  assert property (@(posedge clk) s_arg);

  // BAD: In a package and in an interface
  assert property (@(posedge clk) pkg::s_pkg(a));
  assert property (@(posedge clk) i.s_ifc);

  // BAD: Used as an event control
  sequence s_event;
    @(posedge clk) a ##1 s_event;
  endsequence
  always @(s_event) b <= a;

endmodule
