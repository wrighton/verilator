// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Parameterized class nested in a parameterized class
class Outer #(
    type T = int
);
  class Inner #(
      type U = int
  );
    U v;
    Inner #(U) next;
  endclass
  Inner #(T) h;
  Inner #(bit [6:0]) h7;
  function new();
    h = new;
    h.next = new;
    h7 = new;
  endfunction
endclass

// Parameterized class nested in a class with only value parameters, whose default
// specialization is copied before the others are made, including the UVM
// uvm_analysis_imp_decl form taking the enclosing class's own specialization
class Mon #(
    int A = 1,
    int B = 2
);
  typedef Mon #(A, B) this_t;
  class Imp #(
      type IMP = int,
      type X = int
  );
    IMP imp;
    X x;
    static function int xbits();
      return $bits(X);
    endfunction
  endclass
  Imp #(Mon #(A, B), bit [A:0]) h;
  Imp #(this_t) ht;
  Imp #(Mon) hb;
  Imp #(bit [A+B:0]) hv;
  function new();
    h = new;
    h.imp = this;
    ht = new;
    ht.imp = this;
    hb = new;
    hv = new;
  endfunction
  function int sum();
    return A + B;
  endfunction
  function int xbits();
    return Imp#(this_t, bit [A+B:0])::xbits();
  endfunction
endclass

// Parameterized class nested in a parameterized module
module sub #(
    type T = int
);
  class SubInner #(
      type U = int
  );
    U v;
  endclass
  SubInner #(T) h;
  initial begin
    h = new;
    h.v = '1;
  end
endmodule

module t;
  // Default specializations first, as they are copied differently
  sub s0 ();
  sub #(byte) s8 ();
  sub #(shortint) s16 ();

  initial begin
    automatic Outer o0 = new;
    automatic Outer #(byte) o8 = new;
    automatic Outer #(logic [14:0]) o15 = new;
    o8.h.v = '1;
    o8.h.next.v = 8'h12;
    o8.h7.v = '1;
    o15.h.v = '1;
    o0.h.next.v = '1;
    `checkd($bits(o0.h.next.v), 32);
    `checkd(o0.h.next.v, -1);
    `checkd($bits(o8.h.v), 8);
    `checkd(o8.h.v, -1);
    `checkd(o8.h.next.v, 8'h12);
    `checkd(o8.h7.v, 7'h7f);
    `checkd(o15.h.v, 15'h7fff);
    #1;
    `checkd(s0.h.v, -1);
    `checkd($bits(s0.h.v), 32);
    `checkd(s8.h.v, -1);
    `checkd(s16.h.v, -1);
    `checkd($bits(s16.h.v), 16);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  initial begin
    // Default specialization first, as it is copied
    automatic Mon m0 = new;
    automatic Mon #(3) m3 = new;
    automatic Mon #(4, 5) m45 = new;
    `checkd(m0.h.imp == m0, 1);
    `checkd(m3.h.imp == m3, 1);
    `checkd(m45.ht.imp == m45, 1);
    `checkd(m0.h.imp.sum(), 3);
    `checkd(m3.ht.imp.sum(), 5);
    `checkd(m45.h.imp.sum(), 9);
    `checkd($bits(m0.h.x), 2);
    `checkd($bits(m3.h.x), 4);
    `checkd($bits(m45.ht.x), 32);
    m0.hb.imp = m0;
    `checkd(m0.hb.imp.sum(), 3);
    `checkd($bits(m0.hv.imp), 4);
    `checkd($bits(m3.hv.imp), 6);
    `checkd($bits(m45.hv.imp), 10);
    `checkd(m45.xbits(), 10);
  end
endmodule
