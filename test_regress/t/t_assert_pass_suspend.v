// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  always #5 clk = !clk;

  // Toggles between ticks, so successive attempts alternate vacuous and nonvacuous
  bit a;
  always @(negedge clk) a <= !a;

  // A pass action that suspends past the next tick starts on the tick of its attempt
  int suspend_off_tick = 0;
  assert property (@(posedge clk) a |-> 1) begin
    if ($time % 10 != 5) suspend_off_tick++;
    #13;
  end

  int passes = 0;
  assert property (@(posedge clk) a |-> 1) passes++;

  // A pass action whose local variable is used again after it suspends
  int local_passes = 0;
  assert property (@(posedge clk) a |-> 1) begin
    automatic longint start = $time;
    #2;
    if ($time - start == 2) local_passes++;
  end

  initial begin
    #101;
    `checkd(suspend_off_tick, 0);
    `checkd(passes, 10);
    `checkd(local_passes, 10);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
