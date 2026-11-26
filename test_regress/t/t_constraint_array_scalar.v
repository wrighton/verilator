// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Random arrays that the constraints read only by element, each at an index known
// before the solve, are given to the solver element by element

// Table lookups by a random index into a state array, under a foreach
class Table;
  bit [15:0] tbl[];
  rand bit [7:0] idx[];
  rand bit [15:0] y[];
  rand bit [7:0] free;  // Unconstrained: randomized after the solve, which keeps its values
  int n;
  constraint c {
    idx.size() == n;
    y.size() == n;
    foreach (idx[k]) {
      32'(idx[k]) < n;
      y[k] == tbl[idx[k]];
    }
  }
endclass

// A fixed array, and an element of a size-solved array the array has no element at yet
class Mixed;
  rand bit [6:0] fixed_a[4];
  rand bit [7:0] grow[];
  rand bit [3:0] w;
  rand bit [3:0] w2;
  constraint c {
    fixed_a[0] == 7'd5;
    fixed_a[3] > fixed_a[0];
    grow.size() inside {[1 : 10]};
    grow[5] == 8'd7;
    w < 4'd8;
    w2 > w;
  }
  // A phased solve, whose phase values name the elements too
  constraint c_order {solve w before w2;}
  // Constraints no solution satisfies, reported with the arrays declared by element
  function int contradict();
    return randomize() with {
      w == 4'd1;
      w == 4'd2;
    };
  endfunction
endclass

// The inner object's own constraints, merged into the holder's solve
class Inner;
  rand bit [7:0] arr[4];
  rand bit [7:0] k;
  constraint c {
    arr[3] == 8'd33;
    arr[1] == arr[0] + 8'd1;
  }
endclass
// A derived class declaring constraints has a held object merge them itself
class InnerDerived extends Inner;
  constraint d {arr[2] == 8'd44;}
endclass
class Holder;
  rand Inner h;
  rand bit [7:0] v;
  // A constraint on a member of h merges h's own constraints into this solve, where its
  // arrays stay SMT arrays
  constraint c {
    v == 8'd9;
    h.k == v + 8'd1;
  }
  function new;
    InnerDerived d;
    d = new;
    h = d;
  endfunction
endclass

// An array read whole keeps the arrays it is solved with whole too
class Both;
  rand bit [7:0] whole[3];
  rand bit [7:0] elems[3];
  constraint c {
    whole.sum() with (16'(item)) == 16'd30;
    elems[1] == 8'd2;
  }
endclass

module t;
  initial begin
    Table tb;
    Mixed m;
    Holder hd;
    Both b;
    int ok;
    bit seen[int];
    tb = new;
    tb.n = 16;
    tb.tbl = new[tb.n];
    foreach (tb.tbl[i]) tb.tbl[i] = 16'(i * 3 + 1);
    repeat (4) begin
      ok = tb.randomize();
      `checkd(ok, 1);
      `checkd(tb.idx.size(), tb.n);
      `checkd(tb.y.size(), tb.n);
      foreach (tb.idx[k]) begin
        `checkd(tb.idx[k] < tb.n, 1);
        `checkd(tb.y[k], tb.tbl[tb.idx[k]]);
        seen[tb.idx[k]] = 1;
      end
    end
    // The solution is spread over the indices: at least a quarter of them, over 4 calls
    `checkd(seen.num() >= tb.n / 4, 1);

    m = new;
    repeat (4) begin
      ok = m.randomize();
      `checkd(ok, 1);
      `checkd(m.fixed_a[0], 5);
      `checkd(m.fixed_a[3] > m.fixed_a[0], 1);
      `checkd(m.grow.size() >= 6, 1);
      `checkd(m.grow[5], 7);
      `checkd(m.w < 8, 1);
      `checkd(m.w2 > m.w, 1);
    end
    // A check alone of the current values
    ok = m.randomize(null);
    `checkd(ok, 1);
    m.fixed_a[0] = 7'd6;
    ok = m.randomize(null);
    `checkd(ok, 0);
    // Constraints no solution satisfies leave the values
    m.fixed_a[0] = 7'd5;
    ok = m.contradict();
    `checkd(ok, 0);
    `checkd(m.fixed_a[0], 5);

    hd = new;
    repeat (3) begin
      ok = hd.randomize();
      `checkd(ok, 1);
      `checkd(hd.v, 9);
      `checkd(hd.h.k, 10);
      `checkd(hd.h.arr[3], 33);
      `checkd(hd.h.arr[2], 44);
      `checkd(hd.h.arr[1], 8'(hd.h.arr[0] + 1));
    end

    b = new;
    ok = b.randomize();
    `checkd(ok, 1);
    `checkd(16'(b.whole[0]) + 16'(b.whole[1]) + 16'(b.whole[2]), 30);
    `checkd(b.elems[1], 2);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
