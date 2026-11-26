// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element selected out of range reads zero (IEEE 1800-2023 7.4.6); the expected values below
// select only elements in range

// verilator lint_off WIDTH

class DynIndex;
  rand bit [7:0] arr[];
  rand bit [7:0] pre[];
  rand bit [31:0] i;
  rand bit [7:0] i8;
  rand bit signed [7:0] s;
  rand bit [7:0] y, y8, ys, yp;
  constraint c {
    arr.size() == 5;
    foreach (arr[k]) arr[k] == 8'(k + 8'h31);
    foreach (pre[k]) pre[k] == 8'(k + 8'h71);
    i < 9;
    y == arr[i];
    y8 == arr[i8];
    ys == arr[s];
    yp == pre[i];
  }
  function new();
    pre = new[3];
  endfunction
endclass

class QueueIndex;
  rand bit [6:0] q[$];
  rand int i;
  rand bit [6:0] y;
  constraint c {
    q.size() == 3;
    foreach (q[k]) q[k] == 7'(k + 7'h21);
    i inside {[-4 : 6]};
    y == q[i];
  }
endclass

class FixedIndex;
  rand bit [7:0] arr[4];
  rand bit [6:0] off[4:7];
  rand bit [4:0] grid[3][5];
  rand bit [3:0] i;
  rand bit signed [3:0] s;
  rand bit [39:0] l;
  rand bit [3:0] g0, g1;
  rand bit [7:0] y, ys, yl;
  rand bit [6:0] yo;
  rand bit [4:0] yg;
  constraint c {
    foreach (arr[k]) arr[k] == 8'(k + 8'h51);
    foreach (off[k]) off[k] == 7'(k + 7'h10);
    foreach (grid[a, b]) grid[a][b] == 5'(a * 5 + b + 1);
    y == arr[i];
    ys == arr[s];
    yl == arr[l];
    l < 8 || l[39:32] == 8'h01;
    yo == off[i];
    yg == grid[g0][g1];
  }
endclass

class StateIndex;
  rand bit [7:0] arr[4];
  rand bit [7:0] darr[];
  rand bit [7:0] pre[];
  int i;
  bit [7:0] i8;
  bit [39:0] l;
  bit signed [3:0] s4;
  rand bit [7:0] g2[4][4];
  rand bit [1:0] r2;
  rand bit [7:0] y, yd, yd8, ydl, yds, yp, yp8, ypl, yps, yg;
  rand bit yc;
  constraint c {
    darr.size() == 2;
    foreach (pre[k]) pre[k] == 8'(k + 8'h61);
    yp == pre[i];
    yp8 == pre[i8];
    ypl == pre[l];
    yps == pre[s4];
    foreach (arr[k]) arr[k] == 8'ha5;
    foreach (g2[a, b]) g2[a][b] == 8'(a * 4 + b);
    yg == g2[i][r2];
    foreach (darr[k]) darr[k] == 8'(k + 8'h5a);
    y == arr[i];
    yd == darr[i];
    yd8 == darr[i8];
    ydl == darr[l];
    yds == darr[s4];
    if (arr[i] == 8'ha5) yc == 1'b0;
    else yc == 1'b1;
  }
  function new();
    pre = new[3];
  endfunction
endclass

class ForeachDims;
  rand bit [7:0] m[][2][3];
  rand bit [7:0] q[$];
  rand bit [7:0] z[3];
  constraint c {
    m.size() inside {[1 : 3]};
    foreach (m[i, j, k]) {
      m[i][j][k] == 8'(i * 6 + j * 3 + k + 1);
      z[k] == 8'(k + 8'h70);
    }
  }
  constraint c_if {
    q.size() inside {[1 : 3]};
    if (q.size() > 0) {
      foreach (q[i]) q[i] == 8'(i + 8'h80);
    }
  }
endclass

typedef struct {rand bit [7:0] a;} elem_t;

class StructElem;
  rand elem_t q[];
  rand int i;
  rand bit [7:0] y;
  constraint c {
    q.size() == 3;
    foreach (q[k]) q[k].a == 8'(k + 8'h40);
    i inside {[0 : 5]};
    y == q[i].a;
  }
endclass

class Over;
  rand bit [7:0] arr[];
  rand bit [31:0] i;
  rand bit [7:0] y;
  constraint c {
    arr.size() == 3;
    foreach (arr[k]) arr[k] == 8'h3c;
    i == 3;
    y == arr[i];
    y == 8'hc3;
  }
endclass

class Plain;
  rand bit [7:0] x;
endclass

// verilator lint_on WIDTH

