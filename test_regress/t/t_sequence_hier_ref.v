// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sequences and properties declared in an interface or module, instanced through a hierarchical
// path, compared with the same expressions written inline

package pkg;
  bit pkg_flag = 1'b1;
  function automatic logic pkg_inv(logic x);
    return !x;
  endfunction
endpackage

interface sub_ifc;
  logic x;
  sequence s_x;
    x;
  endsequence
endinterface

interface ifc (
    input clk
);
  logic a, b, c;
  sub_ifc j ();
  sequence s;
    a ##1 b;
  endsequence
  sequence s_bool;
    a && b;
  endsequence
  sequence s_nested;
    s ##1 c;
  endsequence
  sequence s_arg(v);
    a ##1 v;
  endsequence
  sequence s_sub;
    j.x ##1 a;
  endsequence
  sequence s_sub_seq;
    j.s_x ##1 (a == pkg::pkg_flag);
  endsequence
  sequence s_clocked;
    @(posedge clk) a ##1 b;
  endsequence
  function automatic logic inv(logic x);
    return !x;
  endfunction
  sequence s_func;
    inv(a) ##1 pkg::pkg_inv(b);
  endsequence
  property p;
    a |=> b;
  endproperty
  property p_seq;
    s |-> c;
  endproperty
  property p_local;
    logic v;
    (a, v = b) |=> c == v;
  endproperty
  // A nested instance of a property with a local variable
  property p_local_ov;
    logic v;
    (a, v = b) |-> c == v;
  endproperty
  property p_outer;
    p_local_ov;
  endproperty
  // Also instanced in the declaring interface
  int outer_fails = 0, ref_outer_fails = 0;
  assert property (@(posedge clk) p_outer)
  else outer_fails++;
  assert property (@(posedge clk) a |-> c == b)
  else ref_outer_fails++;
  // A method called on a class handle of the interface
  class Cls;
    function automatic logic inv(logic x);
      return !x;
    endfunction
  endclass
  Cls obj = new;
  sequence s_method;
    obj.inv(a) ##1 b;
  endsequence
  // A task called in a match item
  int n_calls = 0;
  task automatic count();
    n_calls++;
  endtask
  // verilator lint_off SIDEEFFECT
  sequence s_task;
    (a, count()) ##1 b;
  endsequence
  // verilator lint_on SIDEEFFECT
  if (1) begin : g
    logic e;
    sequence s;
      a ##1 e;
    endsequence
  end
endinterface

module sub (
    input logic a,
    input logic b
);
  sequence s;
    a ##1 b;
  endsequence
endmodule

