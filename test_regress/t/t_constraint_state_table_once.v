// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A non-random array read by random indices many times is sent to the solver once

localparam int N = 40;

class Lookup;
  bit [15:0] tbl[N];
  rand bit [5:0] idx[N];
  rand bit [15:0] y[N];
  constraint c {
    foreach (idx[k]) {
      idx[k] < 6'(N);
      y[k] == tbl[idx[k]];
    }
  }
endclass

// The same table read in a member object's constraint, solved with the holder's
// (IEEE 1800-2023 18.5.9), next to a different table of the holder
class Inner;
  bit [7:0] t[4];
  rand bit [1:0] i;
  rand bit [7:0] v;
  constraint c {v == t[i];}
endclass

class Outer;
  bit [7:0] t[4];
  rand Inner h;
  rand bit [1:0] i;
  rand bit [7:0] v;
  constraint c {
    v == t[i];
    h.v != v;
  }
  function new();
    h = new;
  endfunction
endclass

// The table of the class of the objects rand base class handles hold, set up when solved
// (IEEE 1800-2023 18.5.2), next to the holder's equal and different tables
class Base;
  rand bit [1:0] i;
  rand bit [7:0] v;
endclass

class Derived extends Base;
  bit [7:0] t[4];
  constraint c {v == t[i];}
endclass

class Holder;
  bit [7:0] t[4];
  bit [7:0] same[4];
  rand Base h, h2;
  rand bit [1:0] i, j;
  rand bit [7:0] v, w;
  constraint c {
    v == t[i];
    w == same[j];
    h.v != v;
    h2.v != w;
  }
endclass

// A table read by an index that is a read of another table, two and three deep
class Nested;
  bit [2:0] t1[8];
  bit [2:0] t2[8];
  bit [2:0] t3[8];
  rand bit [2:0] i;
  rand bit [2:0] two, three;
  constraint c {
    two == t2[t1[i]];
    three == t3[t2[t1[i]]];
  }
endclass

module t;
  initial begin
    automatic Lookup l = new;
    automatic Outer o = new;
    automatic int randomize_result;
    for (int round = 0; round < 2; ++round) begin
      // A changed table is sent again
      foreach (l.tbl[i]) l.tbl[i] = 16'(i * 3 + 1 + round * 1000);
      randomize_result = l.randomize();
      `checkh(randomize_result, 1);
      foreach (l.y[k]) begin
        `checkh(l.y[k], l.tbl[l.idx[k]]);
      end
    end
    o.t = '{8'h10, 8'h11, 8'h12, 8'h13};
    o.h.t = '{8'h20, 8'h21, 8'h22, 8'h23};
    repeat (8) begin
      randomize_result = o.randomize();
      `checkh(randomize_result, 1);
      `checkh(o.v, o.t[o.i]);
      `checkh(o.h.v, o.h.t[o.h.i]);
    end
    begin
      automatic Holder hd = new;
      automatic Derived d = new;
      automatic Derived d2 = new;
      d.t = '{8'h30, 8'h31, 8'h32, 8'h33};
      d2.t = '{8'h50, 8'h51, 8'h52, 8'h53};
      hd.h2 = d2;
      hd.t = '{8'h40, 8'h41, 8'h42, 8'h43};
      hd.same = d.t;
      hd.h = d;
      repeat (8) begin
        randomize_result = hd.randomize();
        `checkh(randomize_result, 1);
        `checkh(hd.v, hd.t[hd.i]);
        `checkh(hd.w, hd.same[hd.j]);
        `checkh(d.v, d.t[d.i]);
        `checkh(d2.v, d2.t[d2.i]);
      end
    end
    begin
      automatic Nested n = new;
      foreach (n.t1[k]) begin
        n.t1[k] = 3'(k + 3);
        n.t2[k] = 3'(k * 5 + 1);
        n.t3[k] = 3'(7 - k);
      end
      repeat (8) begin
        randomize_result = n.randomize();
        `checkh(randomize_result, 1);
        `checkh(n.two, n.t2[n.t1[n.i]]);
        `checkh(n.three, n.t3[n.t2[n.t1[n.i]]]);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
