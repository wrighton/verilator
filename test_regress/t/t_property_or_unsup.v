// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  bit a;
  bit b;
  bit c;

  // Asserted 'or' forms whose failure is not detected
  assert property (@(posedge clk) a |-> (##1 a) or (##1 b) or (##1 c) or (##2 a) or (##2 b));
  assert property (@(posedge clk) a |-> (##[1:2] b) or (##3 c));
  assert property (@(posedge clk) (a |-> ##1 b) or (b |-> ##1 c));
  assert property (@(posedge clk) ((a ##1 b) or (b ##1 a)) intersect (c ##1 c));
  assert property (@(posedge clk) a |-> c throughout ((##1 b) or (##2 b)));
  assert property (@(posedge clk) a |-> (b [*2]) or (c ##1 a));
  assert property (@(posedge clk) a |-> ##[1:2] (##1 ((b ##1 c) or (c ##1 b))));
  assert property (@(posedge clk) (a ##1 b) within (c ##2 c));
  // Operands checked at every clock tick have too many sets of operands still matching
  assert property (@(posedge clk) a |->
      (a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c
       ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c)
      or (b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c
       ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c)
      or (c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c
       ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c)
      or (!a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c
       ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c));
endmodule
