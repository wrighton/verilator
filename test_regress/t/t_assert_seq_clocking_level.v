// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A sequence clocked by a level clocking event, @clk, ticks on every change of clk (IEEE
// 1800-2023 9.4.2), and each attempt failing runs the fail action (16.14.1), also when two
// attempts fail on one tick: an attempt whose 'a' is false, and the one before it, whose 'b' is
// false on that tick.
module t;
  logic clk = 0;
  logic a = 0, b = 0;
  int passes = 0, fails = 0;

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_level;
    @clk a ##1 b;
  endsequence
  // verilog_format: on

  assert property (s_level) passes = passes + 1;
  else fails = fails + 1;

  bit ha[64];
  bit hb[64];
  int exp_passes = 0, exp_fails = 0;
  initial begin
    for (int i = 0; i < 64; ++i) begin
      a = i % 3 != 1;
      b = i % 5 < 3;
      ha[i] = a;
      hb[i] = b;
      #1 clk = ~clk;
      #1;
      // The attempt of this tick fails without 'a', the one of the tick before ends here
      if (!ha[i]) ++exp_fails;
      if (i > 0 && ha[i-1]) begin
        if (hb[i]) ++exp_passes;
        else ++exp_fails;
      end
      `checkd(passes, exp_passes);
      `checkd(fails, exp_fails);
    end
    `checkd(passes, 25);
    `checkd(fails, 38);  // 8 ticks with two attempts failing
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
