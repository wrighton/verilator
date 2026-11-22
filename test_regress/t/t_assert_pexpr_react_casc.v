// DESCRIPTION: Verilator: Concurrent assertion action drives a clocking block output
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// The action runs in the Reactive region, its synchronous drive with #0 output skew matures
// in the Re-NBA region, and the reactive region set is empty before the active region set
// resumes (IEEE 1800-2023 4.4.2.6, 4.5, 14.16). So the Active logic the action wakes reads
// the driven value. p until q fails at ticks 3 and 8 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 16;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  int dq = 0;
  int nfail = 0;
  // Triggers the observer, an event control, so a process of the active region set (Verilator
  // evaluates an always block sensitive to a variable as combinational logic)
  event obs_e;
  int seen_dq = 0;
  int exp_nfail = 0;
  int exp_dq = 0;

  clocking cb @(posedge clk);
    output #0 dq;
  endclocking

  assert property (@(posedge clk) p until q)
  else begin
    cb.dq <= 1000 + cyc;
    ++nfail;
    ->obs_e;
  end

  always #5 clk = ~clk;

  always @(posedge clk) cyc <= cyc + 1;

  always @(obs_e) seen_dq = dq;

  always @(negedge clk) begin
    exp_nfail += NFAIL[cyc-1];
    if (NFAIL[cyc-1] != 0) exp_dq = 1000 + cyc;
    `checkd(nfail, exp_nfail);
    `checkd(dq, exp_dq);
    if (NFAIL[cyc-1] != 0) `checkd(seen_dq, 1000 + cyc);
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(exp_nfail, 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
