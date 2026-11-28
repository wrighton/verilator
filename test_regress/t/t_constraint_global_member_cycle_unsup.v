// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A rand member of its own class's type, reached through another class, of a class also
// randomized alone

class Self;
  rand int v;
  rand Self me;
  constraint c_s {v < 10;}
endclass

class Mid;
  rand Self s;
  constraint c_m {s.v > 2;}
endclass

class Top;
  rand Mid m;
endclass

module t;
  initial begin
    automatic Self alone = new;
    automatic Top top = new;
    automatic int ok;
    ok = alone.randomize();
    ok = top.randomize();
  end
endmodule
