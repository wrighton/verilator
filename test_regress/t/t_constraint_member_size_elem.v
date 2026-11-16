// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constraints on a member array of an element of an object array, where another class
// sizes the same member array of a member object, are not size gated

class ElemLeaf;
  rand int q[$];
  function new();
    q = '{1, 2};
  endfunction
endclass

class ElemSizer;
  rand ElemLeaf sub;
  constraint c_size {sub.q.size() == 3;}
  function new();
    sub = new;
  endfunction
endclass

class ElemUser;
  rand ElemLeaf objs[2];
  constraint c_sel {objs[0].q[1] == 5;}
  constraint c_in {7 inside {objs[1].q};}
  function new();
    foreach (objs[i]) objs[i] = new;
  endfunction
endclass

module t;
  initial begin
    automatic ElemSizer sizer = new;
    automatic ElemUser user = new;
    int ok;
    // Compiled only: the element constraints are lowered next to the size proxy of q
    ok = sizer.randomize();
    ok = user.randomize();
    $finish;
  end
endmodule
