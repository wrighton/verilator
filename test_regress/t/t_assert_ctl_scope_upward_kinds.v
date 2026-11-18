// DESCRIPTION: Verilator: Upward assertion control names from a block, a task, or a class
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// A hierarchical name can start with a task or a named block, searched first at the current
// level and then in higher level modules (IEEE 1800-2023 23.8, 23.9)
module mid;
  class C;
    function void off();
      $assertoff(0, gb.inner);
    endfunction
  endclass
  initial begin
    automatic C c = new;
    $assertoff(0, nb);
    $assertoff(0, tk);
    c.off();
  end
endmodule

module par;
  int block_failures = 0;
  int task_failures = 0;
  int gen_failures = 0;
  int other_failures = 0;
  task automatic tk();
    check :
    assert (1'b0)
    else task_failures++;
  endtask
  initial begin : nb
    #1;
    check :
    assert (1'b0)
    else block_failures++;
  end
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else gen_failures++;
      end
    end
  end
  initial begin
    #1;
    tk();
    other :
    assert (1'b0)
    else other_failures++;
  end
  mid m ();
endmodule

module t;
  par p0 ();
  par p1 ();
  initial begin
    #2;
    `checkd(p0.block_failures, 0);
    `checkd(p1.block_failures, 0);
    `checkd(p0.task_failures, 0);
    `checkd(p1.task_failures, 0);
    `checkd(p0.gen_failures, 0);
    `checkd(p1.gen_failures, 0);
    `checkd(p0.other_failures, 1);
    `checkd(p1.other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
