// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The sizes solved before a resize hold in the solve after it, so that a random bit
// guarding an array size agrees with the size, in a class, its base class, randomize()
// with and a member object, whose array is sized also from empty. The bit is one about
// half the time when both its values allow as many solutions: once d has grown to 3
// elements, either value of x keeps 3

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Guard;
  rand bit [7:0] q[$];
  rand bit [7:0] d[];
  rand bit [7:0] e[];
  rand bit x;
  int mode;
  bit c_on;
  int qcur;
  int dcur;
  int ecur;
  // The sizes of q and e are kept unless a mode puts another in force
  constraint c_state {if (mode == 1) q.size() == 4;}
  constraint c_q {if (!(mode == 1)) q.size() == qcur;}
  constraint c_rand {if (x) d.size() == 3;}
  constraint c_d {if (!x) d.size() == dcur;}
  constraint c_off {
    e.size() == 5;
    foreach (e[i]) e[i] < 10;
  }
  constraint c_e {if (!c_on) e.size() == ecur;}
endclass

// The guards declared in a base class, an element-constrained array in the derived one
class GuardBase;
  rand bit [7:0] q[$];
  rand bit [7:0] d[];
  rand bit x;
  int mode;
  int qcur;
  int dcur;
  constraint c_state {if (mode == 1) q.size() == 4;}
  constraint c_q {if (!(mode == 1)) q.size() == qcur;}
  constraint c_rand {if (x) d.size() == 3;}
  constraint c_d {if (!x) d.size() == dcur;}
endclass
class GuardDerived extends GuardBase;
  rand bit [7:0] e[];
  int ecur;
  constraint c_e {
    e.size() == ecur;
    foreach (e[i]) e[i] < 10;
  }
endclass

// Arrays sized only by the constraints of randomize() with, of the class and of its base
class WithBase;
  rand bit [7:0] q[$];
  rand bit x;
endclass
class WithSized extends WithBase;
  rand bit [7:0] d[];
  rand bit [7:0] e[];
  int ecur;
  constraint c_e {
    e.size() == ecur;
    foreach (e[i]) e[i] < 10;
  }
endclass

// A size equal to a random variable, beside an element-constrained array
class SizeVar;
  rand bit [7:0] d[];
  rand bit [7:0] e[];
  rand int unsigned n;
  constraint c {
    n inside {[1 : 5]};
    d.size() == n;
    e.size() == 2;
    foreach (e[i]) e[i] < 10;
  }
endclass

// The size of an array of a rand member object, guarded in the outer class
class Inner;
  rand bit [7:0] d[];
endclass
class Outer;
  rand Inner in;
  rand bit x;
  constraint c {
    if (x) in.d.size() == 3;
    else in.d.size() == 0;
  }
  function new;
    in = new;
  endfunction
endclass

// The size of a rand member object's array, constrained by the owner, from an empty array
class Member;
  rand bit [6:0] arr[];
endclass
class Owner;
  rand Member m;
  rand int sum;
  int low;
  constraint c {
    m.arr.size() inside {[2 : 4]};
    foreach (m.arr[i]) m.arr[i] inside {[1 : 3]};
    sum == int'(m.arr[0]) + int'(m.arr[1]) + int'(m.arr[2]);
    m.arr.size() == 3;
    sum >= low;
  }
  function new;
    m = new;
  endfunction
endclass

