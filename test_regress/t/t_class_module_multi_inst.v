// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes declared in a module instantiated more than once refer to the
// variables of their own instance, and then have per-instance static members

module sub #(
    parameter int P = 0
) (
    input int v
);
  int x;
  assign x = v + P;
  function int twice();
    return 2 * x;
  endfunction
  class D;
    function int one();
      return 1;
    endfunction
  endclass
  class C;
    static int cnt;
    function new();
      cnt++;
    endfunction
    function int get();
      return x;
    endfunction
    function int getTwice();
      return twice();
    endfunction
    function int viaObject();
      D d = new;
      return d.one();
    endfunction
  endclass
  C c = new;
  covergroup cg;
    cp: coverpoint x {bins b[] = {[1 : 4]};}
  endgroup
  cg cov = new;
endmodule

module mid (
    input int v
);
  sub s (.v(v));
  // A hierarchical reference is to the instance
  class H;
    function int sx();
      return s.x;
    endfunction
  endclass
  H h = new;
endmodule

// A static variable of a module function is per instance
module counter;
  function int next();
    int cnt;
    cnt++;
    return cnt;
  endfunction
  class C;
    function int n();
      return next();
    endfunction
  endclass
  C c = new;
endmodule

class Base #(
    type T = int
);
  task tb();
  endtask
endclass

package mpkg;
  int pv = 1;
  function automatic int inc(int a);
    return a + pv;
  endfunction
endpackage

// A class not referring to the module's instance is shared by its instances
module shared #(
    parameter int SP = 4
);
  function automatic int dbl(int a);
    return 2 * a;
  endfunction
  function int triple(int a);  // Static, but its ports only pass values
    return 3 * a;
  endfunction
  class E;
    static int cnt;
    function new();
      cnt++;
    endfunction
    function int calc(int a);
      return dbl(a) + dbl(0) + mpkg::inc(0) - 1;
    endfunction
    function int calcOne();
      return calc(1);
    endfunction
    function int calcTriple(int a);
      return triple(a);
    endfunction
    function int pkgParam();
      return mpkg::pv + SP;
    endfunction
    // Variables of the class's own methods, also those created for a fork
    function int countCalls();
      static int k;
      k++;
      return k;
    endfunction
    task forked(output int o);
      int i = 1;
      fork
        i++;
      join_none
      o = i;
    endtask
  endclass
  class F extends Base #(int);
    task inherited();
      tb();
    endtask
  endclass
  E e = new;
  covergroup cg with function sample (int s);
    cp: coverpoint s {bins b[] = {[1 : 4]};}
  endgroup
  cg cov = new;
endmodule

// A class not referring to the interface is shared by its instances
interface ifc;
  function automatic int dbl(int a);
    return 2 * a;
  endfunction
  function int quad(int a);
    return 4 * a;
  endfunction
  class D;
    static int cnt;
    function new();
      cnt++;
    endfunction
    function int calc(int a);
      return dbl(a) + quad(0);
    endfunction
    function int calcQuad(int a);
      return quad(a);
    endfunction
    function int countCalls();
      static int k;
      k++;
      return k;
    endfunction
    task forked(output int o);
      int i = 1;
      fork
        i++;
      join_none
      o = i;
    endtask
  endclass
  D d = new;
  covergroup cg with function sample (int s);
    cp: coverpoint s {bins b[] = {[1 : 4]};}
  endgroup
  cg cov = new;
endinterface

module t;
  int va, vb, vm1, vm2, vg[2];
  sub a (.v(va));
  sub b (.v(vb));
  sub #(.P(10)) p1 (.v(va));
  sub #(.P(10)) p2 (.v(vb));
  sub #(.P(20)) sa[2] (.v(va));
  mid m1 (.v(vm1));
  mid m2 (.v(vm2));
  for (genvar i = 0; i < 2; ++i) begin : g
    sub s (.v(vg[i]));
  end
  shared sh1 ();
  shared sh2 ();
  counter c1 ();
  counter c2 ();
  ifc i1 ();
  ifc i2 ();

  initial begin
    va = 1;
    vb = 2;
    vm1 = 3;
    vm2 = 4;
    vg[0] = 5;
    vg[1] = 6;
    #1;
    `checkd(a.c.get(), 1);
    `checkd(b.c.get(), 2);
    `checkd(a.c.getTwice(), 2);
    `checkd(b.c.getTwice(), 4);
    `checkd(p1.c.get(), 11);
    `checkd(p2.c.get(), 12);
    `checkd(m1.s.c.get(), 3);
    `checkd(m2.s.c.get(), 4);
    `checkd(g[0].s.c.get(), 5);
    `checkd(g[1].s.c.get(), 6);
    `checkd(a.c.cnt, 1);
    `checkd(b.c.cnt, 1);
    `checkd(m2.s.c.cnt, 1);
    `checkd(m1.h.sx(), 3);
    `checkd(m2.h.sx(), 4);
    `checkd(sa[0].c.get(), 21);
    `checkd(sa[1].c.cnt, 1);
    for (int n = 1; n <= 4; ++n) begin
      va = n;
      #1;
      a.cov.sample();
      b.cov.sample();
    end
    `checkr(a.cov.get_inst_coverage(), 100.0);
    `checkr(b.cov.get_inst_coverage(), 25.0);
    `checkd(sh1.e.cnt, 2);
    `checkd(sh2.e.calc(va), 8);
    `checkd(sh1.e.calcOne(), 2);
    `checkd(sh2.e.calcTriple(vb), 6);
    `checkd(a.c.viaObject(), 1);
    `checkd(c1.c.n(), 1);
    `checkd(c1.c.n(), 2);
    `checkd(c2.c.n(), 1);
    sh1.cov.sample(1);
    sh2.cov.sample(2);
    sh2.cov.sample(3);
    `checkr(sh1.cov.get_inst_coverage(), 25.0);
    `checkr(sh2.cov.get_inst_coverage(), 50.0);
    `checkd(i1.d.cnt, 2);
    `checkd(i2.d.calc(vb), 4);
    `checkd(i1.d.calcQuad(vb), 8);
    `checkd(sh1.e.pkgParam(), 5);
    `checkd(sh1.e.countCalls(), 1);
    `checkd(sh2.e.countCalls(), 2);
    `checkd(i1.d.countCalls(), 1);
    `checkd(i2.d.countCalls(), 2);
    begin
      int o;
      sh1.e.forked(o);
      `checkd(o, 1);
      i2.d.forked(o);
      `checkd(o, 1);
    end
    i1.cov.sample(1);
    i2.cov.sample(2);
    i2.cov.sample(3);
    `checkr(i1.cov.get_inst_coverage(), 25.0);
    `checkr(i2.cov.get_inst_coverage(), 50.0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
