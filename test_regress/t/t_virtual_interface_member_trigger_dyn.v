// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Writes through a virtual interface to dynamic array, queue and associative array members

typedef int int_q_t[$];
typedef struct {int a;} s_t;

class Cls;
  int x;
endclass

interface Ifc;
  int_q_t q;
  int d[];
  int a[int];
  int w[*];
  string s[$];
  real r[$];
  Cls c[$];
  s_t st[int];
  event ed[];
  event eq[$];
endinterface

interface Out;
  int total;
  int first;
  int dfirst;
  int asum;
  string sfirst;
  real rfirst;
  int cfirst;
  int stfirst;
  int edsize;
endinterface

module t;
  Ifc i ();
  Out o ();
  virtual Ifc vif;
  virtual Out vo;

  // Combinational reads, which are only updated by the virtual interface write triggers
  // (read back through a virtual interface, so not substituted into the reads)
  assign o.total = i.q.size() + i.d.size() + i.a.size() + i.w.size();
  assign o.first = i.q.size() > 0 ? i.q[0] : -1;
  assign o.sfirst = i.s.size() > 0 ? i.s[0] : "";
  assign o.dfirst = i.d.size() > 0 ? i.d[0] : -1;
  assign o.asum = i.a.sum();
  assign o.rfirst = i.r.size() > 0 ? i.r[0] : -1.0;
  assign o.cfirst = i.c.size() > 0 && i.c[0] != null ? i.c[0].x : -1;
  assign o.stfirst = i.st.exists(1) ? i.st[1].a : -1;
  assign o.edsize = i.ed.size();

  initial begin
    vif = i;
    vo = o;
    vif.q = {1, 2};
    #1;
    `checkd(vo.total, 2);
    `checkd(vo.first, 1);
    vif.q[0] = 9;
    #1;
    `checkd(vo.first, 9);
    vif.d = new[3];
    #1;
    `checkd(vo.total, 5);
    vif.d[0] = 4;
    #1;
    `checkd(vo.dfirst, 4);
    vif.a[5] = 1;
    #1;
    `checkd(vo.total, 6);
    vif.a[5] = 3;
    #1;
    `checkd(vo.asum, 3);
    vif.w[7] = 1;
    #1;
    `checkd(vo.total, 7);
    vif.s = {"x"};
    #1;
    `checks(vo.sfirst, "x");
    vif.s[0] = "y";
    #1;
    `checks(vo.sfirst, "y");
    vif.r = {1.5};
    vif.r[0] = 2.5;
    #1;
    `checkr(vo.rfirst, 2.5);
    begin
      Cls c1, c2;
      c1 = new;
      c1.x = 7;
      c2 = new;
      c2.x = 8;
      vif.c = {c1};
      vif.c[0] = c2;
      #1;
      `checkd(vo.cfirst, 8);
    end
    vif.st[1] = '{a: 10};
    vif.st[1] = '{a: 11};
    #1;
    `checkd(vo.stfirst, 11);
    vif.ed = new[2];
    #1;
    `checkd(vo.edsize, 2);
    begin
      // Needs a trigger once a method call is a write of the member
      event e;
      vif.eq.push_back(e);
      vif.eq.push_back(e);
      vif.eq.delete(0);
      `checkd(i.eq.size(), 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
