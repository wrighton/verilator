// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An access through a virtual interface or class handle may be to a variable
// also referenced directly, so values must not be propagated across it

interface ifc (
    output logic o
);
  logic s;
endinterface

interface outer (
    output logic o
);
  ifc sub (o);
endinterface

class Cls;
  int m;
  function void write(Cls h);
    m = 0;
    h.m = 1;
    `checkd(m, 1);
    m = 0;
    if (h != null) h.m = 1;
    `checkd(m, 1);
  endfunction
  function int read(Cls h);
    int x;
    m = 5;
    x = h.m;
    m = 2;
    return x;
  endfunction
endclass

module t;
  logic o, so;
  ifc i (o);
  outer u (so);
  virtual ifc vi;
  Cls c;

  initial begin
    i.s = 0;
    vi = i;
    vi.s = 1;
    `checkd(i.s, 1);
    i.o = 0;
    vi.o = 1;
    `checkd(i.o, 1);
    i.s = 0;
    if (vi != null) vi.s = 1;
    `checkd(i.s, 1);
    u.sub.o = 0;
    vi = u.sub;
    vi.o = 1;
    `checkd(u.sub.o, 1);
    c = new;
    c.write(c);
    `checkd(c.read(c), 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
