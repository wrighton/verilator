// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  rand bit [7:0] x;
  constraint c {
    x dist {7'd2 := 1, [7'd5 : 7'd6] := 1, [9'd300 : 9'd400] :/ 1};
  }
endclass

module t;
  initial begin
    Cls c;
    c = new;
    void'(c.randomize());
  end
endmodule
