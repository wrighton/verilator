// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element solved before the variable it controls takes either value about half the time
// (IEEE 1800-2023 18.5.10); solved together, it is 1 only when x is 0
class ElemFixed;
  rand bit a[2];
  rand bit [7:0] x;
  constraint c {
    a[0] -> x == 0;
    solve a[0] before x;
  }
endclass

class ElemDyn;
  rand bit a[];
  rand bit [7:0] x;
  constraint c {
    a[1] -> x == 0;
    solve a[1] before x;
  }
  function new();
    a = new[2];
  endfunction
endclass

class ElemQueue;
  rand bit a[$];
  rand bit [7:0] x;
  constraint c {
    a[1] -> x == 0;
    solve a[1] before x;
  }
  function new();
    a = '{0, 0};
  endfunction
endclass

class ElemAssoc;
  rand bit a[int];
  rand bit [7:0] x;
  constraint c {
    a[5] -> x == 0;
    solve a[5] before x;
  }
  function new();
    a[5] = 0;
  endfunction
endclass

class Sub;
  rand bit [7:0] y;
endclass

// Elements the ordering cannot name: of an empty queue, by a 64-bit key, a subarray, and a
// member of an object in no constraint
class ElemIgnored;
  rand Sub s;
  rand bit e[$];
  rand bit aa[longint];
  rand bit m[2][3];
  rand bit [7:0] x;
  constraint c {
    foreach (e[i]) e[i] -> x == 0;
    aa[5] -> x == 0;
    m[1][2] -> x == 0;
    solve e[0] before x;
    solve aa[5] before x;
    solve m[1] before x;
    solve s.y before x;
  }
  function new();
    s = new;
    aa[5] = 0;
  endfunction
endclass

module t;
  initial begin
    automatic ElemFixed ef = new;
    automatic ElemDyn ed = new;
    automatic ElemQueue eq = new;
    automatic ElemAssoc ea = new;
    automatic ElemIgnored ei = new;
    automatic int n_fixed = 0;
    automatic int n_dyn = 0;
    automatic int n_queue = 0;
    automatic int n_assoc = 0;
    int randomize_result;
    repeat (200) begin
      randomize_result = ef.randomize();
      `checkd(randomize_result, 1);
      n_fixed += ef.a[0];
      randomize_result = ed.randomize();
      `checkd(randomize_result, 1);
      n_dyn += ed.a[1];
      randomize_result = eq.randomize();
      `checkd(randomize_result, 1);
      n_queue += eq.a[1];
      randomize_result = ea.randomize();
      `checkd(randomize_result, 1);
      n_assoc += ea.a[5];
    end
    if (n_fixed < 50 || n_dyn < 50 || n_queue < 50 || n_assoc < 50) begin
      $write("%%Error: element 1 in %0d, %0d, %0d, %0d of 200\n", n_fixed, n_dyn, n_queue,
             n_assoc);
      `stop;
    end
    // Ordering on elements it cannot name has no effect
    randomize_result = ei.randomize();
    `checkd(randomize_result, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
