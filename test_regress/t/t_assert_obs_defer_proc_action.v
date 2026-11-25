// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An observed deferred assertion in the action block of a procedural concurrent assertion
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  int action_fails;
  int proc_fails;
  function void record_action(int n);
    ++action_fails;
  endfunction
  function void record_proc(int n);
    ++proc_fails;
  endfunction

  always @(posedge clk) begin
    assert property (cyc >= 0) begin
      assert #0 (!cyc[0])
      else record_action(cyc);
    end
    // This deferred assertion of the procedure itself, beside the one in the action, is what
    // makes the action's deferred assertion use its queue, count and event in a process of its
    // own
    assert #0 (cyc != 3)
    else record_proc(cyc);
  end

  initial begin
    #100;
    `checkd(action_fails, 5);
    `checkd(proc_fails, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
