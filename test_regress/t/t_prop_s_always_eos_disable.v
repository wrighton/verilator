// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Attempts a disable iff cancels are no failures at the end of simulation, though their
// threads were in a delay ring

module t;
  logic clk = 1'b0;
  int edges = 0;
  bit abort_now = 1'b0;
  bit good = 1'b1;

  // Five clock edges, then $finish between edges
  initial begin
    repeat (5) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
    end
    #2 $write("*-* All Finished *-*\n");
    $finish;
  end

  always @(posedge clk) edges <= edges + 1;
  // High on the fourth edge alone
  always @(negedge clk) abort_now = edges == 3;

  // Only the attempt of the fifth edge is pending, as the disable cancels the earlier ones
  assert property (@(posedge clk) disable iff (abort_now) s_always [1:3] good)
  else $display("EOS_FAIL");
  assert property (@(posedge clk) disable iff (abort_now) s_always [131:131] good)
  else $display("EOS_FAIL_RING");

endmodule
