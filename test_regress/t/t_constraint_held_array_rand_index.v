// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Arrays with rand_mode(0) read by a random index
class Tables;
  rand bit [15:0] dyn[];
  rand bit [7:0] fixed[16];
  rand bit [7:0] que[$];
  rand int unsigned j;
  rand bit [3:0] k;
  rand bit [15:0] v;
  rand bit [7:0] w;
  rand bit [7:0] x;
  constraint c_dyn {
    j < 64;
    v == dyn[j];
    v > 16'd100;
  }
  constraint c_fixed {w == fixed[k];}
  constraint c_que {x == que[k % 4];}
  function new();
    dyn = new[64];
    foreach (dyn[i]) dyn[i] = 16'(i * 7);
    foreach (fixed[i]) fixed[i] = 8'(i * 3 + 1);
    repeat (4) que.push_back(8'(que.size() + 40));
  endfunction
endclass

// Named only in the solve after the size solve
class Sized;
  rand bit [7:0] arr[4];
  rand bit [7:0] q[$];
  constraint c_q {
    q.size() == 4;
    foreach (q[i]) q[i] == arr[i];
  }
  function new();
    foreach (arr[n]) arr[n] = 8'(n + 20);
  endfunction
endclass

// Named, through two objects, only by a later randomize() with
class Leaf;
  rand bit [7:0] deep[];
  function new();
    deep = new[4];
    foreach (deep[n]) deep[n] = 8'(n + 1);
  endfunction
endclass

class Mid;
  rand Leaf leaf;
  function new();
    leaf = new;
  endfunction
endclass

class Top;
  rand Mid mid;
  rand bit [1:0] n;
  rand bit [7:0] y;
  function new();
    mid = new;
  endfunction
endclass

// Of a rand member object
class Holder;
  rand Tables t;
  rand bit [15:0] u;
  constraint c_u {u == t.dyn[t.j];}
  function new();
    t = new;
  endfunction
endclass

// Read whole as well
class Summed;
  rand bit [7:0] arr[4];
  rand bit [1:0] i;
  rand bit [9:0] s;
  rand bit [7:0] e;
  constraint c_sum {s == arr.sum() with (10'(item));}
  constraint c_e {e == arr[i];}
  function new();
    foreach (arr[n]) arr[n] = 8'(n + 1);
  endfunction
endclass

module t;
  Tables tab;
  Sized sized;
  Top top;
  Holder hold;
  Summed sum;
  int ok;
  bit [15:0] saved[];
  initial begin
    tab = new;
    tab.dyn.rand_mode(0);
    tab.fixed.rand_mode(0);
    tab.que.rand_mode(0);
    saved = tab.dyn;
    repeat (10) begin
      ok = tab.randomize();
      `checkh(ok, 1);
      `checkh(tab.v, tab.dyn[tab.j]);
      `checkh(tab.v > 16'd100, 1'b1);
      `checkh(tab.w, tab.fixed[tab.k]);
      `checkh(tab.x, tab.que[tab.k % 4]);
      `checkh(tab.dyn == saved, 1'b1);
    end
    // An inline constraint reading one more
    ok = tab.randomize() with {fixed[k] == 8'd10;};
    `checkh(ok, 1);
    `checkh(tab.k, 4'd3);
    // Or naming it whole, in this call only
    ok = tab.randomize() with {fixed[2] == 8'd7;};
    `checkh(ok, 1);
    ok = tab.randomize() with {fixed[2] == 8'd8;};
    `checkh(ok, 0);
    // Random again
    tab.dyn.rand_mode(1);
    ok = tab.randomize() with {v == 16'd1234;};
    `checkh(ok, 1);
    `checkh(tab.dyn[tab.j], 16'd1234);
    sized = new;
    sized.arr.rand_mode(0);
    ok = sized.randomize();
    `checkh(ok, 1);
    `checkh(sized.q.size(), 4);
    foreach (sized.q[i]) `checkh(sized.q[i], sized.arr[i]);
    top = new;
    top.mid.leaf.deep.rand_mode(0);
    ok = top.randomize();
    `checkh(ok, 1);
    repeat (5) begin
      ok = top.randomize() with {y == mid.leaf.deep[n];};
      `checkh(ok, 1);
      `checkh(top.y, top.mid.leaf.deep[top.n]);
    end
    hold = new;
    hold.t.dyn.rand_mode(0);
    repeat (5) begin
      ok = hold.randomize();
      `checkh(ok, 1);
      `checkh(hold.u, hold.t.dyn[hold.t.j]);
    end
    sum = new;
    sum.arr.rand_mode(0);
    repeat (5) begin
      ok = sum.randomize();
      `checkh(ok, 1);
      `checkh(sum.s, 10'd10);
      `checkh(sum.e, sum.arr[sum.i]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
