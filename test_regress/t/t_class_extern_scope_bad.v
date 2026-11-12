// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  class Cls;
    int x;
  endclass

  function pkg::new();  // <--- Error: scope is a package
    super.new();
    x = 1;
  endfunction

  function int pkg::Cls::NoSub::f();  // <--- Error: NoSub not found
    return x;
  endfunction

  function int nosuch::Cls::f();  // <--- Error: nosuch not found
    return x;
  endfunction

  constraint pkg::cx { 1; }  // <--- Error: scope is a package
endpackage

module t;
endmodule
