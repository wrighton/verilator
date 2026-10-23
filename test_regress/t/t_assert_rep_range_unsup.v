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
  property p_cons_range_nested;
    @(posedge clk) a |-> (b ##1 a [* 1: 2]) ##1 b;
  endproperty
  property p_cons_range_delay2;
    @(posedge clk) a |-> b [* 1: 2] ##2 a;
  endproperty
  property p_cons_range_range;
    @(posedge clk) a |-> b [* 1: 2] ##[1:2] a;
  endproperty
  property p_cons_range_multi;
    @(posedge clk) a |-> (a ##1 b) [* 1: 2] ##1 b;
  endproperty
  property p_cons_range_seq;
    @(posedge clk) a |-> b [* 1: 2] ##1 (a ##1 b);
  endproperty

  a_nc_range :
  assert property (p_nc_range);
  a_nc_lhs_range :
  assert property (p_nc_lhs_range);
  a_cons_range_nested :
  assert property (p_cons_range_nested);
  a_cons_range_delay2 :
  assert property (p_cons_range_delay2);
  a_cons_range_range :
  assert property (p_cons_range_range);
  a_cons_range_multi :
  assert property (p_cons_range_multi);
  a_cons_range_seq :
  assert property (p_cons_range_seq);
endmodule
