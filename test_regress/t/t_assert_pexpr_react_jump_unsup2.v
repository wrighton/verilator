// DESCRIPTION: Verilator: Jumps after a $finish out of concurrent assertion actions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Only the loop exit V3LinkJump adds after a $finish is dropped; a user jump that follows the
// $finish, on the same line or from one macro, stays unsupported, as does a jump after a $finish
// outside any loop, and a continue of a loop outside the actions.
module t;
  bit clk = 0;
  bit p = 0, q = 0;
  int n = 0;
  always #5 clk = ~clk;

  // verilog_format: off
`define FINISH_BREAK() $finish; break
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q) else begin $finish; break; end
    end
  end
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q) else begin `FINISH_BREAK(); end
    end
  end
  // verilog_format: on

  always @(posedge clk) begin : nb
    assert property (p until q)
    else begin
      $finish;
      disable nb;
    end
    ++n;
  end

  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q)
      else continue;
    end
  end
endmodule
