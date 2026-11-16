// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constraints selecting through rand members of the containing class's type
class Node;
  rand int v;
  rand Node next;
  constraint c1 {v < 9;}
  constraint c2 {next.v > v;}
endclass

// The same reached from a container
class List;
  rand Node head;
  constraint c {head.v < 5;}
endclass

// A member of a class derived from the containing class
typedef class DNode;
class BNode;
  rand int v;
  rand DNode d;
  constraint c {d.v > 0;}
endclass

class DNode extends BNode;
endclass

// A member of the containing class's type, deeper in a container
class Inner;
  rand int v;
  rand Inner next;
  constraint c {next.v > v;}
endclass

class Mid;
  rand Inner inr;
endclass

class Outer;
  rand Mid m;
  constraint c {m.inr.v < 5;}
endclass

module t;
  initial begin
    automatic Node n = new;
    automatic List l = new;
    automatic BNode b = new;
    automatic Outer o = new;
    void'(n.randomize());
    void'(l.randomize());
    void'(b.randomize());
    void'(o.randomize());
  end
endmodule
