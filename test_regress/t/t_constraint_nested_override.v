// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A globally constrained member whose class overrides a constraint of its base class, so both
// have a constraint of the name to clone into the class randomizing it. Only the override
// applies (IEEE 1800-2023 18.5.2), as t_constraint_nested_inherit checks.
class Base;
  rand bit [7:0] x;
  constraint c {x > 1;}
endclass

class Derived extends Base;
  constraint c {x < 100;}
endclass

class Holder;
  rand Derived d;
  constraint h {d.x != 5;}
endclass

module t;
  Holder h = new;
  initial begin
    h.d = new;
    repeat (10) begin
      if (h.randomize() == 0) $stop;
      if (h.d.x == 5) $stop;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
