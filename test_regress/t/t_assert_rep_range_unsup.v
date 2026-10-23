// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk;
  bit a;
  bit b;

  property p_nc_range;
    @(posedge clk) a |-> b [= 1: 2];
  endproperty
  property p_nc_lhs_range;
    @(posedge clk) a [= 1: 2] |-> b;
  endproperty
  property p_goto_range_seq;
    @(posedge clk) a |-> b [-> 1: 2] ##1 a;
  endproperty

  a_nc_range :
  assert property (p_nc_range);
  a_nc_lhs_range :
  assert property (p_nc_lhs_range);
  a_goto_range_seq :
  assert property (p_goto_range_seq);
  // A cover never rejects, so a later element after the range is supported
  c_goto_range_seq :
  cover property (@(posedge clk) b [-> 1: 2] ##1 a);
endmodule
