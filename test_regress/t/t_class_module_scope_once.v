// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package P;
  int n;
  function int next();
    n++;
    return n;
  endfunction
endpackage

// A class declared in a module or interface with several instances
interface ifc;
  class Proxy;
    static int s_base = 10;
    int m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15;
    function new(int v);
      m0 = v;
      m15 = s_base + v;
    endfunction
    static function int base();
      return s_base;
    endfunction
  endclass
  Proxy p;
endinterface

module sub;
  class Cls;
    static int s_base = 20;
    int id = P::next();  // Once per object
    int m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15;
    function new(int v);
      m0 = v;
      m15 = s_base + v;
    endfunction
    static function int base();
      return s_base;
    endfunction
  endclass
  Cls c;
endmodule

module t;
  ifc i[8] ();
  sub s[8] ();

  int v;

  initial begin
`ifdef VERILATOR
    v = $c32("3");
`else
    v = 3;
`endif
    i[2].p = new(v);
    s[5].c = new(v + 1);
    `checkd(i[2].p.m0, 3);
    `checkd(i[2].p.m15, 13);
    `checkd(i[2].p.base(), 10);
    `checkd(s[5].c.m0, 4);
    `checkd(s[5].c.m15, 24);
    `checkd(s[5].c.base(), 20);
    `checkd(s[5].c.id, 1);
    `checkd(P::n, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
