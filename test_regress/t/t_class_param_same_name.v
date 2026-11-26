// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Parameterized classes of the same name in different scopes are different classes

package PkgBase;
  class Agent #(
      int W = 8
  );
    function int width();
      return W;
    endfunction
  endclass
endpackage

package PkgExt;
  class Agent #(
      int W = 8
  ) extends PkgBase::Agent #(W);
    function int twice();
      return 2 * width();
    endfunction
  endclass
endpackage

class OuterA;
  class Inner #(
      type T = int
  );
    T v;
    int a_only;
  endclass
  Inner #(byte) h;
endclass

class OuterB;
  class Inner #(
      type T = int
  );
    T v;
    int b_only;
  endclass
  Inner #(byte) h;
endclass

// A class in each specialization of a module, using its parameter
module ModClass #(
    parameter int Q = 1
);
  class MC #(
      int R = 3
  );
    static function int m();
      return R + Q;
    endfunction
  endclass
  class MT #(
      type T = logic [Q-1:0]
  );
    static function int w();
      return $bits(T);
    endfunction
  endclass
  int r;
  int t;
  initial begin
    r = MC#(4)::m();
    t = MT#(logic [Q+1:0])::w();
  end
endmodule

module t;
  ModClass #(.Q(10)) u_q10 ();
  ModClass #(.Q(20)) u_q20 ();
  // A class in each generate loop iteration, using its genvar
  for (genvar g = 0; g < 2; ++g) begin : gen
    class GC #(
        int S = 0
    );
      static function int s();
        return S + g;
      endfunction
    endclass
    // With only default values, depending on the genvar
    class GD #(
        int S = g * 3
    );
      static function int s();
        return S;
      endfunction
    endclass
    class GT #(
        type T = logic [g:0]
    );
      static function int w();
        return $bits(T);
      endfunction
    endclass
    int z;
    int d;
    int w;
    initial begin
      z = GC#(30)::s();
      d = GD#()::s();
      w = GT#()::w();
    end
  end
  initial begin
    automatic PkgExt::Agent #(16) ext = new;
    automatic PkgBase::Agent #(16) base = ext;
    automatic PkgBase::Agent #(16) base2 = new;
    automatic OuterA oa = new;
    automatic OuterB ob = new;
    #1;
    `checkd(u_q10.r, 14);
    `checkd(u_q20.r, 24);
    `checkd(gen[0].z, 30);
    `checkd(gen[1].z, 31);
    `checkd(u_q10.t, 12);
    `checkd(u_q20.t, 22);
    `checkd(gen[0].d, 0);
    `checkd(gen[1].d, 3);
    `checkd(gen[0].w, 1);
    `checkd(gen[1].w, 2);
    `checkd(ext.twice(), 32);
    `checkd(base.width(), 16);
    `checkd(base2.width(), 16);
    oa.h = new;
    ob.h = new;
    oa.h.a_only = 1;
    ob.h.b_only = 2;
    `checkd(oa.h.a_only, 1);
    `checkd(ob.h.b_only, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
