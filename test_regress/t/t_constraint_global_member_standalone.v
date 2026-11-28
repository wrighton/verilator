// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The constraints of a rand member object are solved with its container's, also when the
// member's class is randomized alone elsewhere, before or after in the source, with or without
// arguments (IEEE 1800-2023 18.5.9)

class Inner;
  rand bit [6:0] x;
  rand bit [3:0] s;
  constraint c_i {x inside {[10 : 20]};}
endclass

class Outer;
  rand Inner in;
  constraint c_o {in.x != 7'd13;}
  function new();
    in = new;
  endfunction
endclass

// Reached through two member objects
class Mid;
  rand Inner in;
  constraint c_m {in.x != 7'd14;}
  function new();
    in = new;
  endfunction
endclass

class Top;
  rand Mid m;
  constraint c_t {m.in.x != 7'd15;}
  function new();
    m = new;
  endfunction
endclass

// Randomized alone only after the container
class Late;
  rand bit [6:0] y;
  constraint c_l {y inside {[30 : 40]};}
endclass

class LateOuter;
  rand Late l;
  constraint c_lo {l.y != 7'd33;}
  function new();
    l = new;
  endfunction
endclass

module t;
  initial begin
    automatic Inner alone = new;
    automatic Mid aloneMid = new;
    automatic Outer o = new;
    automatic Top tp = new;
    automatic LateOuter lo = new;
    automatic Late aloneLate = new;
    automatic int ok;
    // Alone first, with and without arguments
    ok = alone.randomize();
    `checkd(ok, 1);
    alone.x = 7'd12;
    ok = alone.randomize(s);
    `checkd(ok, 1);
    ok = aloneMid.randomize();
    `checkd(ok, 1);
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.in.x inside {[10 : 20]}, 1'b1);
      `checkd(o.in.x != 7'd13, 1'b1);
      ok = tp.randomize();
      `checkd(ok, 1);
      `checkd(tp.m.in.x inside {[10 : 20]}, 1'b1);
      `checkd(tp.m.in.x != 7'd14 && tp.m.in.x != 7'd15, 1'b1);
      ok = lo.randomize();
      `checkd(ok, 1);
      `checkd(lo.l.y inside {[30 : 40]}, 1'b1);
      `checkd(lo.l.y != 7'd33, 1'b1);
    end
    ok = aloneLate.randomize();
    `checkd(ok, 1);
    `checkd(aloneLate.y inside {[30 : 40]}, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