module t;
  int randomize_result;

  initial begin
    // Test: dynamic array elements out of range read zero
    begin
      automatic DynIndex o = new;
      automatic int outOfRange = 0;
      repeat (30) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        if (o.i >= 5) ++outOfRange;
        `checkh(o.y, o.i < 5 ? o.arr[o.i] : 8'h0);
        `checkh(o.y8, o.i8 < 5 ? o.arr[o.i8] : 8'h0);
        `checkh(o.ys, o.s >= 0 && o.s < 5 ? o.arr[o.s] : 8'h0);
        `checkh(o.yp, o.i < 3 ? o.pre[o.i] : 8'h0);
      end
      if (outOfRange == 0 || outOfRange == 30) `stop;
    end

    // Test: queue elements out of range, including negative indices, read zero
    begin
      automatic QueueIndex o = new;
      repeat (30) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.y, o.i >= 0 && o.i < 3 ? o.q[o.i] : 7'h0);
      end
    end

    // Test: fixed array elements out of range read zero
    begin
      automatic FixedIndex o = new;
      repeat (30) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.y, o.i < 4 ? o.arr[o.i[1:0]] : 8'h0);
        `checkh(o.ys, o.s >= 0 && o.s < 4 ? o.arr[o.s[1:0]] : 8'h0);
        `checkh(o.yl, o.l < 4 ? o.arr[o.l[1:0]] : 8'h0);
        `checkh(o.yo, o.i >= 4 && o.i <= 7 ? o.off[o.i] : 7'h0);
        `checkh(o.yg, o.g0 < 3 && o.g1 < 5 ? o.grid[o.g0[1:0]][o.g1[2:0]] : 5'h0);
      end
    end

    // Test: state indices out of range read zero
    begin
      automatic StateIndex o = new;
      automatic int indices[$] = '{-3, -1, 0, 1, 2, 3, 4, 6, 32'h7fffffff};
      foreach (indices[n]) begin
        o.i = indices[n];
        o.i8 = 8'(indices[n]);
        o.l = {8'(n % 2), 32'(indices[n])};
        o.s4 = 4'(indices[n]);
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.y, o.i >= 0 && o.i < 4 ? 8'ha5 : 8'h0);
        `checkh(o.yg, o.i >= 0 && o.i < 4 ? o.g2[o.i[1:0]][o.r2] : 8'h0);
        `checkh(o.yc, o.i >= 0 && o.i < 4 ? 1'b0 : 1'b1);
        `checkh(o.yd, o.i >= 0 && o.i < 2 ? o.darr[o.i[0]] : 8'h0);
        `checkh(o.yd8, o.i8 < 2 ? o.darr[o.i8[0]] : 8'h0);
        `checkh(o.ydl, o.l < 2 ? o.darr[o.l[0]] : 8'h0);
        `checkh(o.yds, o.s4 >= 0 && o.s4 < 2 ? o.darr[o.s4[0]] : 8'h0);
        `checkh(o.yp, o.i >= 0 && o.i < 3 ? o.pre[o.i] : 8'h0);
        `checkh(o.yp8, o.i8 < 3 ? o.pre[o.i8[1:0]] : 8'h0);
        `checkh(o.ypl, o.l < 3 ? o.pre[o.l[1:0]] : 8'h0);
        `checkh(o.yps, o.s4 >= 0 && o.s4 < 3 ? o.pre[o.s4[1:0]] : 8'h0);
      end
    end

    // Test: the elements a foreach visits, as the size is solved
    begin
      automatic ForeachDims o = new;
      automatic int sizes = 0;
      repeat (12) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        sizes |= 1 << o.m.size() | 1 << (o.q.size() + 4);
        foreach (o.m[i, j, k]) `checkh(o.m[i][j][k], 8'(i * 6 + j * 3 + k + 1));
        foreach (o.z[k]) `checkh(o.z[k], 8'(k + 8'h70));
        foreach (o.q[i]) `checkh(o.q[i], 8'(i + 8'h80));
      end
      if (sizes != 'b11101110) `stop;
    end

    // Test: a member of an element selected by a random index
    begin
      automatic StructElem o = new;
      automatic int out = 0;
      repeat (20) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        if (o.i >= 3) ++out;
        `checkh(o.y, o.i < 3 ? o.q[o.i].a : 8'h0);
      end
      if (out == 0) `stop;
    end

    // Test: a std::randomize() argument selected by a variable index
    begin
      automatic bit [7:0] sarr[4] = '{8'd1, 8'd2, 8'd3, 8'd4};
      automatic int k = 2;
      randomize_result = std::randomize(sarr[k]) with {sarr[k] > 8'd200;};
      `checkd(randomize_result, 1);
      if (sarr[2] <= 8'd200) `stop;
      `checkh(sarr[1], 8'd2);
    end

    // Test: an element out of range cannot take another value
    begin
      automatic Over over = new;
      automatic Plain plain = new;
      randomize_result = over.randomize();
      `checkd(randomize_result, 0);
      // An unrelated randomization still succeeds afterwards
      randomize_result = plain.randomize() with {x == 8'h5a;};
      `checkd(randomize_result, 1);
      `checkh(plain.x, 8'h5a);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
