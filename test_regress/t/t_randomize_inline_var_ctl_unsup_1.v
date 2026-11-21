// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Foo;
  int x;

  static function Foo get;
    Foo foo = new;
    return foo;
  endfunction
endclass

class Sub;
  int y;
endclass

class Bar;
  Sub s[2];
endclass

module t;
  initial begin
    automatic Foo foo = Foo::get();
    automatic Foo foos[] = new[1];
    void'(foo.randomize(Foo::get().x));
    void'(foo.randomize(foos[0].x));
    void'(foo.randomize(null));
  end

  // Member of an array element that is not the target
  initial begin
    automatic Bar bar = new;
    void'(bar.randomize(s[0].y));
  end

  // Each argument repeats the target, which would evaluate it more than once
  int cnt;
  function automatic int next_idx;
    cnt++;
    return cnt;
  endfunction
  initial begin
    automatic Foo foos[3];
    automatic int i;
    void'(foos[next_idx()].randomize(x));
    void'(foos[i++].randomize(x));
  end

  // Selects other than of a fixed-size array element
  initial begin
    automatic Foo foos[2];
    automatic Foo q[$];
    void'(foos[0].randomize(foos[1].x));
    void'(q[0].randomize(x));
  end
endmodule
