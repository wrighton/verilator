// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Cls;
  static int y;
  static function bit bar;
    y += 1;
    return bit'(y % 2);
  endfunction
endclass

module t;
  int x;

  function bit foo;
    x += 1;
    return bit'(x % 2);
  endfunction

  always @(posedge foo());

  // Converting Cls::bar first must keep it impure
  bit b;
  initial b = Cls::bar();
  always @(posedge Cls::bar());

endmodule
