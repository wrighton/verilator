// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

`define check_rand(cl, field, cond) \
begin \
  automatic longint prev_result; \
  automatic int ok; \
  if (!bit'(cl.randomize())) $stop; \
  prev_result = longint'(field); \
  if (!(cond)) $stop; \
  repeat(9) begin \
    longint result; \
    if (!bit'(cl.randomize())) $stop; \
    result = longint'(field); \
    if (!(cond)) $stop; \
    if (result != prev_result) ok = 1; \
    prev_result = result; \
  end \
  if (ok != 1) $stop; \
end

class Foo;
  rand int q[$];
  rand int q2[$][$];
  int x = 1;
  constraint c {
    q.size() == 15;
    q2.size() == 10;
  }
endclass

class Bar;
  rand int q[$];
  rand int min_size;
  rand int q2[$];
  constraint c {
    min_size > 2;
    q.size() >= min_size;
    q.size() < 10;
  };
  constraint c2 {
    q2.size() < 7;
  }
endclass

class Baz;
  rand Foo foo_arr[];
  constraint c_foo {
    foo_arr.size == 7;
  }
endclass

class DynSized;
  rand int d[];
  rand int q[$];
  rand bit [2:0] x;
  constraint c {
    d.size() == 4;
    q.size() == 3;
  }
endclass

module t;
  // randomize() with on objects never plainly randomized applies the class size constraints
  initial begin
    automatic Foo foo = new;
    automatic Foo foo_elem = new;
    automatic Bar bar = new;
    automatic DynSized dyn = new;
    if (foo.randomize() with { q.size() > 0; } != 1) $stop;
    if (foo.q.size() != 15) $stop;
    if (foo.q2.size() != 10) $stop;
    // Element constraint only in the with-block
    if (foo_elem.randomize() with { foreach (q[i]) q[i] inside {[1:4]}; } != 1) $stop;
    if (foo_elem.q.size() != 15) $stop;
    foreach (foo_elem.q[i]) if (foo_elem.q[i] < 1 || foo_elem.q[i] > 4) $stop;
    if (dyn.randomize() with { x == 5; } != 1) $stop;
    if (dyn.d.size() != 4 || dyn.q.size() != 3 || dyn.x != 5) $stop;
    // Elements added by the resize are randomized
    if (dyn.d.or() == 0 || dyn.q.or() == 0) $stop;
    repeat (10) begin
      if (bar.randomize() with { min_size == 5; } != 1) $stop;
      if (bar.min_size != 5) $stop;
      if (bar.q.size() < 5 || bar.q.size() > 9) $stop;
      if (bar.q2.size() > 6) $stop;
    end
  end

  initial begin
    automatic Foo foo = new;
    automatic Bar bar = new;
    automatic Baz baz = new;

    void'(foo.randomize());
    if (foo.q.size() != 15) $stop;
    if (foo.q2.size() != 10) $stop;

    `check_rand(bar, bar.q.size(), bar.q.size() > 2 && bar.q.size() < 10);
    `check_rand(bar, bar.q2.size(), bar.q2.size() < 7);

    baz.foo_arr = new[4];
    for (int i = 0; i < 4; i++) baz.foo_arr[i] = new;
    baz.foo_arr[2].x = 2;
    void'(baz.randomize());

    if (baz.foo_arr.size() != 7) $stop;
    for (int i = 0; i < 4; i++) if (baz.foo_arr[i] == null) $stop;
    for (int i = 4; i < 7; i++) if (baz.foo_arr[i] != null) $stop;
    if (baz.foo_arr[2].x != 2) $stop;
    `check_rand(baz, baz.foo_arr[1].q[5], 1'b1);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
