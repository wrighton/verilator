// DESCRIPTION: Verilator: Overlapped implication with a nonconsecutive repetition antecedent
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.9.2 and 16.12.7: x[=N] matches at the N-th x and at each later tick
// before the next x, and the consequent shall hold for every one of these matches.
// The expected counts are cumulative after each sampled tick; attempts whose matches
// have not ended by the last tick are still pending and are not counted.
module t;
  localparam int T = 10;
  bit clk = 0;
  int tick = 0;  // Sampled ticks so far
  // Case 0: first match end point fails late: three attempts fail at tick 4, three pass when x recurs at tick 8
  localparam bit X0[T] = '{0, 0, 1, 0, 0, 1, 0, 0, 1, 0};
  localparam bit Y0[T] = '{0, 0, 1, 1, 0, 1, 1, 1, 1, 1};
  localparam int EXP_PASS0[T] = '{0, 0, 0, 0, 0, 0, 0, 0, 3, 3};
  localparam int EXP_FAIL0[T] = '{0, 0, 0, 0, 3, 3, 3, 3, 3, 3};
  bit x0 = X0[0];
  bit y0 = Y0[0];
  int passes0 = 0;
  int fails0 = 0;
  assert property (@(posedge clk) x0 [= 1] |-> y0) passes0++;
  else fails0++;

  // Case 1: consequent false at the tick of x itself (empty trailing match)
  localparam bit X1[T] = '{0, 1, 0, 0, 1, 0, 0, 0, 0, 0};
  localparam bit Y1[T] = '{1, 0, 1, 1, 1, 1, 1, 1, 1, 1};
  localparam int EXP_PASS1[T] = '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  localparam int EXP_FAIL1[T] = '{0, 2, 2, 2, 2, 2, 2, 2, 2, 2};
  bit x1 = X1[0];
  bit y1 = Y1[0];
  int passes1 = 0;
  int fails1 = 0;
  assert property (@(posedge clk) x1 [= 1] |-> y1) passes1++;
  else fails1++;

  // Case 2: two occurrences, the matches end when the third x arrives
  localparam bit X2[T] = '{1, 0, 1, 0, 0, 1, 0, 0, 0, 0};
  localparam bit Y2[T] = '{1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
  localparam int EXP_PASS2[T] = '{0, 0, 0, 0, 0, 1, 1, 1, 1, 1};
  localparam int EXP_FAIL2[T] = '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  bit x2 = X2[0];
  bit y2 = Y2[0];
  int passes2 = 0;
  int fails2 = 0;
  assert property (@(posedge clk) x2 [= 2] |-> y2) passes2++;
  else fails2++;

  always #5 clk = ~clk;

  always @(posedge clk) tick++;

  // The oracle deliberately uses if/stop, never an assertion.
  always @(negedge clk) begin
    $display("tick=%0d case0 passes=%0d fails=%0d", tick - 1, passes0, fails0);
    `checkd(passes0, EXP_PASS0[tick-1]);
    `checkd(fails0, EXP_FAIL0[tick-1]);
    $display("tick=%0d case1 passes=%0d fails=%0d", tick - 1, passes1, fails1);
    `checkd(passes1, EXP_PASS1[tick-1]);
    `checkd(fails1, EXP_FAIL1[tick-1]);
    $display("tick=%0d case2 passes=%0d fails=%0d", tick - 1, passes2, fails2);
    `checkd(passes2, EXP_PASS2[tick-1]);
    `checkd(fails2, EXP_FAIL2[tick-1]);
    if (tick < T) begin
      x0 = X0[tick];
      y0 = Y0[tick];
      x1 = X1[tick];
      y1 = Y1[tick];
      x2 = X2[tick];
      y2 = Y2[tick];
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
