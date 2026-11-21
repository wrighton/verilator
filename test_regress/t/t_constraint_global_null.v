// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A null rand class handle is not randomized, and the constraints of its class are skipped
// (IEEE 1800-2023 18.4, 18.5.8)

class Inner;
  rand bit [6:0] x;
  constraint c_in {x > 7'd100;}
endclass

class Item;
  rand bit [6:0] v;
  constraint c_v {v < 7'd10;}
endclass

class Mid;
  rand Inner in;
  rand Item a[];
  constraint c_a {foreach (a[i]) a[i].v != 7'd5;}
  function new();
    in = new;
    a = new[2];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

class Outer;
  rand Inner inner;
  rand Mid mid;
  rand bit [3:0] len;
  constraint c {len < 4'd8;}
  function new();
    inner = new;
    mid = new;
  endfunction
endclass

// Fields wider than 64 bits of member objects, registered only through non-null handles
class WideItem;
  rand bit [64:0] w;
  rand bit [2:0][32:0] p;
  constraint c_w {w[64:58] > 7'd100;}
endclass

class WideHolder;
  rand WideItem arr[2];
  function new();
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

class WideSeq;
  rand WideItem item;
  rand WideHolder holder;
  rand bit [6:0] low;
  function new();
    item = new;
    holder = new;
  endfunction
  constraint c_low {low > 7'd100;}
  constraint c {
    item.w[64:58] == low;
    item.p[1][32:26] == low;
    holder.arr[1].w[64:58] == low;
  }
endclass

module t;
  initial begin
    automatic Outer o = new;
    Inner old;
    int randomize_result;
    o.inner.x.rand_mode(1);  // The field's own rand_mode, checked through the handle
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.inner.x > 7'd100, 1'b1);
      `checkd(o.mid.in.x > 7'd100, 1'b1);
      foreach (o.mid.a[i]) `checkd(o.mid.a[i].v < 7'd10, 1'b1);
    end
    // A member object set to null; the object it held is left alone
    old = o.inner;
    old.x = 7'd3;
    o.inner = null;
    o.mid.in = null;
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.len < 4'd8, 1'b1);
      `checkd(old.x, 7'd3);
      foreach (o.mid.a[i]) `checkd(o.mid.a[i].v < 7'd10, 1'b1);
    end
    // A member object with an array of objects
    o.mid = null;
    repeat (5) begin
      randomize_result = o.randomize() with {len > 4'd2;};
      `checkd(randomize_result, 1);
      `checkd(o.len > 4'd2, 1'b1);
    end
    // Never constructed
    begin
      automatic Outer n = new;
      automatic Mid m = n.mid;
      n.inner = null;
      n.mid = null;
      randomize_result = n.randomize();
      `checkd(randomize_result, 1);
      o.mid = m;
    end
    // Set again, to the old object and to other objects
    o.inner = old;
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.inner.x > 7'd100, 1'b1);
      `checkd(o.mid.in.x > 7'd100, 1'b1);
      foreach (o.mid.a[i]) `checkd(o.mid.a[i].v < 7'd10, 1'b1);
    end
    begin
      automatic WideSeq s = new;
      repeat (5) begin
        randomize_result = s.randomize();
        `checkd(randomize_result, 1);
        `checkd(s.low > 7'd100, 1'b1);
        `checkh(s.item.w[64:58], s.low);
        `checkh(s.item.p[1][32:26], s.low);
        `checkh(s.holder.arr[1].w[64:58], s.low);
      end
      // A field with rand_mode off is a state variable
      s.item.w = {7'd117, 57'h0, 1'b1};
      s.item.w.rand_mode(0);
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkh(s.item.w, {7'd117, 57'h0, 1'b1});
      `checkd(s.low, 7'd117);
      `checkh(s.holder.arr[1].w[64:58], 7'd117);
      s.item.w.rand_mode(1);
      s.holder.arr[1].w = {7'd109, 57'h0, 1'b1};
      s.holder.arr[1].w.rand_mode(0);
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkh(s.holder.arr[1].w, {7'd109, 57'h0, 1'b1});
      `checkd(s.low, 7'd109);
      `checkh(s.item.w[64:58], 7'd109);
      s.holder.arr[1].w.rand_mode(1);
      // Null member objects, with the constraint through them off; the objects they held
      // are left alone
      begin
        automatic WideItem oldItem = s.item;
        automatic WideHolder oldHolder = s.holder;
        oldItem.w = 65'h1_2345_6789_abcd_ef01;
        oldItem.p = 99'h7_0123_4567_89ab_cdef_0123_4567;
        oldHolder.arr[1].w = 65'h0_fedc_ba98_7654_3210;
        s.c.constraint_mode(0);
        s.item = null;
        s.holder = null;
        repeat (5) begin
          randomize_result = s.randomize();
          `checkd(randomize_result, 1);
          `checkd(s.low > 7'd100, 1'b1);
          `checkh(oldItem.w, 65'h1_2345_6789_abcd_ef01);
          `checkh(oldItem.p, 99'h7_0123_4567_89ab_cdef_0123_4567);
          `checkh(oldHolder.arr[1].w, 65'h0_fedc_ba98_7654_3210);
        end
        s.item = oldItem;
        s.holder = oldHolder;
        s.c.constraint_mode(1);
        randomize_result = s.randomize();
        `checkd(randomize_result, 1);
        `checkh(s.item.w[64:58], s.low);
        `checkh(s.item.p[1][32:26], s.low);
        `checkh(s.holder.arr[1].w[64:58], s.low);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
