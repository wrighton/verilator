// DESCRIPTION: Verilator: Upward assertion control name found in the top module from one instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

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
  mid m (1'b1);
endmodule

// The mid here finds gb.inner in the top module, the other one in par
// (IEEE 1800-2023 23.8 b)
module t;
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
  par p ();
  mid m (1'b0);
  initial begin
    #2;
    `checkd(p.failures, 0);
    `checkd(failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
