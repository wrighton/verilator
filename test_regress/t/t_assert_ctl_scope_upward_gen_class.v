// DESCRIPTION: Verilator: Upward assertion control name from a class, a block or the top module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// From the class in the mid in par, t is par's generate block; from the one in the top module,
// t is the top module (IEEE 1800-2023 23.8). The class depends on the instance of mid.
module mid (
    input bit off
);
  class C;
    function void f();
      $assertoff(0, t.inner);
    endfunction
  endclass
  always @(posedge off) begin
    automatic C c = new;
    c.f();
  end
endmodule

module par (
    input bit off
);
  int failures = 0;
  if (1) begin : t
    if (1) begin : inner
      always begin
        #2;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  mid m (off);
endmodule

module t;
  int failures = 0;
  bit parent_off;
  bit top_off;
  if (1) begin : inner
    always begin
      #2;
      check :
      assert (1'b0)
      else failures++;
    end
  end
  par p (parent_off);
  mid m (top_off);
  initial begin
    #1;
    parent_off = 1;
    #2;
    `checkd(p.failures, 0);
    `checkd(failures, 1);
    $asserton;
    top_off = 1;
    #2;
    `checkd(p.failures, 1);
    `checkd(failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
