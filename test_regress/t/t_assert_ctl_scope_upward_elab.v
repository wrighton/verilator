// DESCRIPTION: Verilator: Selective assertion control by upward names reaching differently elaborated scopes
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

// One module under parents whose upward-named scope holds a different number of assertions
module mid (
    input bit off
);
  // Upward names through the parent's module name (IEEE 1800-2023 23.8)
  initial if (off) $assertoff(0, par.gb, par.sib);
endmodule

module par #(
    parameter int N = 1,
    parameter bit OFF = 0
);
  int gb_failures = 0;
  if (1) begin : gb
    for (genvar i = 0; i < N; ++i) begin : g
      initial begin
        #1;
        check :
        assert (1'b0)
        else gb_failures++;
      end
    end
  end
  leaf sib ();
  mid m (.off(OFF));
endmodule

// The same one level deeper, through one unparameterized wrapper
module mid2 (
    input bit off
);
  initial if (off) $assertoff(0, gp.gb);
endmodule

module wrap (
    input bit off
);
  mid2 m (.off);
endmodule

module gp #(
    parameter int N = 1,
    parameter bit OFF = 0
);
  int gb_failures = 0;
  if (1) begin : gb
    for (genvar i = 0; i < N; ++i) begin : g
      initial begin
        #1;
        check :
        assert (1'b0)
        else gb_failures++;
      end
    end
  end
  wrap w (.off(OFF));
endmodule

module t;
  par #(.N(2), .OFF(1)) p0 ();
  par #(.N(1), .OFF(1)) p1 ();
  par #(.N(1), .OFF(0)) p2 ();
  par #(.N(2), .OFF(0)) p3 ();
  gp #(.N(2), .OFF(0)) q0 ();
  gp #(.N(1), .OFF(1)) q1 ();
  gp #(.N(2), .OFF(1)) q2 ();
  initial begin
    #2;
    `checkd(p0.gb_failures, 0);
    `checkd(p0.sib.failures, 0);
    `checkd(p1.gb_failures, 0);
    `checkd(p1.sib.failures, 0);
    `checkd(p2.gb_failures, 1);
    `checkd(p2.sib.failures, 1);
    `checkd(p3.gb_failures, 2);
    `checkd(p3.sib.failures, 1);
    `checkd(q0.gb_failures, 2);
    `checkd(q1.gb_failures, 0);
    `checkd(q2.gb_failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
