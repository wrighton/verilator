// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Each attempt of a strong property pending at $finish fails (IEEE 1800-2023 16.12.11),
// also one started on the tick of $finish: attempts 0 to 10 below, of which those of an
// implication with |=> have started their consequent on ticks 1 to 10 only

module t;
  logic clk = 1'b0;
  int cyc = 0;
  int n_until = 0;
  int n_until_ov = 0;
  int n_until_with = 0;
  int n_nested = 0;

  initial forever #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 8) begin
      `checkd(n_until, 4);
      `checkd(n_until_ov, 4);
      `checkd(n_until_with, 4);
      `checkd(n_nested, 4);
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Attempts 0 to 3 wait in one until state, and fail together on tick 5
  assert property (@(posedge clk) (cyc < 4) |=> ((cyc < 5) s_until (cyc == 100)))
  else ++n_until;
  assert property (@(posedge clk) (cyc < 4) |-> ((cyc < 5) s_until (cyc == 100)))
  else if (cyc > 4) ++n_until_ov;
  assert property (@(posedge clk) (cyc < 4) |=> ((cyc < 5) s_until_with (cyc == 100)))
  else ++n_until_with;
  assert property (@(posedge clk) (cyc < 4) |-> (1'b1 |=> ((cyc < 5) s_until (cyc == 100))))
  else ++n_nested;

  // Pending at $finish, each attempt once
  assert property (@(posedge clk) s_always [300:300] 1'b1)
  else $display("EOS_ALWAYS");
  assert property (@(posedge clk) s_eventually 1'b0)
  else $display("EOS_EVENTUALLY");
  assert property (@(posedge clk) 1'b1 s_until 1'b0)
  else $display("EOS_UNTIL");
  assert property (@(posedge clk) 1'b1 s_until_with 1'b0)
  else $display("EOS_UNTIL_WITH");
  assert property (@(posedge clk) (cyc >= 0) |-> (1'b1 s_until 1'b0))
  else $display("EOS_IMPLIED_UNTIL");
  assert property (@(posedge clk) (cyc >= 0) |=> (1'b1 s_until 1'b0))
  else $display("EOS_NEXT_UNTIL");
  assert property (@(posedge clk) (cyc >= 0) |=> s_always [300:300] 1'b1)
  else $display("EOS_NEXT_ALWAYS");

endmodule
