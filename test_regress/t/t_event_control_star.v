// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain, for
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Nested case based on ivtest's nested_impl_event1.v by Martin Whitaker.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Implicit event expressions (IEEE 1800-2023 9.4.2.2) of statements that suspend

module sub;
  int v = 0;
endmodule

interface ifc;
  int sig = 0;
endinterface

class Sub;
  int v = 0;
endclass

class Cls;
  int m = 0;
  int w = 0;
  Sub s = new;
endclass

module t;
  // Nested implicit event controls
  logic a = 0;
  logic b = 0;
  logic c = 0;
  int n1 = 0;
  int n2 = 0;
  always @* begin  // @(b or n1 or c or n2)
    a = b;
    ++n1;
    @* a = c;  // @(c or n2)
    ++n2;
  end
  initial begin
    #10 b = 1;
    #1 `checkd(n1, 1);
    `checkd(n2, 0);
    `checkd(a, 1);
    #9 b = 0;  // Waiting for c only
    #1 `checkd(n1, 1);
    `checkd(a, 1);
    #9 c = 1;
    #1 `checkd(n2, 1);
    `checkd(a, 1);
    #9 c = 0;
    #1 `checkd(n1, 2);
    `checkd(n2, 1);
    `checkd(a, 0);
    #9 c = 1;
    #1 `checkd(n2, 2);
    `checkd(a, 1);
  end

  // A delay in the block does not make it run freely
  logic d = 0;
  logic e;
  int nd = 0;
  always @* begin
    ++nd;
    #1 e = d;
  end
  initial begin
    #2 d = 1;
    #5 `checkd(nd, 1);
    `checkd(e, 1);
  end

  // Not included: what only a wait expression reads, locals, left-hand sides
  logic go = 0;
  int f = 0;
  int g;
  int idx = 0;
  int arr[4];
  int nf = 0;
  always @* begin : blk
    automatic int loc;
    loc = f;
    wait (go);
    arr[idx] = loc + f;
    g = loc;
    ++nf;
  end
  initial begin
    #2 go = 1;
    #1 `checkd(nf, 0);
    #2 f = 3;
    #1 `checkd(nf, 1);
    `checkd(g, 3);
    `checkd(arr[0], 6);
    #2 idx = 2;  // Index on a left-hand side
    #1 `checkd(nf, 2);
    `checkd(arr[2], 6);
  end

  // Event control statement, reading through a function call and a hierarchical reference
  sub s ();
  int h = 0;
  int hv = 0;
  function automatic int twice(int x);
    return 2 * x;
  endfunction
  initial begin
    @* hv = twice(h) + s.v;  // @(h or s.v)
    `checkd($time, 3);
    `checkd(hv, 8);
    @* hv = twice(h) + s.v;
    `checkd($time, 4);
    `checkd(hv, 9);
  end
  initial begin
    #3 h = 4;
    #1 s.v = 1;
  end

  // A member of a class handle or virtual interface is read as a whole
  ifc i ();
  virtual ifc vif = i;
  Cls obj = new;
  Cls objs[2] = '{null, obj};
  int nm = 0;
  int mv = 0;
  always @* begin
    ++nm;
    #1 mv = obj.m + vif.sig + obj.s.v + objs[1].w;
    obj.w = mv;  // Only written
  end
  initial begin
    #2 obj.m = 2;
    #2 `checkd(nm, 1);
    `checkd(mv, 2);
    `checkd(obj.w, 2);
    i.sig = 3;
    #2 `checkd(nm, 2);
    `checkd(mv, 7);
    obj.s.v = 4;
    #2 `checkd(nm, 3);
    `checkd(mv, 16);
  end

  // A disable by name of a block in another process is not a read
  logic k = 0;
  int nk = 0;
  always @* begin
    ++nk;
    #1;
    if (k) disable k_blk;
  end
  initial begin : k_blk
    #50;
  end
  initial begin
    #2 k = 1;
    #2 `checkd(nk, 1);
  end

  initial begin
    #100;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
