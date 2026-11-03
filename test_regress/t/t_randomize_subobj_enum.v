// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Check that an enum value is one of the valid members
`define check_enum_color(gotv) \
  if ((gotv) !== RED && (gotv) !== GREEN && (gotv) !== BLUE) begin \
    $write("%%Error: %s:%0d: invalid color=%0d\n", `__FILE__, `__LINE__, (gotv)); \
    `stop; \
  end

`define check_enum_state(gotv) \
  if ((gotv) !== IDLE && (gotv) !== RUN && (gotv) !== STOP) begin \
    $write("%%Error: %s:%0d: invalid state=%0d\n", `__FILE__, `__LINE__, (gotv)); \
    `stop; \
  end

module t;

  typedef enum logic [1:0] {
    RED = 2'd0,
    GREEN = 2'd1,
    BLUE = 2'd2
  } color_e;

  typedef enum logic [2:0] {
    IDLE = 3'd0,
    RUN = 3'd3,
    STOP = 3'd5
  } state_e;

  class InnerObj;
    rand color_e color;
    rand state_e state;
  endclass

  class OuterObj;
    rand InnerObj inner;

    function new();
      inner = new();
    endfunction
  endclass

  // Nested: TopObj -> MiddleObj -> InnerObj
  class MiddleObj;
    rand InnerObj inner;

    function new();
      inner = new();
    endfunction
  endclass

  class TopObj;
    rand MiddleObj mid;

    function new();
      mid = new();
    endfunction
  endclass

  // A rand enum selected through a rand member in a global constraint keeps its
  // enum domain (IEEE 1800-2023 18.4), and the member's own constraints apply (18.5.8)
  typedef enum int {
    NORTH = 0,
    EAST = 1,
    WEST = 2,
    SOUTH = 3,
    HCB = 4
  } dir_e;

  function automatic bit reqOk(int unsigned kind, dir_e dir);
    return dir inside {NORTH, EAST, WEST, SOUTH, HCB} && kind <= 1 && !(kind == 0 && dir == HCB);
  endfunction

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

  task automatic testGlobal;
    Cfg c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(reqOk(c.init.kind, c.init.dir), 1);
      `checkd(reqOk(c.tgt.kind, c.tgt.dir), 1);
      `checkd(c.init.dir != c.tgt.dir, 1);
      `checkd(c.init.dir inside {WEST, SOUTH}, 1);
    end
  endtask

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

  task automatic testSolveBefore;
    CfgOrd c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(reqOk(c.init.kind, c.init.dir), 1);
      `checkd(reqOk(c.tgt.kind, c.tgt.dir), 1);
      `checkd(c.init.dir != c.tgt.dir, 1);
      `checkd(c.init.dir inside {WEST, SOUTH}, 1);
    end
  endtask

  // Three levels, and an enum narrower than 32 bits with gaps
  class Leaf;
    rand state_e st;
    rand int unsigned vc;
    constraint c_vc {vc < 4;}
  endclass

  class Mid;
    rand Leaf lf;
    constraint c_mid {lf.st != IDLE;}
    function new();
      lf = new;
    endfunction
  endclass

  class Top3;
    rand Mid a, b;
    constraint c_top {a.lf.st != b.lf.st;}
    function new();
      a = new;
      b = new;
    endfunction
  endclass

  task automatic testThreeLevels;
    Top3 c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.a.lf.st inside {RUN, STOP}, 1);
      `checkd(c.b.lf.st inside {RUN, STOP}, 1);
      `checkd(c.a.lf.st != c.b.lf.st, 1);
      `checkd(c.a.lf.vc < 4 && c.b.lf.vc < 4, 1);
    end
  endtask

  // Enum values above 32 bits
  typedef enum bit [39:0] {
    W0 = 40'h00_0000_0003,
    W1 = 40'h10_0000_0001,
    W2 = 40'h80_0000_0000
  } wide_e;

  class Wide;
    rand wide_e w;
  endclass

  class WideHolder;
    rand Wide m;
    rand wide_e pw;
    constraint c_w {
      m.w != W0;
      pw != W1;
    }
    function new();
      m = new;
    endfunction
  endclass

  task automatic testWide;
    WideHolder c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.m.w inside {W1, W2}, 1);
      `checkd(c.pw inside {W0, W2}, 1);
    end
  endtask

  // An item with X/Z bits can't be produced, so it is not in the domain.
  // Constrained, as basic randomization of such an enum is a separate issue.
  typedef enum logic [1:0] {
    F0 = 2'b00,
    FX = 2'b1x,
    F1 = 2'b01
  } four_e;

  class FourPlain;
    rand four_e f;
    constraint c_f {f != F0;}
  endclass

  task automatic testFourState;
    FourPlain p = new;
    int ok;
    repeat (20) begin
      ok = p.randomize();
      `checkd(ok, 1);
      `checkd(p.f, F1);
    end
  endtask

  // Selected only in an inline 'with'; the member's class has no constraints
  class Dir;
    rand dir_e dir;
  endclass

  class DirHolder;
    rand Dir sub;
    function new();
      sub = new;
    endfunction
  endclass

  task automatic testInlineWith;
    DirHolder c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize() with {sub.dir != NORTH;};
      `checkd(ok, 1);
      `checkd(c.sub.dir inside {EAST, WEST, SOUTH, HCB}, 1);
    end
  endtask

  // A nested array access has no fixed solver name; it must still solve
  class DirArr;
    rand DirHolder hs[2];
    constraint c_arr {hs[0].sub.dir != NORTH;}
    function new();
      foreach (hs[i]) hs[i] = new;
    endfunction
  endclass

  task automatic testNestedArray;
    DirArr c = new;
    int ok;
    repeat (20) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.hs[0].sub.dir != NORTH, 1);
    end
  endtask

  initial begin
    int randomize_result;
    OuterObj obj;
    TopObj top;
    obj = new();
    top = new();

    // Test direct sub-object enum (one level deep)
    repeat (20) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      `check_enum_color(obj.inner.color)
      `check_enum_state(obj.inner.state)
    end

    // Test nested sub-object enum (two levels deep)
    repeat (20) begin
      randomize_result = top.randomize();
      `checkd(randomize_result, 1);
      `check_enum_color(top.mid.inner.color)
      `check_enum_state(top.mid.inner.state)
    end

    testGlobal();
    testSolveBefore();
    testThreeLevels();
    testWide();
    testFourState();
    testInlineWith();
    testNestedArray();

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
