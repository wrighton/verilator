// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 BRDR LIFE
// SPDX-License-Identifier: CC0-1.0

class E;
  rand bit [3:0] f[4];
endclass

class C;
  // The array of an object of an array
  rand E objs[2];
  constraint elem_member {unique {objs[0].f};}
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
