// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Replaying the outcomes of attempts, or gating a pass action by a match, does not run the
// sequence match items of the conditions again (IEEE 1800-2023 16.10), here where a local
// variable is read one tick after its attempt assigned it, before another attempt does
// again. The temporary of an impure operand of 'inside' is still evaluated in each.
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
  int bad[5], good[5];
  function automatic void fin(int k, int v, int want);
    if (v == want) ++good[k];
    else ++bad[k];
  endfunction
  property p_cap(int k);
    int v;
    @(posedge clk) (1, v = x) ##1 (1, fin(k, v, x - 10));
  endproperty
  property p_imp;
    int v;
    @(posedge clk) (1, v = x) |-> ##1 (1, fin(4, v, x - 10));
  endproperty
  // The attempts capturing 30 and 40 fail on one tick, at different steps
  property p_two;
    int v;
    @(posedge clk) (1, v = x) ##1 v != 40 ##1 v != 30 ##1 1;
  endproperty

  // The temporary V3Width makes for an impure operand of 'inside' is not a match item
  int gd_calls = 0;
  function automatic int gd(bit [3:0] k);
    ++gd_calls;
    return int'(k);
  endfunction
  int gd_fails = 0, ref_fails = 0;
  bit [3:0] d = 4'h5;
  always @(posedge clk) d <= {d[2:0], d[3] ^ d[2]};
  assert property (@(posedge clk) (gd(d) inside {[0:9]}) ##1 (gd(d) inside {[1:5]}) ##1
                   (gd(d) inside {[2:12]}))
  else gd_fails++;
  assert property (@(posedge clk) (d inside {[0:9]}) ##1 (d inside {[1:5]}) ##1 (d inside {[2:12]}))
  else ref_fails++;

  int fails = 0, passes = 0, imp_passes = 0, two_fails = 0;
  assert property (p_cap(0));
  assert property (p_cap(1))
  else;
  assert property (p_cap(2))
  else fails++;
  assert property (p_cap(3)) passes++;
  assert property (p_imp) imp_passes++;
  assert property (p_two)
  else two_fails++;

  always @(negedge clk) begin
    if (cyc == 20) begin
      for (int k = 0; k < 5; ++k) begin
        `checkd(bad[k], 0);
        `checkd(good[k], 19);
      end
      `checkd(fails, 0);
      `checkd(passes, 19);
      `checkd(imp_passes, 19);
      `checkd(two_fails, 2);
      `checkd(gd_fails, ref_fails);
      `checkd(ref_fails > 0, 1'b1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
