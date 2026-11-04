// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A member of a structure or class object element selected by a random index in a constraint
// compiles; such a constraint is not yet solved, so this test disables it

typedef struct {bit [6:0] tag;} tag_t;

class Item;
  rand bit [14:0] val;
endclass

class Test;
  rand int idx;
  rand tag_t tags[3];
  rand Item items[3];
  rand bit [7:0] other;
  constraint member_c {
    tags[idx].tag == 7'h5;
    items[idx].val == 15'h6;
  }
  constraint other_c {other == 8'd42;}
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
endclass

module t;
  initial begin
    automatic Test obj = new;
    int ok;
    obj.member_c.constraint_mode(0);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.other, 42);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
