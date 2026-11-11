// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Elem;
  rand bit [3:0] y;
endclass

class C;
  rand Elem q[$];
  function Elem first();
    return q[0];
  endfunction
  // IEEE 1800-2023 18.5.13.2, A.1.10: the operand of 'disable soft' must be a
  // constraint_primary, not a field of the result of a method or function call.
  constraint c_bad {
    disable soft q.unique()[0].y;
    disable soft first().y;
  }
  // A field of a call result in an ordinary constraint is only ignored
  constraint c_ignored { soft q.unique()[0].y == 4'h5; }
  function new();
    Elem e = new;
    q.push_back(e);
  endfunction
endclass

module t;
  C c;
  initial begin
    c = new;
    void'(c.randomize());
    $stop;
  end
endmodule
