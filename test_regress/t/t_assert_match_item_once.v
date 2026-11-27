// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The sequence match items of a step run once for each attempt reaching it (IEEE 1800-2023
// 16.10), where the attempt's thread advances, not again where the property checks that the
// step fails, and an attempt reads a local variable before the next attempt assigns it
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  int x = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    x <= x + 10;
  end

  // Called once per attempt, one tick after it captured x
  int bad[8], good[8];
  function automatic void fin(int k, int v, int want);
    if (v == want) ++good[k];
    else ++bad[k];
  endfunction
  // The call is in a step the property also checks for failing
  property p_mid(int k);
    int v;
    @(posedge clk) (1, v = x) ##1 (1, fin(k, v, x - 10)) ##1 1;
  endproperty
  property p_mid_fail(int k);
    int v;
    @(posedge clk) (1, v = x) ##1 (1, fin(k, v, x - 10)) ##1 0;
  endproperty
  property p_not_mid(int k);
    int v;
    @(posedge clk) not ((1, v = x) ##1 (1, fin(k, v, x - 10)) ##1 0);
  endproperty
  property p_not_end(int k);
    int v;
    @(posedge clk) not ((1, v = x) ##1 (1, fin(k, v, x - 10)));
  endproperty

  int fails[8], passes[8];
  assert property (p_mid(0));
  assert property (p_mid(1)) passes[1]++;
  assert property (p_mid_fail(2))
  else fails[2]++;
  assert property (p_not_mid(3));
  assert property (p_not_mid(4)) passes[4]++;
  else fails[4]++;
  assert property (p_not_end(5))
  else fails[5]++;

  always @(negedge clk) begin
    if (cyc == 20) begin
      for (int k = 0; k < 6; ++k) begin
        `checkd(bad[k], 0);
        `checkd(good[k], 19);
      end
      `checkd(passes[1], 18);
      `checkd(fails[2], 18);
      `checkd(passes[4], 18);
      `checkd(fails[4], 0);
      `checkd(fails[5], 19);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
