// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin \
  $write("%%Error: %s:%0d: got=%0d exp=%0d (%s !== %s)\n", \
         `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); \
  `stop; \
end while (0)
// verilog_format: on

// An assertion without 'else' reports a failure with $error, also with a pass action
// (IEEE 1800-2023 16.3, 16.14.1); one with 'else;' reports nothing.
// Each assertion fails at cyc 2 and 4, and $assertfailoff hides the failures at cyc 4.
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  wire ok = cyc != 2 && cyc != 4;

  int passes = 0;
  // A deferred assertion action is a subroutine call (IEEE 1800-2023 16.4)
  function void pass();
    passes++;
  endfunction
  assert property (@(posedge clk) ok) passes++;
  assume property (@(posedge clk) ok) passes++;
  assert property (@(posedge clk) 1 ##1 ok) passes++;
  assert property (@(posedge clk) 1 |-> 1 ##1 ok) passes++;
  assert property (@(posedge clk) ok) passes++;
  else;
  assert property (@(posedge clk) ok)
  else;
  assert property (@(posedge clk) 1 ##1 ok)
  else;

  always @(posedge clk) begin
    assert (ok) passes++;
    assume (ok) passes++;
    assert #0 (ok) pass();
    assert final (ok) pass();
    assert (ok) passes++;
    else;
    assert (ok)
    else;
    assert #0 (ok) pass();
    else;
    assert final (ok)
    else;
  end

  initial begin
    #30 $assertfailoff;
    #20;
    // Ticks at cyc 0..4 for the always and the plain concurrent assertions (each passing on
    // 3); cyc 0..3 for the sequence and the implication, whose attempts check cyc 1..4
    // (passing on 2)
    `checkd(passes, 3 * 9 + 2 * 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  always @(posedge clk) cyc <= cyc + 1;
endmodule
