// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check(cond) do if (!(cond)) begin $write("%%Error: %s:%0d: check failed\n", `__FILE__,`__LINE__); `stop; end while(0);
// verilog_format: on

// A rand enum reached through a rand member in a global constraint keeps its
// enum domain (IEEE 1800-2023 18.4), and the member's own constraints apply (18.5.8)
typedef enum int {
  NORTH = 0,
  EAST = 1,
  WEST = 2,
  SOUTH = 3,
  HCB = 4
} dir_e;

typedef enum logic [2:0] {
  L0 = 3'd1,
  L1 = 3'd2,
  L2 = 3'd6
} lvl_e;

class Req;
  rand int unsigned kind;
  rand dir_e dir;
  constraint c_kind {kind inside {[0 : 1]};}
  constraint c_dir {kind == 0 -> dir != HCB;}
endclass

// tgt.dir is only constrained by 'init.dir != tgt.dir' and Req's own constraints
class Cfg;
  rand Req init;
  rand Req tgt;
  dir_e allowed_q[$] = '{WEST, SOUTH};
  constraint c_distinct {init.dir != tgt.dir;}
  constraint c_init_in {init.dir inside {allowed_q};}
  function new();
    init = new;
    tgt = new;
  endfunction
endclass

// Same with 'solve before' in the member, which adds a separate solve of 'kind'
class ReqOrd;
  rand int unsigned kind;
  rand dir_e dir;
  constraint c_kind {kind inside {[0 : 1]};}
  constraint c_dir {kind == 0 -> dir != HCB;}
  constraint c_ord {solve kind before dir;}
endclass

class CfgOrd;
  rand ReqOrd init;
  rand ReqOrd tgt;
  constraint c_distinct {init.dir != tgt.dir;}
  constraint c_init_in {init.dir inside {WEST, SOUTH};}
  function new();
    init = new;
    tgt = new;
  endfunction
endclass

// Three levels, and an enum narrower than 32 bits with gaps
class Leaf;
  rand lvl_e lvl;
  rand int unsigned vc;
  constraint c_vc {vc < 4;}
endclass

class Mid;
  rand Leaf lf;
  constraint c_mid {lf.lvl != L0;}
  function new();
    lf = new;
  endfunction
endclass

class Top;
  rand Mid a, b;
  constraint c_top {a.lf.lvl != b.lf.lvl;}
  function new();
    a = new;
    b = new;
  endfunction
endclass

// Selected only in an inline 'with'
class CfgWith;
  rand Req r;
  function new();
    r = new;
  endfunction
endclass

// A nested array access has no fixed solver name; it must still solve
class Sub;
  rand dir_e dir;
endclass

class Holder;
  rand Sub sub;
  function new();
    sub = new;
  endfunction
endclass

class CfgArr;
  rand Holder hs[2];
  constraint c_arr {hs[0].sub.dir != NORTH;}
  function new();
    foreach (hs[i]) hs[i] = new;
  endfunction
endclass

module t;
  function automatic bit isDir(dir_e d);
    return d inside {NORTH, EAST, WEST, SOUTH, HCB};
  endfunction
  function automatic bit reqOk(int unsigned kind, dir_e dir);
    return isDir(dir) && kind <= 1 && !(kind == 0 && dir == HCB);
  endfunction

  initial begin
    Cfg c;
    CfgOrd co;
    Top tp;
    CfgWith cw;
    CfgArr ca;
    int ok;
    c = new;
    co = new;
    tp = new;
    cw = new;
    ca = new;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `check(reqOk(c.init.kind, c.init.dir));
      `check(reqOk(c.tgt.kind, c.tgt.dir));
      `check(c.init.dir != c.tgt.dir);
      `check(c.init.dir inside {WEST, SOUTH});

      ok = co.randomize();
      `checkd(ok, 1);
      `check(reqOk(co.init.kind, co.init.dir));
      `check(reqOk(co.tgt.kind, co.tgt.dir));
      `check(co.init.dir != co.tgt.dir);
      `check(co.init.dir inside {WEST, SOUTH});

      ok = tp.randomize();
      `checkd(ok, 1);
      `check(tp.a.lf.lvl inside {L1, L2});
      `check(tp.b.lf.lvl inside {L1, L2});
      `check(tp.a.lf.lvl != tp.b.lf.lvl);
      `check(tp.a.lf.vc < 4 && tp.b.lf.vc < 4);

      ok = cw.randomize() with {r.dir != NORTH;};
      `checkd(ok, 1);
      `check(reqOk(cw.r.kind, cw.r.dir));
      `check(cw.r.dir != NORTH);

      ok = ca.randomize();
      `checkd(ok, 1);
      `check(ca.hs[0].sub.dir != NORTH);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
