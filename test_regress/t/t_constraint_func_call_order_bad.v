// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 18.5.11: function arguments are solved before the constraint calling the
// function, so a circular dependency is an error

class Funcs;
  static function bit [7:0] f(bit [7:0] d);
    if (d[0]) return d >> 1;
    return d + 8'd3;
  endfunction
endclass

class Cls;
  rand bit [7:0] x;
  rand bit [7:0] y;
  constraint c_x {x == Funcs::f(y);}
  constraint c_y {y == Funcs::f(x);}
endclass

module t;
  initial begin
    automatic Cls c = new;
    int randomize_result;
    randomize_result = c.randomize();
  end
endmodule
