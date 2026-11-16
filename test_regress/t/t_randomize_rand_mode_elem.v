// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// rand_mode() of single elements of arrays (IEEE 1800-2023 18.8)

typedef struct {int W;} param_t;

class Item #(
    parameter param_t P = '{W: 8}
);
  rand bit [P.W-1:0] v;
  rand bit [P.W-1:0] u;
  constraint c_v {v != 0;}
endclass

typedef Item#('{W: 8}) item_t;

class ItemD extends item_t;
  int id;
  rand bit [7:0] d;
  rand bit [3:0] arr[2];
  rand item_t sub;
endclass

// Arrays randomized without the solver
class Basic;
  rand bit [6:0] b[];
  rand bit [6:0] bq[$];
  rand bit [6:0] bf[3:1];
  rand bit [6:0] ba[1:3];
  rand item_t a[];
  rand item_t aq[$];
  rand item_t af[2:4];
  function new();
    b = new[3];
    bq = '{0, 0, 0};
    a = new[3];
    foreach (a[i]) a[i] = new;
    repeat (3) begin
      item_t it = new;
      aq.push_back(it);
    end
    foreach (af[i]) af[i] = new;
  endfunction
endclass

// Arrays referenced by constraints, so randomized by the solver
class Solved;
  rand bit [7:0] b[];
  rand bit [6:0] bf[3:1];
  rand bit [64:0] bw[$];
  rand item_t a[];
  rand ItemD af[2:3];
  rand bit [7:0] sum;
  rand bit [7:0] w;
  constraint c {
    foreach (b[i]) b[i] > 8'h10;
    foreach (bf[i]) bf[i] > 7'h10;
    foreach (bw[i]) bw[i] > 65'h10;
    foreach (a[i]) a[i].v > 8'h10;
    foreach (af[i]) af[i].d > af[i].v;
    sum == b[1] + 8'(bf[3]);
    w == a[1].u;
    bw[0] == bw[1] + 1;
  }
  function new();
    b = new[3];
    bw = '{0, 0};
    a = new[3];
    foreach (a[i]) a[i] = new;
    foreach (af[i]) af[i] = new;
  endfunction
endclass

// Size constraint growing the array
class Sized;
  rand bit [7:0] q[$];
  int n;
  constraint c_size {q.size() == n;}
endclass

// No constraints of its own, sized by randomize() with
class Unsized;
  rand bit [7:0] q[$];
endclass

// All elements switched off in pre_randomize, as e.g. a transaction's strobes
class Trans #(
    parameter param_t P = '{W: 8}
);
  rand Item #(P) m_wstrb[];
  rand bit [3:0] m_len;
  constraint c_len {m_len inside {[1 : 4]};}
  function void pre_randomize();
    foreach (m_wstrb[i]) m_wstrb[i].rand_mode(0);
  endfunction
  function new();
    m_wstrb = new[2];
    foreach (m_wstrb[i]) m_wstrb[i] = new;
  endfunction
endclass

