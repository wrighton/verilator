// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The constraints of the object of a null rand handle do not apply, as there is no object
// (IEEE 1800-2023 18.5.8), also when the object holding the handle selects through it

class Leaf;
  rand bit [7:0] x;
  rand bit en;
  constraint c_x {x < 8'd50;}
  constraint c_en {soft en == 1'b0;}
  constraint c_arr {foreach (arr[i]) arr[i] < 8'd9;}
  rand bit [7:0] arr[2];
endclass

class Mid;
  rand Leaf leaf;
endclass

class Holder;
  rand Leaf leaf;
  rand Mid mid;
  rand bit [7:0] y;
  constraint c_guard {
    if (leaf != null) {
      leaf.x > 8'd10;
      leaf.en == 1'b1;
    }
    if (mid != null && mid.leaf != null) mid.leaf.x > 8'd20;
    y < 8'd5;
  }
endclass

// A bare expression, and soft constraints in a loop, of the object
class Bare;
  rand bit [6:0] x;
  rand bit [6:0] a[2];
  constraint c_x {x;}
  constraint c_a {foreach (a[i]) soft a[i] == 7'd23;}
endclass

class BareHolder;
  rand Bare b;
  constraint c_b {
    if (b != null) {
      b.x == 7'd23;
      b.a[0] == 7'd37;
    }
  }
endclass

// Soft constraints in a loop over an array of the object, which the holder does not read
class LoopHolder;
  rand Bare b;
  rand bit [7:0] z;
  constraint c_z {z < 5;}
endclass

// The size of an array of the object, which the holder does not read
class Sized;
  rand bit [3:0] q[$];
  constraint c_size {q.size() == 2;}
endclass

class SizedHolder;
  rand Sized s;
  rand bit [7:0] z;
  constraint c_z {z < 5;}
endclass

// A soft constraint under a condition of the object
class SoftIf;
  rand bit [7:0] x;
  rand bit [7:0] y;
  constraint c_if {if (x > 10) soft y == 3;}
endclass

class SoftIfHolder;
  rand SoftIf e;
  rand bit [7:0] z;
  constraint c_e {
    if (e != null) e.x > 20;
    z < 5;
  }
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int randomize_result;
    randomize_result = h.randomize();
    `checkd(randomize_result, 1);
    `checkd(h.y < 8'd5, 1'b1);
    h.mid = new;
    randomize_result = h.randomize();
    `checkd(randomize_result, 1);
    h.leaf = new;
    h.mid.leaf = new;
    repeat (5) begin
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
      `checkd(h.leaf.x > 8'd10 && h.leaf.x < 8'd50, 1'b1);
      // The member's soft constraint stays soft against the holder's
      `checkd(h.leaf.en, 1'b1);
      `checkd(h.mid.leaf.x > 8'd20 && h.mid.leaf.x < 8'd50, 1'b1);
      `checkd(h.mid.leaf.en, 1'b0);
      `checkd(h.leaf.arr[1] < 8'd9, 1'b1);
    end
    begin
      automatic BareHolder bh = new;
      bh.b = new;
      randomize_result = bh.randomize();
      `checkd(randomize_result, 1);
      `checkd(bh.b.x, 23);
      `checkd(bh.b.a[0], 37);
      `checkd(bh.b.a[1], 23);
    end
    begin
      automatic LoopHolder lh = new;
      randomize_result = lh.randomize();
      `checkd(randomize_result, 1);
      lh.b = new;
      randomize_result = lh.randomize();
      `checkd(randomize_result, 1);
      `checkd(lh.b.a[0], 23);
      `checkd(lh.b.a[1], 23);
    end
    begin
      automatic SizedHolder zh = new;
      randomize_result = zh.randomize();
      `checkd(randomize_result, 1);
    end
    begin
      automatic SoftIfHolder sh = new;
      randomize_result = sh.randomize();
      `checkd(randomize_result, 1);
      sh.e = new;
      randomize_result = sh.randomize();
      `checkd(randomize_result, 1);
      `checkd(sh.e.x > 20, 1'b1);
      `checkd(sh.e.y, 3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
