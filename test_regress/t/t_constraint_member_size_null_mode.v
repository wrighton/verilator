// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// The size constraint of a member object, with a constraint mode, while the handle is null

class ModeLeaf;
  rand int q[$];
  constraint c_size {q.size() == 3;}
  function new();
    q = '{1, 2};
    c_size.constraint_mode(1);
  endfunction
endclass

class ModeRoot;
  rand ModeLeaf sub;
  rand int v;
  constraint c_touch {sub != null -> sub.q.sum() == 6;}
  constraint c_bad {v == 1;}
endclass

module t;
  initial begin
    automatic ModeRoot r = new;
    int ok;
    automatic bit failed = 0;
    // Null member object: not randomized, its constraints not applied
    ok = r.randomize();
    `checkd(ok, 1);
    `checkd(r.v, 1);
    ok = r.randomize() with {v == 2;};
    `checkd(ok, 0);
    ok = r.randomize() with {v == 1;};
    `checkd(ok, 1);
    r.sub = new;
    ok = r.randomize();
    `checkd(ok, 1);
    `checkd(r.sub.q.size(), 3);
    `checkd(r.sub.q.sum(), 6);
    r.sub.c_size.constraint_mode(0);
    r.sub.q = '{1, 2};
    ok = r.randomize();
    `checkd(ok, 1);
    `checkd(r.sub.q.size(), 2);
    `checkd(r.sub.q.sum(), 6);
    r.sub.c_size.constraint_mode(1);
    ok = r.randomize() with {v == 1;};
    `checkd(ok, 1);
    `checkd(r.sub.q.size(), 3);
    `checkd(r.sub.q.sum(), 6);
    r.sub = null;
    ok = r.randomize() with {v == 2;};
    `checkd(ok, 0);
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
