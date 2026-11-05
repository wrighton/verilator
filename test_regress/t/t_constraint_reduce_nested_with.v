// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 by Wilson Snyder and Contributors
// SPDX-License-Identifier: CC0-1.0

// Nested array reductions with 'with' over the rows of multi-dimensional rand arrays
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class OneHot;
  rand bit m_ids[4][4];
  constraint c_one {m_ids.sum(item1) with ((item1.sum(item2) with (int'(item2)))) == 1;}
  function void check(int exp);
    int total = 0;
    foreach (m_ids[i, j]) total += int'(m_ids[i][j]);
    `checkd(total, exp);
  endfunction
endclass

typedef bit [3:0] row_t[4];

class RowRefs;
  rand row_t m_t[3];
  rand bit m_f[4][5];
  rand bit m_r[4][3];
  rand int m_a;
  constraint c_rows {
    m_t.sum(r) with (r.sum(e) with (int'(e))) == 7;
    foreach (m_f[i]) m_f[i].sum() with (int'(item)) == i + 1;
    // A fixed-size row selected by a random index
    m_a inside {[0 : 3]};
    m_r[m_a].sum() with (int'(item)) == 3;
    m_r.sum(r) with (r.sum(e) with (int'(e))) == 3;
  }
  function void check();
    int total = 0;
    foreach (m_t[i, j]) total += int'(m_t[i][j]);
    `checkd(total, 7);
    foreach (m_f[i]) begin
      total = 0;
      foreach (m_f[i][j]) total += int'(m_f[i][j]);
      `checkd(total, i + 1);
    end
    foreach (m_r[i]) begin
      total = 0;
      foreach (m_r[i][j]) total += int'(m_r[i][j]);
      `checkd(total, i == m_a ? 3 : 0);
    end
  endfunction
endclass

class Ops;
  rand bit [3:0] m_a[2][5];
  rand bit [3:0] m_x[3][2];
  rand bit [3:0] m_o[3][2];
  rand bit [3:0] m_p[2][2];
  rand byte unsigned m_s[3][2];
  rand bit m_sh[3][3];
  constraint c_ops {
    m_a.and(r) with (r.and(e) with (e)) == 4'h9;
    m_x.xor(r) with (r.xor(e) with (e)) == 4'h6;
    m_o.or(r) with (r.or(e) with (e)) == 4'h0;
    m_p.product(r) with (r.product(e) with (32'(e))) == 30;
    m_s.sum(r) with (r.sum()) == 8'd77;  // Inner reduction without 'with'
    m_sh.sum() with (item.sum() with (int'(item))) == 2;  // Inner 'item' shadows the outer
  }
  function void check();
    bit [3:0] a = '1;
    bit [3:0] x = 0;
    bit [3:0] o = 0;
    int p = 1;
    byte unsigned s = 0;
    int sh = 0;
    foreach (m_a[i, j]) a &= m_a[i][j];
    foreach (m_x[i, j]) x ^= m_x[i][j];
    foreach (m_o[i, j]) o |= m_o[i][j];
    foreach (m_p[i, j]) p *= int'(m_p[i][j]);
    foreach (m_s[i, j]) s += m_s[i][j];
    foreach (m_sh[i, j]) sh += int'(m_sh[i][j]);
    `checkd(a, 4'h9);
    `checkd(x, 4'h6);
    `checkd(o, 4'h0);
    `checkd(p, 30);
    `checkd(s, 77);
    `checkd(sh, 2);
  endfunction
endclass

class Index;
  rand bit [7:0] m_v[3][4];
  // Each element equals its outer index * 4 + its inner index
  constraint c_idx {m_v.sum(r) with (r.sum(e) with (int'(e != 8'(r.index * 4 + e.index)))) == 0;}
  function void check();
    foreach (m_v[i, j]) `checkd(m_v[i][j], 8'(i * 4 + j));
  endfunction
endclass

class ThreeD;
  rand bit m_c[2][3][4];
  constraint c_3d {m_c.sum(x) with (x.sum(y) with (y.sum(z) with (int'(z)))) == 2;}
  function void check();
    int total = 0;
    foreach (m_c[i, j, k]) total += int'(m_c[i][j][k]);
    `checkd(total, 2);
  endfunction
endclass

class Rows;
  rand int m_d[3][];
  rand bit m_x[2];
  function new();
    foreach (m_d[i]) m_d[i] = new[i + 1];
  endfunction
  constraint c_rows {
    m_d.sum(r) with (r.sum(e) with (int'(e > 0 && e < 10))) == 6;
    m_d[0].sum() with (item) == 4;
    foreach (m_d[i]) m_d[i].sum() with (item) == i + 4;
    m_x.sum(r) with (m_d[r.index + 1].sum() with (item)) == 11;
  }
  function void check();
    int total = 0;
    foreach (m_d[i, j]) total += int'(m_d[i][j] > 0 && m_d[i][j] < 10);
    `checkd(total, 6);
    `checkd(m_d[0][0], 4);
    foreach (m_d[i]) begin
      total = 0;
      foreach (m_d[i][j]) total += m_d[i][j];
      `checkd(total, i + 4);
    end
  endfunction
endclass

class ForeachIdx;
  rand int m_p[3];
  // m_p is a permutation of 1..3
  constraint c_perm {foreach (m_p[i]) m_p.sum() with (int'(item == i + 1)) == 1;}
  function void check();
    int sorted[3] = m_p;
    sorted.sort();
    foreach (sorted[i]) `checkd(sorted[i], i + 1);
  endfunction
endclass

class Sub;
  rand bit [3:0] m_arr[3];
  rand int m_darr[];
  function new();
    m_darr = new[2];
  endfunction
endclass

class Members;
  typedef struct {
    rand bit [3:0] arr[3];
    rand int darr[];
  } st_t;
  rand st_t m_st;
  rand Sub m_sub;
  function new();
    m_st.darr = new[2];
    m_sub = new;
  endfunction
  constraint c_members {
    m_st.arr.sum() with (int'(item)) == 20;
    m_st.darr.sum() with (item) == 7;
    m_sub.m_arr.sum() with (int'(item)) == 21;
    m_sub.m_darr.sum() with (item) == 9;
    foreach (m_st.darr[i]) m_st.darr[i] inside {[0 : 10]};
    foreach (m_sub.m_darr[i]) m_sub.m_darr[i] inside {[0 : 10]};
  }
  function void check();
    `checkd(m_st.arr[0] + m_st.arr[1] + m_st.arr[2], 20);
    `checkd(m_st.darr[0] + m_st.darr[1], 7);
    `checkd(m_sub.m_arr[0] + m_sub.m_arr[1] + m_sub.m_arr[2], 21);
    `checkd(m_sub.m_darr[0] + m_sub.m_darr[1], 9);
  endfunction
endclass

module t;
  initial begin
    OneHot oh;
    Ops ops;
    Index idx;
    ThreeD td;
    Rows rows;
    ForeachIdx fi;
    Members mem;
    RowRefs rr;
    int ok;
    int k;
    oh = new;
    ops = new;
    idx = new;
    td = new;
    rows = new;
    fi = new;
    mem = new;
    rr = new;
    k = 5;
    repeat (20) begin
      ok = oh.randomize();
      `checkd(ok, 1);
      oh.check(1);
      ok = ops.randomize();
      `checkd(ok, 1);
      ops.check();
      ok = idx.randomize();
      `checkd(ok, 1);
      idx.check();
      ok = td.randomize();
      `checkd(ok, 1);
      td.check();
      ok = rows.randomize();
      `checkd(ok, 1);
      rows.check();
      ok = fi.randomize();
      `checkd(ok, 1);
      fi.check();
      ok = mem.randomize();
      `checkd(ok, 1);
      mem.check();
      ok = rr.randomize();
      `checkd(ok, 1);
      rr.check();
      // A caller variable in an inline constraint is state
      idx.c_idx.constraint_mode(0);
      ok = idx.randomize() with {m_v.sum(r) with (r.sum(e) with (32'(e) * k)) == 10;};
      `checkd(ok, 1);
      `checkd(idx.m_v.sum(r) with (r.sum(e) with (32'(e))), 2);
      idx.c_idx.constraint_mode(1);
      oh.c_one.constraint_mode(0);
      ok = oh.randomize() with {m_ids.sum(r) with (r.sum(e) with (int'(e))) == 3;};
      `checkd(ok, 1);
      oh.check(3);
      oh.c_one.constraint_mode(1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
