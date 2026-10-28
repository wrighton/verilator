// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Interface classes used without going through a forward typedef (IEEE 1800-2023 8.26.4)

// Package ipkg, with a forward typedef and the declaration of iclass, is in a later file
package epkg;
  interface class cclass2 extends ipkg::iclass;
    pure virtual function int doit2();
  endclass

  class cclass implements cclass2;
    virtual function int doit();
      return 1;
    endfunction
    virtual function int doit2();
      return 2;
    endfunction
  endclass
endpackage

// Implemented before its forward typedef
class ClsEarly implements IfLate;
  virtual function int f();
    return 3;
  endfunction
endclass

typedef interface class IfLate;

interface class IfLate;
  pure virtual function int f();
endclass

module t;
  initial begin
    automatic epkg::cclass c = new;
    automatic ClsEarly e = new;
    if (c.doit() != 1) $stop;
    if (c.doit2() != 2) $stop;
    if (e.f() != 3) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
