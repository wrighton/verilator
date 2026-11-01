// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// Mutating methods on an element of a container that is a class member

interface Ifc;
  int q[$];
  int m[int][$];
endinterface

interface Out;
  int qsize;
  int m3;
endinterface

typedef struct {int m[int][$];} s_t;

class Sub;
  int m[string][$];
endclass

class Cfg;
  int m[int][$];
  int d[int][];
  int a[int][int];
  int k[int];
  int ki;
  int w[*][$];
  int qq[$][$];
  int dq[][$];
  int f[2][longint][$];
  string sq[int][$];
  s_t s;
  Sub sub;
  function new;
    sub = new;
  endfunction
endclass

module t;
  Ifc ifc ();
  Out out ();
  virtual Ifc vif;
  virtual Out vout;
  Cfg gc;

  // Updated by the virtual interface write triggers, read back through a virtual interface
  assign out.qsize = ifc.q.size();
  assign out.m3 = ifc.m.exists(3) ? ifc.m[3].size() : 0;

  function automatic Cfg get_cfg();
    return gc;
  endfunction

  function automatic void fill(ref Cfg c);
    c.m[1].push_back(3);
    c.m[1].push_back(1);
    c.m[1].push_front(2);
    c.m[1].insert(1, 5);
    `checkp(c.m[1], "'{'h2, 'h5, 'h3, 'h1}");
    c.m[1].sort();
    `checkp(c.m[1], "'{'h1, 'h2, 'h3, 'h5}");
    c.m[1].reverse();
    `checkp(c.m[1], "'{'h5, 'h3, 'h2, 'h1}");
    c.m[1].shuffle();
    `checkd(c.m[1].sum(), 11);
    c.m[1].insert(2, 4);
    c.m[1].rsort();
    `checkp(c.m[1], "'{'h5, 'h4, 'h3, 'h2, 'h1}");
    c.m[1].delete(1);
    c.m[1].sort();
    `checkd(c.m[1].pop_front(), 1);
    `checkd(c.m[1].pop_back(), 5);
    c.m[1].delete(0);
    `checkp(c.m[1], "'{'h3}");
    c.m[2] = {4, 5};
    c.m[2].delete();
    `checkd(c.m[2].size(), 0);
    c.d[0] = '{4, 3};
    c.d[0].reverse();
    `checkp(c.d[0], "'{'h3, 'h4}");
    c.d[0].delete();
    `checkd(c.d[0].size(), 0);
    c.a[0][1] = 1;
    c.a[0][2] = 2;
    c.a[0].delete(1);
    `checkp(c.a[0], "'{'h2:'h2}");
    c.w[5].push_back(6);
    c.qq.push_back(c.m[1]);
    c.qq[0].push_back(7);
    `checkp(c.qq, "'{'{'h3, 'h7}}");
    c.dq = new[1];
    c.dq[0].push_back(8);
    c.f[1][64'h1_0000_0000].push_back(9);
    c.sq[0].push_back("x");
    c.s.m[0].push_back(10);
    c.sub.m["k"].push_back(11);
    c.k[4] = 0;
    c.k[6] = 0;
    void'(c.k.first(c.ki));
    `checkd(c.ki, 4);
    void'(c.k.next(c.ki));
    `checkd(c.ki, 6);
  endfunction

  task automatic drive(Cfg c, int k);
    #1;
    c.m[k].push_back(12);
    c.m[k] = {};
    c.m[k].push_back(13);
  endtask

  initial begin
    Cfg c;
    c = new;
    fill(c);
    drive(c, 7);
    gc = c;
    get_cfg().m[8].push_back(8);
    vif = ifc;
    vif.q.push_back(1);
    vif.q.push_back(2);
    vif.m[3].push_back(4);
    vout = out;
    #1;
    `checkd(vout.qsize, 2);
    `checkd(vout.m3, 1);
    `checkp(ifc.m[3], "'{'h4}");
    `checkp(c.w[5], "'{'h6}");
    `checkp(c.dq[0], "'{'h8}");
    `checkp(c.f[1][64'h1_0000_0000], "'{'h9}");
    `checkp(c.sq[0], "'{\"x\"}");
    `checkp(c.s.m[0], "'{'ha}");
    `checkp(c.sub.m["k"], "'{'hb}");
    `checkp(c.m[7], "'{'hd}");
    `checkp(c.m[8], "'{'h8}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
