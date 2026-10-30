// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The outermost randomize() calls of different threads have different stamps, so an object
// one thread's call randomized is not taken as randomized by another thread's call

import "DPI-C" function int stamps_differ_over_threads();

class Item;
  rand bit [3:0] v;
endclass

module t;
  initial begin
    automatic Item it = new;
    automatic int randomize_result;
    randomize_result = it.randomize();
    `checkd(randomize_result, 1);
    `checkd(stamps_differ_over_threads(), 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
