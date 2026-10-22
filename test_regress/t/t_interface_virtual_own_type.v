// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Interfaces declaring variables of their own virtual interface type

interface ifc;
  logic [6:0] r;
  modport mp(input r);
  function automatic bit same(virtual ifc o);
    virtual ifc v;
    virtual ifc.mp m;
    v = o;
    m = o;
    return v == o && m.r == r && v.r == o.r;
  endfunction
endinterface

// Two interfaces referencing each other's virtual interface type
interface ifa;
  logic [6:0] r;
  function automatic logic [6:0] get(virtual ifb o);
    return o.s;
  endfunction
endinterface

interface ifb;
  logic [6:0] s;
  function automatic logic [6:0] get(virtual ifa o);
    return o.r;
  endfunction
endinterface

class Cls;
  virtual ifc v;
endclass

module t;
  ifc i ();
  ifc j ();
  ifa a ();
  ifb b ();

  initial begin
    automatic Cls c = new;
    c.v = i;
    i.r = 7'h15;
    j.r = 7'h2a;
    a.r = 7'h4c;
    b.s = 7'h33;
    `checkh(i.same(i), 1'b1);
    `checkh(i.same(j), 1'b0);
    `checkh(c.v.same(i), 1'b1);
    `checkh(c.v.same(j), 1'b0);
    `checkh(a.get(b), 7'h33);
    `checkh(b.get(a), 7'h4c);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
