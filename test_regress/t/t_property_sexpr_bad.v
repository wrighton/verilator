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
endmodule
