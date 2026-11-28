// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The constraints of the objects of a fixed-size rand array of class handles that the
// container's constraints reference are solved with them, as for a dynamic array or queue

class E;
  rand bit [6:0] v;
  rand bit [6:0] w;
  rand bit [6:0] a[2];
  constraint ec {
    v inside {[10 : 20]};
    w == v + 1;
    // The item on the array member is ignored, the other is solved
    if (v > 7'd12) {
      w != 7'd15;
      a[0] == 7'd1;
    }
  }
endclass

class Fixed;
  rand E arr[3];
  constraint c_g {foreach (arr[i]) arr[i] != null -> arr[i].v != 7'd15;}
  function new();
    foreach (arr[i]) arr[i] = new;
    // A null element has no constraints
    arr[1] = null;
  endfunction
endclass

class NegLo;
  rand E nl[1:-1];
  constraint c_g {nl[-1].v == 7'd12;}
  function new();
    foreach (nl[i]) nl[i] = new;
  endfunction
endclass

class Mid;
  rand E arr[2];
endclass

class Top;
  rand Mid m;
  constraint c_g {m.arr[0].v == 7'd11;}
  function new();
    m = new;
    foreach (m.arr[i]) m.arr[i] = new;
  endfunction
endclass

// A fixed-size array reached through an element of a queue or associative array, selected by
// a foreach index, keeps its registration by path
class Containers;
  rand Mid ms[$];
  rand Mid as[int];
  constraint c_g {
    foreach (ms[i]) foreach (ms[i].arr[j]) ms[i].arr[j].v inside {[3 : 5]};
    foreach (as[k]) as[k].arr[1].v == 7'd4;
  }
  function new();
    Mid mid;
    for (int i = 0; i < 2; ++i) begin
      mid = new;
      foreach (mid.arr[j]) mid.arr[j] = new;
      ms.push_back(mid);
    end
    as[5] = new;
    foreach (as[5].arr[j]) as[5].arr[j] = new;
  endfunction
endclass

// With the constraint mode of an object set, the objects' constraints are not solved with
// the container's, as for a dynamic array
class Cm;
  rand bit [6:0] v;
  constraint c {v < 7'd50;}
endclass

class CmHolder;
  rand Cm cms[2];
  constraint c_g {foreach (cms[i]) cms[i].v > 7'd60;}
  function new();
    foreach (cms[i]) cms[i] = new;
  endfunction
endclass

module t;
  task automatic check(E e);
    `checkd(e.v inside {[10 : 20]}, 1'b1);
    `checkd(e.w, e.v + 7'd1);
    `checkd(e.v > 7'd12 && e.w == 7'd15, 1'b0);
  endtask

  initial begin
    automatic Fixed f = new;
    automatic NegLo n = new;
    automatic Top tp = new;
    automatic CmHolder ch = new;
    automatic Containers cs = new;

    automatic int ok;
    ch.cms[0].c.constraint_mode(0);
    repeat (20) begin
      ok = f.randomize();
      `checkd(ok, 1);
      `checkd(f.arr[1], null);
      check(f.arr[0]);
      check(f.arr[2]);
      `checkd(f.arr[0].v != 7'd15 && f.arr[2].v != 7'd15, 1'b1);
      ok = n.randomize();
      `checkd(ok, 1);
      `checkd(n.nl[-1].v, 7'd12);
      foreach (n.nl[i]) check(n.nl[i]);
      ok = tp.randomize();
      `checkd(ok, 1);
      `checkd(tp.m.arr[0].v, 7'd11);
      foreach (tp.m.arr[i]) check(tp.m.arr[i]);
      ok = ch.randomize();
      `checkd(ok, 1);
      foreach (ch.cms[i]) `checkd(ch.cms[i].v > 7'd60, 1'b1);
      ok = cs.randomize();
      `checkd(ok, 1);
      foreach (cs.ms[i]) foreach (cs.ms[i].arr[j]) `checkd(cs.ms[i].arr[j].v inside {[3 : 5]}, 1'b1);
      `checkd(cs.as[5].arr[1].v, 7'd4);

    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
