// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A soft constraint under a constraint 'if', implication or foreach guard stays
// soft (IEEE 1800-2023 18.5.14), so a conflicting hard constraint discards it.

class SoftCond;
  bit sel = 1;
  rand bit [6:0] x, y, z, w, k, p, q, d, v, u;
  rand bit [2:0] m;
  rand bit [4:0] a[3];
  rand bit [4:0] b[2:1];
  constraint c_if {if (sel) soft x == 3;}
  constraint c_impl {sel -> soft y == 3;}
  constraint c_else {
    if (!sel) z == 1;
    else soft z == 3;
  }
  constraint c_then {
    if (sel) soft v == 3;
    else v == 1;
  }
  constraint c_multi {
    if (sel) {
      soft u == 3;
      u > 1;
    }
  }
  constraint c_m {m == 2;}
  // Rand-dependent inner guard, hard and soft items in one branch
  constraint c_nest {
    if (sel) {
      if (m != 0) {
        w > 2;
        soft w == 3;
      }
    }
  }
  constraint c_if_foreach {if (sel) foreach (a[i]) soft a[i] == 5'(i + 3);}
  constraint c_foreach_if {foreach (b[i]) if (sel) soft b[i] == 5'(i);}
  constraint c_wide {if (sel) soft k;}
  // Later soft constraints have priority
  constraint c_prio_p {
    if (sel) soft p == 1;
    soft p == 2;
  }
  constraint c_prio_q {
    soft q == 2;
    if (sel) soft q == 1;
  }
  constraint c_dist {if (sel) d dist {0 := 5, 1 := 1, 2 := 1};}
endclass

module t;
  initial begin
    automatic SoftCond obj = new;
    automatic int ok;
    repeat (10) begin
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.x, 3);
      `checkd(obj.y, 3);
      `checkd(obj.z, 3);
      `checkd(obj.v, 3);
      `checkd(obj.u, 3);
      `checkd(obj.w, 3);
      foreach (obj.a[i]) `checkd(obj.a[i], 5'(i + 3));
      foreach (obj.b[i]) `checkd(obj.b[i], 5'(i));
      `checkd(obj.k != 0, 1);
      `checkd(obj.p, 2);
      `checkd(obj.q, 1);
      `checkd(obj.d <= 2, 1);

      ok = obj.randomize() with {x == 5;};
      `checkd(ok, 1);
      `checkd(obj.x, 5);
      ok = obj.randomize() with {y == 5;};
      `checkd(ok, 1);
      `checkd(obj.y, 5);
      ok = obj.randomize() with {z == 5;};
      `checkd(ok, 1);
      `checkd(obj.z, 5);
      ok = obj.randomize() with {v == 5;};
      `checkd(ok, 1);
      `checkd(obj.v, 5);
      ok = obj.randomize() with {u == 5;};
      `checkd(ok, 1);
      `checkd(obj.u, 5);
      ok = obj.randomize() with {w == 5;};
      `checkd(ok, 1);
      `checkd(obj.w, 5);
      ok = obj.randomize() with {a[1] == 9;};
      `checkd(ok, 1);
      `checkd(obj.a[1], 9);
      `checkd(obj.a[2], 5);
      ok = obj.randomize() with {b[2] == 7;};
      `checkd(ok, 1);
      `checkd(obj.b[2], 7);
      `checkd(obj.b[1], 1);
      ok = obj.randomize() with {k == 0;};
      `checkd(ok, 1);
      `checkd(obj.k, 0);
      ok = obj.randomize() with {d == 2;};
      `checkd(ok, 1);
      `checkd(obj.d, 2);
      // An inline guarded soft constraint has priority over the class ones
      ok = obj.randomize() with {if (sel) soft x == 4;};
      `checkd(ok, 1);
      `checkd(obj.x, 4);
    end

    obj.sel = 0;
    repeat (10) begin
      ok = obj.randomize() with {d == 9;};
      `checkd(ok, 1);
      `checkd(obj.z, 1);
      `checkd(obj.v, 1);
      `checkd(obj.p, 2);
      `checkd(obj.q, 2);
      `checkd(obj.d, 9);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
