// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// An array with rand_mode() off is read as state (IEEE 1800-2023 18.8), also by a random index

class Inner;
  rand bit [15:0] d[];
  function new();
    d = new[4];
    foreach (d[i]) d[i] = 16'(i + 10);
  endfunction
endclass

class Held;
  rand bit [15:0] tbl[];
  rand bit [15:0] que[$];
  rand bit [15:0] fix[4];
  rand Inner h;
  rand int unsigned j, k;
  rand bit [15:0] v, w, x, y, m;
  rand bit [31:0] s;
  constraint c {
    j < 4;
    k < 8;
    v == tbl[j];
    w == que[j];
    x == fix[j];
    y == tbl[k];
    m == h.d[j];
    s == tbl.sum() with (32'(item));
  }
  function new();
    tbl = new[4];
    foreach (tbl[i]) tbl[i] = 16'(i + 1);
    que = '{16'd7, 16'd2, 16'd5, 16'd0};
    foreach (fix[i]) fix[i] = 16'(i * 3);
    h = new;
  endfunction
endclass

// A large held table, which the solve only reads
class Large;
  rand bit [15:0] big[];
  rand int unsigned j;
  rand bit [15:0] v;
  constraint c {
    j < 2000;
    v == big[j];
  }
  function new();
    big = new[2000];
    foreach (big[i]) big[i] = 16'(i * 7);
  endfunction
endclass

module t;
  initial begin
    automatic Held o = new;
    automatic bit [15:0] tbl[] = o.tbl;
    automatic bit [15:0] que[$] = o.que;
    automatic bit [15:0] fix[4] = o.fix;
    automatic bit [15:0] d[] = o.h.d;
    automatic int ok;
    o.tbl.rand_mode(0);
    o.que.rand_mode(0);
    o.fix.rand_mode(0);
    o.h.d.rand_mode(0);
    repeat (8) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.v, o.tbl[o.j]);
      `checkh(o.w, o.que[o.j]);
      `checkh(o.x, o.fix[o.j]);
      `checkh(o.y, o.k < 4 ? o.tbl[o.k] : 16'h0);
      `checkh(o.m, o.h.d[o.j]);
      `checkh(o.s, 32'd10);
      `checkh(o.tbl == tbl && o.que == que && o.fix == fix && o.h.d == d, 1'b1);
    end
    // The index is solved from the elements
    ok = o.randomize() with {v == 16'd3;};
    `checkh(ok, 1);
    `checkh(o.j, 2);
    ok = o.randomize() with {v == 16'd5;};
    `checkh(ok, 0);
    // Solved again
    o.tbl.rand_mode(1);
    ok = o.randomize() with {
      tbl.size() == 4;
      v == 16'd1234;
    };
    `checkh(ok, 1);
    `checkh(o.tbl[o.j], 16'd1234);
    begin
      automatic Large held = new;
      held.big.rand_mode(0);
      repeat (3) begin
        ok = held.randomize();
        `checkh(ok, 1);
        `checkh(held.v, held.big[held.j]);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
