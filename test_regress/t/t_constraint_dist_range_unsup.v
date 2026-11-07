// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C;
  rand bit [99:0] y;
  rand bit signed [99:0] sy;
  constraint c_y {y dist {[5 : $] :/ 1};}
  constraint c_sy {sy dist {[-100'sd3 : 100'sd3] :/ 1};}
  rand bit [99:0] z;
  bit [99:0] lo = 5;
  constraint c_z {z dist {[lo : 20] :/ 1};}
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
