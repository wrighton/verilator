// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Sub;
  rand int arr[];

  function new();
    arr = new[10];
  endfunction
endclass

class Indep;
  rand int val;
  Sub s[];

  function new();
    s = new[10];
  endfunction
endclass

class Holder;
  rand Sub s[2];

  function new();
    foreach (s[i]) s[i] = new;
  endfunction
endclass

class Cls;
  function int randomize_gpr(Indep i);
    return (i.randomize() with {
      if (i.s[0].arr.size > 0) {
        i.val inside {i.s[0].arr};
      }
    });
  endfunction
endclass

class Leaf;
  rand int v;
endclass

class Node;
  rand Leaf leaf;

  function new();
    leaf = new;
  endfunction
endclass

// A field of an object of the last element or of a method result's element
class NodeQueue;
  rand Node q[$];
  constraint c_state {
    q[$].leaf.v < 5;
    q.unique()[0].leaf.v < 5;
  }
endclass

module t;
  Cls c;
  Indep i;

  initial begin
    c = new;
    i = new;

    c.randomize_gpr(i);
  end

  initial begin
    automatic Holder h = new;
    void'(h.randomize() with {s[0].arr.size() == 2;});
  end

  initial begin
    automatic NodeQueue n = new;
    void'(n.randomize());
  end
endmodule
