// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Foo;
  rand int zero;
  int two;
endclass

class Bar extends Foo;
  rand int one;
  static int three;

  function void test;
    logic [1:0] ok = '0;
    zero = 100;
    one = 200;
    two = 300;
    three = 400;
    for (int i = 0; i < 20; i++) begin
      void'(randomize(one));
      if (zero != 100) $stop;
      if (one != 200) ok[0] = 1;
      if (two != 300) $stop;
      if (three != 400) $stop;
    end
    if (!ok[0]) $stop;
    ok = '0;

    if (zero.rand_mode() != 1) $stop;
    if (one.rand_mode() != 1) $stop;
    zero = 500;
    one = 600;
    two = 700;
    three = 800;
    one.rand_mode(0);
    for (int i = 0; i < 20; i++) begin
      void'(randomize(one, two));
      if (zero != 500) $stop;
      if (one != 600) ok[0] = 1;
      if (two != 700) ok[1] = 1;
      if (three != 800) $stop;
    end
    if (one.rand_mode() != 0) $stop;
    one.rand_mode(1);
    if (ok != 'b11) $stop;
  endfunction
endclass

class Baz;
  int four;
  Bar bar;

  function new;
    bar = new;
  endfunction
endclass

class Qux;
  Baz baz;

  function new;
    baz = new;
  endfunction
endclass

class Boo extends Bar;
  rand int five;
endclass

class Item;
  rand int x;
  rand int y;
  int w;

  function void set;
    x = 1;
    y = 2;
    w = 3;
  endfunction

  function bit [2:0] changed;
    return {w != 3, y != 2, x != 1};
  endfunction
endclass

class Holder;
  rand int r;
  Item tr = new;

  function void randomize_w;
    void'(tr.randomize(w));
  endfunction
endclass

class HolderExt extends Holder;
  function void randomize_this_y;
    void'(this.tr.randomize(y));
  endfunction

  function void randomize_super_x;
    void'(super.tr.randomize(x));
  endfunction
endclass

class Outer;
  rand int r;
  Holder b = new;
endclass

module t;
  int idx_calls;
  function automatic int idx_count(int i);
    idx_calls++;
    return i;
  endfunction

  // randomize() with arguments on a target selected through members or an array
  task automatic test_selected_target;
    automatic Holder b = new;
    automatic HolderExt d = new;
    automatic Outer a = new;
    automatic Item h[3];
    automatic int idx = 1;
    automatic bit [2:0] changed[10];
    automatic int randomize_result;
    foreach (h[k]) h[k] = new;
    for (int i = 0; i < 20; i++) begin
      b.tr.set();
      randomize_result = b.tr.randomize(x);
      `checkd(randomize_result, 1);
      changed[0] |= b.tr.changed();
      d.tr.set();
      randomize_result = d.tr.randomize(x);
      `checkd(randomize_result, 1);
      changed[1] |= d.tr.changed();
      d.tr.set();
      d.randomize_this_y();
      d.randomize_super_x();
      changed[2] |= d.tr.changed();
      a.b.tr.set();
      randomize_result = a.b.tr.randomize(x, y);
      `checkd(randomize_result, 1);
      changed[3] |= a.b.tr.changed();
      foreach (h[k]) h[k].set();
      randomize_result = h[1].randomize(w);
      `checkd(randomize_result, 1);
      changed[4] |= h[0].changed() | h[2].changed();
      changed[5] |= h[1].changed();
      h[idx].set();
      randomize_result = h[idx].randomize(y) with {y > 2;};
      `checkd(randomize_result, 1);
      if (h[idx].y <= 2) `stop;
      changed[6] |= h[idx].changed();
      // A null argument is not an argument list, so the target may have side effects
      randomize_result = h[idx_count(2)].randomize(null);
      `checkd(randomize_result, 1);
      // Randomizing a member of the target does not make the target rand
      b.randomize_w();
      b.tr.set();
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      changed[7] |= b.tr.changed();
      a.b.tr.set();
      randomize_result = a.randomize();
      `checkd(randomize_result, 1);
      randomize_result = a.b.randomize();
      `checkd(randomize_result, 1);
      changed[8] |= a.b.tr.changed();
      b.tr.set();
      b.randomize_w();
      changed[9] |= b.tr.changed();
    end
    `checkd(changed[0], 3'b001);
    `checkd(changed[1], 3'b001);
    `checkd(changed[2], 3'b011);
    `checkd(changed[3], 3'b011);
    `checkd(changed[4], 3'b000);
    `checkd(changed[5], 3'b100);
    `checkd(changed[6], 3'b010);
    `checkd(changed[7], 3'b000);
    `checkd(changed[8], 3'b000);
    `checkd(changed[9], 3'b100);
  endtask

  initial begin
    automatic Boo boo = new;
    automatic Bar bar = boo;
    automatic Qux qux = new;
    automatic logic [2:0] ok = '0;

    bar.test;

    bar.zero = 1000;
    bar.one = 2000;
    bar.two = 3000;
    bar.three = 4000;
    boo.five = 999999;
    for (int i = 0; i < 20; i++) begin
      automatic int res = bar.randomize(two);
      if (boo.five != 999999) $stop;
    end

    bar.zero = 1000;
    bar.one = 2000;
    bar.two = 3000;
    bar.three = 4000;
    boo.five = 999999;
    for (int i = 0; i < 20; i++) begin
      automatic int res = bar.randomize(two) with {two > 3000 && two < 4000;};
      if (bar.zero != 1000) $stop;
      if (bar.one != 2000) $stop;
      if (!(bar.two > 3000 && bar.two < 4000)) $stop;
      if (bar.three != 4000) $stop;
      if (boo.five != 999999) $stop;
    end

    qux.baz.bar.zero = 5000;
    qux.baz.bar.one = 6000;
    qux.baz.bar.two = 7000;
    qux.baz.bar.three = 8000;
    qux.baz.four = 9000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz));
      if (qux.baz.bar.zero != 5000) $stop;
      if (qux.baz.bar.one != 6000) $stop;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) $stop;
    end
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.bar));
      if (qux.baz.bar.zero != 5000) ok[0] = 1;
      if (qux.baz.bar.one != 6000) ok[1] = 1;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) $stop;
    end
    if (!ok[0]) $stop;
    if (!ok[1]) $stop;
    ok = '0;
    qux.baz.bar.zero = 10000;
    qux.baz.bar.one = 20000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.four));
      if (qux.baz.bar.zero != 10000) $stop;
      if (qux.baz.bar.one != 20000) $stop;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) ok[0] = 1;
    end
    if (!ok[0]) $stop;
    ok = '0;
    qux.baz.four = 30000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.bar, qux.baz.bar.one, baz.four));
      if (qux.baz.bar.zero != 10000) ok[0] = 1;
      if (qux.baz.bar.one != 20000) ok[1] = 1;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 30000) ok[2] = 1;
    end
    if (ok != 'b111) $stop;

    test_selected_target();

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
