// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ns

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;

  function automatic time now();
    return $time;
  endfunction
  function automatic time later();
    return now() + 1;
  endfunction
  // Reading the time through mutual recursion
  function automatic time rec_a(int n);
    return ((n > 0) ? rec_b(n - 1) : 0) + $time;
  endfunction
  function automatic time rec_b(int n);
    return (n > 0) ? rec_a(n - 1) : 0;
  endfunction
  // A static or non-virtual class method, of a known body
  class Arithmetic;
    static function automatic int twice(int n);
      return n + n;
    endfunction
    function int thrice(int n);
      return 3 * n;
    endfunction
  endclass
  Arithmetic arith = new;
  function automatic int calc(int n);
    return Arithmetic::twice(n) + arith.thrice(n);
  endfunction
  int unsigned method_passes, method_fails;
  property p_method;
    int x;
    @(posedge clk) (1, x = calc(cnt)) |=> (x == 5 * (cnt - 1));
  endproperty
  assert property (p_method) method_passes++;
  else method_fails++;

  // A virtual method called through 'super', which binds statically
  class Parent;
    virtual function int twice(int n);
      return 2 * n;
    endfunction
  endclass
  class Child extends Parent;
    function int twice(int n);
      return 300 + n;
    endfunction
    function int call_parent(int n);
      return super.twice(n);
    endfunction
  endclass
  Child child = new;
  function automatic int calc_parent(int n);
    return child.call_parent(n);
  endfunction
  // Or dynamically dispatched, all overrides being known
  function automatic int calc_dispatch(int n);
    return child.twice(n);
  endfunction
  int unsigned dispatch_passes, dispatch_fails;
  property p_dispatch;
    int x;
    @(posedge clk) (1, x = calc_dispatch(cnt)) |=> (x == 300 + cnt - 1);
  endproperty
  assert property (p_dispatch) dispatch_passes++;
  else dispatch_fails++;
  int unsigned super_passes, super_fails;
  property p_super;
    int x;
    @(posedge clk) (1, x = calc_parent(cnt)) |=> (x == 2 * (cnt - 1));
  endproperty
  assert property (p_super) super_passes++;
  else super_fails++;

  // Not changed by a method of the same name in an unrelated class drawing a random value
  class PureBase;
    virtual function int value(int n);
      return n;
    endfunction
  endclass
  class PureChild extends PureBase;
    function int value(int n);
      return 2 * n;
    endfunction
  endclass
  class OtherBase;
    virtual function int value(int n);
      return n + 1;
    endfunction
  endclass
  class OtherChild extends OtherBase;
    function int value(int n);
      return n + int'($urandom());
    endfunction
  endclass
  PureChild pure_child = new;
  PureBase pure_base = pure_child;
  OtherChild other_child = new;
  OtherBase other_base = other_child;
  function automatic int calc_family(int n);
    return pure_base.value(n);
  endfunction
  int unsigned family_passes, family_fails;
  property p_family;
    int x;
    @(posedge clk) (1, x = calc_family(cnt)) |=> (x == 2 * (cnt - 1));
  endproperty
  assert property (p_family) family_passes++;
  else family_fails++;
  int other_draw;
  initial other_draw = other_base.value(4);

  // Nor by an override in a class not deriving from the class of the object called on
  class Root;
    virtual function int value(int n);
      return 2 * n;
    endfunction
  endclass
  class PureMid extends Root;
  endclass
  class PureLeaf extends PureMid;
    function int call_own(int n);
      return value(n);
    endfunction
  endclass
  class RandomSibling extends Root;
    function int value(int n);
      return n + int'($urandom());
    endfunction
  endclass
  PureLeaf pure_leaf = new;
  PureMid pure_mid = pure_leaf;
  RandomSibling random_sibling = new;
  Root sibling_root = random_sibling;
  function automatic int calc_mid(int n);
    return pure_mid.value(n) + pure_leaf.call_own(n) - 2 * n;
  endfunction
  int unsigned mid_passes, mid_fails;
  property p_mid;
    int x;
    @(posedge clk) (1, x = calc_mid(cnt)) |=> (x == 2 * (cnt - 1));
  endproperty
  assert property (p_mid) mid_passes++;
  else mid_fails++;
  int sibling_draw;
  initial sibling_draw = sibling_root.value(4);

  // A method calling a method of the same name on an object of another class
  class Delegate;
    virtual function int forward(int n);
      return 2 * n;
    endfunction
  endclass
  class Delegator;
    Delegate delegate = new;
    virtual function int forward(int n);
      return delegate.forward(n);
    endfunction
  endclass
  Delegator delegator = new;
  function automatic int calc_delegator(int n);
    return delegator.forward(n);
  endfunction
  int unsigned delegate_passes, delegate_fails;
  property p_delegate;
    int x;
    @(posedge clk) (1, x = calc_delegator(cnt)) |=> (x == 2 * (cnt - 1));
  endproperty
  assert property (p_delegate) delegate_passes++;
  else delegate_fails++;

  // Read in the cycle of the match item
  int unsigned overlap_passes, overlap_fails;
  property p_overlap;
    time t;
    @(posedge clk) (1, t = $time) |-> (t == $time);
  endproperty
  assert property (p_overlap) overlap_passes++;
  else overlap_fails++;

  // A value of a pure function with a subroutine call match item, which runs once per match
  function automatic int plus_one(int n);
    return n + 1;
  endfunction
  int unsigned notes;
  function automatic void note();
    ++notes;
  endfunction
  int unsigned pure_passes, pure_fails;
  property p_pure_call;
    int v;
    @(posedge clk) (cnt[0], v = plus_one(cnt), note()) |-> (v == cnt + 1);
  endproperty
  assert property (p_pure_call) pure_passes++;
  else pure_fails++;

  // In an unpacked array
  typedef int pair_t[2];
  int unsigned array_passes, array_fails;
  property p_array;
    pair_t a;
    @(posedge clk) (1, a = '{int'($time), int'($time) + 1}) |=> (a[1] == int'($time) - 9);
  endproperty
  assert property (p_array) array_passes++;
  else array_fails++;

  // Mutual recursion not reading the time
  function automatic bit is_even(int n);
    return (n == 0) ? 1'b1 : is_odd(n - 1);
  endfunction
  function automatic bit is_odd(int n);
    return (n == 0) ? 1'b0 : is_even(n - 1);
  endfunction

  // A local variable assigned the time holds the time of the match
  int unsigned realtime_passes, realtime_fails;
  property p_realtime;
    realtime c;
    @(posedge clk) (1, c = $realtime) |=> (c == $realtime - 10);
  endproperty
  assert property (p_realtime) realtime_passes++;
  else realtime_fails++;

  int unsigned time_passes, time_fails;
  property p_time;
    time c;
    @(posedge clk) (1, c = $time) |=> (c == $time - 10);
  endproperty
  assert property (p_time) time_passes++;
  else time_fails++;

  int unsigned stime_passes, stime_fails;
  property p_stime;
    int unsigned c;
    @(posedge clk) (1, c = $stime + 5) |=> (c == $stime - 5);
  endproperty
  assert property (p_stime) stime_passes++;
  else stime_fails++;

  // Read in the cycle of the assignment, and from a value with a signal
  int unsigned same_passes, same_fails;
  property p_same;
    realtime c;
    @(posedge clk) (1, c = $realtime + cnt) ##0 (c == $realtime + cnt);
  endproperty
  assert property (p_same) same_passes++;
  else same_fails++;

  int unsigned cnt_passes, cnt_fails;
  property p_cnt;
    realtime c;
    @(posedge clk) (1, c = cnt) |=> (c == cnt - 1);
  endproperty
  assert property (p_cnt) cnt_passes++;
  else cnt_fails++;

  // Read in two later cycles, with a signal, and through another local variable
  int unsigned twice_passes, twice_fails;
  property p_twice;
    time c;
    @(posedge clk) (1, c = $time) |=> (c + 10 == $time) ##1 (c + 20 == $time);
  endproperty
  assert property (p_twice) twice_passes++;
  else twice_fails++;

  int unsigned mixed_passes, mixed_fails;
  property p_mixed;
    longint c;
    @(posedge clk) (1, c = 64'(cnt) * 1000 + $time) |=> (c == 64'(cnt - 1) * 1000 + $time - 10);
  endproperty
  assert property (p_mixed) mixed_passes++;
  else mixed_fails++;

  int unsigned via_passes, via_fails;
  property p_via;
    time a, b;
    @(posedge clk) (1, a = $time) |=> (1, b = a + 1) ##1 (b == $time - 19);
  endproperty
  assert property (p_via) via_passes++;
  else via_fails++;

  // A random value with the time, read twice, is the same at both reads
  int unsigned random_passes, random_fails;
  property p_random;
    time x, copy;
    @(posedge clk) (1, x = $time + time'($urandom())) |=> (1, copy = x) ##1 (x == copy);
  endproperty
  assert property (p_random) random_passes++;
  else random_fails++;

  // The time read by a called function
  int unsigned func_passes, func_fails;
  property p_func;
    time c, d;
    @(posedge clk) (1, c = now(), d = later()) |=> (c == $time - 10 && d == $time - 9);
  endproperty
  assert property (p_func) func_passes++;
  else func_fails++;

  int unsigned rec_passes, rec_fails;
  property p_rec;
    time c, d;
    @(posedge clk) (1, c = rec_a(0), d = rec_b(1)) |=> (d == $time - 10 && c == d);
  endproperty
  assert property (p_rec) rec_passes++;
  else rec_fails++;

  int unsigned even_passes, even_fails;
  property p_even;
    bit e;
    @(posedge clk) (1, e = is_even(cnt % 4)) |=> (e == ((cnt - 1) % 2 == 0));
  endproperty
  assert property (p_even) even_passes++;
  else even_fails++;

  // A value with a random value drawn, copied in a later cycle
  int unsigned copy_passes, copy_fails;
  property p_copy;
    time x, copy;
    @(posedge clk) (1, x = now() + time'($urandom())) |=> (1, copy = x) ##1 (x == copy);
  endproperty
  assert property (p_copy) copy_passes++;
  else copy_fails++;

  // Reassignments each reading the previous value twice
  int unsigned chain_passes, chain_fails;
  property p_chain;
    time x;
    @(posedge clk) (1, x = now()) ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x)
        ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x)
        ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x)
        ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x) ##0 (1, x = x + x)
        ##0 (x == $time * 32768);
  endproperty
  assert property (p_chain) chain_passes++;
  else chain_fails++;

  // A procedural assertion under a condition, of the time
  property p_proc_time;
    realtime t;
    (1, t = $realtime) |-> (t >= 0);
  endproperty
  int unsigned proc_time_passes, proc_time_fails;
  always @(posedge clk) begin
    if (cnt[1]) begin
      assert property (p_proc_time) proc_time_passes++;
      else proc_time_fails++;
    end
  end

  initial begin
    #100;
    `checkd(proc_time_passes, 4);
    `checkd(proc_time_fails, 0);
    `checkd(pure_passes, 10);
    `checkd(pure_fails, 0);
    `checkd(notes, 5);
    `checkd(overlap_passes, 10);
    `checkd(overlap_fails, 0);
    `checkd(array_passes, 9);
    `checkd(array_fails, 0);
    `checkd(delegate_passes, 9);
    `checkd(delegate_fails, 0);
    `checkd(mid_passes, 9);
    `checkd(mid_fails, 0);
    `checkd(family_passes, 9);
    `checkd(family_fails, 0);
    `checkd(dispatch_passes, 9);
    `checkd(dispatch_fails, 0);
    `checkd(super_passes, 9);
    `checkd(super_fails, 0);
    `checkd(method_passes, 9);
    `checkd(method_fails, 0);
    `checkd(even_passes, 9);
    `checkd(even_fails, 0);
    `checkd(rec_passes, 9);
    `checkd(rec_fails, 0);
    `checkd(copy_passes, 8);
    `checkd(copy_fails, 0);
    `checkd(twice_passes, 8);
    `checkd(twice_fails, 0);
    `checkd(mixed_passes, 9);
    `checkd(mixed_fails, 0);
    `checkd(via_passes, 8);
    `checkd(via_fails, 0);
    `checkd(random_passes, 8);
    `checkd(random_fails, 0);
    `checkd(func_passes, 9);
    `checkd(func_fails, 0);
    `checkd(chain_passes, 10);
    `checkd(chain_fails, 0);
    `checkd(realtime_passes, 9);
    `checkd(realtime_fails, 0);
    `checkd(time_passes, 9);
    `checkd(time_fails, 0);
    `checkd(stime_passes, 9);
    `checkd(stime_fails, 0);
    `checkd(same_passes, 10);
    `checkd(same_fails, 0);
    `checkd(cnt_passes, 9);
    `checkd(cnt_fails, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
