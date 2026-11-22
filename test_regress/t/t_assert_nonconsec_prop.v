// DESCRIPTION: Verilator: Nonconsecutive repetition as a property
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.9.2: x[=2] is x[->2] ##1 !x[*0:$], so its first match ends at the second x
// (!x[*0] is empty), where the property passes. The counts are cumulative after each tick;
// attempts without a second x by the last tick are still pending.
module t;
  localparam int T = 10;
  localparam bit X[T] = '{0, 1, 0, 1, 1, 0, 0, 1, 0, 0};
  localparam int EXP_PASS[T] = '{0, 0, 0, 2, 4, 4, 4, 5, 5, 5};
  localparam int EXP_PASS_NONOV[T] = '{0, 0, 0, 1, 3, 3, 3, 4, 4, 4};

  bit clk = 0;
  int tick = 0;
  bit x = X[0];
  int passes = 0;
  int passes_nonov = 0;

  assert property (@(posedge clk) x [= 2]) passes++;
  assert property (@(posedge clk) 1 |=> x [= 2]) passes_nonov++;

  always #5 clk = ~clk;

  always @(posedge clk) tick <= tick + 1;

  always @(negedge clk) begin
    `checkd(passes, EXP_PASS[tick-1]);
    `checkd(passes_nonov, EXP_PASS_NONOV[tick-1]);
    if (tick < T) begin
      x = X[tick];
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
