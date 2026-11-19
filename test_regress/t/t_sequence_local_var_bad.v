// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input in
);

  // A typed formal may not be assigned (IEEE 1800-2023 16.8.1)
  sequence s_typed(int x);
    (1, x = 1);
  endsequence

  // A module input may not be assigned
  sequence s_input;
    (1, in = 1);
  endsequence

  assert property (@(posedge clk) s_typed(1));
  assert property (@(posedge clk) s_input);

  // An untyped formal the sequence assigns needs an entire local variable as
  // its actual argument (IEEE 1800-2023 16.10)
  sequence s_assign(lv);
    (1, lv = in);
  endsequence
  property p_select;
    bit [2:0] t;
    @(posedge clk) s_assign(t[1]) |=> t[1];
  endproperty
  assert property (p_select);
  sequence s_assign_outer(lv);
    s_assign(lv);
  endsequence
  property p_select_outer;
    bit [2:0] t;
    @(posedge clk) s_assign_outer(t[2]) |=> t[2];
  endproperty
  assert property (p_select_outer);
  property p_legal;
    bit t;
    @(posedge clk) s_assign(t) |=> t;
  endproperty
  assert property (p_legal);
  bit static_var;
  assert property (@(posedge clk) s_assign(static_var) |=> static_var);
endmodule
