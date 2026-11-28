// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A property 'or' with a strong always fails at the end of simulation while only strong
// operands of an attempt are still pending (IEEE 1800-2023 16.12.4, 16.12.11)

module t (
    input clk
);
  int cyc = 0;
  wire a = 1'b1;
  wire b = 1'b0;
  wire d = cyc < 5;

  assert property (@(posedge clk) d or (s_always [0:3] a))
  else $display("EOS_OR");
  assert property (@(posedge clk) (s_always [0:3] a) or d)
  else $display("EOS_OR_SWAPPED");
  assert property (@(posedge clk) d or (s_always [2:3] a))
  else $display("EOS_OR_LATE");
  // A sequence operand failing at once leaves the strong operand alone
  assert property (@(posedge clk) (s_always [0:3] a) or (b ##5 a))
  else $display("EOS_OR_SEQ_FAILED");
  // A pending sequence operand is weak, as is a weak always
  assert property (@(posedge clk) (s_always [0:3] a) or (a ##5 a))
  else $display("EOS_OR_SEQ_PENDING_BAD");
  assert property (@(posedge clk) d or (always [0:3] a))
  else $display("EOS_OR_WEAK_BAD");
  // Also with an implication operand
  assert property (@(posedge clk) (a |-> b) or (s_always [0:3] a))
  else $display("EOS_OR_IMPL");

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
