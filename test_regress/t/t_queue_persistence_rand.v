// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

localparam int N = 4096;

// Elements removed by randomize() while passed by reference continue to exist as outdated
// references (IEEE 1800-2023 13.5.2)
class Holder;
  rand int q[$];
  rand int d[];
  constraint c_size {
    q.size() == 2;
    d.size() == 2;
  }
  function int bump(ref int a, ref int b);
    automatic int ok = randomize();
    `checkd(ok, 1);
    a = a + 1;
    b = b + 1;
    return a + b;
  endfunction
endclass

class Regrow;
  rand int q[$];
  int m = 4;
  constraint c_size {
    q.size() == m;
    foreach (q[i]) q[i] == i;
  }
  function void bump(ref int removed, ref int survivor);
    automatic int ok;
    m = 2;
    ok = randomize();
    `checkd(ok, 1);
    m = 4;
    ok = randomize();
    `checkd(ok, 1);
    removed = -7;
    survivor = 42;
  endfunction
endclass

class Regrow2;
  rand int q[$];
  int m = 10;
  constraint c_size {
    q.size() == m;
    foreach (q[i]) q[i] == i;
  }
  function void bump(ref int removed);
    automatic int ok;
    void'(q.pop_back());
    void'(q.pop_back());
    m = 12;
    ok = randomize();
    `checkd(ok, 1);
    removed = 77;
  endfunction
endclass

// As Regrow2, growing by more than one element after the removed element's storage node was
// emptied; 130 elements put it second in its node with libstdc++'s nodes of 128 ints
class Regrow3;
  rand int q[$];
  int m = 0;
  constraint c_size {
    q.size() == m;
    foreach (q[i]) q[i] == i;
  }
  function void bump(ref int removed);
    automatic int ok;
    void'(q.pop_back());
    void'(q.pop_back());
    m = 130;
    ok = randomize();
    `checkd(ok, 1);
    removed = 77;
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic Regrow g = new;
    automatic Regrow2 g2 = new;
    automatic Regrow3 g3 = new;
    automatic int got;
    repeat (N) h.q.push_back(7);
    h.d = new[N];
    got = h.bump(h.q[3000], h.d[3000]);
    `checkd(got, 9);
    `checkd(h.q.size(), 2);
    `checkd(h.d.size(), 2);
    got = g.randomize();
    `checkd(got, 1);
    g.bump(g.q[2], g.q[0]);
    `checkd(g.q.size(), 4);
    `checkd(g.q[3], 3);
    // IEEE 1800-2023 7.10.3 keeps the reference to the remaining element bound, so the write
    // would be seen as q[0] == 42; growing the queue where an element passed by reference was
    // removed, in storage holding remaining elements, outdates every reference into the queue
    `checkd(g.q[0], 0);
    got = g2.randomize();
    `checkd(got, 1);
    g2.bump(g2.q[9]);
    `checkd(g2.q.size(), 12);
    // The new element constructed where the removed one was is not changed through the
    // outdated reference
    `checkd(g2.q[9], 9);
    for (int i = 0; i < 130; ++i) g3.q.push_back(i);
    g3.bump(g3.q[129]);
    `checkd(g3.q.size(), 130);
    `checkd(g3.q[128], 128);
    `checkd(g3.q[129], 129);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
