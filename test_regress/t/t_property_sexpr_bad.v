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

  // A property declared after its instance after a leading cycle delay is fine
  cover property (@(posedge clk) ##1 p_later);

  // Property if/else has lower precedence than a cycle delay, so this is fine
  assert property (@(posedge clk) if (val) val ##1 val else val ##2 val);

  property p_later;
    val |-> val;
  endproperty
endmodule
