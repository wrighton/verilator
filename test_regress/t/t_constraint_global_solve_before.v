// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The ordering of a rand member object's variables, solved with the constraints of an object
// holding it, also through two and three levels of member objects (IEEE 1800-2023 18.5.9)

class Leaf;
  rand bit [7:0] x;
  rand bit y;
  // Without the ordering, y would almost never be 1
  constraint c_order {
    solve y before x;
    y -> x == 0;
  }
endclass

class Mid;
  rand Leaf leaf;
  function new();
    leaf = new;
  endfunction
endclass

class Outer;
  rand Mid mid;
  function new();
    mid = new;
  endfunction
endclass

// Each holder solves one ordering, as several orderings in one solve are not spread evenly
class Holder2;
  rand Mid mid;
  constraint c_x {mid.leaf.x != 8'd255;}
  function new();
    mid = new;
  endfunction
endclass

class Holder3;
  rand Outer outer;
  constraint c_x {outer.mid.leaf.x != 8'd255;}
  function new();
    outer = new;
  endfunction
endclass

module t;
  initial begin
    automatic Holder2 h2 = new;
    automatic Holder3 h3 = new;
    automatic int randomize_result;
    automatic int ones2 = 0;
    automatic int ones3 = 0;
    repeat (40) begin
      randomize_result = h2.randomize();
      `checkd(randomize_result, 1);
      if (h2.mid.leaf.y) begin
        `checkd(h2.mid.leaf.x, 0);
        ++ones2;
      end
      randomize_result = h3.randomize();
      `checkd(randomize_result, 1);
      if (h3.outer.mid.leaf.y) begin
        `checkd(h3.outer.mid.leaf.x, 0);
        ++ones3;
      end
    end
    `checkd(ones2 > 5, 1'b1);
    `checkd(ones3 > 5, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
