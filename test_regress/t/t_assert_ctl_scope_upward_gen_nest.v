// DESCRIPTION: Verilator: Upward assertion control name reached through two nested modules
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

// The mid in par finds gb.inner in par, though a qar holding one is above it; the mid in qar
// finds it in qar (IEEE 1800-2023 23.8 b)
module par (
    input bit off
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
  mid m (off);
endmodule

module qar #(
    parameter bit OFF_P = 1,
    parameter bit OFF_Q = 1
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
  par p (OFF_P);
  mid m (OFF_Q);
endmodule

module t;
  qar #(.OFF_P(1), .OFF_Q(0)) q0 ();
  qar #(.OFF_P(0), .OFF_Q(1)) q1 ();
  initial begin
    #2;
    `checkd(q0.p.failures, 0);
    `checkd(q0.failures, 1);
    `checkd(q1.p.failures, 1);
    `checkd(q1.failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
