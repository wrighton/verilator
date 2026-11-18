// DESCRIPTION: Verilator: Upward assertion control name through generate blocks of two modules
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// Each mid finds gb.inner in its own parent (IEEE 1800-2023 23.8 b), and the parents are of
// different modules
module mid (
    input bit off
);
  initial if (off) $assertoff(0, gb.inner);
endmodule

module par #(
    parameter bit OFF = 1
);
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
  mid m (OFF);
endmodule

module qar #(
    parameter bit OFF = 1
);
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
  mid m (OFF);
endmodule

module t;
  par p0 ();
  par #(.OFF(0)) p1 ();
  qar q0 ();
  qar #(.OFF(0)) q1 ();
  initial begin
    #2;
    `checkd(p0.failures, 0);
    `checkd(p1.failures, 1);
    `checkd(q0.failures, 0);
    `checkd(q1.failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
