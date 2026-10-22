// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  bit a = 0;
  bit b = 0;

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

  assert property (@(posedge clk) a |-> q_clk);
  assert property (@(posedge clk) a |-> q_strong);
  // A property instance as an actual argument
  assert property (@(posedge clk) a |-> q_arg(q_ovl));
  // A property instance as a sequence operand
  assert property (@(posedge clk) q_ovl ##1 a);
  assert property (@(posedge clk) a ##1 q_ovl);
  assert property (@(posedge clk) q_ovl [*2]);
  assert property (@(posedge clk) q_ovl [->2]);
  assert property (@(posedge clk) q_ovl [=2]);
  assert property (@(posedge clk) q_ovl intersect (a ##1 b));
  assert property (@(posedge clk) q_ovl within (a ##1 b));
  assert property (@(posedge clk) a throughout q_ovl);

endmodule
