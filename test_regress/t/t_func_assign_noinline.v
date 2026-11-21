// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Static function, so its locals are shared by all calls
function void split(input string list, output string items[$]);
  string q[$];
  string cur;
  q = {};
  cur = "";
  for (int i = 0; i < list.len(); ++i) begin
    if (list[i] == ",") begin
      q.push_back(cur);
      cur = "";
    end
    else begin
      cur = {cur, list.substr(i, i)};
    end
  end
  q.push_back(cur);
  items = q;
endfunction

// Return whether 'name' is in the comma separated list of the +names= plusarg
function automatic bit in_names(string name);
  string list;
  string items[$];
  if (!$value$plusargs("names=%s", list)) return 0;
  split(list, items);
  foreach (items[i]) if (items[i] == name) return 1;
  return 0;
endfunction

class Cls;
  static int last;
  static function int twice(int a);
    last = a;
    return 2 * last;
  endfunction
endclass

class Cnt;
  static int n = 4;
  static function int get_n();
    return n;
  endfunction
endclass

interface ifc;
  function int get5();
    int t;
    t = 5;
    return t;
  endfunction
endinterface

module leaf #(
    parameter string NAME = ""
) (
    output logic named
);
  // Constant inputs, so computed once
  assign named = in_names(NAME);
endmodule

module use_ifc (
    ifc i,
    output int five
);
  // Called through an interface port, with constant inputs
  assign five = i.get5();
endmodule

