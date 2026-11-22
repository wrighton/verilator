// DESCRIPTION: Verilator: Assertion control scope from a class in an interface instantiated twice
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface leafi;
  initial check : assert (1'b1);
endinterface

interface ifc;
  leafi sib ();
  class C;
    function void off();
      $assertoff(0, sib);
    endfunction
  endclass
  initial begin
    automatic C c = new;
    c.off();
  end
endinterface

module t;
  ifc i0 ();
  ifc i1 ();
endmodule
