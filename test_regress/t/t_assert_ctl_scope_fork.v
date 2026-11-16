// DESCRIPTION: Assertion-control operand ownership in timed fork branches.
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-License-Identifier: CC0-1.0
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on
`timescale 1ns / 1ps
module assertion_leaf;
  int failures = 0;
  initial begin
    #2;
    labelled_check :
    assert (1'b0)
    else failures++;
  end
endmodule
module t;
  assertion_leaf a ();
  assertion_leaf b ();
  assertion_leaf c ();
  int argument_calls = 0;
  function automatic int level_value();
    argument_calls++;
    return 0;
  endfunction
  task automatic disable_b(input int level);
    $assertoff(level, b);
  endtask
  initial begin
    fork
      begin
        #1;
        $assertoff(level_value(), a);
      end
      begin
        #1;
        disable_b(level_value());
      end
    join_none
    #3;
    `checkd(argument_calls, 2);
    `checkd(a.failures, 0);
    `checkd(b.failures, 0);
    `checkd(c.failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
