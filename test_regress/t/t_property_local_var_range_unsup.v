// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc;
  logic valid;
  default clocking @(posedge clk);
  endclocking

  // Range delay (##[1:3]) over a property-local match-item capture is
  // not yet supported: per-attempt storage is needed to disambiguate
  // overlapping in-flight attempts.
  property p_range;
    int prev;
    @(posedge clk) (valid,
    prev = cyc
    ) |-> ##[1:3] (cyc > prev);
  endproperty
  assert property (p_range);

  // Composite sequence operator (sequence `and`) under a captured local
  // variable reference is also out of scope for the v1 substitution.
  property p_composite;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> (cyc == snap) and ##1 (cyc == snap + 1);
  endproperty
  assert property (p_composite);

  // A nested range delay in the consequent's prefix is unsupported.
  // Propagate its diagnostic through the enclosing concatenation
  // without continuing substitution after the failure.
  property p_nested_in_pre;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> (1'b1 ##[1:3] (cyc > snap)) ##2 (cyc > snap);
  endproperty
  assert property (p_nested_in_pre);

  // A nested range delay in the consequent's body is unsupported.
  // Propagate its diagnostic through the enclosing concatenation
  // without continuing substitution after the failure.
  property p_nested_in_body;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> ##2 (1'b1 ##[1:3] (cyc > snap));
  endproperty
  assert property (p_nested_in_body);

  // A range delay after a match item within a sequence is unsupported.
  sequence s_range;
    int snap;
    (1, snap = cyc) ##[1:3] (cyc > snap);
  endsequence
  assert property (@(posedge clk) valid |-> s_range);

  // A composite sequence operator after a match item within a sequence is
  // unsupported.
  property p_seq_composite;
    int snap;
    @(posedge clk) valid |-> (1, snap = cyc) ##1 valid [* 2] ##1 (cyc > snap);
  endproperty
  assert property (p_seq_composite);

  // A match item assigning part of a local variable is unsupported.
  property p_part_select;
    bit [3:1] part;
    @(posedge clk) (valid, part[2] = cyc[0]) |=> (cyc[0] != part[2]);
  endproperty
  assert property (p_part_select);

  // A reference after both operands of a sequence 'or' assigned the local
  // variable is unsupported.
  property p_or_operand;
    int snap;
    @(posedge clk) ((valid, snap = cyc) or (1'b0 ##1 (valid, snap = cyc))) |=> (cyc > snap);
  endproperty
  assert property (p_or_operand);

  // A reference after an 'or' whose operand assigned a value assigned before it
  // is unsupported, also when the operand unassigned it first, through nested
  // operators.
  property p_or_reassigned;
    int x;
    @(posedge clk) (1, x = cyc) ##1 (((1, x = cyc) ##1 valid) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_reassigned);
  property p_or_unassigned;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((((1, x = cyc) and (1, x = cyc)) ##1 (1, x = cyc)) ##1 valid) or 1'b1)
    ##1 (x > 0);
  endproperty
  assert property (p_or_unassigned);
  property p_or_of_or;
    int x;
    @(posedge clk) (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) or 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_of_or);
  property p_and_in_or;
    int x;
    @(posedge clk) (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) and 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_and_in_or);

  // Of unsupported constructs in both operands of 'and', the left one's is
  // reported.
  property p_both_unsupported;
    int a, b;
    @(posedge clk)
    ((1, b = cyc) ##[1:3] (cyc > b) ##1 (cyc > b + 1) ##1 (cyc > b + 2) ##1 (cyc > b + 3))
    and ((1, a = cyc) ##[1:2] (cyc == a));
  endproperty
  assert property (p_both_unsupported);

  // A reference after a composite operator is unsupported, also for a value
  // untimed in its operand, assigned in both operands of 'or', or assigned
  // before it and in its operand.
  property p_untimed_operand;
    int x;
    @(posedge clk) (((1, x = cyc) ##[1:2] 1'b1) and 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_untimed_operand);
  property p_or_both_assign;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) or 1'b1)
                      or ((1, x = cyc) ##1 valid ##1 valid ##1 valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_or_both_assign);
  property p_before_and_operand;
    int x, y;
    @(posedge clk)
    (1, x = cyc, y = cyc) ##1 (((1, x = cyc) ##1 valid) intersect (valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_before_and_operand);
  property p_before_more_operand;
    int w, x, y, z;
    @(posedge clk)
    (1, w = cyc, x = cyc) ##1 (((1, x = cyc, y = cyc, z = cyc) ##1 valid) intersect (valid ##1 valid))
    ##1 (w > 0);
  endproperty
  assert property (p_before_more_operand);
  property p_before_other_operand;
    int w, y;
    @(posedge clk) (1, w = cyc) ##1 (((1, y = cyc) ##1 valid) intersect (valid ##1 valid)) ##1 (w > 0);
  endproperty
  assert property (p_before_other_operand);
  property p_or_larger_or;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((1, x = cyc) ##1 valid)
                      or ((((1, x = cyc) ##1 valid) or 1'b1) ##1 valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_or_larger_or);
  // Of a sequential operator whose first operand is unsupported, the first is
  // reported, also when the second is a composite operator.
  property p_within_after;
    int x;
    @(posedge clk) ((1, x = cyc) ##[1:2] (cyc == x)) within ((valid ##1 valid) and valid);
  endproperty
  assert property (p_within_after);
  // An unsupported construct in the smaller right operand of 'and' is reported
  // when the left has none.
  property p_right_unsupported;
    int a;
    @(posedge clk) (valid ##1 valid ##1 valid ##1 valid ##1 valid ##1 valid ##1 valid)
    and ((1, a = cyc) ##[1:2] (cyc == a));
  endproperty
  assert property (p_right_unsupported);

  // A composite operator reading a value an earlier one assigned is unsupported.
  property p_composite_after;
    int t;
    @(posedge clk) valid |-> ((1, t = cyc) intersect 1'b1) ##1 ((cyc > t) and 1'b1);
  endproperty
  assert property (p_composite_after);

  // A read after a range delay, in an antecedent, in an assigned value, in a
  // match item condition, in a subroutine call argument, or in an operand of
  // a property operator, is unsupported.
  property p_range_antecedent;
    int t;
    @(posedge clk) (valid, t = cyc) ##[1:2] (cyc > t && cyc < t + 9) |-> 1'b1;
  endproperty
  assert property (p_range_antecedent);
  property p_range_value;
    int t, u;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (1, u = t) ##1 (u != 0);
  endproperty
  assert property (p_range_value);
  property p_range_condition;
    int t, u;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (cyc > t, u = 1) ##1 (u != 0);
  endproperty
  assert property (p_range_condition);
  property p_range_call;
    int t;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (1, $write("%0d", t));
  endproperty
  assert property (p_range_call);
  property p_range_nested;
    int t;
    @(posedge clk) (valid, t = cyc) ##[1:2] 1'b1 |-> (1'b1 |-> (1'b1 ##1 (cyc == t)));
  endproperty
  assert property (p_range_nested);

  // A value assigned before, or in an operand of, an earlier composite operator
  // and read after a later one is unsupported.
  property p_untimed_through;
    int x;
    @(posedge clk) valid |-> (1, x = cyc) ##1 ((valid ##1 1'b1) and 1'b1) ##1 (cyc > x);
  endproperty
  assert property (p_untimed_through);
  property p_untracked_through;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) intersect 1'b1) ##1 ((valid ##1 1'b1) and 1'b1) ##1 (cyc > x);
  endproperty
  assert property (p_untracked_through);

  // A value assigned in an operand of a composite operator in an operand of a
  // nested implication and read in its consequent is unsupported.
  property p_nested_and;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) and 1'b1) |-> (cyc == x);
  endproperty
  assert property (p_nested_and);
  property p_nested_intersect;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) intersect 1'b1) |-> (cyc == x);
  endproperty
  assert property (p_nested_intersect);

  // Of several values used across a composite operator, the first read is
  // reported.
  property p_first_read;
    int a, b, c;
    @(posedge clk)
    (1'b1, a = cyc) ##[1:2] (1'b1, b = cyc) ##[1:2] (1'b1, c = cyc) ##[1:2]
    ((cyc > c && cyc > b && cyc > a) intersect 1'b1);
  endproperty
  assert property (p_first_read);

  // A read after an unbounded repetition assigning the variable is unsupported.
  property p_rep_unbounded;
    int t;
    @(posedge clk) valid |-> ((1, t = cyc) [* 1:$]) ##1 (cyc > t);
  endproperty
  assert property (p_rep_unbounded);

  // A read after first_match of a sequence assigning the variable is
  // unsupported.
  property p_first_match;
    int t;
    @(posedge clk) valid |-> first_match((1, t = cyc) ##[1:2] 1'b1) ##1 (cyc > t);
  endproperty
  assert property (p_first_match);

  // An impure value assigned to a local variable is unsupported, also when
  // overwritten in the same match item.
  int calls;
  function automatic int bump();
    calls++;
    return calls;
  endfunction
  property p_overwritten;
    int snap;
    @(posedge clk) (1, snap = bump(), snap = cyc) |=> (cyc > snap);
  endproperty
  assert property (p_overwritten);
  property p_impure_unread;
    int snap;
    @(posedge clk) (1, snap = bump()) |=> 1;
  endproperty
  assert property (p_impure_unread);
  property p_impure_read;
    int t;
    @(posedge clk) (1, t = bump()) |=> (t != 0);
  endproperty
  assert property (p_impure_read);
  property p_urandom_range;
    int t;
    @(posedge clk) (1, t = $urandom_range(9, 1)) |=> (t != 0);
  endproperty
  assert property (p_urandom_range);

  // An impure value read more than once, conditionally, or through 'inside'
  property p_impure_twice;
    int t;
    @(posedge clk) (1, t = bump()) ##0 (t + t != 0);
  endproperty
  assert property (p_impure_twice);
  property p_impure_cond;
    int t;
    @(posedge clk) (1, t = bump()) ##0 (valid ? t != 0 : 1'b1);
  endproperty
  assert property (p_impure_cond);
  property p_impure_implies;
    int t;
    @(posedge clk) (1, t = bump()) ##0 (valid -> t != 0);
  endproperty
  assert property (p_impure_implies);
  property p_impure_inside;
    int t;
    @(posedge clk) (1, t = bump()) ##0 (t inside {[1 : 3], 6});
  endproperty
  assert property (p_impure_inside);

  // A value drawing a random value in a called function, read more than once, or later
  function automatic int draw();
    return $urandom_range(1000);
  endfunction
  property p_draw_twice;
    int t;
    @(posedge clk) 1 |=> (1, t = draw()) ##0 (t + 1 == t * 2 - t + 1);
  endproperty
  assert property (p_draw_twice);
  property p_draw_later;
    int t, u;
    @(posedge clk) (1, t = draw(), u = draw()) |=> (t != u);
  endproperty
  assert property (p_draw_later);

  // A value reading an impure value, not read
  property p_impure_copy;
    int t, u;
    @(posedge clk) (1, t = bump(), u = t) ##0 1;
  endproperty
  assert property (p_impure_copy);

  // A value calling a function drawing a random value and reading its argument, read twice
  function automatic int draw_arg(int k);
    return int'($urandom()) + k;
  endfunction
  property p_draw_arg;
    int t;
    @(posedge clk) (1, t = draw_arg(cyc)) ##0 (t + 1 == t * 2 - t + 1);
  endproperty
  assert property (p_draw_arg);

  // Impure values in one cycle, which reads may evaluate out of their order
  int mark;
  function automatic bit first();
    mark = 1;
    return 1'b1;
  endfunction
  function automatic bit second();
    mark = 2;
    return 1'b1;
  endfunction
  function automatic bit identity(bit v);
    return v;
  endfunction
  function automatic void third();
    mark = 3;
  endfunction
  property p_order;
    bit a, b;
    @(posedge clk) 1 |=> (1, a = first(), b = second()) ##0 (b & a);
  endproperty
  assert property (p_order);
  property p_order_relay;
    bit a, b, c;
    @(posedge clk) 1 |=> (1, a = first(), b = second(), c = identity(b)) ##0 (c & a);
  endproperty
  assert property (p_order_relay);
  // A pure value reading what an impure value of the same cycle writes, or reading it
  bit flag;
  function automatic bit set_flag();
    flag = 1'b1;
    return 1'b1;
  endfunction
  function automatic bit read_flag();
    return flag;
  endfunction
  property p_order_read;
    bit x, y;
    @(posedge clk) 1 |=> (1, x = set_flag(), y = read_flag()) ##0 (x & y);
  endproperty
  assert property (p_order_read);
  property p_impure_derived;
    int v, w;
    @(posedge clk) (1, v = bump(), w = v + 1) ##0 (w != 0);
  endproperty
  assert property (p_impure_derived);
  // An impure value in a property with a composite sequence operator, which the order of its
  // match items may not follow
  int st;
  function automatic bit setter();
    st = cyc + 100;
    return 1'b1;
  endfunction
  function automatic int getter();
    return st;
  endfunction
  property p_impure_and;
    bit x;
    int y;
    @(posedge clk) (1, x = setter()) ##0 x
        ##0 ((cyc >= 0 ##3 1) and ((1, y = getter()) ##0 (y == cyc + 100) ##0 1 ##0 1));
  endproperty
  assert property (p_impure_and);
  property p_impure_intersect;
    bit x;
    int y;
    @(posedge clk) (1, x = setter()) ##0 x
        ##0 ((cyc >= 0 ##2 1) intersect ((1, y = getter()) ##0 (y == cyc + 100) ##0 1 ##0 1));
  endproperty
  assert property (p_impure_intersect);
  property p_impure_and_swapped;
    bit x;
    int y;
    @(posedge clk) (1, x = setter()) ##0 x
        ##0 (((1, y = getter()) ##0 (y == cyc + 100) ##0 1 ##0 1) and (cyc >= 0 ##3 1));
  endproperty
  assert property (p_impure_and_swapped);

  // An impure value after a condition that may be false
  bit wrote;
  function automatic bit set_wrote();
    wrote = 1'b1;
    return 1'b1;
  endfunction
  property p_impure_guarded;
    bit x;
    @(posedge clk) valid |=> (1, x = set_wrote()) ##0 x;
  endproperty
  assert property (p_impure_guarded);
  // In a single cycle, a value with side effects on a variable after a condition that may be
  // false
  int unsigned increments;
  function automatic int increment(int n);
    ++increments;
    return n + 1;
  endfunction
  property p_impure_single_guarded;
    int v;
    @(posedge clk) (cyc[0], v = increment(cyc)) |-> (v == cyc + 1);
  endproperty
  assert property (p_impure_single_guarded);
  // Also through a dynamically dispatched call
  int unsigned tallies;
  class tally_base;
    virtual function int tally(int n);
      ++tallies;
      return n;
    endfunction
  endclass
  tally_base tb = new;
  function automatic int through_tally(int n);
    return tb.tally(n);
  endfunction
  property p_impure_single_dispatch;
    int v;
    @(posedge clk) (cyc[0], v = through_tally(cyc)) |-> (v == cyc);
  endproperty
  assert property (p_impure_single_dispatch);
  // Also through a variable of a function kept between calls
  function int next_id();
    int id;
    id = id + 1;
    return id;
  endfunction
  property p_impure_single_static;
    int v;
    @(posedge clk) (cyc[0], v = next_id()) |-> (v > 0);
  endproperty
  assert property (p_impure_single_static);
  function automatic int next_auto_id();
    static int id;
    id = id + 1;
    return id;
  endfunction
  property p_impure_single_static_local;
    int v;
    @(posedge clk) (cyc[0], v = next_auto_id()) |-> (v > 0);
  endproperty
  assert property (p_impure_single_static_local);
  // Also with the write and the read in one value
  int kept;
  function automatic int set_kept(int n);
    kept = n;
    return n;
  endfunction
  function automatic int get_kept();
    return kept;
  endfunction
  property p_impure_single_both;
    int v;
    @(posedge clk) (cyc[0], v = set_kept(cyc) + get_kept()) |-> (v >= 0);
  endproperty
  assert property (p_impure_single_both);
  // Also through a variable of a function kept between calls, assigned after a jump out of a
  // block
  function int skip_reset(int n);
    int state;
    begin : reset_block
      if (n != -1) disable reset_block;
      state = 0;
    end
    state += 1;
    return n;
  endfunction
  property p_impure_single_jump;
    int v;
    @(posedge clk) (cyc[0], v = skip_reset(cyc)) |-> (v >= 0);
  endproperty
  assert property (p_impure_single_jump);
  // Also through a call in the assignment of the variable reading it
  function int hidden_read(int n);
    static int s;
    s = hidden_helper(n);
    return n + s;
  endfunction
  function int hidden_helper(int n);
    return hidden_read.s + 1;
  endfunction
  property p_impure_single_hidden;
    int v;
    @(posedge clk) (cyc[0], v = hidden_read(cyc)) |-> (v >= 0);
  endproperty
  assert property (p_impure_single_hidden);
  // Also with values each reading what the other writes
  int ping, pong;
  function automatic int set_ping(int n);
    ping = pong + 1;
    return n;
  endfunction
  function automatic int set_pong(int n);
    pong = ping + 1;
    return n;
  endfunction
  property p_impure_single_cycle;
    int v, w;
    @(posedge clk) (cyc[0], v = set_ping(cyc), w = set_pong(cyc)) |-> (v == w);
  endproperty
  assert property (p_impure_single_cycle);
  property p_impure_xz;
    bit x;
    @(posedge clk) 1'bx ##0 (1, x = set_wrote()) ##0 x;
  endproperty
  assert property (p_impure_xz);
  // A value calling a virtual method, an override of which draws a random value, also one
  // overriding a virtual method of its base class
  class source_base;
    virtual function int value();
      return 0;
    endfunction
  endclass
  class source extends source_base;
    function int value();
      return 1;
    endfunction
  endclass
  class random_source extends source;
    function int value();
      return $urandom();
    endfunction
  endclass
  source src;
  function automatic int through_handle();
    return src.value();
  endfunction
  property p_impure_method;
    int x;
    @(posedge clk) (1, x = through_handle()) |=> (x == 0);
  endproperty
  assert property (p_impure_method);
  // An interface class method, an implementation of which draws a random value
  interface class value_if;
    pure virtual function int value();
  endclass
  class pure_value implements value_if;
    virtual function int value();
      return 1;
    endfunction
  endclass
  class random_value implements value_if;
    virtual function int value();
      return $urandom();
    endfunction
  endclass
  value_if vif;
  function automatic int through_interface();
    return vif.value();
  endfunction
  property p_impure_interface;
    int x;
    @(posedge clk) (1, x = through_interface()) |=> (x == 0);
  endproperty
  assert property (p_impure_interface);
  // A virtual method, an override of which has side effects
  int overrides_called;
  class pure_base;
    virtual function int value(int n);
      return n;
    endfunction
  endclass
  class impure_child extends pure_base;
    function int value(int n);
      overrides_called++;
      return n;
    endfunction
  endclass
  pure_base pb;
  function automatic int through_override(int n);
    return pb.value(n);
  endfunction
  property p_impure_override;
    int x;
    @(posedge clk) (1, x = through_override(cyc)) |=> (x == cyc - 1);
  endproperty
  assert property (p_impure_override);
  // A value calling a virtual method recursively through another function, conservatively
  class recursive_base;
    virtual function int recurse_value(int k);
      return (k > 0) ? recurse(this, k - 1) : 0;
    endfunction
  endclass
  function automatic int recurse(recursive_base r, int k);
    return r.recurse_value(k);
  endfunction
  recursive_base rb;
  function automatic int through_recursion(int k);
    return rb.recurse_value(k);
  endfunction
  property p_impure_recursion;
    int x;
    @(posedge clk) (1, x = through_recursion(cyc)) |=> (x == 0);
  endproperty
  assert property (p_impure_recursion);
  // Recursively through an override calling the method on another object
  class depth_base;
    virtual function int depth(int k);
      return k;
    endfunction
  endclass
  class depth_child extends depth_base;
    depth_base other;
    virtual function int depth(int k);
      return (k > 0) ? other.depth(k - 1) : 0;
    endfunction
  endclass
  depth_base db;
  function automatic int through_depth(int k);
    return db.depth(k);
  endfunction
  property p_impure_override_recursion;
    int x;
    @(posedge clk) (1, x = through_depth(cyc)) |=> (x == 0);
  endproperty
  assert property (p_impure_override_recursion);
  // A method calling a method of the same name, drawing a random value, on another class
  class random_delegate;
    virtual function int value(int k);
      return k + int'($urandom());
    endfunction
  endclass
  class delegator;
    random_delegate rd = new;
    virtual function int value(int k);
      return rd.value(k);
    endfunction
  endclass
  delegator dl;
  function automatic int through_delegator(int k);
    return dl.value(k);
  endfunction
  property p_random_delegate;
    int x;
    @(posedge clk) (1, x = through_delegator(cyc)) |=> (x == 0);
  endproperty
  assert property (p_random_delegate);
  // A value calling an imported function not declared pure
  import "DPI-C" function int c_draw();
  function automatic int through_dpi();
    return c_draw();
  endfunction
  property p_impure_dpi;
    int x;
    @(posedge clk) (1, x = through_dpi()) |=> (x == 0);
  endproperty
  assert property (p_impure_dpi);
  property p_order_call;
    bit a;
    @(posedge clk) 1 |=> (1, a = first()) ##0 (1, third()) ##0 a;
  endproperty
  assert property (p_order_call);

  // An impure value in an operand of a composite sequence operator
  property p_impure_or;
    int t;
    @(posedge clk) valid |=> (1'b1 or ((1, t = bump()) ##0 (t != 0)));
  endproperty
  assert property (p_impure_or);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    valid <= (cyc == 2);
  end

endmodule
