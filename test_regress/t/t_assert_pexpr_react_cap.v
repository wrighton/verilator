// DESCRIPTION: Verilator: Concurrent assertion actions with captured inputs and delays
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// p until q fails at tick 3 for the attempts of ticks 0-3 and at tick 8 for those of ticks
// 6-8; the attempts of ticks 4-5 pass at tick 5 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 16;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  int exp_nfail = 0;

  // Test: an action of a procedural assertion reads the value its automatic inputs had when
  // the instance was queued, also after the action suspends (IEEE 1800-2023 16.14.6.1)
  localparam int NSTARTS = 7;
  localparam int STARTS[NSTARTS] = '{0, 1, 2, 3, 6, 7, 8};  // Ticks of the failing attempts
  int nfailu = 0;
  int got_k[$];
  int got_k_late[$];
  int exp_k[$];
  always @(posedge clk) begin
    automatic int k = cyc;
    assert property (p until q)
    else begin
      automatic int k_copy = k;  // The action's own automatic
      got_k.push_back(k_copy);
      #2;
      got_k_late.push_back(k);
    end
  end

  // Test: each action is a process of its own, so delays do not serialize them
  int late_n = 0;
  time late_t[$];
  assert property (@(posedge clk) p until q)
  else begin
    #1;
    late_t.push_back($time);
    ++late_n;
  end
  int zero_n = 0;
  assert property (@(posedge clk) p until q)
  else begin
    #0;
    ++zero_n;
  end

  always #5 clk = ~clk;

  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    exp_nfail += NFAIL[cyc-1];
    for (int i = 0; i < NFAIL[cyc-1]; i++) exp_k.push_back(STARTS[nfailu+i]);
    nfailu += NFAIL[cyc-1];
    got_k.sort();
    got_k_late.sort();
    `checkd(got_k.size(), exp_k.size());
    `checkd(got_k_late.size(), exp_k.size());
    foreach (exp_k[i]) begin
      `checkd(got_k[i], exp_k[i]);
      `checkd(got_k_late[i], exp_k[i]);
    end
    `checkd(late_n, exp_nfail);
    `checkd(zero_n, exp_nfail);
    `checkd(late_t.size(), NFAIL[cyc-1]);
    // One time unit after the posedge, five before this negedge
    foreach (late_t[i]) `checkd(late_t[i], $time - 4);
    late_t.delete();
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(exp_nfail, 7);
      `checkd(nfailu, NSTARTS);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
