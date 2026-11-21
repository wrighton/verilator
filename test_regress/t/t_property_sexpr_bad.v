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

  // s_eventually is a property operator, not a sequence operand
  assert property (@(posedge clk) val |-> ##1 s_eventually val);
  assert property (@(posedge clk) (s_eventually val) ##1 val);

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
  // Only the direct operand of a leading cycle delay may be a property operator
  cover property (@(posedge clk) ##1 (if (val) val else val));

  // Property operators and instances as an implication antecedent
  property p_impl;
    val |-> val;
  endproperty
  property p_not;
    not val;
  endproperty
  property p_until;
    val until val;
  endproperty
  property p_always;
    s_always [1:2] val;
  endproperty
  property p_abort;
    accept_on (val) val;
  endproperty
  property p_nested;
    p_impl;
  endproperty
  assert property (@(posedge clk) (val |-> val) |-> val);
  assert property (@(posedge clk) (val until val) |=> val);
  assert property (@(posedge clk) (not val) #-# val);
  assert property (@(posedge clk) p_impl |-> val);
  assert property (@(posedge clk) p_not |-> val);
  assert property (@(posedge clk) p_until |-> val);
  assert property (@(posedge clk) p_always |-> val);
  assert property (@(posedge clk) p_abort |-> val);
  assert property (@(posedge clk) p_nested |-> val);
  // Property instance as a sequence operand or body
  sequence s_prop;
    p_impl;
  endsequence
  cover property (@(posedge clk) p_impl ##1 val);
  // A property declared after its instance after a leading cycle delay is fine
  cover property (@(posedge clk) ##1 p_later);

  // Property if/else has lower precedence than a cycle delay, so this is fine
  assert property (@(posedge clk) if (val) val ##1 val else val ##2 val);

  property p_later;
    val |-> val;
  endproperty
endmodule
