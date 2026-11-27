// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A state member read through a class handle is not read when the handle is null: a guard such
// as 'if (h != null)' keeps the read out, also of a guard condition, else it is an evaluation
// error that fails randomize() (IEEE 1800-2023 18.5.12)

class Item;
  rand bit [6:0] v;
endclass

// Guarded reads of the elements of state arrays of handles, some null
class Arrays;
  Item fixed[3];
  Item queue[$];
  rand bit [6:0] y;
  rand bit [6:0] z;
  constraint c_fixed {foreach (fixed[i]) if (fixed[i] != null) y > fixed[i].v;}
  constraint c_queue {foreach (queue[i]) if (queue[i] != null) z > queue[i].v;}
  function new();
    Item a = new;
    a.v = 7'd20;
    fixed[1] = a;
    queue.push_back(null);
    queue.push_back(a);
  endfunction
endclass

// A guarded read through a state handle
class Scalar;
  Item it;
  rand bit [6:0] y;
  constraint c_guarded {if (it != null) y > it.v;}
endclass

// Reads in guard conditions: through a null handle, kept out by an enclosing false guard
class Conditions;
  Item it;
  int mode;
  rand bit [6:0] y;
  rand bit [6:0] z;
  rand bit [6:0] w;
  rand bit [6:0] x;
  rand bit [6:0] v;
  constraint c_nested {if (it != null) {if (it.v > 3) y > 90;}}
  constraint c_mode {if (mode == 4) {if (it.v > 3) z > 90;}}
  constraint c_implication {(it != null) -> (it.v > 3 -> w > 90);}
  constraint c_and {if (it != null && it.v > 3) x > 90;}
  constraint c_cond {v > (it != null ? it.v : 7'd10);}
endclass

// An unguarded read in a guard condition
class UnguardedCondition;
  Item it;
  rand bit [6:0] y;
  constraint c_cond {if (it.v > 3) y > 90;}
endclass

// An unguarded read through a null state handle
class Unguarded;
  Item it;
  rand bit [6:0] y;
  constraint c_read {y > it.v;}
endclass

module t;
  initial begin
    automatic Arrays a = new;
    automatic Scalar s = new;
    automatic Unguarded u = new;
    automatic Conditions cn = new;
    automatic UnguardedCondition uc = new;
    automatic int randomize_result;
    repeat (5) begin
      randomize_result = a.randomize();
      `checkd(randomize_result, 1);
      `checkd(a.y > 7'd20, 1'b1);
      `checkd(a.z > 7'd20, 1'b1);
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
    end
    s.it = new;
    s.it.v = 7'd50;
    randomize_result = s.randomize();
    `checkd(randomize_result, 1);
    `checkd(s.y > 7'd50, 1'b1);
    repeat (5) begin
      randomize_result = cn.randomize();
      `checkd(randomize_result, 1);
      `checkd(cn.v > 7'd10, 1'b1);
    end
    cn.it = new;
    cn.it.v = 7'd5;
    cn.mode = 4;
    randomize_result = cn.randomize();
    `checkd(randomize_result, 1);
    `checkd(cn.y > 7'd90, 1'b1);
    `checkd(cn.z > 7'd90, 1'b1);
    `checkd(cn.w > 7'd90, 1'b1);
    `checkd(cn.x > 7'd90, 1'b1);
    `checkd(cn.v > 7'd5, 1'b1);
    randomize_result = uc.randomize();
    `checkd(randomize_result, 0);
    uc.it = new;
    uc.it.v = 7'd5;
    randomize_result = uc.randomize();
    `checkd(randomize_result, 1);
    `checkd(uc.y > 7'd90, 1'b1);
    randomize_result = u.randomize();
    `checkd(randomize_result, 0);
    u.it = new;
    u.it.v = 7'd60;
    randomize_result = u.randomize();
    `checkd(randomize_result, 1);
    `checkd(u.y > 7'd60, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
