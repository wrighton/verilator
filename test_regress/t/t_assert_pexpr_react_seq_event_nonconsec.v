// DESCRIPTION: Verilator: Sequence event control of a nonconsecutive repetition
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 9.4.2.4: @(s) resumes when sequence s matches. With a [=2] and a high at the clocks
// at 15 and 35 only, the first match ends at the clock at 35 (the second a).
module t;
  bit clk = 0;
  bit a = 0;
  time resumed = 0;
  sequence s;
    @(posedge clk) a [=2];
  endsequence
  always #5 clk = ~clk;
  initial begin
    #12 a = 1;
    #10 a = 0;
    #10 a = 1;
    #10 a = 0;
  end
  initial begin
    @(s);
    resumed = $time;
  end
  initial begin
    #100;
    `checkd(resumed, 35);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
