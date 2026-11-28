// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The constraints of the objects of a rand associative array of class handles that the
// container's constraints reference are solved with them, for each key it holds

class E;
  rand bit [6:0] v;
  rand bit [6:0] w;
  rand bit [6:0] a[2];
  constraint ec {
    v inside {[10 : 20]};
    w == v + 1;
    // The item on the array member is ignored, the other is solved
    if (v > 7'd12) {
      w != 7'd15;
      a[0] == 7'd1;
    }
  }
endclass

class ByInt;
  rand E aa[int];
  constraint c_g {foreach (aa[k]) aa[k] != null -> aa[k].v != 7'd15;}
  function new();
    aa[3] = new;
    aa[-7] = new;
    // A null entry has no constraints
    aa[100] = null;
  endfunction
endclass

class ByString;
  rand E aa[string];
  constraint c_g {foreach (aa[k]) aa[k].v != 7'd16;}
  function new();
    aa["x"] = new;
    aa["yy"] = new;
  endfunction
endclass

class Empty;
  rand E aa[int];
  constraint c_g {foreach (aa[k]) aa[k].v != 7'd16;}
endclass

// Reached through a member object, with a null entry
class Mid;
  rand E aa[int];
endclass

class Through;
  rand Mid m;
  constraint c_g {foreach (m.aa[k]) m.aa[k] != null -> m.aa[k].v != 7'd17;}
  function new();
    m = new;
    m.aa[2] = new;
    m.aa[4] = null;
    m.aa[5] = new;
  endfunction
endclass

// By constant keys, of which one null
class ByKey;
  rand Mid m;
  constraint c_g {
    m.aa[4] != null -> m.aa[4].v != 7'd18;
    m.aa[2].v != 7'd19;
  }
  function new();
    m = new;
    m.aa[2] = new;
    m.aa[4] = null;
  endfunction
endclass

module t;
  task automatic check(E e);
    `checkd(e.v inside {[10 : 20]}, 1'b1);
    `checkd(e.w, e.v + 7'd1);
    `checkd(e.v > 7'd12 && e.w == 7'd15, 1'b0);
  endtask

  initial begin
    automatic ByInt bi = new;
    automatic ByString bs = new;
    automatic Empty em = new;
    automatic Through th = new;
    automatic ByKey bk = new;
    automatic int ok;
    repeat (20) begin
      ok = bi.randomize();
      `checkd(ok, 1);
      `checkd(bi.aa[100], null);
      check(bi.aa[3]);
      check(bi.aa[-7]);
      `checkd(bi.aa[3].v != 7'd15 && bi.aa[-7].v != 7'd15, 1'b1);
      ok = bs.randomize();
      `checkd(ok, 1);
      foreach (bs.aa[k]) begin
        check(bs.aa[k]);
        `checkd(bs.aa[k].v != 7'd16, 1'b1);
      end
      ok = em.randomize();
      `checkd(ok, 1);
      `checkd(em.aa.size(), 0);
      ok = th.randomize();
      `checkd(ok, 1);
      `checkd(th.m.aa[4], null);
      check(th.m.aa[2]);
      check(th.m.aa[5]);
      `checkd(th.m.aa[2].v != 7'd17 && th.m.aa[5].v != 7'd17, 1'b1);
      ok = bk.randomize();
      `checkd(ok, 1);
      check(bk.m.aa[2]);
      `checkd(bk.m.aa[2].v != 7'd19, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
