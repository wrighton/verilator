// DESCRIPTION: Verilator: Upward assertion control scope from a class in a module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
  initial check : assert (1'b1);
endmodule

module par;
  leaf sib ();
  class C;
    function void off();
      $assertoff(0, sib);
    endfunction
  endclass
  initial begin
    automatic C c = new;
    c.off();
  end
endmodule

module t;
  par p0 ();
  par p1 ();
endmodule
