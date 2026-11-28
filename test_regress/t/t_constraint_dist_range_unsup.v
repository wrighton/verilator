// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C;
  rand bit [99:0] z;
  bit [99:0] lo = 5;
  constraint c_z {z dist {[lo : 20] :/ 1};}
endclass

class Oversize;
  rand bit [64:0] w;
  constraint c_w {w dist {[65'd0 : 65'h10000000000000000] :/ 1};}
endclass

module t;
  initial begin
    automatic C c = new;
    automatic Oversize o = new;
    void'(c.randomize());
    void'(o.randomize());
  end
endmodule
