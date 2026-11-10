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
    end else begin
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

module leaf #(
    parameter string NAME = ""
) (
    output logic named
);
  // Constant inputs, so evaluated once at initialization, with in_names not inlined
  assign named = in_names(NAME);
endmodule

module t;
  logic clk = 0;
  always #5 clk = ~clk;

  logic [3:0] named;
  leaf #(.NAME("n0")) u0 (.named(named[0]));
  leaf #(.NAME("n1")) u1 (.named(named[1]));
  leaf #(.NAME("n2")) u2 (.named(named[2]));
  leaf #(.NAME("n3")) u3 (.named(named[3]));

  // Two calls, each with its own automatic variables
  wire [1:0] named12 = {in_names("n1"), in_names("n2")};

  // Constant arguments, but reads a module variable, so inlined to follow it
  int m;
  function int plus_m(int a);
    return m + a;
  endfunction
  wire integer m_p3 = plus_m(3);

  // Writes a module variable, so inlined
  int flag;
  function int set_flag();
    flag = 1;
    return 2;
  endfunction
  wire integer two = set_flag();

  // Nonblocking assignment, so inlined
  function int nba_static();
    int s;
    s <= 3;
    return 4;
  endfunction
  // verilator lint_off COMBDLY
  wire integer four = nba_static();
  // verilator lint_on COMBDLY

  // Read-write access after a write, so not inlined
  function int pop_first();
    int q[$];
    q = {7, 8};
    return q.pop_front();
  endfunction
  wire integer seven = pop_first();

  // Nonblocking event trigger, so inlined
  function int nba_event();
    event e;
    ->>e;
    return 5;
  endfunction
  wire integer five = nba_event();

`ifdef VERILATOR
  // Public, so inlined
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

  // Calls impure functions that are never inlined, so not checked, and a blocking trigger
  function automatic int fact(int n);
    static int depth;
    depth = n;
    return n <= 1 ? 1 : n * fact(n - 1);
  endfunction
  function int sq(int a);
    return a * a;
  endfunction
  function int fact_twice(int a);
    event e;
    ->e;
    return fact(a) + Cls::twice(a) + sq(a);
  endfunction
  wire integer fact_tw = fact_twice(3);
  // A function never inlined, and a pure function, so inlined
  wire integer fact_sq = fact(4) + sq(3);

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    m <= m + 2;
    `checkd(m_p3, m + 3);
    if (cyc == 1) begin
      `checkd(named, 4'b1010);
      `checkd(named12, 2'b10);
      `checkd(flag, 1);
      `checkd(two, 2);
      `checkd(four, 4);
      `checkd(five, 5);
      `checkd(seven, 7);
      `checkd(pub_n3, 1'b1);
      `checkd(fact_tw, 21);
      `checkd(fact_sq, 33);
    end
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
