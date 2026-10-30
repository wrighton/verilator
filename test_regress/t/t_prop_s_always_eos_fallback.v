// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A strong always pending at $finish, whose antecedent keeps the earlier lowering of a range of
// counts (a zero-minimum repetition next to a ranged delay): the attempts its merged threads
// cannot tell apart fail once

module t (
    input clk
);

  int cyc = 0;
  bit b = 0;
  bit c = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    b <= (cyc % 3 != 0);
    c <= (cyc >= 7);
    if (cyc == 10) begin
      $display("*-* All Finished *-*");
      $finish;
    end
  end

  assert property (@(posedge clk) (b [* 0: 1] ##[1:2] c) |-> s_always[1: 5] 1'b1)
  else $display("EOS_FALLBACK");

endmodule
