// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// constraint_mode() of the constraints of rand member objects that the container's
// constraints solve together with it (IEEE 1800-2023 18.9)

class Leaf;
  rand bit [7:0] z;
  constraint c_z {z == 7;}
endclass

class Bar;
  rand bit [7:0] x;
  rand Leaf leaf;
  constraint c_x {x == 5;}
  static constraint c_low {x < 128;}
  function new();
    leaf = new;
  endfunction
endclass

class Elem;
  rand bit [7:0] x;
  constraint c_x {x == 5;}
  static constraint c_low {x < 128;}
endclass

class Foo;
  rand Bar bar;
  rand Elem bars[];
  rand bit y;
  constraint c {
    bar.x > 0 -> y == 1;
    bar.leaf.z > 0 -> y == 1;
    foreach (bars[i]) bars[i].x != 1;
  }
  function new();
    bar = new;
    bars = new[2];
    foreach (bars[i]) bars[i] = new;
  endfunction
endclass

// A rand member object that may be null, its constraint having a mode
class NullHolder;
  rand Elem e;
  rand bit [7:0] y;
  constraint c {
    if (e != null) e.x != 1;
    y < 5;
  }
endclass

// The same through a rand member object of a rand member object
class NullMid;
  rand Elem e;
endclass

class NullNestHolder;
  rand NullMid m;
  rand bit [7:0] y;
  constraint c {
    if (m != null && m.e != null) m.e.x != 1;
    y < 5;
  }
endclass

// A constraint on a static rand variable, of the object and of a rand member object of its class
class SBase;
  rand int bv;
  static rand int sb;
  constraint c_sb {sb inside {[100 : 109]};}
endclass

class SDerived extends SBase;
  rand SBase mem;
  function new();
    mem = new;
  endfunction
endclass

module t;
  // Before the randomize() calls in source order, so the constraint is cloned after it is
  // known to have a constraint_mode()
  function automatic void leaf_off(Foo f);
    f.bar.leaf.c_z.constraint_mode(0);
  endfunction

  initial begin
    automatic Foo f = new;
    int randomize_result;
    int x_free, z_free, b0_free, b1_free, x_high;

    // Turned off after a randomize() call, in source order
    randomize_result = f.randomize();
    `checkd(randomize_result, 1);
    `checkd(f.bar.x, 5);
    `checkd(f.bar.leaf.z, 7);
    f.bar.c_x.constraint_mode(0);
    leaf_off(f);
    f.bars[1].c_x.constraint_mode(0);
    repeat (40) begin
      randomize_result = f.randomize();
      `checkd(randomize_result, 1);
      if (f.bar.x != 5) ++x_free;
      if (f.bar.leaf.z != 7) ++z_free;
      if (f.bars[0].x != 5) ++b0_free;
      if (f.bars[1].x != 5) ++b1_free;
      if (f.bar.x >= 128 || f.bars[1].x >= 128) ++x_high;
    end
    if (x_free == 0 || z_free == 0 || b1_free == 0) `stop;
    `checkd(b0_free, 0);
    `checkd(x_high, 0);

    // A static constraint
    f.bar.c_low.constraint_mode(0);
    x_high = 0;
    repeat (40) begin
      randomize_result = f.randomize();
      `checkd(randomize_result, 1);
      if (f.bar.x >= 128) ++x_high;
    end
    if (x_high == 0) `stop;

    // The container's constraint_mode() is not that of the objects' constraints
    f.bar.c_x.constraint_mode(1);
    f.bar.leaf.c_z.constraint_mode(1);
    f.constraint_mode(0);
    repeat (20) begin
      randomize_result = f.randomize();
      `checkd(randomize_result, 1);
      `checkd(f.bar.x, 5);
      `checkd(f.bar.leaf.z, 7);
    end

    // All constraints of an object, not those of its member objects
    f.bar.constraint_mode(0);
    x_free = 0;
    repeat (20) begin
      randomize_result = f.randomize();
      `checkd(randomize_result, 1);
      if (f.bar.x != 5) ++x_free;
      `checkd(f.bar.leaf.z, 7);
    end
    if (x_free == 0) `stop;

    begin
      automatic NullHolder nh = new;
      // The constraint mode is not read through the null handle, of no object, so of no
      // constraints (IEEE 1800-2023 18.5.8)
      randomize_result = nh.randomize();
      `checkd(randomize_result, 1);
      nh.e = new;
      randomize_result = nh.randomize();
      `checkd(randomize_result, 1);
      `checkd(nh.e.x, 5);
      nh.e.c_x.constraint_mode(0);
      randomize_result = nh.randomize();
      `checkd(randomize_result, 1);
    end

    begin
      automatic NullNestHolder nn = new;
      randomize_result = nn.randomize();
      `checkd(randomize_result, 1);
      nn.m = new;
      randomize_result = nn.randomize();
      `checkd(randomize_result, 1);
      nn.m.e = new;
      randomize_result = nn.randomize();
      `checkd(randomize_result, 1);
      `checkd(nn.m.e.x, 5);
    end

    begin
      automatic SDerived sd = new;
      sd.sb.rand_mode(0);
      SBase::sb = 5;
      randomize_result = sd.randomize();
      `checkd(randomize_result, 0);
      // The member object's constraint still applies
      sd.c_sb.constraint_mode(0);
      randomize_result = sd.randomize();
      `checkd(randomize_result, 0);
      sd.mem.c_sb.constraint_mode(0);
      randomize_result = sd.randomize();
      `checkd(randomize_result, 1);
      `checkd(SBase::sb, 5);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
