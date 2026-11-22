// DESCRIPTION: Verilator: Upward assertion control name, a block in one parent, the top in one
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// From the mid in par, t is par's generate block, the closer scope; from the mid in the top
// module, t is the top module (IEEE 1800-2023 23.8)
module mid;
  initial $assertoff(0, t.inner);
endmodule

module par;
  int failures = 0;
  if (1) begin : t
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

module t;
  int failures = 0;
  int other_failures = 0;
  if (1) begin : inner
    initial begin
      #1;
      check :
      assert (1'b0)
      else failures++;
    end
  end
  initial begin
    #1;
    other :
    assert (1'b0)
    else other_failures++;
  end
  mid m ();
  par p ();
  initial begin
    #2;
    `checkd(p.failures, 0);
    `checkd(failures, 0);
    `checkd(other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
