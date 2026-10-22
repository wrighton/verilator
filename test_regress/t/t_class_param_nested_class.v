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
  sub #(byte) s8 ();
  sub #(shortint) s16 ();

  initial begin
    automatic Outer #(byte) o8 = new;
    automatic Outer #(logic [14:0]) o15 = new;
    o8.h.v = '1;
    o8.h.next.v = 8'h12;
    o8.h7.v = '1;
    o15.h.v = '1;
    `checkd($bits(o8.h.v), 8);
    `checkd(o8.h.v, -1);
    `checkd(o8.h.next.v, 8'h12);
    `checkd(o8.h7.v, 7'h7f);
    `checkd(o15.h.v, 15'h7fff);
    #1;
    `checkd(s8.h.v, -1);
    `checkd(s16.h.v, -1);
    `checkd($bits(s16.h.v), 16);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
