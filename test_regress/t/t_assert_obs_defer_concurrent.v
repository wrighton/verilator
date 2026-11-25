// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Deferred immediate assertions in the action blocks of concurrent assertions, beside other
// concurrent assertions and procedures
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  int action_fails;
  int proc_fails;
  function void record_action();
    ++action_fails;
  endfunction
  function void record_proc();
    ++proc_fails;
  endfunction

  // Test: an observed deferred assertion in a pass action
  assert property (@(posedge clk) 1) begin
    assert #0 (!cyc[0])
    else record_action();
  end

  // Test: a cover with an action after it
  cover property (@(posedge clk) cyc[1]) begin
  end

  // Test: a procedure after them, with its own deferred assertion
  always @(posedge clk) begin
    assert #0 (cyc != 3)
    else record_proc();
  end

  initial begin
    #100;
    `checkd(action_fails, 5);
    `checkd(proc_fails, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
