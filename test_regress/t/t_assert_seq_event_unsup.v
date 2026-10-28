// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  bit a, b;
  logic g = 0;

  default clocking @(posedge clk);
  endclocking

  // verilog_format: off
  sequence s_nonedge;
    @(g) a ##1 b;
  endsequence

  sequence s_inner;
    a ##1 b;
  endsequence
  sequence s_ref;
    s_inner ##1 a;
  endsequence

  // Legal but its endpoint topology is not buildable, so the wait could never
  // resume; rejected rather than silently ignored.
  sequence s_or;
    @(posedge clk) (a ##1 b) or (a ##2 b);
  endsequence
  // verilog_format: on

  // Not legal, a sequence instance is not an expression, but not yet reported as such;
  // s_inner stays referenced from the inlined body of s_ref
  bit x;
  initial x = s_ref;

  initial begin
    @s_nonedge;
    @s_or;
  end
endmodule
