// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A future sampled value function in the boolean consequent of a multi-cycle property
module t;
  bit clk = 0;
  always #1 clk = ~clk;
  global clocking @(posedge clk);
  endclocking

  int cyc = 0;
  logic a = 0, b = 0;
  logic [31:0] hist_a = 0, hist_b = 0;
  int fails = 0, ref_fails = 0;
  int nonov_fails = 0, ref_nonov_fails = 0;

  assert property (@(posedge clk) a [*2] |-> $steady_gclk(b))
  else fails++;

  assert property (@(posedge clk) a |=> $future_gclk(b))
  else nonov_fails++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[1] | cyc[3];
    b <= cyc[2] ^ cyc[0];
    hist_a[cyc] = a;
    hist_b[cyc] = b;
    // The attempt of the previous cycle, now that its future value is known
    if (cyc >= 2 && hist_a[cyc-2] && hist_a[cyc-1] && hist_b[cyc-1] != hist_b[cyc]) ref_fails++;
    // The non-overlapped attempt of two cycles ago, checked at the previous cycle
    if (cyc >= 2 && hist_a[cyc-2] && !hist_b[cyc]) ref_nonov_fails++;
    if (cyc == 30) $finish;
  end

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails, ref_fails);
    `checkd(fails, 10);
    `checkd(nonov_fails, ref_nonov_fails);
    `checkd(nonov_fails, 10);
    $write("*-* All Finished *-*\n");
  end
endmodule
