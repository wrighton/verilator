// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// s_always attempts pending at $finish do not fail after $assertfailoff.
// Without it the same assertions fail, see t_prop_s_always_eos_count.

`define stop $stop

module t (
    input clk
);

  int cyc = 0;

  assert property (@(posedge clk) s_always[1: 3] 1'b1);
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else `stop;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $assertfailoff;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
