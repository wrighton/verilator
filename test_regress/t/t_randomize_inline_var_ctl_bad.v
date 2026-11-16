// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Foo;
  int x;

  function void test;
    int y;
    void'(randomize(y));
  endfunction
endclass

class Bar;
  int y;
  Foo f = new;

  function void test;
    void'(f.randomize(f));
  endfunction
endclass

module t;
  initial begin
    automatic Foo foo = new;
    automatic Foo qux = new;
    automatic Bar bar = new;
    automatic int x;
    automatic Foo foos[2];
    void'(foo.randomize(x, foo.x, null, qux.x, bar.y, 0 + 1, x ** 2));
    // The target object itself is not one of its properties
    void'(foo.randomize(foo));
    void'(bar.f.randomize(bar.f));
    void'(foos[1].randomize(foos[1]));
  end
endmodule
