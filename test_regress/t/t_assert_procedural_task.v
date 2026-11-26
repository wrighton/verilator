// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A procedural concurrent assertion in a task (IEEE 1800-2023 16.14.6)
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic value = 1;

  // Test: a variable of the assertion's own action block is in its scope
  int seen;
  task automatic sample(input bit arg);
    assert property (@(posedge clk) value) begin
      automatic int scratch;
      scratch = 17;
      seen = scratch;
    end
  endtask

  initial begin
    sample(1);
    @(posedge clk);
    #1;
    `checkd(seen, 17);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
