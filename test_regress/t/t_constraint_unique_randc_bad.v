// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Sub;
  randc bit [1:0] rc;
endclass

class C;
  randc bit [1:0] r;
  randc bit [1:0] ra[2];
  rand bit [1:0] x, y;
  rand bit [1:0] arr[3];
  rand Sub s;
  randc bit [1:0] i;
  rand bit [1:0] q[$];

  constraint scalar_c {unique {x, r, y};}
  constraint array_c {unique {arr, ra};}
  constraint element_c {unique {x, ra[1]};}
  constraint member_c {unique {s.rc, y};}
  // A randc index is not a member
  constraint index_c {unique {arr[i], y};}
  constraint queue_c {unique {q[0], x};}

  function new;
    s = new;
  endfunction
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
