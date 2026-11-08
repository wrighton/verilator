// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 by Wilson Snyder and Contributors
// SPDX-License-Identifier: CC0-1.0

// Test case for array reduction methods with 'with' clause in constraints (issue #6455)
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class test_sum;
  rand byte array[5];
  rand byte repeated_value;

  constraint c {
    // Ensure exactly 3 occurrences of repeated_value using sum
    array.sum() with (int'(item == repeated_value)) == 3;

    // All other values should appear exactly once
    foreach (array[i]) {
      array[i] != repeated_value -> array.sum() with (int'(item == array[i])) == 1;
    }
  }

  function void verify();
    int count_map[byte];
    int repeated_count = 0;
    int i;

    i = randomize();
    `checkd(i, 1);

    // Count occurrences
    foreach (array[idx]) begin
      if (!count_map.exists(array[idx])) count_map[array[idx]] = 0;
      count_map[array[idx]]++;
    end

    // Check repeated_value appears exactly 3 times
    if (count_map.exists(repeated_value)) begin
      repeated_count = count_map[repeated_value];
      if (repeated_count != 3) begin
        $display("%%Error: sum test - repeated_value=%0d appears %0d times, expected 3",
                 repeated_value, repeated_count);
        $stop;
      end
    end
    else begin
      $display("%%Error: sum test - repeated_value=%0d doesn't appear in array", repeated_value);
      $stop;
    end

    // Check all other values appear exactly once
    foreach (count_map[val]) begin
      if (val != repeated_value && count_map[val] != 1) begin
        $display("%%Error: sum test - value=%0d appears %0d times, expected 1", val,
                 count_map[val]);
        $stop;
      end
    end
  endfunction
endclass

class test_product;
  rand bit [3:0] array[4];

  constraint c {
    // Product of non-zero elements should be <= 100
    array.product() with (item != 0 ? int'(item) : 1) <= 100;
    // At least 2 non-zero elements
    array.sum() with (int'(item != 0)) >= 2;
  }

  function void verify();
    int prod = 1;
    int nonzero_count = 0;
    int i;

    i = randomize();
    `checkd(i, 1);

    foreach (array[idx]) begin
      if (array[idx] != 0) begin
        prod *= array[idx];
        nonzero_count++;
      end
    end

    if (prod > 100) begin
      $display("%%Error: product test - product %0d > 100", prod);
      $stop;
    end

    if (nonzero_count < 2) begin
      $display("%%Error: product test - only %0d non-zero elements", nonzero_count);
      $stop;
    end
  endfunction
endclass

class state_sub;
  rand int r;
  int k;
  constraint c {r inside {[1 : 9]};}
endclass

class test_state;
  rand int a[3];
  rand bit [6:0] d[];
  rand shortint q[$];
  rand int s;
  rand bit [6:0] p;
  rand bit [6:0] n;
  rand bit [6:0] o;
  rand shortint x;
  rand int ix;
  rand int sk;
  rand int sr;
  rand int ss;
  rand int ls;
  rand int ns;
  rand int ws;
  rand int kw;
  rand int nx;
  int nb[3];
  int off;
  int w[3];
  bit [6:0] mask;
  rand state_sub sub;
  state_sub st;

  function new();
    d = new[4];
    q = '{0, 0, 0};
    sub = new;
    st = new;
  endfunction

  constraint c {
    // State variables and state array elements in 'with' keep their values
    foreach (a[i]) a[i] inside {[-50 : 50]};
    s == a.sum() with (item * w[item.index] + off);
    p == d.product() with (item ^ mask);
    n == d.and() with (item | mask);
    o == d.or() with (item & mask);
    x == q.xor() with (item ^ shortint'(off));
    ix == q.sum() with (int'(item.index) * off);
    // Members of a random and of a state object
    sk == a.sum() with (item + sub.k);
    sr == a.sum() with (item + sub.r);
    ss == a.sum() with (item - st.k);
    // A reduction of a state array, nested or with a random 'with' expression
    ns == a.sum() with (item + w.sum());
    kw inside {[1 : 9]};
    ws == w.sum() with (item * kw);
    nx == a.sum(e) with (nb.sum(f) with (e + f));
  }

  function void verify();
    int exp_s = 0;
    bit [6:0] exp_p = 1;
    bit [6:0] exp_n = '1;
    bit [6:0] exp_o = 0;
    shortint exp_x = 0;
    int exp_ix = 0;
    int exp_sk = 0;
    int exp_sr = 0;
    int exp_ss = 0;
    int exp_ns = 0;
    int exp_ws = 0;
    int exp_nx = 0;
    int i;
    int set_off;
    int set_w[3];
    bit [6:0] set_mask;
    int set_sub_k;
    int set_st_k;
    int set_nb[3];

    set_off = $urandom_range(1000, 1);
    foreach (set_w[k]) set_w[k] = $urandom_range(9) - 4;
    set_mask = 7'($urandom);
    set_sub_k = $urandom_range(1000);
    set_st_k = $urandom_range(1000);
    foreach (set_nb[k]) set_nb[k] = $urandom_range(1000) - 500;
    nb = set_nb;
    off = set_off;
    w = set_w;
    mask = set_mask;
    sub.k = set_sub_k;
    st.k = set_st_k;

    i = randomize();
    `checkd(i, 1);
    `checkd(off, set_off);
    foreach (w[k]) `checkd(w[k], set_w[k]);
    `checkd(mask, set_mask);
    `checkd(sub.k, set_sub_k);
    `checkd(st.k, set_st_k);
    foreach (nb[k]) `checkd(nb[k], set_nb[k]);
    foreach (a[k]) begin
      exp_s += a[k] * set_w[k] + set_off;
      exp_sk += a[k] + set_sub_k;
      exp_sr += a[k] + sub.r;
      exp_ss += a[k] - set_st_k;
      exp_ns += a[k] + set_w[0] + set_w[1] + set_w[2];
      exp_ws += set_w[k] * kw;
      foreach (set_nb[j]) exp_nx += a[k] + set_nb[j];
    end
    foreach (d[k]) begin
      exp_n &= d[k] | set_mask;
      exp_p *= d[k] ^ set_mask;
      exp_o |= d[k] & set_mask;
    end
    foreach (q[k]) begin
      exp_x ^= q[k] ^ shortint'(set_off);
      exp_ix += k * set_off;
    end
    `checkd(s, exp_s);
    `checkd(p, exp_p);
    `checkd(n, exp_n);
    `checkd(o, exp_o);
    `checkd(x, exp_x);
    `checkd(ix, exp_ix);
    `checkd(sk, exp_sk);
    `checkd(sr, exp_sr);
    `checkd(ss, exp_ss);
    `checkd(ns, exp_ns);
    `checkd(ws, exp_ws);
    `checkd(nx, exp_nx);
  endfunction
endclass

class test_and;
  rand bit [7:0] array[3];

  constraint c {
    // AND of all elements with a mask should equal specific value
    array.and() with (item & 8'hF0) == 8'h50;
  }

  function void verify();
    bit [7:0] result = 8'hFF;
    int i;

    i = randomize();
    `checkd(i, 1);

    foreach (array[idx]) begin
      result &= (array[idx] & 8'hF0);
    end

    if (result != 8'h50) begin
      $display("%%Error: and test - result 0x%0h != 0x50", result);
      $stop;
    end
  endfunction
endclass

class test_or;
  rand bit [7:0] array[3];

  constraint c {
    // OR of specific bits should set bit 3
    (array.or() with (item & 8'h08)) == 8'h08;
    // At least one element has bit 3 set
    array.sum() with (int'((item & 8'h08) != 0)) >= 1;
  }

  function void verify();
    bit [7:0] result = 8'h00;
    int i;

    i = randomize();
    `checkd(i, 1);

    foreach (array[idx]) begin
      result |= (array[idx] & 8'h08);
    end

    if (result != 8'h08) begin
      $display("%%Error: or test - result 0x%0h != 0x08", result);
      $stop;
    end
  endfunction
endclass

class test_xor;
  rand bit [7:0] array[4];

  constraint c {
    // XOR of all elements should be non-zero (parity check)
    array.xor() with (item) != 0;
    // Ensure some variation
    array.sum() with (int'(item != 0)) >= 2;
  }

  function void verify();
    bit [7:0] result = 8'h00;
    int i;

    i = randomize();
    `checkd(i, 1);

    foreach (array[idx]) begin
      result ^= array[idx];
    end

    if (result == 0) begin
      $display("%%Error: xor test - result is 0");
      $stop;
    end
  endfunction
endclass

class test_nested;
  rand int x;
  int a[2];
  byte b[3];

  constraint c {
    // The inner 'with' uses the outer one's argument, which keeps the outer element type
    x == a.sum(p) with (b.sum(q) with (p + int'(q)));
  }

  function void verify();
    int expected = 0;
    int i;

    foreach (a[idx]) a[idx] = $urandom_range(100000, 1000);
    foreach (b[idx]) b[idx] = byte'($urandom);
    foreach (a[ai]) foreach (b[bi]) expected += a[ai] + int'(b[bi]);

    i = randomize();
    `checkd(i, 1);
    `checkd(x, expected);
  endfunction
endclass

typedef enum bit [7:0] {SEND = 8'h88, RECV = 8'h89, WRITE = 8'h8a} kind_e;

class sum_item;
  rand kind_e kind;

  function int weight();
    return 1;
  endfunction
endclass

class sum_items;
  rand sum_item items[];
  rand int unsigned n;

  function int two();
    return 2;
  endfunction

  function new();
    items = new[4];
    foreach (items[i]) items[i] = new;
  endfunction
endclass

class sum_holder;
  sum_items b;
endclass

class same_sum_items;
  rand kind_e kind;
  rand same_sum_items items[];

  function new(bit populate = 1);
    if (populate) begin
      items = new[4];
      foreach (items[i]) items[i] = new(0);
    end
  endfunction
endclass

module t;
  test_sum sum_inst;
  test_product product_inst;
  test_and and_inst;
  test_or or_inst;
  test_xor xor_inst;
  test_nested nested_inst;

  initial begin
    // Test sum
    sum_inst = new();
    repeat (20) sum_inst.verify();
    $display("sum test PASSED");

    // Test product
    product_inst = new();
    repeat (20) product_inst.verify();
    $display("product test PASSED");

    // Test and
    and_inst = new();
    repeat (20) and_inst.verify();
    $display("and test PASSED");

    // Test state variables in 'with'
    begin
      test_state state_inst;
      int loc;
      int ok;
      int exp_ls;
      state_inst = new();
      repeat (20) state_inst.verify();
      // So is a caller's local variable in an inline constraint
      repeat (20) begin
        loc = $urandom_range(1000);
        ok = state_inst.randomize() with { ls == a.sum() with (item + loc); };
        `checkd(ok, 1);
        exp_ls = 0;
        foreach (state_inst.a[k]) exp_ls += state_inst.a[k] + loc;
        `checkd(state_inst.ls, exp_ls);
      end
      $display("state test PASSED");
    end

    // Test or
    or_inst = new();
    repeat (20) or_inst.verify();
    $display("or test PASSED");

    // Test xor
    xor_inst = new();
    repeat (20) xor_inst.verify();
    $display("xor test PASSED");

    // Test nested 'with'
    nested_inst = new();
    repeat (20) nested_inst.verify();
    $display("nested test PASSED");

    // Inline reductions of element-class members keep the iterator receiver.
    begin
      sum_items g;
      sum_holder a;
      int ok;
      int sends;
      int recvs;
      g = new;
      a = new;
      a.b = g;
      repeat (20) begin
        ok = g.randomize() with {
          n inside {[2:4]};
          items.sum() with (int'(item.kind == SEND)) > 0;
          items.sum() with (int'(item.kind == RECV)) > 0;
          foreach (items[i]) items[i].kind inside {SEND, RECV};
        };
        `checkd(ok, 1);
        sends = 0;
        recvs = 0;
        foreach (g.items[i]) begin
          `checkd((g.items[i].kind inside {SEND, RECV}), 1'b1);
          sends += int'(g.items[i].kind == SEND);
          recvs += int'(g.items[i].kind == RECV);
        end
        `checkd(sends > 0, 1'b1);
        `checkd(recvs > 0, 1'b1);
        `checkd(g.n inside {[2:4]}, 1'b1);

        // The named iterator and the target's field may occur in the same expression.
        ok = g.randomize() with {
          n == two();
          items.sum(elem) with (int'(elem.kind == SEND) + n + elem.weight()) == 14;
          items.sum(elem) with (int'(elem.index)) == 6;
          foreach (items[i]) items[i].kind inside {SEND, RECV};
        };
        `checkd(ok, 1);
        sends = 0;
        foreach (g.items[i]) begin
          `checkd((g.items[i].kind inside {SEND, RECV}), 1'b1);
          sends += int'(g.items[i].kind == SEND);
        end
        `checkd(g.n, 2);
        `checkd(sends, 2);

        // Explicit target paths within 'with' use the solved value, not the stale sentinel.
        g.n = 100;
        ok = g.randomize() with {
          n == two();
          items.sum(elem) with (int'(elem.kind == SEND) + g.n + elem.weight()) == 14;
          foreach (items[i]) items[i].kind inside {SEND, RECV};
        };
        `checkd(ok, 1);
        sends = 0;
        foreach (g.items[i]) begin
          `checkd((g.items[i].kind inside {SEND, RECV}), 1'b1);
          sends += int'(g.items[i].kind == SEND);
        end
        `checkd(g.n, 2);
        `checkd(sends, 2);

        // The iterator shadows the caller's handle; the structured target stays distinct.
        a.b.n = 100;
        ok = a.b.randomize() with {
          n == two();
          items.sum(g) with (int'(g.kind == SEND) + a.b.n + g.weight()) == 14;
          foreach (items[i]) items[i].kind inside {SEND, RECV};
        };
        `checkd(ok, 1);
        sends = 0;
        foreach (a.b.items[i]) begin
          `checkd((a.b.items[i].kind inside {SEND, RECV}), 1'b1);
          sends += int'(a.b.items[i].kind == SEND);
        end
        `checkd(a.b.n, 2);
        `checkd(sends, 2);
      end
    end

    // The element and the randomize target may have the same class type.
    begin
      same_sum_items g;
      int ok;
      int sends;
      g = new;
      repeat (20) begin
        ok = g.randomize() with {
          kind == SEND;
          items.sum() with (int'(item.kind == kind)) == 1;
          foreach (items[i]) items[i].kind inside {SEND, RECV};
        };
        `checkd(ok, 1);
        `checkd(g.kind, SEND);
        sends = 0;
        foreach (g.items[i]) begin
          `checkd((g.items[i].kind inside {SEND, RECV}), 1'b1);
          sends += int'(g.items[i].kind == SEND);
        end
        `checkd(sends, 1);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
