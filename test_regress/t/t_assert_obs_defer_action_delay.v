// DESCRIPTION: Verilator: observed deferred assertion whose action task has a delay
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The action of an observed deferred assertion is a single subroutine call, which may be a task
// (IEEE 1800-2023 16.4), run in the Reactive region; here a task with a zero delay, so the report
// waits once before it counts.
module t (
    input clk
);

  int cyc = 0;
  int nrep = 0;
  always @(posedge clk) cyc <= cyc + 1;

  task automatic tk();
    #0 ++nrep;
  endtask

  always @(posedge clk) assert #0 (1'b1) tk();

  always @(negedge clk) begin
    if (cyc == 21) begin
      // The reports of the posedges with sampled cyc 0..20 each counted once before this negedge
      if (nrep < 1) `stop;
      `checkd(nrep, 21);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
