// DESCRIPTION: Verilator: Assertion control scopes reached through interface ports
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each instance counts the failures of its assertion; a controlled instance keeps 0, others reach 4.
// A scope name that crosses a port of interface type names the instance connected to that port
// (IEEE 1800-2023 20.11, 25.3).

interface ifc (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
  modport mp(input clk);
endinterface

interface ifc2 (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
endinterface

interface ifcp #(
    parameter int N = 1
) (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
endinterface

// An interface with an interface port of its own
interface ifco (
    input logic clk,
    ifc inner
);
endinterface

// A: the connected instance declared before or after another of the same interface
module sub (
    ifc p
);
  initial $assertoff(0, p.a1);
endmodule
module first_order (
    input logic clk
);
  ifc off_i (.clk(clk));
  ifc on_i (.clk(clk));
  sub s (.p(off_i));
endmodule
module last_order (
    input logic clk
);
  ifc on_i (.clk(clk));
  ifc off_i (.clk(clk));
  sub s (.p(off_i));
endmodule

// B: one module instantiated twice with swapped connections
module holder (
    ifc x,
    ifc y
);
  sub s (.p(x));
endmodule

// C: the control runs from one caller instance only
module subg (
    ifc p,
    input bit off
);
  initial if (off) $assertoff(0, p.a1);
endmodule

// D: the port is a later component of the name
module child (
    ifc p
);
endmodule
module par (
    ifc x
);
  child c (.p(x));
  initial $assertoff(0, c.p.a1);
endmodule

// E: upward name by module name, then a port of that instance
module leafu;
  initial $assertoff(0, holderu.p.a1);
endmodule
module holderu (
    ifc p
);
  leafu l ();
endmodule

// F: a port connected to another port
module leafq (
    ifc q
);
  initial $assertoff(0, q.a1);
endmodule
module subf (
    ifc p
);
  leafq l (.q(p));
endmodule

// G: differently parameterized connections, directly and upward
module subp (
    ifcp p
);
  initial $assertoff(0, p.a1);
endmodule
module leafgu;
  initial $assertoff(0, holdgu.p.a1);
endmodule
module holdgu (
    ifcp p
);
  leafgu l ();
endmodule

// H: the port itself names the connected instance, directly and as a later component
module subh (
    ifc p
);
  initial $assertoff(0, p);
endmodule
module parh (
    ifc x
);
  child c (.p(x));
  initial $assertoff(0, c.p);
endmodule

// Two ports in one name
module subo (
    ifco po
);
  initial $assertoff(0, po.inner.a1);
endmodule

// K: elements of an interface port array
module suba (
    ifc p[2]
);
  initial $assertoff(0, p[0].a1);
endmodule
module subb (
    ifc p[2]
);
  initial $assertoff(0, p[1].a1);
endmodule

// N: a generic interface port
module subn (
    interface p
);
  initial $assertoff(0, p.a1);
endmodule

// M: absolute names through a port
module subm (
    ifc p
);
endmodule

// An interface holding a generate block and a nested interface instance, each with an assertion
interface ifcg (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
  if (1) begin : gb
    int m = 0;
    a1 :
    assert property (@(posedge clk) 0)
    else m++;
  end
  ifc sub (.clk(clk));
endinterface

// Instance and child paths differ after the port; a level limit counts from the port's instance
module subgb (
    ifcg p
);
  initial $assertoff(0, p.gb.a1);
endmodule
module subsub (
    ifcg p
);
  initial $assertoff(0, p.sub.a1);
endmodule
module sublev (
    ifcg p
);
  initial $assertcontrol(4, 15, 7, 1, p);
endmodule
module sublev2 (
    ifcg p
);
  initial $assertcontrol(4, 15, 7, 2, p);
endmodule

// A name whose first identifier is shadowed by a closer generate block named t
module subsh (
    ifc p
);
endmodule
module shadow (
    ifc x
);
  if (1) begin : t
    subsh sx (.p(x));
  end
  initial $assertoff(0, t.sx.p.a1);
endmodule

// Two spellings of one assertion in one control
module subdup (
    ifc p
);
  initial $assertoff(0, p.a1, p.a1);
endmodule

// A module-local class calling the control through the port
module subcls (
    ifc p
);
  class C;
    static task off();
      $assertoff(0, p.a1);
    endtask
  endclass
  initial C::off();
endmodule

// The statement is in a generate block of its module
module parg (
    ifc x
);
  if (1) begin : g
    child c (.p(x));
    initial $assertoff(0, c.p.a1);
  end
endmodule
module parhg (
    ifc x
);
  if (1) begin : g
    child c (.p(x));
    initial $assertoff(0, c.p);
  end
endmodule

// The first name is a top module from one instance and a closer generate block from another
module subsx (
    ifc p
);
endmodule
module midx;
  initial $assertoff(0, t.sxm.p.a1);
endmodule
module wrapx (
    ifc x
);
  if (1) begin : t
    subsx sxm (.p(x));
  end
  midx m ();
endmodule
module midy;
  initial $assertoff(0, t.sym.p.a1);
endmodule
module wrapy (
    ifc x
);
  if (1) begin : t
    subsx sym (.p(x));
  end
  midy m ();
endmodule

// The statement in a task, a block with a declaration, a fork, and a foreach body
module stask (
    ifc p
);
  task automatic off();
    $assertoff(0, p.a1);
  endtask
  initial off();
endmodule
module sbeg (
    ifc p
);
  initial begin
    int k;
    k = 1;
    $assertoff(0, p.a1);
  end
endmodule
module sfork (
    ifc p
);
  initial
  fork
    $assertoff(0, p.a1);
  join
endmodule
module sfe (
    ifc p
);
  int arr[2];
  initial foreach (arr[i]) if (i == 0) $assertoff(0, p.a1);
endmodule

// Package code naming one of its own tasks as the scope (IEEE 1800-2023 20.11, 26.2): it has no
// instances (pins V3LinkDot assertControlThroughPort's package fallback, and the old path's
// "instance symbol is null: a package is not an instance" arm). An untargeted task keeps counting.
package pkc_ctl;
  int n = 0;
  int m = 0;
  task automatic chk(input bit v);
    a1 :
    assert (v)
    else n++;
  endtask
  task automatic chk2(input bit v);
    a2 :
    assert (v)
    else m++;
  endtask
  task automatic off();
    // The child path is "$root.chk" in dumps; a task holds no cells, so it selects this task
    $assertoff(0, chk);
  endtask
endpackage

module t;
  logic clk = 0;
  int cyc = 0;

  first_order fa (.clk(clk));
  last_order la (.clk(clk));
  ifc free_i (.clk(clk));

  ifc b0 (.clk(clk));
  ifc b1 (.clk(clk));
  ifc b2 (.clk(clk));
  ifc b3 (.clk(clk));
  holder hb0 (
      .x(b0),
      .y(b1)
  );
  holder hb1 (
      .x(b3),
      .y(b2)
  );

  ifc c0 (.clk(clk));
  ifc c1 (.clk(clk));
  subg sc0 (
      .p(c0),
      .off(1'b1)
  );
  subg sc1 (
      .p(c1),
      .off(1'b0)
  );

  ifc d0 (.clk(clk));
  ifc d1 (.clk(clk));
  ifc d2 (.clk(clk));
  par pd0 (.x(d0));
  par pd1 (.x(d2));

  ifc e0 (.clk(clk));
  ifc e1 (.clk(clk));
  ifc e2 (.clk(clk));
  holderu he0 (.p(e0));
  holderu he1 (.p(e2));

  ifc f0 (.clk(clk));
  ifc f1 (.clk(clk));
  subf sf (.p(f0));

  ifcp #(1) g0 (.clk(clk));
  ifcp #(2) g1 (.clk(clk));
  ifcp #(2) g2 (.clk(clk));
  subp sg0 (.p(g0));
  subp sg1 (.p(g1));
  ifcp #(1) gu0 (.clk(clk));
  ifcp #(2) gu1 (.clk(clk));
  ifcp #(2) gu2 (.clk(clk));
  holdgu hg0 (.p(gu0));
  holdgu hg1 (.p(gu1));

  ifc h0 (.clk(clk));
  ifc h1 (.clk(clk));
  ifc h2 (.clk(clk));
  ifc h3 (.clk(clk));
  subh sh (.p(h0));
  parh ph (.x(h2));

  ifc in0 (.clk(clk));
  ifc in1 (.clk(clk));
  ifco o0 (
      .clk(clk),
      .inner(in0)
  );
  subo so (.po(o0));

  ifc ka[2] (.clk(clk));
  ifc kb[2] (.clk(clk));
  ifc kc[2] (.clk(clk));
  suba sk0 (.p(ka));
  suba sk1 (.p(kb));
  subb sk2 (.p(kc));

  ifc la0[2] (.clk(clk));
  ifc lb0[2] (.clk(clk));
  sub sl0 (.p(la0[0]));
  sub sl1 (.p(lb0[1]));

  ifc n0 (.clk(clk));
  ifc n1 (.clk(clk));
  ifc2 n2 (.clk(clk));
  ifc2 n3 (.clk(clk));
  subn sn0 (.p(n0));
  subn sn1 (.p(n2));

  ifc m0 (.clk(clk));
  ifc m1 (.clk(clk));
  ifc m2 (.clk(clk));
  ifc m3 (.clk(clk));
  subm sm (.p(m0));
  subm sm2 (.p(m2));
  initial begin
    $assertoff(0, $root.t.sm.p.a1);
    $assertoff(0, t.sm2.p.a1);
  end

  ifcg q0 (.clk(clk));
  ifcg q1 (.clk(clk));
  ifcg q2 (.clk(clk));
  ifcg q3 (.clk(clk));
  subgb sq0 (.p(q0));
  subsub sq1 (.p(q1));
  sublev sq2 (.p(q2));
  ifcg q4 (.clk(clk));
  sublev2 sq4 (.p(q4));

  ifc w0 (.clk(clk));
  ifc w1 (.clk(clk));
  shadow sw (.x(w0));

  ifc u0 (.clk(clk));
  ifc u1 (.clk(clk));
  subdup su (.p(u0));

  ifc z0 (.clk(clk));
  ifc z1 (.clk(clk));
  ifc z2 (.clk(clk));
  subcls sz0 (.p(z0));
  subcls sz1 (.p(z2));

  ifc gg0 (.clk(clk));
  ifc gg1 (.clk(clk));
  ifc gg2 (.clk(clk));
  parg pg0 (.x(gg0));
  parg pg1 (.x(gg2));
  ifc hgg0 (.clk(clk));
  ifc hgg1 (.clk(clk));
  parhg ph0 (.x(hgg0));

  // Instances in both orders
  ifc xa0 (.clk(clk));
  ifc xa1 (.clk(clk));
  ifc xb0 (.clk(clk));
  subsx sxm (.p(xb0));
  wrapx wx (.x(xa0));
  midx mx ();
  ifc ya0 (.clk(clk));
  ifc ya1 (.clk(clk));
  ifc yb0 (.clk(clk));
  subsx sym (.p(yb0));
  midy my ();
  wrapy wy (.x(ya0));

  // A modport selected in the connection
  ifc mp0 (.clk(clk));
  ifc mp1 (.clk(clk));
  ifc mp2 (.clk(clk));
  sub smp0 (.p(mp0.mp));
  sub smp1 (.p(mp2.mp));

  ifc ta0 (.clk(clk));
  ifc ta1 (.clk(clk));
  ifc ta2 (.clk(clk));
  stask sta0 (.p(ta0));
  stask sta1 (.p(ta2));
  ifc tb0 (.clk(clk));
  ifc tb1 (.clk(clk));
  ifc tb2 (.clk(clk));
  sbeg stb0 (.p(tb0));
  sbeg stb1 (.p(tb2));
  ifc tc0 (.clk(clk));
  ifc tc1 (.clk(clk));
  ifc tc2 (.clk(clk));
  sfork stc0 (.p(tc0));
  sfork stc1 (.p(tc2));
  ifc td0 (.clk(clk));
  ifc td1 (.clk(clk));
  ifc td2 (.clk(clk));
  sfe std0 (.p(td0));
  sfe std1 (.p(td2));

  initial begin
    pkc_ctl::chk(0);
    pkc_ctl::chk2(0);
    `checkd(pkc_ctl::n, 1);
    `checkd(pkc_ctl::m, 1);
    pkc_ctl::off();
    pkc_ctl::chk(0);
    pkc_ctl::chk2(0);
    `checkd(pkc_ctl::n, 1);
    `checkd(pkc_ctl::m, 2);
  end

  always #5 clk = ~clk;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 4) begin
      `checkd(fa.off_i.n, 0);
      `checkd(fa.on_i.n, 4);
      `checkd(la.off_i.n, 0);
      `checkd(la.on_i.n, 4);
      `checkd(free_i.n, 4);
      `checkd(b0.n, 0);
      `checkd(b1.n, 4);
      `checkd(b2.n, 4);
      `checkd(b3.n, 0);
      `checkd(c0.n, 0);
      `checkd(c1.n, 4);
      `checkd(d0.n, 0);
      `checkd(d1.n, 4);
      `checkd(d2.n, 0);
      `checkd(e0.n, 0);
      `checkd(e1.n, 4);
      `checkd(e2.n, 0);
      `checkd(f0.n, 0);
      `checkd(f1.n, 4);
      `checkd(g0.n, 0);
      `checkd(g1.n, 0);
      `checkd(g2.n, 4);
      `checkd(gu0.n, 0);
      `checkd(gu1.n, 0);
      `checkd(gu2.n, 4);
      `checkd(h0.n, 0);
      `checkd(h1.n, 4);
      `checkd(h2.n, 0);
      `checkd(h3.n, 4);
      `checkd(in0.n, 0);
      `checkd(in1.n, 4);
      `checkd(ka[0].n, 0);
      `checkd(ka[1].n, 4);
      `checkd(kb[0].n, 0);
      `checkd(kb[1].n, 4);
      `checkd(kc[0].n, 4);
      `checkd(kc[1].n, 0);
      `checkd(la0[0].n, 0);
      `checkd(la0[1].n, 4);
      `checkd(lb0[0].n, 4);
      `checkd(lb0[1].n, 0);
      `checkd(n0.n, 0);
      `checkd(n1.n, 4);
      `checkd(n2.n, 0);
      `checkd(n3.n, 4);
      `checkd(m0.n, 0);
      `checkd(m1.n, 4);
      `checkd(m2.n, 0);
      `checkd(m3.n, 4);
      `checkd(q0.n, 4);
      `checkd(q0.gb.m, 0);
      `checkd(q0.sub.n, 4);
      `checkd(q1.n, 4);
      `checkd(q1.gb.m, 4);
      `checkd(q1.sub.n, 0);
      `checkd(q2.n, 0);
      `checkd(q2.gb.m, 0);
      `checkd(q2.sub.n, 4);
      `checkd(q3.n, 4);
      `checkd(q3.gb.m, 4);
      `checkd(q3.sub.n, 4);
      `checkd(q4.n, 0);
      `checkd(q4.gb.m, 0);
      `checkd(q4.sub.n, 0);
      `checkd(w0.n, 0);
      `checkd(w1.n, 4);
      `checkd(u0.n, 0);
      `checkd(u1.n, 4);
      `checkd(z0.n, 0);
      `checkd(z1.n, 4);
      `checkd(z2.n, 0);
      `checkd(gg0.n, 0);
      `checkd(gg1.n, 4);
      `checkd(gg2.n, 0);
      `checkd(hgg0.n, 0);
      `checkd(hgg1.n, 4);
      `checkd(xa0.n, 0);
      `checkd(xa1.n, 4);
      `checkd(xb0.n, 0);
      `checkd(ya0.n, 0);
      `checkd(ya1.n, 4);
      `checkd(yb0.n, 0);
      `checkd(mp0.n, 0);
      `checkd(mp1.n, 4);
      `checkd(mp2.n, 0);
      `checkd(ta0.n, 0);
      `checkd(ta1.n, 4);
      `checkd(ta2.n, 0);
      `checkd(tb0.n, 0);
      `checkd(tb1.n, 4);
      `checkd(tb2.n, 0);
      `checkd(tc0.n, 0);
      `checkd(tc1.n, 4);
      `checkd(tc2.n, 0);
      `checkd(td0.n, 0);
      `checkd(td1.n, 4);
      `checkd(td2.n, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
