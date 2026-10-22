// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk,
  input clk2
);
  logic a, b;

  // verilog_format: off
  sequence s_multi;
    @(posedge clk) a;
  endsequence

  sequence s_nest;
    @(posedge clk) b;
  endsequence

  sequence s_level;
    @clk a;
  endsequence

  sequence s_level2;
    @clk a
  endsequence
  // verilog_format: on

  assert property (@(posedge clk2) s_multi);
  assert property (s_nest ##1 a);
  assert property (s_level);
  assert property (s_level2);
  assert property (@(posedge clk2) a ##1 s_nest);

  sub u_sub (.clk(clk));
endmodule

// A default clocking with several clocking events is not a sequence's single clock
module sub (
  input clk
);
  logic a;
  default clocking @(posedge clk or negedge clk);
  endclocking
  // verilog_format: off
  sequence s_pos;
    @(posedge clk) a;
  endsequence
  // verilog_format: on
  assert property (a ##1 s_pos);
endmodule
