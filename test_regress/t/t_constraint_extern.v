// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Packet;
  rand int one;
  rand int two;

  extern function void f();
  constraint cone;
  extern constraint ctwo;
  constraint cmissing;  // Ok per IEEE 1800-2023 18.5.1

endclass

constraint Packet::cone { one > 0 && one < 2; }

constraint Packet::ctwo { two > 1 && two < 3; }

function void Packet::f();
endfunction

package pkg;
  class Outer;
    rand int three;
    extern constraint cthree;
    class Inner;
      rand int four;
      extern constraint cfour;
    endclass
  endclass

  // Package-qualified class scope (IEEE 1800-2023 8.24)
  constraint pkg::Outer::cthree { three > 2 && three < 4; }

  constraint pkg::Outer::Inner::cfour { four > 3 && four < 5; }
endpackage

module t;

  Packet p;
  pkg::Outer o;
  pkg::Outer::Inner i;

  int v;

  initial begin
    p = new;
    v = p.randomize();
    if (v != 1) $stop;
    if (p.one != 1) $stop;
    if (p.two != 2) $stop;

    o = new;
    v = o.randomize();
    if (v != 1) $stop;
    if (o.three != 3) $stop;
    i = new;
    v = i.randomize();
    if (v != 1) $stop;
    if (i.four != 4) $stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
