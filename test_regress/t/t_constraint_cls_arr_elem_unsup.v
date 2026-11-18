// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The items of an element class constraint on its scalar members hold when the class
// holding a rand array of the elements solves them; items on an array member are ignored.
class Item;
  rand bit [6:0] value;
  rand bit [6:0] v;
  rand bit [6:0] arr[2];
  constraint ec {
    v < 7'd5;
    arr[0] < 7'd5;
    v < arr[1];
    if (v > 7'd1) {arr[1] > 7'd2;}
  }
endclass

class Holder;
  rand Item items[2];
  constraint c {items[0].value == 7'd9;}
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int ok;
    repeat (20) begin
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.items[0].value, 9);
      foreach (h.items[i]) `checkd(h.items[i].v < 7'd5, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
