// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Foo;
  rand int x;
endclass

class Cls;
  rand int assocarr[string];
  rand int dynarr[][];
  rand int q[$];
  rand Cls cls;
  rand int i;
  rand Foo foo;
  rand int y;
  int st;
  constraint dynsize {
    dynarr.size < 20;
    dynarr.size > 0;
    dynarr[1].size < 10;
  }
  constraint statedep { i < st + 2; }
  constraint global_constraint {
    foo.x < y;
  }
endclass

class Elem;
  rand bit [3:0] y;
endclass

class Calls;
  rand Elem q[$];
  // A field of a call result in a constraint is only ignored
  constraint c_ignored { soft q.unique()[0].y == 4'h5; }
endclass

// IEEE 1800-2023 18.5.12 example
class SList;
  rand int n;
  rand SList next;
  constraint sort { if (next != null) n < next.n; }
endclass

module t;
  Cls obj;
  SList head;
  Calls calls;
  int res;

  initial begin
    obj = new;
    obj.foo = new;
    res = obj.randomize();
    res = obj.randomize() with { dynarr.size > 2; };
    head = new;
    head.next = new;
    res = head.randomize();
    calls = new;
    res = calls.randomize();
  end
endmodule
