// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constraints over 2048-term expressions, with and without a state
// variable, must verilate in bounded memory, and their solutions must
// satisfy the expressions.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`define T4 a + b + 8'd3 + a
`define T16 `T4 + `T4 + `T4 + `T4
`define T64 `T16 + `T16 + `T16 + `T16
`define T256 `T64 + `T64 + `T64 + `T64
`define T1024 `T256 + `T256 + `T256 + `T256
`define T2048 `T1024 + `T1024

class Long;
  rand bit [7:0] a;
  rand bit [7:0] b;
  constraint c_long {8'(`T2048 + a) == 8'd36;}
  function bit holds();
    return 8'(`T2048 + a) == 8'd36;
  endfunction
endclass

class LongState;
  rand bit [7:0] a;
  rand bit [7:0] b;
  bit [7:0] lim = 8'd5;
  constraint c_long {8'(`T2048 + a) == 8'd36 + lim;}
  function bit holds();
    return 8'(`T2048 + a) == 8'd36 + lim;
  endfunction
endclass

module t;
  initial begin
    automatic Long c = new;
    automatic LongState cs = new;
    automatic int ok;
    ok = c.randomize();
    `checkd(ok, 1);
    `checkd(c.holds(), 1);
    ok = cs.randomize();
    `checkd(ok, 1);
    `checkd(cs.holds(), 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
