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

  // Test: of two evaluations in a time step, with an $assertkill between them, only the first
  // is dropped
  logic again_clk = 0;
  int again_n = 0;
  a_again :
  assert property (@(posedge again_clk) 1'b0)
  else ++again_n;
  initial begin
    #3 again_clk = 1;
    #0 $assertkill(0, a_again);
    $asserton(0, a_again);
    #0 again_clk = 0;
    #0 again_clk = 1;
  end

  always @(negedge clk) begin
    if (cyc == 10) begin
      `checkd(fail_n, 4);
      `checkd(again_n, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
