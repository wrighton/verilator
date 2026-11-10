// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A string literal in a trigger expression must be escaped in the trigger debug dump
module t;
  logic clk = 0;
  logic rst_n = 1;
  logic a = 0;
  always #5 clk = ~clk;

  property p_or;
    @(posedge clk) disable iff ($test$plusargs("knob_off") || !rst_n) a |=> !a;
  endproperty
  property p_not;
    @(posedge clk) disable iff (!$test$plusargs("knob_on") || !rst_n) $rose(a) |-> a [*3];
  endproperty
  assert property (p_or);
  assert property (p_not);

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    repeat (4) @(negedge clk);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
