// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  // Fired every cycle, but its only waiter has no observable effect
  event unobserved;
  int unused_hits = 0;
  always @(posedge clk) ->unobserved;
  always @(unobserved) unused_hits <= unused_hits + 1;

  event observed;
  int hits = 0;
  always @(posedge clk) ->observed;
  always @(observed) hits <= hits + 1;

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkd(hits, cyc);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
