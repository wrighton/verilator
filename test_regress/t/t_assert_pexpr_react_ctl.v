// DESCRIPTION: Verilator: Assertion controls and concurrent assertion actions in the Reactive region
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// x[=1] |-> y fails at tick 1 for the attempts of ticks 0-1, at tick 4 for that of tick 2, at
// tick 10 for those of ticks 7-8 and at tick 12 for those of ticks 9-11, and passes at tick 8
// for those of ticks 3-6 (IEEE 1800-2023 16.9.2, 16.12.7). The attempts deciding at tick 8
// resume, and no attempt decides in its first activation there.
// The PassOff at tick 8 is issued by Active logic of the time step the attempts also activate
// in; no result depends on their order, as no attempt starting at tick 8 decides there, and
// those executing then are not affected.
// IEEE 1800-2023 20.11: FailOff and PassOff do not affect an attempt already executing,
// including its pass or fail action, nor so other actions queued in the same time step.
module t;
  localparam int T = 13;
  localparam bit X[T] = '{0, 1, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0};
  localparam bit Y[T] = '{1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0};
  // Tick 1: FailOff from an action; 8: PassOff from Active logic
  localparam int NFAIL[T] = '{0, 2, 0, 0, 1, 0, 0, 0, 0, 0, 2, 0, 3};
  localparam int NPASS[T] = '{0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit x = X[0];
  bit y = Y[0];
  int na = 0;
  int nb = 0;
  int npass = 0;
  int ncover = 0;
  int exp_nfail = 0;
  int exp_npass = 0;

  assert property (@(posedge clk) x [= 1] |-> y)
  else begin
    // At tick 1, issued in the Reactive region after the decision of every attempt of the tick
    if (cyc == 2) $assertcontrol(9);
    ++na;
  end
  assert property (@(posedge clk) x [= 1] |-> y) ++npass;
  else ++nb;
  cover property (@(posedge clk) x [= 1] |-> y) ++ncover;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 8) $assertcontrol(7);
  end

  always @(negedge clk) begin
    exp_nfail += NFAIL[cyc-1];
    exp_npass += NPASS[cyc-1];
    `checkd(na, exp_nfail);
    `checkd(nb, exp_nfail);
    `checkd(npass, exp_npass);
    `checkd(ncover, exp_npass);
    if (cyc == 2) $assertcontrol(8);
    if (cyc == 9) $assertcontrol(6);
    if (cyc < T) begin
      x = X[cyc];
      y = Y[cyc];
    end
    else begin
      `checkd(exp_nfail, 8);
      `checkd(exp_npass, 4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
