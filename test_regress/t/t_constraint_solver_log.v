// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Packet;
  rand int one;
  constraint a {one > 0 && one < 2;}
endclass

// Its constraint and value are longer than a pipe buffer
class Long;
  rand bit [19999:0] w;
  constraint c {w != 0;}
endclass

module t;

  Packet p;
  Long l;

  int v;

  initial begin
    p = new;
    v = p.randomize();
    if (v != 1) $stop;
    if (p.one != 1) $stop;
    l = new;
    v = l.randomize();
    if (v != 1) $stop;
    if (l.w == 0) $stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
