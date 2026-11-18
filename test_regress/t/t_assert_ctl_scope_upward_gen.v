// DESCRIPTION: Verilator: Upward assertion control name starting with an ancestor's generate block
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// gb is not visible in mid, so gb.inner is searched upward from each instantiation's parent
// scope (IEEE 1800-2023 23.8 b): each mid controls its own parent's gb.inner
module mid;
  initial $assertoff(0, gb.inner);
endmodule

module wrap;
  mid m ();
endmodule

module par #(
    parameter bit DIRECT = 1
);
  int inner_failures = 0;
  int other_failures = 0;
  if (1) begin : gb
    if (1) begin : inner
      initial begin
        #1;
        check :
        assert (1'b0)
        else inner_failures++;
      end
    end
  end
  initial begin
    #1;
    other :
    assert (1'b0)
    else other_failures++;
  end
  if (DIRECT) begin : direct
    mid m ();
  end
  else begin : wrapped
    wrap w ();
  end
endmodule

module t;
  par #(.DIRECT(1)) p0 ();
  par #(.DIRECT(1)) p1 ();
  par #(.DIRECT(0)) q0 ();
  initial begin
    #2;
    `checkd(p0.inner_failures, 0);
    `checkd(p1.inner_failures, 0);
    `checkd(q0.inner_failures, 0);
    `checkd(p0.other_failures, 1);
    `checkd(p1.other_failures, 1);
    `checkd(q0.other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