module t;
  logic clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Instances each reading the plusarg list
  logic [3:0] named;
  leaf #(.NAME("n0")) u0 (.named(named[0]));
  leaf #(.NAME("n1")) u1 (.named(named[1]));
  leaf #(.NAME("n2")) u2 (.named(named[2]));
  leaf #(.NAME("n3")) u3 (.named(named[3]));
  initial #1 `checkd(named, 4'b1010);

  // Two calls, each with its own automatic variables
  wire [1:0] named12 = {in_names("n1"), in_names("n2")};
  initial #1 `checkd(named12, 2'b10);

  // Reads a module variable, so follows its changes
  int m = 0;
  function int plus_m(int a);
    return m + a;
  endfunction
  wire integer m_p3 = plus_m(3);
  always @(posedge clk) begin
    `checkd(m_p3, m + 3);
    m <= m + 2;
  end

  // Constant argument, so computed once, and a variable argument, so follows its changes
  function int plus_one(int a);
    int t;
    t = a + 1;
    return t;
  endfunction
  wire integer plus_c = plus_one(4);
  int v = 0;
  wire integer plus_v = plus_one(v);
  initial #1 `checkd(plus_c, 5);
  always @(posedge clk) begin
    `checkd(plus_v, v + 1);
    v <= v + 3;
  end

  // Writes a module variable
  int flag;
  function int set_flag();
    flag = 1;
    return 2;
  endfunction
  wire integer two = set_flag();
  initial begin
    #1;
    `checkd(flag, 1);
    `checkd(two, 2);
  end

  // Writes a module variable in a called function
  int nested_flag;
  function int set_nested();
    nested_flag = 6;
    return 1;
  endfunction
  function int call_set_nested();
    return set_nested() + 1;
  endfunction
  wire integer two_nested = call_set_nested();
  initial begin
    #1;
    `checkd(nested_flag, 6);
    `checkd(two_nested, 2);
  end

  // Reads a static variable that a called function wrote
  function int set_s();
    int s;
    s = 3;
    return 1;
  endfunction
  function int get_s();
    int r;
    r = set_s();
    return r + set_s.s;
  endfunction
  wire integer four_s = get_s();
  initial #1 `checkd(four_s, 4);

  // Reads a static variable that it wrote only on some paths, so follows other writes of it
  function automatic int cond_static(input bit set);
    static int s = 0;
    if (set) s = 17;
    return s;
  endfunction
  wire integer cond_s = cond_static(1'b0);
  always @(posedge clk) begin
    if (cyc == 1) cond_static.s <= 42;
    if (cyc == 1) `checkd(cond_s, 0);
    if (cyc == 2) `checkd(cond_s, 42);
  end

  // Drives a net that is forced and released later
  wire integer forced_lhs = plus_one(6);
  initial begin
    #1;
    `checkd(forced_lhs, 7);
    force forced_lhs = 1;
    #1;
    `checkd(forced_lhs, 1);
    release forced_lhs;
    #1;
    `checkd(forced_lhs, 7);
  end

  // Writes a static variable read by a procedural continuous assignment, which Verilator then
  // evaluates again (Verilator-specific, as $time is not an operand)
  function int rhs_s();
    int s;
    s = int'($time) + 1;
    return s;
  endfunction
  wire integer rhs1 = rhs_s();
  int rhs_src = 0;
  int rhs_dst;
  initial begin
    // verilator lint_off IEEEMAYDEPRECATE
    assign rhs_dst = rhs_s.s + rhs_src;
    // verilator lint_on IEEEMAYDEPRECATE
    #1;
    `checkd(rhs1, 1);
    `checkd(rhs_dst, 1);
    rhs_src = 5;
    #1;
    `checkd(rhs1, 2);
    `checkd(rhs_dst, 7);
  end

  // Writes an array element through a reference argument
  task automatic incr_ref(ref int x);
    x = x + 1;
  endtask
  int ref_arr[2] = '{1, 2};
  initial begin
    #1;
    incr_ref(ref_arr[1]);
    #1;
    `checkd(ref_arr[1], 3);
  end

  // Writes and then reads its return variable and an output
  function void out_rw(output int o);
    o = 4;
    o = o + 1;
  endfunction
  function int ret_rw();
    int t;
    t = 0;
    out_rw(t);
    ret_rw = t;
    ret_rw = ret_rw + 1;
  endfunction
  wire integer ret6 = ret_rw();
  initial #1 `checkd(ret6, 6);

  // Read static variables that are forced, or assigned by a procedural continuous assignment,
  // later. Verilator-specific: these are not operands of the assignments (IEEE 1800-2023 10.3.2),
  // so other simulators may keep the old values.
  function int forced_s();
    int s;
    s = $test$plusargs("none") ? 7 : 8;
    return s;
  endfunction
  wire integer forced8 = forced_s();
  function int cont_s();
    int s;
    s = $test$plusargs("none") ? 7 : 9;
    return s;
  endfunction
  wire integer cont9 = cont_s();
  initial begin
    #1;
    `checkd(forced8, 8);
    `checkd(cont9, 9);
    force forced_s.s = 42;
    // verilator lint_off IEEEMAYDEPRECATE
    assign cont_s.s = 43;
    // verilator lint_on IEEEMAYDEPRECATE
    #1;
    `checkd(forced8, 42);
    `checkd(cont9, 43);
  end

  // Read-write access to a static variable after a write
  function int pop_first();
    int q[$];
    q = {7, 8};
    return q.pop_front();
  endfunction
  wire integer seven = pop_first();
  initial #1 `checkd(seven, 7);

  // Read-write access to a static variable before any write, so not computed once. Its value
  // is not checked: as the assignment has no inputs, it might never be computed.
  function int pop_empty();
    int q[$];
    void'(q.pop_front());
    q.push_back(9);
    return q.size();
  endfunction
  wire integer pop_e = pop_empty();

  // Pushes to a static queue before any write, so reads it first
  function int pushed();
    int q[$];
    q.push_back(4);
    return 1;
  endfunction
  wire integer pushed1 = pushed();
  initial #1 `checkd(pushed1, 1);

  // Pushes to an element of a static array of queues before any write, so reads it first
  function int pushed_elem();
    int qa[2][$];
    qa[1].push_back(6);
    return 2;
  endfunction
  wire integer pushed_e2 = pushed_elem();
  initial #1 `checkd(pushed_e2, 2);

  // Increments a static variable before any write, so reads it first
  function int incr_s();
    int s;
    s = s + 1;
    return 3;
  endfunction
  wire integer incr3 = incr_s();
  initial #1 `checkd(incr3, 3);

  // Passes a static variable to an inout argument before any write, so reads it first
  function automatic void incr_arg(inout int x);
    x = x + 1;
  endfunction
  function int inout_s();
    int s;
    incr_arg(s);
    return 4;
  endfunction
  wire integer inout4 = inout_s();
  initial #1 `checkd(inout4, 4);

  // Writes a static variable of another function, called before or after it
  function int set_wf1();
    wf1.s = 5;
    return 1;
  endfunction
  function int wf1();
    int s;
    s = 1;
    void'(set_wf1());
    return s;
  endfunction
  function int set_wf2();
    wf2.s = 5;
    return 1;
  endfunction
  function int wf2();
    int s;
    s = 1;
    void'(set_wf2());
    return s;
  endfunction
  wire integer set1 = set_wf1();
  wire integer wf1_v = wf1();
  wire integer wf2_v = wf2();
  wire integer set2 = set_wf2();
  initial begin
    #1;
    `checkd(set1, 1);
    `checkd(wf1_v, 5);
    `checkd(wf2_v, 5);
    `checkd(set2, 1);
  end

  // Called functions shared by several calls
  function int leaf_tw(int a);
    int t;
    t = 2 * a;
    return t;
  endfunction
  function int mid_tw(int a);
    return leaf_tw(a) + leaf_tw(a + 1);
  endfunction
  function int top_tw(int a);
    return mid_tw(a) + leaf_tw(a);
  endfunction
  wire integer tw_a = top_tw(1);
  wire integer tw_b = top_tw(2);
  initial begin
    #1;
    `checkd(tw_a, 8);
    `checkd(tw_b, 14);
  end

  // Mutually recursive
  function automatic int is_even(int n);
    static int depth;
    depth = n;
    return n == 0 ? 1 : is_odd(n - 1);
  endfunction
  function automatic int is_odd(int n);
    static int depth;
    depth = n;
    return n == 0 ? 0 : is_even(n - 1);
  endfunction
  wire integer even5 = is_even(5);
  wire integer even6 = is_even(6);
  initial begin
    #1;
    `checkd(even5, 0);
    `checkd(even6, 1);
  end

  // Recursive and pure functions
  function automatic int fact(int n);
    static int depth;
    depth = n;
    return n <= 1 ? 1 : n * fact(n - 1);
  endfunction
  function int sq(int a);
    return a * a;
  endfunction
  function int fact_sq_f(int a);
    return fact(a) + sq(a);
  endfunction
  wire integer fact_sq3 = fact_sq_f(3);
  wire integer fact_sq = fact(4) + sq(3);
  initial begin
    #1;
    `checkd(fact_sq3, 15);
    `checkd(fact_sq, 33);
  end

  // Triggers an event
  function int trigger(int a);
    event e;
    ->e;
    return a;
  endfunction
  wire integer trig3 = trigger(3);
  initial #1 `checkd(trig3, 3);

  // Returns early before reading a static variable it did not write
  function int early_s(int a);
    int s;
    if (a == 0) return 1;
    return s + 2;
  endfunction
  wire integer early2 = early_s(1);
  initial #1 `checkd(early2, 2);

  // Returns early after writing a static variable it reads later
  function int early_w(int a);
    int s;
    s = 2;
    if (a == 0) return 1;
    return s + 1;
  endfunction
  wire integer early3 = early_w(1);
  initial #1 `checkd(early3, 3);

  // Reads a static variable after a block that might be left before writing it
  function int after_blk(int a);
    int s;
    begin : blk
      if (a == 0) disable blk;
      s = 4;
    end
    return s;
  endfunction
  wire integer after4 = after_blk(1);
  initial #1 `checkd(after4, 4);

  // Checks an immediate assertion
  function int asserted(int a);
    int t;
    t = a;
    assert (t == 3);
    return t;
  endfunction
  wire integer asserted3 = asserted(3);
  initial #1 `checkd(asserted3, 3);

  // Controls assertions
  function int assert_on(int a);
    int t;
    t = a;
    $asserton;
    return t;
  endfunction
  wire integer assert_on8 = assert_on(8);
  initial #1 `checkd(assert_on8, 8);

`ifdef VERILATOR
  // Runs C code
  function int c_expr();
    int t;
    t = $c32("6");
    return t;
  endfunction
  wire integer c6 = c_expr();
  initial #1 `checkd(c6, 6);
  function int c_stmt();
    int t;
    t = 7;
    $c("/* C statement */");
    return t;
  endfunction
  wire integer c7 = c_stmt();
  initial #1 `checkd(c7, 7);
`endif

  // Calls a class method
  function int cls_twice(int a);
    int t;
    t = Cls::twice(a);
    return t + 1;
  endfunction
  wire integer cls_tw = cls_twice(3);
  initial #1 `checkd(cls_tw, 7);

  // Calls a class getter, which may become a read of the class variable
  function int cnt_get();
    int t;
    t = Cnt::get_n();
    return t;
  endfunction
  wire integer cnt4 = cnt_get();
  initial #1 `checkd(cnt4, 4);

  // Read by name elsewhere after the call wrote it
  function int mark();
    int s;
    s = 3;
    return 1;
  endfunction
  wire integer marked = mark();
  initial begin
    #1;
    `checkd(marked, 1);
    `checkd(mark.s, 3);
  end

  // Delayed continuous assignments, and a reader of a static variable they write
  function int dly_one(int a);
    int t;
    t = a + 1;
    return t;
  endfunction
  wire integer delayed3;
  assign #2 delayed3 = dly_one(2);
  wire integer probe3 = dly_one.t;
  wire [31:0] #2 net_delayed4 = plus_one(3);
  wire [31:0] #2 net_delayed5;
  assign net_delayed5 = plus_one(4);
  initial begin
    #3;
    `checkd(delayed3, 3);
    `checkd(probe3, 3);
    `checkd(net_delayed4, 4);
    `checkd(net_delayed5, 5);
  end

  // A combinational procedure with constant inputs
  int comb11;
  always_comb comb11 = plus_one(10);
  initial #1 `checkd(comb11, 11);

  // Called through an interface port
  ifc ifc_i ();
  int five;
  use_ifc u_ifc (
      .i(ifc_i),
      .five(five)
  );
  initial #1 `checkd(five, 5);

  // Calls through a virtual interface
  function int vif_five();
    virtual ifc vi;
    vi = ifc_i;
    return vi.get5();
  endfunction
  wire integer five_v = vif_five();
  initial #1 `checkd(five_v, 5);

  // Exported to C
  export "DPI-C" function exported_one;
  function int exported_one();
    int t;
    t = 1;
    return t;
  endfunction
  wire integer one_e = exported_one();
  initial #1 `checkd(one_e, 1);

`ifdef VERILATOR
  // Public
  // verilator lint_off UNOPTPUBLIC
  function bit pub_named();
    /*verilator public*/
    return in_names("n3");
  endfunction
  // verilator lint_on UNOPTPUBLIC
  wire pub_n3 = pub_named();
`else
  wire pub_n3 = 1'b1;
`endif
  initial #1 `checkd(pub_n3, 1'b1);
endmodule
