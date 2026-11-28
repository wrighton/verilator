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
  constraint ec {
    v inside {[10 : 20]};
    w == v + 1;
    if (v > 7'd12) w != 7'd15;
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

// Reached through a member object
class Mid;
  rand E aa[int];
endclass

class Through;
  rand Mid m;
  constraint c_g {foreach (m.aa[k]) m.aa[k] != null -> m.aa[k].v != 7'd17;}
  function new();
    m = new;
    m.aa[2] = new;
    m.aa[5] = new;
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
      foreach (th.m.aa[k]) begin
        check(th.m.aa[k]);
        `checkd(th.m.aa[k].v != 7'd17, 1'b1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
