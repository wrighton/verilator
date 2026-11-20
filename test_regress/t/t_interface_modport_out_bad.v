// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Obj;
  int v;
endclass

interface ifc;
  int x;
  Obj h;
  Obj harr[2];
  int seed;
  modport rd(input x, input h, input harr, input seed);
endinterface

class Cls;
  function void set(output int o);
    o = 5;
  endfunction
  function void set_h(output Obj o);
    o = new;
  endfunction
  function void inout_h(inout Obj o);
    o = new;
  endfunction
  function void ref_h(ref Obj o);
    o = new;
  endfunction
endclass

module sub (
    ifc.rd p
);
  Cls c;
  initial begin
    c = new;
    // Output argument of a class method call
    c.set(p.x);
    // Also for the handle itself, not just a member of its object
    c.set_h(p.h);
    c.inout_h(p.h);
    c.ref_h(p.h);
    // Only the selected handle is read; the index writes 'seed'
    c.set(p.harr[$random(p.seed) & 1].v);
  end
endmodule

module t;
  ifc i ();
  sub u (.p(i));
endmodule
