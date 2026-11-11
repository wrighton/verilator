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

class test_nested_indices;
  rand bit [6:0] a[3];
  int inner[2];
  rand int equal_sum;
  rand int unequal_sum;
  rand int delta_sum;
  rand bit [6:0] shifted[3:1];
  int ascending[2:3];
  rand int shifted_sum;
  int bias;

  function new();
    inner = '{1, 2};
    ascending = '{5, 6};
  endfunction

  constraint c {
    foreach (a[i]) a[i] == 7'(i + bias);
    // Different reduction indices must not compare equal before their loops are scoped.
    equal_sum == a.sum(outer) with (inner.sum(elem) with
        (elem.index == outer.index ? int'(outer) : 0));
    unequal_sum == a.sum(outer) with (inner.sum(elem) with
        (elem.index != outer.index ? int'(outer) : 0));
    delta_sum == a.sum(outer) with (inner.sum(elem) with
        ((elem.index - outer.index) * int'(outer)));
    // Compare declared indices, not storage offsets, across differently directed ranges.
    foreach (shifted[i]) shifted[i] == 7'(i + bias);
    shifted_sum == shifted.sum(outer) with (ascending.sum(elem) with
        (elem.index == outer.index ? int'(outer) : 0));
  }

  function void verify(int turn);
    int ok;
    int expected_equal = 0;
    int expected_unequal = 0;
    int expected_delta = 0;
    int expected_shifted = 0;
    bias = turn + 1;
    ok = randomize();
    `checkd(ok, 1);
    foreach (a[i]) begin
      `checkd(a[i], 7'(i + bias));
      foreach (inner[j]) begin
        if (i == j) expected_equal += int'(a[i]);
        else expected_unequal += int'(a[i]);
        expected_delta += (j - i) * int'(a[i]);
      end
    end
    foreach (shifted[i]) begin
      `checkd(shifted[i], 7'(i + bias));
      foreach (ascending[j]) if (i == j) expected_shifted += int'(shifted[i]);
    end
    `checkd(equal_sum, expected_equal);
    `checkd(unequal_sum, expected_unequal);
    `checkd(delta_sum, expected_delta);
    `checkd(shifted_sum, expected_shifted);
    // At turn zero, the original {1, 2, 3} reproducer sums to 3, not 12.
    `checkd(equal_sum, 2 * bias + 1);
  endfunction
endclass

class test_value_carriers;
  rand int a[3];
  rand bit choose;
  rand int state_sum;
  rand int state_product;
  rand int random_sum;
  rand int random_product;
  rand int logical_value;
  rand int function_value;
  int bias;

  function int keep_value(int value);
    return value;
  endfunction

  // Multiple returns keep the call's arguments in the function-value carrier path.
  function int pick_value(bit selected);
    if (selected) return 23;
    return 29;
  endfunction

  constraint c {
    foreach (a[i]) a[i] == i + bias;
    state_sum == a.sum() with (item.index == 1 ? int'(item) : 0);
    state_product == a.product() with (item.index == 1 ? int'(item) : 1);
    random_sum == a.sum() with (choose ? int'(item) : 0);
    random_product == a.product() with (choose ? int'(item) : 1);
    logical_value == keep_value(int'((a[0] > 0) && (a[2] > 0)));
    function_value == pick_value(choose);
  }

  function void verify(int turn);
    int ok;
    int sum_value = 0;
    int product_value = 1;
    bias = turn + 1;
    ok = randomize() with {choose == bit'(turn % 2);};
    `checkd(ok, 1);
    foreach (a[i]) begin
      `checkd(a[i], i + bias);
      sum_value += a[i];
      product_value *= a[i];
    end
    `checkd(state_sum, a[1]);
    `checkd(state_product, a[1]);
    `checkd(random_sum, choose ? sum_value : 0);
    `checkd(random_product, choose ? product_value : 1);
    `checkd(logical_value, 1);
    `checkd(function_value, choose ? 23 : 29);
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

class test_guard_iterators;
  rand bit [6:0] a[3];
  rand bit [6:0] guarded;
  rand bit [6:0] arms;
  rand bit [6:0] nested;
  state_sub children[3];
  state_sub left;
  state_sub right;
  int inner[2];
  int bias;
  int expected;
  int expected_arms;
  int expected_nested;
  bit enabled = 1;

  function new();
    foreach (children[i]) children[i] = new;
    left = new;
    right = new;
    inner = '{1, 2};
  endfunction

  constraint c {
    foreach (a[i]) a[i] == 7'(i + bias);
    if (enabled) {
      // The receiver index is bound inside the reduction, not in the outer guard.
      if (a.sum() with (children[item.index].k != 0 ? int'(item) : 0) == expected)
        guarded == 7'd23;
      else
        guarded == 7'd29;
      // Neither arm may be sampled before its iterator-dependent selector is bound.
      if (a.sum() with (item.index == 1 ? left.k * int'(item) : right.k * int'(item))
          == expected_arms)
        arms == 7'd31;
      else
        arms == 7'd37;
      // Inner and outer named iterators keep distinct bindings.
      if (a.sum(outer) with (inner.sum(elem) with
          (children[elem.index].k * int'(outer)))
          == expected_nested)
        nested == 7'd41;
      else
        nested == 7'd43;
    }
  }

  function void verify(int turn);
    int ok;
    int selected = 0;
    int weighted = 0;
    int nested_weighted = 0;
    bias = turn + 1;
    left.k = turn + 2;
    right.k = turn + 3;
    foreach (children[i]) children[i].k = (i + turn) % 2;
    foreach (children[i]) begin
      if (children[i].k != 0) selected += i + bias;
      weighted += (i == 1 ? left.k : right.k) * (i + bias);
      nested_weighted += (children[0].k + children[1].k) * (i + bias);
    end
    // Both outcomes are checked; the random guards must not become unconstrained.
    expected = selected + turn % 2;
    expected_arms = weighted + turn % 2;
    expected_nested = nested_weighted + turn % 2;
    ok = randomize();
    `checkd(ok, 1);
    `checkd(guarded, turn % 2 == 0 ? 7'd23 : 7'd29);
    `checkd(arms, turn % 2 == 0 ? 7'd31 : 7'd37);
    `checkd(nested, turn % 2 == 0 ? 7'd41 : 7'd43);
    foreach (a[i]) `checkd(a[i], 7'(i + bias));
  endfunction
endclass

class test_guard_contexts;
  rand bit [6:0] a[];
  rand bit pick;
  rand bit [6:0] out;
  state_sub children[3];
  bit enabled = 1;

  function new();
    a = new[3];
    foreach (children[i]) begin
      children[i] = new;
      children[i].k = 1;
    end
  endfunction

  constraint size_c {a.size() == 3;}
  constraint index_c {
    // A bound dynamic-array index can select state values without a receiver error.
    if (a.sum() with (int'(item.index < 2 ? 1 : 0)) == 2) out == 7'd47;
  }
  constraint nested_c {
    if (pick) {
      if (a.sum() with (children[item.index].k * int'(item)) > 0) out == 7'd47;
    }
  }
  constraint soft_c {
    soft !((a.sum() with (children[item.index].k * int'(item)) > 0) -> (out == 7'd47));
  }
  constraint sift_c {
    if (enabled && (a.sum() with (children[item.index].k * int'(item)) > 0)) out == 7'd47;
  }
endclass

class test_guard_state_reductions;
  bit [6:0] a[3];
  state_sub children[3];
  rand int gate;
  rand bit [6:0] out;
  rand bit pick;
  bit enabled = 1;

  function new();
    foreach (children[i]) begin
      a[i] = 7'(i + 1);
      children[i] = new;
      children[i].k = 1;
    end
  endfunction

  constraint plain_c {
    if (a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6)
      out == 7'd23;
  }
  constraint and_left_c {
    if (enabled && (a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6))
      out == 7'd23;
  }
  constraint and_right_c {
    if ((a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6) && enabled)
      out == 7'd23;
  }
  constraint or_left_c {
    if (enabled || (a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6))
      out == 7'd23;
  }
  constraint or_right_c {
    if ((a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6) || enabled)
      out == 7'd23;
  }
  constraint atomic_c {
    // Each STATE reduction is a value inside a RANDOM comparison, not a STATE leaf.
    if (a.sum() with (children[item.index].k != 0 ? int'(item) : 0) == gate)
      out == 7'd23;
    if (a.product() with (children[item.index].k != 0 ? int'(item) : 1) == gate)
      out == 7'd23;
    if (a.and() with (children[item.index].k != 0 ? int'(item) : -1) == gate)
      out == 7'd23;
    if (a.or() with (children[item.index].k != 0 ? int'(item) : 0) == gate)
      out == 7'd23;
    if (a.xor() with (children[item.index].k != 0 ? int'(item) : 0) == gate)
      out == 7'd23;
  }
  constraint pure_c {
    if (a.sum() with (int'(item)) == gate) out == 7'd23;
  }
  constraint wrapped_c {
    if ((a.sum() with (children[item.index].k * int'(item))) + 1 == gate)
      out == 7'd23;
  }
  constraint unary_c {
    if (-(a.sum() with (children[item.index].k * int'(item))) == gate)
      out == 7'd23;
  }
  constraint cond_c {
    if ((enabled ? a.sum() with (children[item.index].k * int'(item)) : 0) == gate)
      out == 7'd23;
  }
  constraint mixed_c {
    if ((a.sum() with (children[item.index].k == 1 ? int'(item) : 0) == 6) || pick)
      out == 7'd23;
  }
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

    // Nested reduction indices keep independent bindings without guards or handles.
    begin
      automatic test_nested_indices g = new;
      for (int turn = 0; turn < 8; ++turn) g.verify(turn);
    end

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

    // Guarded symbolic element fields retain their original solver-name paths.
    begin
      automatic sum_items g = new;
      kind_e chosen;
      int ok;
      for (int turn = 0; turn < 4; ++turn) begin
        chosen = turn % 2 == 0 ? SEND : RECV;
        ok = g.randomize() with {
          foreach (items[i]) items[i].kind == chosen;
          if (items.sum() with (int'(item.kind == SEND)) > 0) n == 3;
          else n == 5;
        };
        `checkd(ok, 1);
        `checkd(g.n, chosen == SEND ? 3 : 5);
        foreach (g.items[i]) `checkd(g.items[i].kind, chosen);
        ok = g.randomize() with {
          foreach (items[i]) items[i].kind == chosen;
          if (items.sum(elem) with (int'(elem.kind == SEND) + elem.weight()) > 4) n == 3;
          else n == 5;
        };
        `checkd(ok, 1);
        `checkd(g.n, chosen == SEND ? 3 : 5);
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

    // Guarded reductions must keep item and item.index inside their binding loops.
    begin
      automatic test_guard_iterators g = new;
      int ok;
      automatic int selected = 0;
      for (int turn = 0; turn < 8; ++turn) g.verify(turn);
      // Isolate the inline guard from the class constraints and force both outcomes.
      g.c.constraint_mode(0);
      foreach (g.children[i]) if (g.children[i].k != 0) selected += i + g.bias;
      for (int branch = 0; branch < 2; ++branch) begin
        g.expected = selected + branch;
        g.guarded = branch == 0 ? 7'd29 : 7'd23;
        ok = g.randomize() with {
          foreach (a[i]) a[i] == 7'(i + bias);
          if (a.sum(elem) with (children[elem.index].k != 0 ? int'(elem) : 0) == expected)
            guarded == 7'd23;
          else
            guarded == 7'd29;
        };
        `checkd(ok, 1);
        `checkd(g.guarded, branch == 0 ? 7'd23 : 7'd29);
      end
      g.c.constraint_mode(1);
      // Active receiver errors fail the call and do not survive restoration.
      begin
        automatic state_sub saved = g.children[1];
        g.children[1] = null;
        ok = g.randomize();
        `checkd(ok, 0);
        g.children[1] = saved;
        g.verify(0);
      end
      begin
        automatic state_sub saved = g.left;
        g.left = null;
        ok = g.randomize();
        `checkd(ok, 0);
        g.left = saved;
        g.verify(1);
      end
      // A disabled state guard still eliminates invalid receivers entirely.
      g.enabled = 0;
      foreach (g.children[i]) g.children[i] = null;
      g.left = null;
      g.right = null;
      ok = g.randomize();
      `checkd(ok, 1);
    end

    // Iterator-bound ERROR remains hard even beneath random, negated, or soft guards.
    begin
      automatic test_guard_contexts g = new;
      int ok;
      g.nested_c.constraint_mode(0);
      g.soft_c.constraint_mode(0);
      g.sift_c.constraint_mode(0);
      ok = g.randomize();
      `checkd(ok, 1);
      `checkd(g.out, 7'd47);
      g.index_c.constraint_mode(0);
      g.children[1] = null;
      g.nested_c.constraint_mode(1);
      ok = g.randomize() with {pick == 0;};
      `checkd(ok, 0);
      g.nested_c.constraint_mode(0);
      g.soft_c.constraint_mode(1);
      ok = g.randomize();
      `checkd(ok, 0);
      g.soft_c.constraint_mode(0);
      g.sift_c.constraint_mode(1);
      g.enabled = 0;
      ok = g.randomize();
      `checkd(ok, 1);
    end

    // Native STATE reductions report ERROR before truth/falsity is sampled.
    begin
      automatic test_guard_state_reductions g = new;
      state_sub saved;
      int ok;
      g.and_left_c.constraint_mode(0);
      g.and_right_c.constraint_mode(0);
      g.or_left_c.constraint_mode(0);
      g.or_right_c.constraint_mode(0);
      g.mixed_c.constraint_mode(0);
      g.atomic_c.constraint_mode(0);
      g.pure_c.constraint_mode(0);
      g.wrapped_c.constraint_mode(0);
      g.unary_c.constraint_mode(0);
      g.cond_c.constraint_mode(0);
      ok = g.randomize();
      `checkd(ok, 1);
      `checkd(g.out, 7'd23);
      saved = g.children[1];
      g.children[1] = null;
      ok = g.randomize();
      `checkd(ok, 0);
      g.children[1] = saved;
      ok = g.randomize();
      `checkd(ok, 1);
      g.plain_c.constraint_mode(0);
      g.children[1] = null;
      g.enabled = 0;
      g.and_left_c.constraint_mode(1);
      g.and_right_c.constraint_mode(1);
      ok = g.randomize();
      `checkd(ok, 1);
      g.and_left_c.constraint_mode(0);
      g.and_right_c.constraint_mode(0);
      g.enabled = 1;
      g.or_left_c.constraint_mode(1);
      g.or_right_c.constraint_mode(1);
      ok = g.randomize();
      `checkd(ok, 1);
      `checkd(g.out, 7'd23);
      g.or_left_c.constraint_mode(0);
      g.or_right_c.constraint_mode(0);
      g.mixed_c.constraint_mode(1);
      ok = g.randomize() with {pick == 1;};
      `checkd(ok, 0);
      g.children[1] = saved;
      ok = g.randomize();
      `checkd(ok, 1);
      g.mixed_c.constraint_mode(0);
      g.atomic_c.constraint_mode(1);
      ok = g.randomize() with {gate == 6;};
      `checkd(ok, 1);
      `checkd(g.out, 7'd23);
      g.children[1] = null;
      ok = g.randomize() with {gate == 6;};
      `checkd(ok, 0);
      g.children[1] = saved;
      g.atomic_c.constraint_mode(0);
      g.pure_c.constraint_mode(1);
      ok = g.randomize() with {gate == 6;};
      `checkd(ok, 1);
      `checkd(g.out, 7'd23);
      g.pure_c.constraint_mode(0);
      for (int mode = 0; mode < 3; ++mode) begin
        automatic int expected = mode == 0 ? 7 : mode == 1 ? -6 : 6;
        g.wrapped_c.constraint_mode(mode == 0);
        g.unary_c.constraint_mode(mode == 1);
        g.cond_c.constraint_mode(mode == 2);
        g.enabled = 1;
        ok = g.randomize() with {gate == expected;};
        `checkd(ok, 1);
        `checkd(g.out, 7'd23);
        g.children[1] = null;
        ok = g.randomize() with {gate == expected;};
        `checkd(ok, 0);
        g.children[1] = saved;
        ok = g.randomize() with {gate == expected;};
        `checkd(ok, 1);
        `checkd(g.out, 7'd23);
      end
      // A STATE conditional must not evaluate its unselected native callback.
      g.enabled = 0;
      g.children[1] = null;
      ok = g.randomize() with {gate == 0;};
      `checkd(ok, 1);
      `checkd(g.out, 7'd23);
    end

    // Reduction selectors and values must be prepared at each element, not outside the loop.
    begin
      automatic test_value_carriers carrier = new;
      for (int turn = 0; turn < 8; ++turn) carrier.verify(turn);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
