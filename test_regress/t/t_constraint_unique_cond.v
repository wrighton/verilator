// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 BRDR LIFE
// SPDX-License-Identifier: CC0-1.0

// A 'unique' nested in a constraint 'if' arm, over scalar rand members or over
// a statically sized array, applies only when the arm's condition holds.

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

class C;
  rand bit [1:0] x, y, z;
  rand bit sel;

  constraint c {
    if (sel) {
      unique {x, y, z};
    } else {
      unique {x, y};
    }
  }
endclass

class A;
  rand bit [1:0] arr[4];
  rand bit [1:0] one[1];
  rand bit sel;

  constraint c {
    if (sel) {
      unique {arr};
      // A single element is trivially unique
      unique {one};
    }
  }
endclass

class Sub;
  rand bit on;
endclass

// The guard is a member of a rand sub-object
class G;
  rand Sub s;
  rand bit [1:0] arr[4];

  constraint c {
    if (s.on) {
      unique {arr};
    }
  }

  function new;
    s = new;
  endfunction
endclass

class Arrs;
  rand bit [1:0] one[1];
  rand bit [1:0] two[2];
endclass

// Over arrays of a rand member object, followed by other 'if's of the same
// constraint, and the single element case that adds no constraint
class M;
  rand Arrs o;
  rand bit sel;
  rand bit [1:0] x;

  constraint c {
    if (sel) unique {o.one};
    if (!sel) x == 2'd3;
    if (sel) unique {o.two};
    foreach (o.two[i]) if (x != 2'd3) o.two[i] != 2'd0;
  }
  constraint c_alone {if (sel) unique {o.one};}
  constraint c_else {
    if (x == 2'd0) unique {o.one};
    else unique {o.one};
  }

  function new;
    o = new;
  endfunction
endclass

module t;
  initial begin
    automatic C c = new;
    automatic A a = new;
    automatic G g = new;
    automatic M m = new;
    int ok;

    // The 'then' arm holds: its operands are pairwise distinct
    for (int i = 0; i < 20; ++i) begin
      ok = c.randomize() with {sel == 1;};
      `checkd(ok, 1);
      `checkh(c.x == c.y, 1'b0);
      `checkh(c.x == c.z, 1'b0);
      `checkh(c.y == c.z, 1'b0);
    end
    // and cannot be violated
    ok = c.randomize() with {
      sel == 1;
      x == y;
    };
    `checkd(ok, 0);

    // The 'else' arm holds: only its own operands are constrained
    for (int i = 0; i < 20; ++i) begin
      ok = c.randomize() with {sel == 0;};
      `checkd(ok, 1);
      `checkh(c.x == c.y, 1'b0);
    end
    ok = c.randomize() with {
      sel == 0;
      y == z;
    };
    `checkd(ok, 1);
    ok = c.randomize() with {
      sel == 0;
      x == y;
    };
    `checkd(ok, 0);

    // An array 'unique' under the same guard: four distinct 2-bit values are a
    // permutation of 0..3, and are unconstrained once the guard is false
    for (int i = 0; i < 20; ++i) begin
      ok = a.randomize() with {sel == 1;};
      `checkd(ok, 1);
      foreach (a.arr[j]) foreach (a.arr[k]) if (j != k) `checkh(a.arr[j] == a.arr[k], 1'b0);
    end
    ok = a.randomize() with {
      sel == 1;
      arr[0] == arr[1];
    };
    `checkd(ok, 0);
    ok = a.randomize() with {
      sel == 0;
      arr[0] == arr[1];
    };
    `checkd(ok, 1);

    // A guard reached through a sub-object applies the same way
    for (int i = 0; i < 20; ++i) begin
      ok = g.randomize() with {s.on == 1;};
      `checkd(ok, 1);
      foreach (g.arr[j]) foreach (g.arr[k]) if (j != k) `checkh(g.arr[j] == g.arr[k], 1'b0);
    end
    ok = g.randomize() with {
      s.on == 1;
      arr[0] == arr[1];
    };
    `checkd(ok, 0);

    // Member object arrays: the guarded constraints after a single element hold
    for (int i = 0; i < 20; ++i) begin
      ok = m.randomize();
      `checkd(ok, 1);
      if (m.sel) `checkh(m.o.two[0] == m.o.two[1], 1'b0);
      else `checkd(m.x, 3);
      if (m.x != 2'd3) `checkh(m.o.two[0] == 2'd0 || m.o.two[1] == 2'd0, 1'b0);
    end
    ok = m.randomize() with {
      sel == 1;
      o.two[0] == o.two[1];
    };
    `checkd(ok, 0);
    for (int i = 0; i < 20; ++i) begin
      ok = m.randomize() with {
        if (sel) unique {o.one};
        if (sel) x == 2'd1;
      };
      `checkd(ok, 1);
      if (m.sel) `checkd(m.x, 1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
