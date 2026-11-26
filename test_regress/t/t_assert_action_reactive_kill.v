// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An $assertkill after the evaluation of a concurrent assertion, in the same time step, drops
// its action pending for the Reactive region (IEEE 1800-2023 20.11, 16.14.1)
module t (
    input clk
);

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // Test: fails on every tick, until killed and so turned off
  int fail_n = 0;
  a_fail :
  assert property (@(posedge clk) cyc < 0)
  else ++fail_n;

  always @(posedge clk) if (cyc == 4) #0 $assertkill;

  always @(negedge clk) begin
    if (cyc == 10) begin
      `checkd(fail_n, 4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
