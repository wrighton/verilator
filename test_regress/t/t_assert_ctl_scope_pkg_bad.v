// DESCRIPTION: Verilator: Assertion control scope named from a class in a package
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  class P;
    function void off();
      // Package items cannot refer to the design hierarchy (IEEE 1800-2023 26.2)
      $assertoff(0, sib);
    endfunction
  endclass
endpackage

module leaf;
  initial check : assert (1'b1);
endmodule

module t;
  leaf sib ();
  initial begin
    automatic pkg::P p = new;
    p.off();
  end
endmodule
