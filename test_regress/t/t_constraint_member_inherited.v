// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Sub;
  rand bit [7:0] x;
endclass

// Randomized itself, and lowered before the derived class
class Base;
  rand Sub s;
  rand bit [7:0] y;
  function new;
    s = new;
  endfunction
endclass

// Constrains a member object through an inherited handle
class Derived extends Base;
  constraint c {
    s.x < 5;
    y == s.x + 1;
  }
endclass

// Not randomized itself; its constraint is shared by two derived classes
class Shared;
  rand Sub s;
  function new;
    s = new;
  endfunction
  constraint c {s.x inside {[10 : 12]};}
endclass

class SharedA extends Shared;
endclass

class SharedB extends Shared;
endclass

module t;
  task automatic test_inherited();
    automatic Base b = new;
    automatic Derived d = new;
    automatic int ok;
    repeat (10) begin
      ok = b.randomize();
      `checkd(ok, 1);
      d.s.x = 200;
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.s.x < 5, 1'b1);
      `checkd(d.y, d.s.x + 1);
    end
  endtask

  task automatic test_shared();
    automatic SharedA sa = new;
    automatic SharedB sb = new;
    automatic int ok;
    repeat (10) begin
      sa.s.x = 200;
      sb.s.x = 200;
      ok = sa.randomize();
      `checkd(ok, 1);
      ok = sb.randomize();
      `checkd(ok, 1);
      `checkd(sa.s.x inside {[10 : 12]}, 1'b1);
      `checkd(sb.s.x inside {[10 : 12]}, 1'b1);
    end
  endtask

  initial begin
    test_inherited();
    test_shared();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
