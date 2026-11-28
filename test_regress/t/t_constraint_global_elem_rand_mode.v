// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// rand_mode(0) of a variable of an object of a rand handle array, which the object holding the
// array constrains: a state variable in that object (IEEE 1800-2023 18.8)

class Elem;
  rand bit [6:0] v;
  rand bit [6:0] w;
  constraint c_odd {v[0] == 1'b1;}
endclass

class QueueHolder;
  rand Elem items[$];
  constraint c_big {foreach (items[i]) items[i].v > 7'd20;}
  function new();
    Elem e;
    repeat (2) begin
      e = new;
      items.push_back(e);
    end
  endfunction
endclass

class FixedHolder;
  rand Elem items[2];
  constraint c_big {foreach (items[i]) items[i].v > 7'd20;}
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
endclass

class DynHolder;
  rand Elem items[];
  constraint c_big {foreach (items[i]) items[i].v > 7'd20;}
  function new();
    items = new[2];
    foreach (items[i]) items[i] = new;
  endfunction
endclass

class AssocHolder;
  rand Elem items[int];
  constraint c_big {foreach (items[i]) items[i].v > 7'd20;}
  function new();
    items[3] = new;
    items[7] = new;
  endfunction
endclass

// The array of a rand member object
class Sub;
  rand Elem arr[$];
  function new();
    Elem e;
    repeat (2) begin
      e = new;
      arr.push_back(e);
    end
  endfunction
endclass

class OuterHolder;
  rand Sub s;
  constraint c_big {foreach (s.arr[i]) s.arr[i].v > 7'd20;}
  function new();
    s = new;
  endfunction
endclass

module t;
  initial begin
    automatic QueueHolder qh = new;
    automatic FixedHolder fh = new;
    automatic DynHolder dh = new;
    automatic AssocHolder ah = new;
    automatic OuterHolder oh = new;
    automatic int randomize_result;
    automatic int changed;

    qh.items[1].v.rand_mode(0);
    qh.items[1].v = 7'd31;
    changed = 0;
    repeat (10) begin
      randomize_result = qh.randomize();
      `checkd(randomize_result, 1);
      if (qh.items[1].v != 7'd31) ++changed;
      `checkd(qh.items[0].v > 7'd20, 1'b1);
    end
    `checkd(changed, 0);
    // The other variable of the object, and the variable in the other object, still change
    `checkd(qh.items[0].v[0], 1'b1);
    // A state value against the constraints fails the call, as for any state variable
    qh.items[1].v = 7'd11;
    randomize_result = qh.randomize();
    `checkd(randomize_result, 0);
    `checkd(qh.items[1].v, 11);
    // Enabled again, it is randomized
    qh.items[1].v.rand_mode(1);
    randomize_result = qh.randomize();
    `checkd(randomize_result, 1);
    `checkd(qh.items[1].v > 7'd20, 1'b1);

    fh.items[0].v.rand_mode(0);
    fh.items[0].v = 7'd41;
    dh.items[1].v.rand_mode(0);
    dh.items[1].v = 7'd51;
    ah.items[7].v.rand_mode(0);
    ah.items[7].v = 7'd61;
    oh.s.arr[1].v.rand_mode(0);
    oh.s.arr[1].v = 7'd71;
    repeat (5) begin
      randomize_result = fh.randomize();
      `checkd(randomize_result, 1);
      `checkd(fh.items[0].v, 41);
      randomize_result = dh.randomize();
      `checkd(randomize_result, 1);
      `checkd(dh.items[1].v, 51);
      randomize_result = ah.randomize();
      `checkd(randomize_result, 1);
      `checkd(ah.items[7].v, 61);
      `checkd(ah.items[3].v > 7'd20, 1'b1);
      randomize_result = oh.randomize();
      `checkd(randomize_result, 1);
      `checkd(oh.s.arr[1].v, 71);
      `checkd(oh.s.arr[0].v > 7'd20, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
