// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Random arrays the solver keeps whole, as SMT arrays: each is used other than by
// element at an index known before the solve, or is solved with an array that is

class Uses;
  rand bit [3:0] at_rand[4];  // At a random index
  rand bit [1:0] k;
  rand bit [3:0] uniq[3];  // unique
  rand bit [3:0] member[3];  // inside the array
  rand bit [3:0] x;
  rand bit [3:0] summed[3];  // A method
  rand bit [3:0] ordered[2];  // solve-before
  rand bit [3:0] last[];  // At an index of its solved size
  rand bit [3:0] frozen[2];  // rand_mode of the array
  rand bit [3:0] elem_mode[2];  // rand_mode of an element
  rand bit [3:0] listed[2];  // An argument of randomize()
  rand bit [3:0] outside[2];  // Constrained by a with clause from outside
  constraint c {
    at_rand[k] == 4'd5;
    unique {uniq};
    x inside {member};
    summed.sum() with (int'(item)) == 9;
    solve ordered[0] before ordered[1];
    ordered[1] > ordered[0];
    last.size() inside {[1 : 4]};
    last[last.size() - 1] == 4'd3;
    frozen[0] == 4'd1;
    elem_mode[0] == 4'd2;
    listed[1] == 4'd4;
    outside[0] != 4'd0;
  }
endclass

// Arrays solved with an array kept whole: in a derived class's solve
class MixBase;
  rand bit [3:0] b_elig[4];
  constraint c_b {b_elig[0] == 4'd1;}
endclass
class MixDerived extends MixBase;
  rand bit [3:0] d_sum[3];
  constraint c_d {d_sum.sum() with (int'(item)) == 6;}
endclass

// Beside a non-random array read whole
class StateWhole;
  bit [3:0] tbl[4] = '{4'd1, 4'd2, 4'd3, 4'd4};
  rand bit [3:0] x;
  rand bit [3:0] el[2];
  constraint c {
    x inside {tbl};
    el[0] == 4'd2;
  }
endclass

// In a solve merging an object whose arrays are kept whole
class MInner;
  rand bit [7:0] marr[2];
  rand bit [7:0] mk;
  constraint c {marr[0] == 8'd1;}
endclass
class MInnerDerived extends MInner;
  constraint d {marr[1] == 8'd2;}
endclass
class MHolder;
  rand MInner h;
  rand bit [7:0] hel[2];
  constraint c {
    h.mk == 8'd3;
    hel[0] == 8'd4;
  }
  function new;
    MInnerDerived d;
    d = new;
    h = d;
  endfunction
endclass

module t;
  initial begin
    Uses u;
    MixDerived md;
    StateWhole sw;
    MHolder mh;
    int ok;
    md = new;
    ok = md.randomize();
    `checkd(ok, 1);
    `checkd(md.b_elig[0], 1);
    `checkd(int'(md.d_sum[0]) + int'(md.d_sum[1]) + int'(md.d_sum[2]), 6);
    sw = new;
    ok = sw.randomize();
    `checkd(ok, 1);
    `checkd(sw.x >= 1 && sw.x <= 4, 1);
    `checkd(sw.el[0], 2);
    mh = new;
    ok = mh.randomize();
    `checkd(ok, 1);
    `checkd(mh.h.mk, 3);
    `checkd(mh.h.marr[0], 1);
    `checkd(mh.h.marr[1], 2);
    `checkd(mh.hel[0], 4);
    u = new;
    u.frozen.rand_mode(0);
    u.frozen = '{4'd1, 4'd7};
    u.elem_mode[1].rand_mode(0);
    u.elem_mode[1] = 4'd6;
    repeat (3) begin
      ok = u.randomize();
      `checkd(ok, 1);
      `checkd(u.at_rand[u.k], 5);
      `checkd(u.uniq[0] != u.uniq[1] && u.uniq[1] != u.uniq[2] && u.uniq[0] != u.uniq[2], 1);
      `checkd(u.x == u.member[0] || u.x == u.member[1] || u.x == u.member[2], 1);
      `checkd(int'(u.summed[0]) + int'(u.summed[1]) + int'(u.summed[2]), 9);
      `checkd(u.ordered[1] > u.ordered[0], 1);
      `checkd(u.last[u.last.size() - 1], 3);
      `checkd(u.frozen[1], 7);
      `checkd(u.elem_mode[0], 2);
      `checkd(u.elem_mode[1], 6);
      `checkd(u.listed[1], 4);
    end
    ok = u.randomize(listed);
    `checkd(ok, 1);
    `checkd(u.listed[1], 4);
    ok = u.randomize() with {outside[1] == 4'd8;};
    `checkd(ok, 1);
    `checkd(u.outside[1], 8);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
