// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test: a member of an object of a rand class handle array selected by an index that reads a state
// array by a random index

class Item;
  rand bit [6:0] v;
endclass

class Holder;
  rand Item items[4];
  bit [1:0] lut[4];
  rand bit [1:0] lj;
  constraint c {items[lut[lj]].v == 7'd40;}
  function new();
    foreach (items[i]) items[i] = new;
    lut = '{2'd1, 2'd2, 2'd0, 2'd2};
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int ok;
    repeat (10) begin
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.items[h.lut[h.lj]].v, 40);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
