// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// An array of the object that is not random, read by a random index, is read as state, as an
// array whose rand_mode() is off (IEEE 1800-2023 18.3), its elements as they are at each call;
// and so is an array with rand_mode() off between random indexes

class Own;
  bit [7:0] tbl[4];
  bit [7:0] dtbl[];
  bit [7:0] qtbl[$];
  rand bit [1:0] j;
  rand bit [7:0] w, x, y;
  constraint c {
    w == tbl[j];
    x == dtbl[j];
    y == qtbl[j];
  }
endclass

// A random index into an array with rand_mode() off, itself selected by a random index
class Nested;
  rand bit [2:0] a0[6], a1[6], a2[6];
  rand bit [2:0] d0[], d1[], d2[];
  rand bit [2:0] k;
  rand bit [2:0] v, u;
  constraint c {
    k < 6;
    a2[k] < 6;
    a1[a2[k]] < 6;
    v == a0[a1[a2[k]]];
    v != 0;
    d2[k] < 6;
    d1[d2[k]] < 6;
    u == d0[d1[d2[k]]];
    u != 0;
  }
  function new();
    d0 = new[6];
    d1 = new[6];
    d2 = new[6];
  endfunction
endclass

module t;
  initial begin
    automatic Own o = new;
    automatic Nested n = new;
    automatic int ok;
    o.tbl = '{8'h21, 8'h42, 8'h63, 8'h84};
    o.dtbl = '{8'h11, 8'h12, 8'h13};
    o.qtbl = '{8'h31, 8'h32, 8'h33, 8'h34};
    repeat (10) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.w, o.tbl[o.j]);
      // A position past the end reads 0
      `checkh(o.x, o.j < 3 ? o.dtbl[o.j] : 8'h0);
      `checkh(o.y, o.qtbl[o.j]);
      `checkh(o.tbl[0], 8'h21);
      `checkh(o.dtbl.size(), 3);
    end
    // Elements changed since the last call
    o.tbl[2] = 8'h99;
    o.qtbl.delete(3);
    ok = o.randomize() with {
      w == 8'h99;
    };
    `checkh(ok, 1);
    `checkh(o.j, 2);
    `checkh(o.y, 8'h33);
    ok = o.randomize() with {
      y == 8'h34;
    };
    `checkh(ok, 0);
    // A copy reads its own arrays, also with its original gone
    begin
      automatic Own c = new o;
      c.tbl[0] = 8'hc0;
      o.tbl[0] = 8'h0f;
      o = null;
      repeat (2) begin
        ok = c.randomize() with {
          j == 0;
        };
        `checkh(ok, 1);
        `checkh(c.w, 8'hc0);
      end
    end
    foreach (n.a1[i]) n.a1[i] = 3'(5 - i);
    foreach (n.d1[i]) n.d1[i] = 3'(i);
    n.a1.rand_mode(0);
    n.d1.rand_mode(0);
    repeat (10) begin
      ok = n.randomize();
      `checkh(ok, 1);
      `checkh(n.v, n.a0[n.a1[n.a2[n.k]]]);
      `checkh(n.u, n.d0[n.d1[n.d2[n.k]]]);
      `checkh(n.v != 0 && n.u != 0, 1'b1);
      `checkh(n.a1[0], 3'd5);
      `checkh(n.d1[5], 3'd5);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
