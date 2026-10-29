// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Inline constraint reading a caller's base class member that the caller's
// class shadows

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  int lim = 7;
  int blim = 9;
endclass

class Target;
  rand int x;
  rand int y;
endclass

class Mid extends Base;
  int lim = 5;
endclass

class Sub extends Mid;
  int blim = 4;
  function int f(Target other);
    return other.randomize() with { x == super.lim; y == super.blim; };
  endfunction
  function int g(Target other);
    return other.randomize() with { x == lim; y == blim; };
  endfunction
endclass

module t;
  initial begin
    automatic Target tg = new;
    automatic Sub s = new;
    `checkd(s.f(tg), 1);
    `checkd(tg.x, 5);
    `checkd(tg.y, 9);
    `checkd(s.g(tg), 1);
    `checkd(tg.x, 5);
    `checkd(tg.y, 4);
    s.lim = 15;
    `checkd(s.f(tg), 1);
    `checkd(tg.x, 15);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
