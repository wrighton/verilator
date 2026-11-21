// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off DECLFILENAME
module t (
    input clk
);

  bit a = 0;
  bit b = 0;
  bit c = 0;

  property q_clk;
    @(posedge clk) b;
  endproperty

  property q_strong;
    strong(b ##1 a);
  endproperty

  property q_ovl;
    b |=> a;
  endproperty

  property q_arg(x);
    x;
  endproperty

  property q_loc;
    logic v;
    (b, v = a) |=> a == v;
  endproperty

  property q_arg_strong(x);
    strong(x ##1 x);
  endproperty

  property q_chain(x);
    q_arg_strong(x);
  endproperty

  assert property (@(posedge clk) a |-> q_clk);
  assert property (@(posedge clk) a |-> q_strong);
  // A multi-cycle body with a match item
  assert property (@(posedge clk) b |-> q_loc);
  // A property instance as an actual argument
  assert property (@(posedge clk) a |-> q_arg(q_ovl));
  // Reported at the nested instance also in a composite or through a chain, and 'c' that
  // only the rejected instance reads is not reported as unused
  assert property (@(posedge clk) q_strong or a);
  assert property (@(posedge clk) a |-> q_chain(c));
  // A property instance as a sequence operand or implication antecedent is illegal, see
  // t_property_sexpr_bad

endmodule
