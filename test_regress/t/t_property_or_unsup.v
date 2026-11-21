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
  assert property (@(posedge clk) a |-> (##[1:2] b) or (##3 c));
  assert property (@(posedge clk) (a |-> ##1 b) or (b |-> ##1 c));
  assert property (@(posedge clk) ((a ##1 b) or (b ##1 a)) intersect (c ##1 c));
  assert property (@(posedge clk) a |-> c throughout ((##1 b) or (##2 b)));
  assert property (@(posedge clk) a |-> (b [*2]) or (c ##1 a));
  assert property (@(posedge clk) a |-> ##[1:2] (##1 ((b ##1 c) or (c ##1 b))));
  assert property (@(posedge clk) (a ##1 b) within (c ##2 c));
  assert property (@(posedge clk) (a |-> ##1 b) or (b |-> ##1 c) or (c |-> ##1 a) or (a |-> ##2 b)
      or (b |-> ##2 c));
  assert property (@(posedge clk) ((a |-> ((##1 b) or (##1 c))) or (##2 a)) or ((##2 b) or (##2 c)
      or (##3 a)));
  // A later step after a sequence 'or' would reject before another operand matches
  assert property (@(posedge clk) a |-> ((b[->1]) or (##2 c) or (##3 a) or (##4 b) or (##5 c))
      ##1 a);
  assert property (@(posedge clk) a |-> ((##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c))
      ##1 a);
  // Another operator would see the end of every operand of a sequence 'or'
  assert property (@(posedge clk) a |-> b throughout ((##2 a) or (##3 b) or (##4 c) or (##5 a)
      or (##6 b)));
  assert property (@(posedge clk) a |-> ((##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c))
      and c);
  // An implication inside another property operator is not at the end of the property body
  assert property (@(posedge clk) (a |-> ((##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c)))
      and (b |-> c));
  // An operand holding another operator would count every end inside it
  assert property (@(posedge clk) a |-> ((c throughout ((##2 a) or (##3 b) or (##4 c) or (##5 a)
      or (##6 b))) or (b ##2 a) or (c ##3 b) or (a ##4 c) or (b ##5 a)));
  assert property (@(posedge clk) a |-> ((c throughout (##3 a)) or (##2 b) or (c ##3 c)
      or (a ##4 a) or (b ##5 b)));
  assert property (@(posedge clk) a |-> (b ##1 ((c throughout (##1 a)) or b)) or (##2 b)
      or (c ##3 c) or (a ##4 a) or (b ##5 b));
  assert property (@(posedge clk) a |-> (b ##1 (b or (c throughout (##1 a)))) or (##2 b)
      or (c ##3 c) or (a ##4 a) or (b ##5 b));
  assert property (@(posedge clk) a |-> (b ##1 (c throughout (##1 a))) or (##2 b) or (c ##3 c)
      or (a ##4 a) or (b ##5 b));
  assert property (@(posedge clk) a |-> ((c throughout (##1 a)) ##1 b) or (##2 b) or (c ##3 c)
      or (a ##4 a) or (b ##5 b));
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
