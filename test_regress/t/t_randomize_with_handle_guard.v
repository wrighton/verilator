// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A comparison of class handles in inline constraints reads state, as randomize() does not
// assign handles

class Leaf;
  rand bit [7:0] v;
endclass

class Mid;
  rand Leaf items[];
endclass

class Top;
  rand Mid m;
  rand Leaf items[];
endclass

module t;
  initial begin
    automatic Top t1 = new;
    automatic int randomize_result;
    t1.m = new;
    t1.m.items = new[3];
    t1.items = new[3];
    foreach (t1.m.items[i]) t1.m.items[i] = new;
    foreach (t1.items[i]) t1.items[i] = new;
    t1.items[1] = null;
    t1.m.items[2] = null;
    repeat (10) begin
      // A guard of each element
      randomize_result = t1.randomize() with {
        foreach (items[j]) if (items[j] != null) items[j].v == 8'(j + 40);
      };
      `checkd(randomize_result, 1);
      `checkd(t1.items[0].v, 40);
      `checkd(t1.items[2].v, 42);
      // Through a member object
      randomize_result = t1.randomize() with {
        foreach (m.items[j]) if (m.items[j] != null) m.items[j].v == 8'(j + 50);
      };
      `checkd(randomize_result, 1);
      `checkd(t1.m.items[0].v, 50);
      `checkd(t1.m.items[1].v, 51);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
