// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A null rand class handle is not randomized, and the constraints of its class are skipped
// (IEEE 1800-2023 18.4, 18.5.8)

class Inner;
  rand bit [6:0] x;
  constraint c_in {x > 7'd100;}
endclass

class Sized;
  rand bit [6:0] q[$];
  constraint c_q {
    q.size() inside {[1 : 3]};
    foreach (q[i]) q[i] < 7'd10;
  }
endclass

class Mid;
  rand Inner in;
  rand Sized sz;
  function new();
    in = new;
    sz = new;
  endfunction
endclass

class Outer;
  rand Inner inner;
  rand Mid mid;
  rand Sized sized;
  rand bit [3:0] len;
  constraint c {len < 4'd8;}
  function new();
    inner = new;
    mid = new;
    sized = new;
  endfunction
endclass

// A member object replaced by another between calls
class Leaf;
  rand bit [6:0] x;
  rand bit [6:0] q[$];
  bit [6:0] key;
  constraint c_leaf {
    x == key;
    q.size() == 2;
    foreach (q[i]) q[i] == key + 7'(i);
  }
endclass

class Root;
  rand Leaf h;
  rand bit [6:0] y;
  constraint c_y {y < 7'd20;}
endclass

module t;
  initial begin
    automatic Outer o = new;
    automatic Root r = new;
    automatic Leaf a = new;
    automatic Leaf b = new;
    automatic Leaf seq[$];
    Inner old;
    Sized olds;
    int randomize_result;
    o.inner.x.rand_mode(1);  // The field's own rand_mode, read through the handle
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.inner.x > 7'd100, 1'b1);
      `checkd(o.mid.in.x > 7'd100, 1'b1);
      `checkd(o.sized.q.size() inside {[1 : 3]}, 1'b1);
      `checkd(o.mid.sz.q.size() inside {[1 : 3]}, 1'b1);
    end
    // Member objects set to null; the objects they held are left alone
    old = o.inner;
    old.x = 7'd3;
    olds = o.sized;
    olds.q = '{50, 60, 70, 80};
    o.inner = null;
    o.mid.in = null;
    o.sized = null;
    o.mid.sz = null;
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.len < 4'd8, 1'b1);
      `checkd(old.x, 7'd3);
      `checkd(olds.q.size(), 4);
    end
    // A null member object holding member objects, with an inline constraint
    o.mid = null;
    repeat (5) begin
      randomize_result = o.randomize() with {len > 4'd2;};
      `checkd(randomize_result, 1);
      `checkd(o.len > 4'd2 && o.len < 4'd8, 1'b1);
    end
    // Never constructed
    begin
      automatic Outer n = new;
      n.inner = null;
      n.mid = null;
      n.sized = null;
      randomize_result = n.randomize();
      `checkd(randomize_result, 1);
    end
    // Set again, to the old objects and to new ones
    o.inner = old;
    o.sized = olds;
    o.mid = new;
    repeat (5) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.inner.x > 7'd100, 1'b1);
      `checkd(o.mid.in.x > 7'd100, 1'b1);
      `checkd(o.sized.q.size() inside {[1 : 3]}, 1'b1);
      foreach (o.sized.q[i]) `checkd(o.sized.q[i] < 7'd10, 1'b1);
    end
    // The variables are those of the object the handle holds at each call; another object it
    // held before is left alone
    a.key = 7'd23;
    b.key = 7'd37;
    seq = '{a, null, b, a, b, a};
    for (int withBlock = 0; withBlock < 2; ++withBlock) begin
      foreach (seq[i]) begin
        a.x = 7'd91;
        b.x = 7'd92;
        a.q = '{7'd101};
        b.q = '{7'd111};
        r.h = seq[i];
        randomize_result = withBlock == 1 ? r.randomize() with {y > 7'd10;} : r.randomize();
        `checkd(randomize_result, 1);
        `checkd(r.y < 7'd20, 1'b1);
        `checkd(a.x, r.h == a ? 7'd23 : 7'd91);
        `checkd(b.x, r.h == b ? 7'd37 : 7'd92);
        `checkd(a.q.size(), r.h == a ? 2 : 1);
        `checkd(b.q.size(), r.h == b ? 2 : 1);
        if (r.h != null) `checkd(r.h.q[1], r.h.key + 7'd1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
