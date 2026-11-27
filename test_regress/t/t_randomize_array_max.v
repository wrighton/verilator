// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A size constraint giving an array more elements than +verilator+rand+array+max+<n> makes
// randomize() fail, before any array is resized

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Item;
  rand int v;
endclass

// Handle array, its size read by a variable, with no element constraint
class Handles;
  rand Item q[$];
  rand int x;
  constraint c {
    x == q.size();
    x > 32'd2_000_000;
  }
endclass

// Value queue, its size read in a foreach
class Values;
  rand int w[$];
  constraint c {
    w.size() > 32'd2_000_000;
    foreach (w[i]) if (i == w.size() - 1) w[i] == 7;
  }
endclass

// Dynamic array with an element constraint, so sized in a phase of its own
class Phased;
  rand int a[];
  constraint c {
    a.size() > 32'd2_000_000;
    foreach (a[i]) a[i] == i;
  }
endclass

// An array within the limit beside one over it is not resized either
class Sibling;
  rand int ok_q[$];
  rand int big_q[$];
  constraint c_ok {ok_q.size() == 3;}
  constraint c_big {big_q.size() > 32'd2_000_000;}
endclass

// Sized only by a constraint turned off, so not resized at all
class Off;
  rand int w[$];
  rand int x;
  constraint c {
    x == w.size();
    x > 32'd2_000_000;
  }
endclass

// Sized only in an inline constraint
class Inline;
  rand int w[$];
endclass

// A size the constraints bound is given, however large, unless the limit is lowered
class Bounded;
  rand int b[$];
  rand int n;
  constraint c {
    b.size() == n;
    n inside {[1 : 5]};
  }
endclass

// Sized only by reading its last element, so nothing bounds the size the solver gives
class LastElem;
  rand int q[$];
  constraint c {q[q.size() - 1] == 5;}
endclass

class LastByte;
  rand byte q[$];
endclass

class LastDyn;
  rand int d[];
  constraint c {d[d.size() - 1] == 5;}
endclass

class LastRead;
  rand int q[$];
  rand int x;
  constraint c {
    x == q[q.size() - 1];
    x == 5;
  }
endclass

module t;
  initial begin
    automatic Handles handles = new;
    automatic Values values = new;
    automatic Phased phased = new;
    automatic Sibling sibling = new;
    automatic Off off = new;
    automatic Inline inl = new;
    automatic Bounded bounded = new;
    automatic LastElem lastElem = new;
    automatic LastByte lastByte = new;
    automatic LastDyn lastDyn = new;
    automatic LastRead lastRead = new;
    int ok;
    // An oversize fails, leaving the array as it was
    ok = handles.randomize();
    `checkh(ok, 0);
    `checkh(handles.q.size(), 0);
    values.w = '{1, 2, 3};
    ok = values.randomize();
    `checkh(ok, 0);
    `checkh(values.w.size(), 3);
    `checkh(values.w[2], 3);
    ok = phased.randomize();
    `checkh(ok, 0);
    `checkh(phased.a.size(), 0);
    // Neither array is resized
    sibling.ok_q = '{4, 5};
    ok = sibling.randomize();
    `checkh(ok, 0);
    `checkh(sibling.ok_q.size(), 2);
    `checkh(sibling.big_q.size(), 0);
    // No constraint sizes it, so it keeps its size, and randomize() succeeds
    off.w = '{1, 2};
    off.c.constraint_mode(0);
    ok = off.randomize();
    `checkh(ok, 1);
    `checkh(off.w.size(), 2);
    inl.w = '{1, 2, 3};
    ok = inl.randomize() with {
      w.size() > 32'd2_000_000;
      foreach (w[i]) if (i == w.size() - 1) w[i] == 7;
    };
    `checkh(ok, 0);
    `checkh(inl.w.size(), 3);
    // An array sized only by an element read, which leaves the size unbounded, keeps its
    // size if the constraints allow it, else takes the least size they allow
    ok = lastElem.randomize();
    `checkh(ok, 1);
    `checkh(lastElem.q.size(), 1);
    `checkh(lastElem.q[0], 5);
    lastByte.q = '{1, 2};
    ok = lastByte.randomize() with {q[q.size() - 1] == 5;};
    `checkh(ok, 1);
    `checkh(lastByte.q.size(), 2);
    `checkh(lastByte.q[1], 5);
    ok = lastDyn.randomize();
    `checkh(ok, 1);
    `checkh(lastDyn.d.size(), 1);
    `checkh(lastDyn.d[0], 5);
    ok = lastRead.randomize();
    `checkh(ok, 1);
    `checkh(lastRead.q.size(), 1);
    `checkh(lastRead.q[0], 5);
    // A bounded one is given, unless +verilator+rand+array+max+2 lowers the limit below it
    bounded.b = '{1, 2, 3};
    ok = bounded.randomize();
    if ($test$plusargs("lowered")) begin
      // The solver may still pick 1 or 2, which the limit allows
      if (ok != 0 && bounded.b.size() > 2) begin
        $write("%%Error: size %0d over the lowered limit\n", bounded.b.size());
        `stop;
      end
    end else begin
      `checkh(ok, 1);
      if (bounded.b.size() < 1 || bounded.b.size() > 5) begin
        $write("%%Error: bad size %0d\n", bounded.b.size());
        `stop;
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
