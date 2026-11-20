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

  // The actual argument of an untyped formal assigned in a sequence must be an entire local
  // variable (IEEE 1800-2023 16.10)
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  sequence s_capture(lv);
    (1, lv = cyc[0]);
  endsequence
  sequence s_forward(w);
    s_capture(w);
  endsequence

  logic m = 0;
  property p_module_var;
    s_capture(m) |=> 1;
  endproperty
  assert property (@(posedge clk) p_module_var);

  property p_forward_module_var;
    s_forward(m) |=> 1;
  endproperty
  assert property (@(posedge clk) p_forward_module_var);

  property p_property(lv);
    s_capture(lv) |=> 1;
  endproperty
  property p_property_module_var;
    p_property(m);
  endproperty
  assert property (@(posedge clk) p_property_module_var);

  logic [3:1] mw = 0;
  property p_module_select;
    s_capture(mw[2]) |=> 1;
  endproperty
  assert property (@(posedge clk) p_module_select);

  property p_constant;
    s_capture(1'b1) |=> 1;
  endproperty
  assert property (@(posedge clk) p_constant);

  property p_expression;
    logic t;
    s_capture(!t) |=> 1;
  endproperty
  assert property (@(posedge clk) p_expression);

  property p_cast;
    logic t;
    s_capture(1'(t)) |=> 1;
  endproperty
  assert property (@(posedge clk) p_cast);

  // Passed on through a typed formal
  sequence s_typed_forward(bit w);
    s_capture(w);
  endsequence
  property p_typed_sequence_module_var;
    s_typed_forward(m) |=> 1;
  endproperty
  assert property (@(posedge clk) p_typed_sequence_module_var);
  property p_typed_sequence_constant;
    s_typed_forward(1'b1) |=> 1;
  endproperty
  assert property (@(posedge clk) p_typed_sequence_constant);

  property p_typed_forward(bit w);
    s_capture(w) |=> 1;
  endproperty
  property p_typed_property_module_var;
    p_typed_forward(m);
  endproperty
  assert property (@(posedge clk) p_typed_property_module_var);
  property p_typed_property_constant;
    p_typed_forward(1'b1);
  endproperty
  assert property (@(posedge clk) p_typed_property_constant);

  assert property (@(posedge clk) s_capture(m));
endmodule