// Solved together with the constraints of an enclosing object (IEEE 1800-2023 18.5.9)
class Outer;
  rand Solved s;
  rand item_t it;
  constraint c_o {s.b[0] < 8'h80;}
  function new();
    s = new;
    it = new;
  endfunction
endclass

module t;

  task automatic test_basic();
    int randomize_result;
    Basic bas = new;
    int changed = 0;
    int mode;
    bit on = 1;
    bas.b[1] = 7'h11;
    bas.bq[1] = 7'h12;
    bas.bf[3] = 7'h13;
    bas.ba[1] = 7'h14;
    bas.a[1].v = 8'h00;  // Violates c_v, which is not used while a[1] is off
    bas.aq[1].v = 8'h15;
    bas.af[3].v = 8'h16;
    bas.b[1].rand_mode(0);
    bas.bq[1].rand_mode(0);
    bas.bf[3].rand_mode(0);
    bas.ba[1].rand_mode(0);
    bas.a[1].rand_mode(0);
    bas.aq[1].rand_mode(0);
    bas.af[3].rand_mode(0);
    `checkh(bas.b[1].rand_mode(), 0);
    `checkh(bas.b[0].rand_mode(), 1);
    `checkh(bas.bq[1].rand_mode(), 0);
    `checkh(bas.bq[2].rand_mode(), 1);
    `checkh(bas.bf[3].rand_mode(), 0);
    `checkh(bas.bf[1].rand_mode(), 1);
    `checkh(bas.ba[1].rand_mode(), 0);
    `checkh(bas.ba[3].rand_mode(), 1);
    `checkh(bas.a[1].rand_mode(), 0);
    `checkh(bas.af[2].rand_mode(), 1);
    repeat (20) begin
      automatic bit [6:0] b0 = bas.b[0];
      automatic bit [7:0] a0 = bas.a[0].v;
      automatic bit [6:0] bf1 = bas.bf[1];
      automatic bit [6:0] ba3 = bas.ba[3];
      randomize_result = bas.randomize();
      `checkd(randomize_result, 1);
      `checkh(bas.b[1], 7'h11);
      `checkh(bas.bq[1], 7'h12);
      `checkh(bas.bf[3], 7'h13);
      `checkh(bas.ba[1], 7'h14);
      `checkh(bas.a[1].v, 8'h00);
      `checkh(bas.aq[1].v, 8'h15);
      `checkh(bas.af[3].v, 8'h16);
      if (bas.b[0] != b0 && bas.a[0].v != a0 && bas.bf[1] != bf1 && bas.ba[3] != ba3) ++changed;
    end
    if (changed == 0) `stop;
    // Nor checked by randomize(null) (IEEE 1800-2023 18.11.1)
    randomize_result = bas.randomize(null);
    `checkd(randomize_result, 1);
    // The element object itself is still randomized by its own randomize()
    randomize_result = bas.a[1].randomize();
    `checkd(randomize_result, 1);
    if (bas.a[1].v == 8'h00) `stop;
    // Back on, with a variable argument
    bas.b[1].rand_mode(on);
    bas.af[3].rand_mode(on);
    mode = bas.b[1].rand_mode();
    `checkh(mode, 1);
    changed = 0;
    repeat (20) begin
      randomize_result = bas.randomize();
      `checkd(randomize_result, 1);
      if (bas.b[1] != 7'h11 && bas.af[3].v != 8'h16) ++changed;
      `checkh(bas.bq[1], 7'h12);
    end
    if (changed == 0) `stop;
    // Without an index, rand_mode() sets all elements
    bas.bq.rand_mode(1);
    `checkh(bas.bq[1].rand_mode(), 1);
    bas.bq[1].rand_mode(0);
    bas.bq.rand_mode(0);
    `checkh(bas.bq[2].rand_mode(), 0);
    bas.rand_mode(1);
    `checkh(bas.bq[1].rand_mode(), 1);
    `checkh(bas.ba[1].rand_mode(), 1);
  endtask

  task automatic test_solved();
    int randomize_result;
    Solved sol = new;
    int changed = 0;
    sol.b[1] = 8'h21;
    sol.bf[3] = 7'h22;
    sol.bw[1] = 65'h1_0000_0000_0000_0123;
    sol.a[1].v = 8'h23;
    sol.a[1].u = 8'h24;
    sol.af[3].v = 8'h00;  // Violates c_v, which is not used while af[3] is off
    sol.af[3].d = 8'h26;
    sol.b[1].rand_mode(0);
    sol.bf[3].rand_mode(0);
    sol.bw[1].rand_mode(0);
    sol.a[1].rand_mode(0);
    sol.af[3].rand_mode(0);
    repeat (20) begin
      automatic bit [7:0] b0 = sol.b[0];
      randomize_result = sol.randomize();
      `checkd(randomize_result, 1);
      `checkh(sol.b[1], 8'h21);
      `checkh(sol.bf[3], 7'h22);
      `checkh(sol.bw[1], 65'h1_0000_0000_0000_0123);
      `checkh(sol.a[1].v, 8'h23);
      `checkh(sol.a[1].u, 8'h24);
      `checkh(sol.af[3].v, 8'h00);
      `checkh(sol.af[3].d, 8'h26);
      if (sol.af[2].d <= sol.af[2].v) `stop;
      // Off elements are state variables of the constraints
      `checkh(sol.sum, 8'h43);
      `checkh(sol.w, 8'h24);
      `checkh(sol.bw[0], 65'h1_0000_0000_0000_0124);
      if (sol.b[0] != b0) ++changed;
    end
    if (changed == 0) `stop;
    randomize_result = sol.randomize() with {b[0] == b[1] + 1;};
    `checkd(randomize_result, 1);
    `checkh(sol.b[0], 8'h22);
    randomize_result = sol.randomize() with {b[1] == 8'h30;};
    `checkd(randomize_result, 0);
    sol.b[1] = 8'h01;  // Violates c
    randomize_result = sol.randomize();
    `checkd(randomize_result, 0);
    `checkh(sol.b[1], 8'h01);
  endtask

  task automatic test_sized();
    int randomize_result;
    Sized siz = new;
    int changed = 0;
    siz.q = '{8'h31, 8'h32};
    siz.q[0].rand_mode(0);
    siz.n = 5;
    repeat (10) begin
      randomize_result = siz.randomize();
      `checkd(randomize_result, 1);
      `checkh(siz.q.size(), 5);
      `checkh(siz.q[0], 8'h31);
      `checkh(siz.q[4].rand_mode(), 1);
      if (siz.q[1] != 8'h32) ++changed;
    end
    if (changed == 0) `stop;
  endtask

  task automatic test_unsized();
    int randomize_result;
    Unsized uns = new;
    uns.q = '{8'h35};
    uns.q[0].rand_mode(0);
    randomize_result = uns.randomize() with {q.size() == 3; q[0] == q[2];};
    `checkd(randomize_result, 1);
    `checkh(uns.q.size(), 3);
    `checkh(uns.q[0], 8'h35);
    `checkh(uns.q[2], 8'h35);
  endtask

  task automatic test_trans();
    int randomize_result;
    Trans #('{W: 8}) tr = new;
    tr.m_wstrb[0].v = 8'h41;
    tr.m_wstrb[1].v = 8'h42;
    repeat (5) begin
      randomize_result = tr.randomize();
      `checkd(randomize_result, 1);
      `checkh(tr.m_wstrb[0].v, 8'h41);
      `checkh(tr.m_wstrb[1].v, 8'h42);
      `checkh(tr.m_wstrb[1].rand_mode(), 0);
    end
  endtask

  task automatic test_outer();
    int randomize_result;
    Outer out = new;
    out.s.b[1] = 8'h51;
    out.s.b[1].rand_mode(0);
    repeat (5) begin
      randomize_result = out.randomize();
      `checkd(randomize_result, 1);
      `checkh(out.s.b[1], 8'h51);
      if (out.s.b[0] >= 8'h80) `stop;
    end
  endtask

  initial begin
    test_basic();
    test_solved();
    test_sized();
    test_unsized();
    test_trans();
    test_outer();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
