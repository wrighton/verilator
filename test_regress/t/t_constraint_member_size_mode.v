// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

class ModeLeaf;
  rand int q[$];
  function new();
    q = '{1, 2};
  endfunction
endclass

class MemberModes;
  rand ModeLeaf sub;
  int total;
  constraint c_size {sub.q.size() == 3;}
  constraint c_also_size {sub.q.size() == 3;}
  constraint c_sum {sub.q.sum() == total;}
  constraint c_domain {sub.q.sum() inside {total, total + 1};}
  constraint c_low {soft sub.q.sum() == total;}
  constraint c_high {soft sub.q.sum() == total + 1;}
  bit guard;
  constraint c_guard {if (guard) sub.q.sum() == total;}
  function new();
    sub = new;
    c_low.constraint_mode(0);
    c_high.constraint_mode(0);
    c_guard.constraint_mode(0);
  endfunction
endclass

module t;
  initial begin
    automatic MemberModes a = new;
    int ok;
    automatic bit failed = 0;
    for (int turn = 0; turn < 4; ++turn) begin
      a.total = 10 + turn;
      a.c_size.constraint_mode(1);
      a.c_also_size.constraint_mode(1);
      a.sub.q = '{1, 2};
      ok = a.randomize();
      `checkd(ok, 1);
      `checkd(a.sub.q.size(), 3);
      `checkd(a.sub.q.sum(), a.total);
      a.c_size.constraint_mode(0);
      ok = a.randomize();
      `checkd(ok, 1);
      `checkd(a.sub.q.size(), 3);
      `checkd(a.sub.q.sum(), a.total);
      a.c_also_size.constraint_mode(0);
      a.sub.q = '{1, 2};
      ok = a.randomize();
      `checkd(ok, 1);
      `checkd(a.sub.q.size(), 2);
      `checkd(a.sub.q.sum(), a.total);
    end
    a.sub.q = '{4, 6};
    a.total = 10;
    a.sub.q.rand_mode(0);
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.size(), 2);
    `checkd(a.sub.q.sum(), 10);
    a.total = 11;
    ok = a.randomize();
    `checkd(ok, 0);
    `checkd(a.sub.q.sum(), 10);
    a.sub.q.rand_mode(1);
    a.total = 12;
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.size(), 2);
    `checkd(a.sub.q.sum(), 12);
    a.c_sum.constraint_mode(0);
    a.c_low.constraint_mode(1);
    a.c_high.constraint_mode(1);
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.sum(), 13);
    // A guarded reduction, with its constraint on and off, and with the array sized or not
    a.c_low.constraint_mode(0);
    a.c_high.constraint_mode(0);
    a.c_guard.constraint_mode(1);
    a.guard = 1;
    a.total = 14;
    a.sub.q = '{1, 2};
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.size(), 2);
    `checkd(a.sub.q.sum(), 14);
    a.c_size.constraint_mode(1);
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.size(), 3);
    `checkd(a.sub.q.sum(), 14);
    a.c_size.constraint_mode(0);
    a.guard = 0;
    a.total = 16;
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.size(), 3);
    `checkd(a.sub.q.sum() inside {16, 17}, 1);
    a.c_guard.constraint_mode(0);
    a.guard = 1;
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.sub.q.sum() inside {16, 17}, 1);
    // Complete the native solver log even on failure; the driver requires this success marker.
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
