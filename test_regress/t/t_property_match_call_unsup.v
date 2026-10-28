// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  logic a, b, c;
  logic [3:0] d;

  task automatic note(input logic x);
    $display("note %0d", x);
  endtask

  sequence s_call;
    (a ##1 b, $display("s_call"));
  endsequence

  property p_call;
    logic [3:0] v;
    (a ##1 b, v = d, $display("v=%0d", v)) |-> c;
  endproperty

  // Antecedent
  assert property (@(posedge clk) (a ##1 b, $display("a then b")) |-> c);
  assert property (@(posedge clk) (a, $display("a")) ##1 b |-> c);
  assert property (@(posedge clk) (a ##1 b, note(b)) |-> c);
  assert property (@(posedge clk) s_call |-> c);
  assert property (@(posedge clk) p_call);
  // Consequent
  assert property (@(posedge clk) a |-> (b ##1 c, $display("b then c")));
  assert property (@(posedge clk) a |=> b ##1 (c, $display("c")));
  // Sequence
  assert property (@(posedge clk) (a [* 1: 2], $display("a run")) ##1 b);
  cover property (@(posedge clk) (a ##1 b, $display("a then b")));

endmodule
