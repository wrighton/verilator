// DESCRIPTION: Verilator: Upward assertion control name found in a farther instance
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

// The par holding mid has no gb, so gb.inner is found in the par above it
// (IEEE 1800-2023 23.8 c)
module par #(
    parameter bit HAS = 1,
    parameter bit OFF = 1
);
  int failures = 0;
  int other_failures = 0;
  if (HAS) begin : gb
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
    par #(.HAS(0), .OFF(OFF)) sub ();
  end
  else begin : leaf
    mid m (OFF);
  end
endmodule

module t;
  par p0 ();
  par #(.OFF(0)) p1 ();
  initial begin
    #2;
    `checkd(p0.failures, 0);
    `checkd(p1.failures, 1);
    `checkd(p0.other_failures, 1);
    `checkd(p1.other_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