module t;
  localparam int CALLS = 300;
  initial begin
    automatic Guard g = new;
    automatic int randomize_result;
    automatic int counts[2] = '{0, 0};
    automatic real chi;
    g.q = '{1, 2};
    g.e = new[2];
    g.c_off.constraint_mode(0);
    repeat (CALLS) begin
      automatic bit grown = g.d.size() == 3;
      g.qcur = g.q.size();
      g.dcur = g.d.size();
      g.ecur = g.e.size();
      randomize_result = g.randomize();
      `checkd(randomize_result, 1);
      `checkd(g.q.size(), 2);
      `checkd(g.e.size(), 2);
      `checkd(g.d.size(), g.x ? 3 : g.dcur);
      if (grown) counts[g.x]++;
    end
    // Likewise with an inline constraint, solved the same two ways
    repeat (100) begin
      g.qcur = g.q.size();
      g.dcur = g.d.size();
      g.ecur = g.e.size();
      randomize_result = g.randomize() with {x || !x;};
      `checkd(randomize_result, 1);
      `checkd(g.q.size(), 2);
      `checkd(g.e.size(), 2);
      `checkd(g.d.size(), g.x ? 3 : g.dcur);
    end
    // Likewise for guards of a base class, and for sizes in with only, as d is grown and
    // reset to 2 elements and q asked to grow to 4 from 2
    begin
      automatic GuardDerived b = new;
      automatic WithSized w = new;
      automatic bit mode;
      automatic int qcur;
      automatic int dcur;
      b.e = new[2];
      w.e = new[2];
      for (int n = 0; n < 150; ++n) begin
        if (n % 7 == 0) begin
          b.d = new[2];
          w.d = new[2];
        end
        if (n % 5 == 0) begin
          b.q = '{1, 2};
          w.q = '{1, 2};
        end
        mode = n % 3 == 0;
        b.mode = int'(mode);
        b.qcur = b.q.size();
        b.dcur = b.d.size();
        b.ecur = b.e.size();
        // A base class's guards also when randomize() with of the derived class is called
        // from here, before the class's own randomize()
        if (n % 2 == 1) randomize_result = b.randomize() with {x || !x;};
        else randomize_result = b.randomize();
        `checkd(randomize_result, 1);
        `checkd(b.e.size(), 2);
        `checkd(b.q.size(), mode ? 4 : b.qcur);
        `checkd(b.d.size(), b.x ? 3 : b.dcur);
        qcur = w.q.size();
        dcur = w.d.size();
        w.ecur = w.e.size();
        randomize_result = w.randomize() with {
          if (local::mode) q.size() == 4;
          else q.size() == local::qcur;
          if (x) d.size() == 3;
          else d.size() == local::dcur;
        };
        `checkd(randomize_result, 1);
        `checkd(w.e.size(), 2);
        `checkd(w.q.size(), mode ? 4 : qcur);
        `checkd(w.d.size(), w.x ? 3 : dcur);
      end
    end
    begin
      automatic SizeVar sv = new;
      automatic Outer o = new;
      automatic int ones = 0;
      repeat (200) begin
        randomize_result = sv.randomize();
        `checkd(randomize_result, 1);
        `checkd(sv.d.size(), sv.n);
        `checkd(sv.e.size(), 2);
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkd(o.in.d.size(), o.x ? 3 : 0);
        ones += o.x;
      end
      // Both values of x, which the outer class's size guard leaves free
      if (ones < 20 || ones > 180) begin
        $write("%%Error: member size guard x one %0d of 200\n", ones);
        `stop;
      end
    end
    begin
      automatic Owner ow = new;
      for (int i = 0; i < 8; ++i) begin
        ow.m.arr = '{7, 8, 9};
        if (i % 2 == 1) ow.m.arr.delete();
        ow.low = 50;
        randomize_result = ow.randomize();
        `checkd(randomize_result, 0);
        ow.low = 2;
        randomize_result = ow.randomize();
        `checkd(randomize_result, 1);
        `checkd(ow.m.arr.size(), 3);
        `checkd(ow.sum, int'(ow.m.arr[0]) + int'(ow.m.arr[1]) + int'(ow.m.arr[2]));
        foreach (ow.m.arr[j]) `checkd(ow.m.arr[j] inside {[1 : 3]}, 1'b1);
      end
    end
    // Past 10.8 with one degree of freedom, one time in a thousand
    chi = 0.0;
    foreach (counts[i]) begin
      automatic real expected = real'(counts[0] + counts[1]) / 2.0;
      chi += (real'(counts[i]) - expected) * (real'(counts[i]) - expected) / expected;
    end
    if (chi > 10.8) begin
      $write("%%Error: x one %0d of %0d\n", counts[1], counts[0] + counts[1]);
      `stop;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
