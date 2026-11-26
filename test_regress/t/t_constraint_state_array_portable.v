// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Constraints reading non-random arrays through a random index are given to the solver without
// constant arrays, which are outside the SMT-LIB logics, as an index test per element

localparam int BIG = 256;

class StateIndex;
  rand int k, k2, ka;
  rand bit [7:0] yf, yd, yq, ya, yg;
  bit [7:0] f[4];
  bit [7:0] d[];
  bit [7:0] q[$];
  bit [7:0] aa[int];
  bit [7:0] g[3][3];
  constraint c {
    k inside {[0 : 3]};
    k2 inside {[0 : 2]};
    ka inside {[0 : 4]};
    yf == f[k];
    yd == d[k];
    yq == q[k];
    ya == aa[ka];
    yg == g[k2][k % 3];
  }
endclass

// Arrays with rand_mode(0) hold their elements
class ModeOff;
  rand int k;
  rand int unsigned sum;
  rand bit [7:0] yf, yd, yq;
  rand bit [7:0] f[4];
  rand bit [7:0] d[];
  rand bit [7:0] q[$];
  constraint c {
    k inside {[0 : 3]};
    yf == f[k];
    yd == d[k];
    yq == q[k];
    sum == d.sum() with (32'(item));
  }
endclass

// Members of a struct array element chosen by a random index
typedef struct {
  rand bit [7:0] vals[3];
  rand bit [7:0] grid[2][2];
} item_t;

class MemberIndex;
  rand int idx;
  rand bit [7:0] yv, yg;
  rand item_t items[2];
  constraint c {
    idx inside {[0 : 3]};
    foreach (items[i]) {
      foreach (items[i].vals[j]) items[i].vals[j] == 8'(i * 3 + j + 1);
      foreach (items[i].grid[j, l]) items[i].grid[j][l] == 8'(8'h40 + i * 4 + j * 2 + l);
    }
    yv == items[idx].vals[1];
    yg == items[idx].grid[1][0];
  }
endclass

class Big;
  rand int k;
  rand bit [15:0] y;
  bit [15:0] t[];
  constraint c {
    k inside {[0 : BIG - 1]};
    y == t[k];
  }
endclass

module t;
  initial begin
    automatic StateIndex o = new;
    automatic Big b = new;
    automatic int randomize_result;
    o.f = '{8'h10, 8'h11, 8'h12, 8'h13};
    o.d = '{8'h20, 8'h21, 8'h22};
    o.q = '{8'h30, 8'h31};
    o.aa = '{1: 8'h41, 3: 8'h43, default: 8'h4d};
    foreach (o.g[i, j]) o.g[i][j] = 8'(8'h50 + i * 3 + j);
    repeat (20) begin
      randomize_result = o.randomize();
      `checkh(randomize_result, 1);
      `checkh(o.yf, o.f[o.k]);
      `checkh(o.yd, o.k < 3 ? o.d[o.k] : 8'h0);
      `checkh(o.yq, o.k < 2 ? o.q[o.k] : 8'h0);
      `checkh(o.ya, o.aa.exists(o.ka) ? o.aa[o.ka] : 8'h4d);
      `checkh(o.yg, o.g[o.k2][o.k % 3]);
    end
    begin
      automatic ModeOff m = new;
      m.f = '{8'h60, 8'h61, 8'h62, 8'h63};
      m.d = '{8'h70, 8'h71, 8'h72};
      m.q = '{8'h80, 8'h81};
      m.f.rand_mode(0);
      m.d.rand_mode(0);
      m.q.rand_mode(0);
      repeat (20) begin
        randomize_result = m.randomize();
        `checkh(randomize_result, 1);
        `checkh(m.yf, m.f[m.k]);
        `checkh(m.yd, m.k < 3 ? m.d[m.k] : 8'h0);
        `checkh(m.yq, m.k < 2 ? m.q[m.k] : 8'h0);
        `checkh(m.sum, 32'h70 + 32'h71 + 32'h72);
      end
      `checkh(m.d[1], 8'h71);
    end
    begin
      automatic MemberIndex mi = new;
      automatic int out = 0;
      repeat (20) begin
        randomize_result = mi.randomize();
        `checkh(randomize_result, 1);
        if (mi.idx >= 2) ++out;
        `checkh(mi.yv, mi.idx < 2 ? mi.items[mi.idx[0]].vals[1] : 8'h0);
        `checkh(mi.yg, mi.idx < 2 ? mi.items[mi.idx[0]].grid[1][0] : 8'h0);
      end
      if (out == 0) `stop;
    end
    b.t = new[BIG];
    foreach (b.t[i]) b.t[i] = 16'(i * 7 + 1);
    repeat (3) begin
      randomize_result = b.randomize();
      `checkh(randomize_result, 1);
      `checkh(b.y, b.t[b.k]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
