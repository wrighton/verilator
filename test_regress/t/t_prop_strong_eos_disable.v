// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A disable iff cancels the attempts started before it (IEEE 1800-2023 16.12.1), which then
// neither fail later nor at the end of simulation

module t;
  logic clk = 1'b0;
  int cyc = 0;
  int n_until = 0;
  int n_until_with = 0;
  // Disabled on ticks 6, 15 and 24 of the ticks 0 to 32, so attempts 25 to 32 are pending at
  // the end
  wire dis = cyc == 6 || cyc == 15 || cyc == 24;
  // Disabled on tick 12, so of the attempts the left operand fails on tick 14, those of ticks
  // 13 and 14 fail
  wire dis_rt = cyc == 12;
  wire lhs = cyc != 14;

  initial forever #5 clk = ~clk;

  initial begin
    repeat (33) @(posedge clk);
    #2;
    `checkd(n_until, 2);
    `checkd(n_until_with, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  always @(posedge clk) cyc <= cyc + 1;

  assert property (@(posedge clk) disable iff (dis) s_eventually 1'b0)
  else $display("EOS_EVENTUALLY");
  assert property (@(posedge clk) disable iff (dis) 1'b1 s_until 1'b0)
  else $display("EOS_UNTIL");
  assert property (@(posedge clk) disable iff (dis) 1'b1 s_until_with 1'b0)
  else $display("EOS_UNTIL_WITH");
  assert property (@(posedge clk) disable iff (dis) s_always [300:300] 1'b1)
  else $display("EOS_ALWAYS");

  // The attempts after tick 14 stay pending, and fail at the end of simulation, after the
  // counts are checked
  assert property (@(posedge clk) disable iff (dis_rt) lhs s_until (cyc == 100))
  else ++n_until;
  assert property (@(posedge clk) disable iff (dis_rt) lhs s_until_with (cyc == 100))
  else ++n_until_with;

endmodule