module chk (
    ifc pi
);
  int fails = 0, ref_fails = 0;
  assert property (@(posedge pi.clk) pi.c |-> pi.s)
  else fails++;
  assert property (@(posedge pi.clk) pi.c |-> pi.a ##1 pi.b)
  else ref_fails++;
endmodule

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int cyc = 0;

  ifc i (clk);
  ifc ia[2] (clk);
  sub u (i.b, i.c);
  chk ck (i);
  logic d;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    i.a <= cyc[0] ^ cyc[3];
    i.b <= cyc[1];
    i.c <= cyc[2] | cyc[0];
    i.j.x <= cyc[1] ^ cyc[2];
    i.g.e <= cyc[2];
    d <= cyc[3];
    ia[1].a <= cyc[1];
    ia[1].b <= cyc[2];
    if (cyc == 40) $finish;
  end

  int fails[17], ref_fails[17];
  assert property (@(posedge clk) i.c |-> i.s)
  else fails[0]++;
  assert property (@(posedge clk) i.c |-> i.a ##1 i.b)
  else ref_fails[0]++;
  assert property (@(posedge clk) i.s_bool)
  else fails[1]++;
  assert property (@(posedge clk) i.a && i.b)
  else ref_fails[1]++;
  assert property (@(posedge clk) i.s_nested)
  else fails[2]++;
  assert property (@(posedge clk) i.a ##1 i.b ##1 i.c)
  else ref_fails[2]++;
  assert property (@(posedge clk) i.s_arg(d))
  else fails[3]++;
  assert property (@(posedge clk) i.a ##1 d)
  else ref_fails[3]++;
  assert property (@(posedge clk) i.s_sub)
  else fails[4]++;
  assert property (@(posedge clk) i.j.x ##1 i.a)
  else ref_fails[4]++;
  assert property (@(posedge clk) i.p)
  else fails[5]++;
  assert property (@(posedge clk) i.a |=> i.b)
  else ref_fails[5]++;
  assert property (@(posedge clk) i.p_seq)
  else fails[6]++;
  assert property (@(posedge clk) i.a ##1 i.b |-> i.c)
  else ref_fails[6]++;
  assert property (@(posedge clk) i.p_local)
  else fails[7]++;
  assert property (@(posedge clk) i.a |=> i.c == $past(i.b))
  else ref_fails[7]++;
  assert property (@(posedge clk) u.s)
  else fails[8]++;
  assert property (@(posedge clk) i.b ##1 i.c)
  else ref_fails[8]++;
  assert property (@(posedge clk) ia[1].s)
  else fails[9]++;
  assert property (@(posedge clk) ia[1].a ##1 ia[1].b)
  else ref_fails[9]++;
  assert property (@(posedge clk) i.g.s)
  else fails[10]++;
  assert property (@(posedge clk) i.a ##1 i.g.e)
  else ref_fails[10]++;

  assert property (@(posedge clk) i.s_func)
  else fails[11]++;
  assert property (@(posedge clk) !i.a ##1 !i.b)
  else ref_fails[11]++;

  assert property (@(posedge clk) i.s_sub_seq)
  else fails[12]++;
  assert property (@(posedge clk) i.j.x ##1 i.a)
  else ref_fails[12]++;

  assert property (@(posedge clk) d |-> i.p_outer)
  else fails[13]++;
  assert property (@(posedge clk) d |-> (i.a |-> i.c == i.b))
  else ref_fails[13]++;

  assert property (@(posedge clk) ia[1].p_outer)
  else fails[15]++;
  assert property (@(posedge clk) ia[1].a |-> ia[1].c == ia[1].b)
  else ref_fails[15]++;

  assert property (@(posedge clk) i.s_method)
  else fails[16]++;
  assert property (@(posedge clk) !i.a ##1 i.b)
  else ref_fails[16]++;

  assert property (@(posedge clk) i.s_task |-> i.c)
  else fails[14]++;
  // verilator lint_off SIDEEFFECT
  assert property (@(posedge clk) (i.a, i.count()) ##1 i.b |-> i.c)
  else ref_fails[14]++;
  // verilator lint_on SIDEEFFECT

  int events = 0;
  always @(i.s_clocked) events++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    for (int k = 0; k < 17; k++) `checkd(fails[k], ref_fails[k]);
    `checkd(fails[0], 16);
    `checkd(fails[1], 31);
    `checkd(fails[2], 30);
    `checkd(fails[3], 21);
    `checkd(fails[4], 28);
    `checkd(fails[5], 9);
    `checkd(fails[6], 3);
    `checkd(fails[7], 9);
    `checkd(fails[8], 21);
    `checkd(fails[9], 26);
    `checkd(fails[10], 23);
    `checkd(fails[11], 20);
    `checkd(fails[13], 4);
    `checkd(fails[14], 3);
    `checkd(fails[15], 10);
    `checkd(fails[16], 23);
    `checkd(i.outer_fails, i.ref_outer_fails);
    `checkd(i.outer_fails, 10);
    `checkd(ck.fails, ck.ref_fails);
    `checkd(ck.fails, 16);
    `checkd(events, 10);
    $write("*-* All Finished *-*\n");
  end
endmodule
