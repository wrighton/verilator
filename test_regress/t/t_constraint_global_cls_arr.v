// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Foo;
  rand int abcd;
endclass

class Bar;
  rand Foo foo_arr[];

  function new();
    foo_arr = new[12];
    foreach (foo_arr[i]) foo_arr[i] = new;
  endfunction

  constraint c {
    foo_arr.size() == 10;
    foreach (foo_arr[i]) foo_arr[i].abcd < 8;
  }
endclass

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class RandModeBase;
  rand bit [6:0] a;
endclass

class RandModeItem extends RandModeBase;
  rand bit b;
endclass

class RandModeArray;
  rand RandModeItem arr[];
  rand bit dis;
  bit [6:0] expected_a;

  constraint c {
    foreach (arr[i]) {
      dis -> arr[i].b;
      if (i != 1) arr[i].b == 1;
      arr[i].a == expected_a;
    }
  }

  function new();
    arr = new[3];
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

class RandModeDerivedOwner extends RandModeArray;
  rand bit marker;
  constraint d { marker == dis; }
endclass

class RandModeSkippedBase;
  rand RandModeItem arr[];
  rand bit dis;
  constraint c { foreach (arr[i]) dis -> arr[i].b; }
  function new();
    arr = new[3];
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

class RandModeSkippedMiddle extends RandModeSkippedBase;
  rand RandModeItem other[];
  constraint e { foreach (other[i]) other[i].b == 1; }
  function new();
    super.new();
    other = new[1];
    other[0] = new;
  endfunction
endclass

class RandModeOnlyLeafOwner extends RandModeSkippedMiddle;
  rand bit marker;
  constraint d { marker == dis; }
endclass

class RandModeKinds;
  rand RandModeItem fixed_arr[3:1];
  rand RandModeItem ascending_arr[1:3];
  rand RandModeItem queue_arr[$];
  rand RandModeItem assoc_arr[int];
  bit want_fixed = 1;
  bit want_ascending = 1;
  bit want_queue = 1;
  bit want_assoc = 1;

  constraint c {
    foreach (fixed_arr[i]) fixed_arr[i].b == want_fixed;
    foreach (ascending_arr[i]) ascending_arr[i].b == want_ascending;
    foreach (queue_arr[i]) queue_arr[i].b == want_queue;
    foreach (assoc_arr[i]) assoc_arr[i].b == want_assoc;
  }

  function new();
    RandModeItem item;
    foreach (fixed_arr[i]) fixed_arr[i] = new;
    foreach (ascending_arr[i]) ascending_arr[i] = new;
    repeat (2) begin
      item = new;
      queue_arr.push_back(item);
    end
    assoc_arr[11] = new;
    assoc_arr[-2] = new;
  endfunction
endclass

class RandModeLeaf;
  rand bit b;
endclass

class RandModeParent;
  rand RandModeLeaf sub;
  function new();
    sub = new;
  endfunction
endclass

class RandModeDirectNested;
  rand RandModeParent obj;
  rand bit dis;
  constraint c { dis -> obj.sub.b; }
  function new();
    obj = new;
  endfunction
endclass

