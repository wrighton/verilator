// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  bit val;

  always @(posedge clk) begin
    $write("*-* All Finished *-*\n");
    $finish;
  end

  assert property (@(posedge clk) ##1 not val);

  // Property operators as sequence operands
  cover property (@(posedge clk) (val |-> val) ##1 val);
  cover property (@(posedge clk) (val |=> val) [*2]);
  cover property (@(posedge clk) (val #-# val) [->2]);
  cover property (@(posedge clk) (val until val) [=2]);
  cover property (@(posedge clk) (s_always [1:2] val) intersect val);
  cover property (@(posedge clk) (accept_on (val) val) within val);
  cover property (@(posedge clk) (val |-> val) throughout val);
  cover property (@(posedge clk) ((val |-> val) and val) ##1 val);
  cover property (@(posedge clk) (if (val) val) ##1 val);
  cover property (@(posedge clk) (if (val) val else val) ##1 val);
  cover property (@(posedge clk) (case (val) 1'b0: val; default: val; endcase) ##1 val);
  cover property (@(posedge clk) (s_eventually val) [*2]);
  cover property (@(posedge clk) (not val) [*2]);
  // Property operators in an implication antecedent
  cover property (@(posedge clk) (val |-> val) |-> val);
  cover property (@(posedge clk) (val until val) #-# val);
  cover property (@(posedge clk) (not val) |-> val);
  cover property (@(posedge clk) ##1 (val until val) |-> val);
  // Property operators as the operand of a cycle delay
  cover property (@(posedge clk) ##1 (val until val));
  cover property (@(posedge clk) ##1 (val |-> val) ##1 val);

  // Property instances as sequence operands, declared before and after their use
  property p_before;
    val |-> val;
  endproperty
  cover property (@(posedge clk) p_before [*2]);
  cover property (@(posedge clk) ##1 p_after);

  // Property instances in sequence-only positions
  sequence s_before;
    p_before;
  endsequence
  cover property (@(posedge clk) s_before |-> val);
  cover property (@(posedge clk) s_after |-> val);
  cover sequence (@(posedge clk) p_before);
  cover property (@(posedge clk) strong(p_before));
  property p_match;
    bit v;
    (p_before, v = val);
  endproperty
  cover property (@(posedge clk) p_match);

  property p_after;
    val |-> val;
  endproperty
  sequence s_after;
    p_after;
  endsequence
endmodule
