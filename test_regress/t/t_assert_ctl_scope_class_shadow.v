// DESCRIPTION: Verilator: A class scope name that shadows the top module name
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module leaf;
  int failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
  end
endmodule

module par (
    input bit off
);
  // This block is named like the top module, and is found first from the class
  // (IEEE 1800-2023 23.8), so t.l names this instance's leaf
  if (1) begin : t
    leaf l ();
  end
  class C;
    function void off_l();
      $assertoff(0, t.l);
    endfunction
  endclass
  initial begin
    if (off) begin
      automatic C c = new;
      c.off_l();
    end
  end
endmodule

module t;
  int top_failures = 0;
  par p0 (.off(1'b1));
  par p1 (.off(1'b0));
  initial begin
    #1;
    top_check :
    assert (1'b0)
    else top_failures++;
    #1;
    `checkd(p0.t.l.failures, 0);
    `checkd(p1.t.l.failures, 1);
    `checkd(top_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
