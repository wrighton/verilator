// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// Test: a delayed NBA and a forked process read one variable of their task; the NBA uses the value
// when it runs (17), and the process, which starts once its parent blocks, the parent's later
// write (39)
module t;
  localparam realtime STEP = 1ns;
  class Box;
    int n;
  endclass
  Box o;
  int seen;
  task automatic drive(Box h);
    int v = 17;
    h.n <= #(STEP * 2) v;
    fork
      seen = v;
    join_none
    v = 39;
    #STEP;
  endtask
  initial begin
    o = new;
    drive(o);
    #(STEP * 3);
    `checkd(o.n, 17);
    `checkd(seen, 39);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