module t;
  Bar bar;
  initial begin
    bar = new();
    bar.randomize();
    if (bar.foo_arr.size() != 10) $stop;
    foreach (bar.foo_arr[i]) begin
      if (bar.foo_arr[i].abcd >= 8) $stop;
    end
    // IEEE 1800-2023 18.8: A selected field with rand_mode off is STATE,
    // even when a constraint on the enclosing object names that field.
    begin
      automatic RandModeArray c = new;
      RandModeItem selected;
      int result;
      string saved_rng;
      selected = c.arr[1];
      c.arr[1].b.rand_mode(0);
      c.arr[0].b = 1;
      c.arr[2].b = 1;
      saved_rng = c.get_randstate();
      // IEEE 1800-2023 18.11.1: The first call is a checker, not a generator.
      result = c.randomize(null);
      `checkd(result, 1);
      `checkd(c.arr[1].b, 0);
      c.dis = 1;
      result = c.randomize(null);
      `checkd(result, 0);
      `checkd(c.arr[1].b, 0);
      `checkd(c.dis, 1);
      c.arr[1].b = 1;
      result = c.randomize(null);
      `checkd(result, 1);
      `checkd(c.arr[1].b, 1);
      c.arr[2].b = 0;
      result = c.randomize(null);
      `checkd(result, 0);
      `checkd(c.arr[1].b, 1);
      `checkd(c.get_randstate() == saved_rng, 1);
      c.arr[2].b = 1;
      c.arr[1].b = 0;
      c.dis = 0;
      `checkd(c.arr[1].b.rand_mode(), 0);
      `checkd(c.arr[0].b.rand_mode(), 1);
      `checkd(c.arr[1].a.rand_mode(), 1);
      for (int cycle = 1; cycle <= 20; ++cycle) begin
        c.expected_a = 7'(cycle);
        c.arr[1].b = 0;
        result = c.randomize();
        `checkd(result, 1);
        `checkd(c.dis, 0);
        `checkd(c.arr[1].b, 0);
        `checkd(c.arr[1] == selected, 1);
        `checkd(c.arr[0].b, 1);
        `checkd(c.arr[2].b, 1);
        foreach (c.arr[i]) `checkd(c.arr[i].a, c.expected_a);
      end
      // IEEE 1800-2023 18.6.3: An inconsistent constraint fails without
      // changing the old values, rather than solving a frozen field anew.
      result = c.randomize() with { dis == 1; };
      `checkd(result, 0);
      `checkd(c.dis, 0);
      `checkd(c.arr[1].b, 0);
      foreach (c.arr[i]) `checkd(c.arr[i].a, c.expected_a);
      c.arr[1].b.rand_mode(1);
      result = c.randomize() with { dis == 1; };
      `checkd(result, 1);
      `checkd(c.arr[1].b, 1);
      c.arr[1].b.rand_mode(0);
      result = c.randomize() with { dis == 0; arr[1].b == 0; };
      `checkd(result, 0);
      `checkd(c.arr[1].b, 1);
      // The inherited instance field has its own mode in the selected object.
      c.arr[1].a.rand_mode(0);
      result = c.randomize() with { dis == 0; };
      `checkd(result, 1);
      `checkd(c.arr[1].a, 20);
      c.expected_a = 21;
      result = c.randomize() with { dis == 0; };
      `checkd(result, 0);
      `checkd(c.arr[1].a, 20);
      foreach (c.arr[i]) `checkd(c.arr[i].a, 20);
      c.arr[1].a.rand_mode(1);
      result = c.randomize() with { dis == 0; };
      `checkd(result, 1);
      foreach (c.arr[i]) `checkd(c.arr[i].a, 21);
    end
    begin
      automatic RandModeDerivedOwner c = new;
      RandModeItem selected;
      int result;
      selected = c.arr[1];
      c.arr[0].b = 1;
      c.arr[2].b = 1;
      c.arr[1].b.rand_mode(0);
      result = c.randomize(null);
      `checkd(result, 1);
      for (int cycle = 1; cycle <= 20; ++cycle) begin
        c.expected_a = 7'(cycle);
        c.arr[1].b = 0;
        result = c.randomize();
        `checkd(result, 1);
        `checkd(c.arr[1].b, 0);
        `checkd(c.dis, 0);
        `checkd(c.marker, 0);
        `checkd(c.arr[1] == selected, 1);
      end
      result = c.randomize() with { dis == 1; };
      `checkd(result, 0);
      `checkd(c.arr[1].b, 0);
      c.arr[1].b.rand_mode(1);
      result = c.randomize() with { dis == 1; };
      `checkd(result, 1);
      `checkd(c.arr[1].b, 1);
      `checkd(c.marker, 1);
    end
    begin
      automatic RandModeOnlyLeafOwner c = new;
      RandModeItem selected;
      int result;
      selected = c.arr[1];
      c.other[0].b = 1;
      c.arr[1].b.rand_mode(0);
      // Neither owning ancestor is randomized separately; the middle owns another array.
      result = c.randomize(null);
      `checkd(result, 1);
      for (int cycle = 0; cycle < 20; ++cycle) begin
        c.arr[1].b = 0;
        result = c.randomize();
        `checkd(result, 1);
        `checkd(c.arr[1].b, 0);
        `checkd(c.arr[1] == selected, 1);
        `checkd(c.dis, 0);
        `checkd(c.marker, 0);
        `checkd(c.other[0].b, 1);
      end
      result = c.randomize() with { dis == 1; };
      `checkd(result, 0);
      `checkd(c.arr[1].b, 0);
      c.arr[1].b.rand_mode(1);
      result = c.randomize() with { dis == 1; };
      `checkd(result, 1);
      `checkd(c.arr[1].b, 1);
      `checkd(c.marker, 1);
      `checkd(c.other[0].b, 1);
    end
    begin
      automatic RandModeKinds c = new;
      int result;
      c.fixed_arr[2].b = 1;
      c.ascending_arr[2].b = 1;
      c.queue_arr[1].b = 1;
      c.assoc_arr[-2].b = 1;
      c.fixed_arr[2].b.rand_mode(0);
      c.ascending_arr[2].b.rand_mode(0);
      c.queue_arr[1].b.rand_mode(0);
      c.assoc_arr[-2].b.rand_mode(0);
      result = c.randomize();
      `checkd(result, 1);
      c.want_fixed = 0;
      c.want_ascending = 0;
      c.want_queue = 0;
      c.want_assoc = 0;
      result = c.randomize();
      `checkd(result, 0);
      `checkd(c.fixed_arr[2].b, 1);
      `checkd(c.ascending_arr[2].b, 1);
      `checkd(c.queue_arr[1].b, 1);
      `checkd(c.assoc_arr[-2].b, 1);
      // Each shape must cause rejection without another shape's contradiction.
      c.want_ascending = 1;
      c.want_queue = 1;
      c.want_assoc = 1;
      result = c.randomize();
      `checkd(result, 0);
      `checkd(c.fixed_arr[2].b, 1);
      c.want_fixed = 1;
      c.want_ascending = 0;
      result = c.randomize();
      `checkd(result, 0);
      `checkd(c.ascending_arr[2].b, 1);
      c.want_ascending = 1;
      c.want_queue = 0;
      result = c.randomize();
      `checkd(result, 0);
      `checkd(c.queue_arr[1].b, 1);
      c.want_queue = 1;
      c.want_assoc = 0;
      result = c.randomize();
      `checkd(result, 0);
      `checkd(c.assoc_arr[-2].b, 1);
      c.want_fixed = 0;
      c.want_ascending = 0;
      c.want_queue = 0;
      c.fixed_arr[2].b.rand_mode(1);
      c.ascending_arr[2].b.rand_mode(1);
      c.queue_arr[1].b.rand_mode(1);
      c.assoc_arr[-2].b.rand_mode(1);
      result = c.randomize();
      `checkd(result, 1);
      `checkd(c.fixed_arr[2].b, 0);
      `checkd(c.ascending_arr[2].b, 0);
      `checkd(c.queue_arr[1].b, 0);
      `checkd(c.assoc_arr[-2].b, 0);
    end
    begin
      automatic RandModeDirectNested c = new;
      RandModeLeaf selected;
      int result;
      selected = c.obj.sub;
      // The direct nested path is supported independently of array-member lowering.
      result = c.randomize() with { dis == 1; };
      `checkd(result, 1);
      `checkd(c.obj.sub.b, 1);
      c.obj.sub.b.rand_mode(0);
      for (int cycle = 0; cycle < 20; ++cycle) begin
        c.obj.sub.b = 0;
        result = c.randomize();
        `checkd(result, 1);
        `checkd(c.obj.sub.b, 0);
        `checkd(c.dis, 0);
        `checkd(c.obj.sub == selected, 1);
      end
      result = c.randomize() with { dis == 1; };
      `checkd(result, 0);
      `checkd(c.obj.sub.b, 0);
      `checkd(c.dis, 0);
      c.obj.sub.b.rand_mode(1);
      result = c.randomize() with { dis == 1; };
      `checkd(result, 1);
      `checkd(c.obj.sub.b, 1);
      c.obj.sub.b.rand_mode(0);
      result = c.randomize() with { dis == 0; obj.sub.b == 0; };
      `checkd(result, 0);
      `checkd(c.obj.sub.b, 1);
      `checkd(c.dis, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
