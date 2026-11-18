// DESCRIPTION: Verilator: Upward assertion control name from a generate block or an instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module mid;
  initial $assertoff(0, gb.inner);
endmodule

// In par, gb is a generate block; in qar, gb is an instance (IEEE 1800-2023 23.8 b)
module par;
  int failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else failures++;
      end
    end
  end
  mid m ();
endmodule

module leaf;
  int failures = 0;
  if (1) begin : inner
    initial begin
      #1;
      check :
      assert (1'b0)
      else failures++;
    end
  end
endmodule

module qar;
  int other_failures = 0;
  initial begin
    #1;
    other :
    assert (1'b0)
    else other_failures++;
  end
  leaf gb ();
  mid m ();
endmodule

module t;
  par p ();
  qar q ();
  initial begin
    #2;
    `checkd(p.failures, 0);
    `checkd(q.gb.failures, 0);
    `checkd(q.other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
