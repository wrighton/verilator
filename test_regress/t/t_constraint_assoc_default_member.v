// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A key an associative array of class handles does not hold reads its default, so a member of
// a default object is read as of the elements (IEEE 1800-2023 7.8.6); a null default or a
// null element has no members

class Sub;
  int nr;
  function new(int n);
    nr = n;
  endfunction
endclass

class Obj;
  int nr;
  Sub sub;
  function new(int n, int s);
    nr = n;
    sub = new(s);
  endfunction
endclass

// Only the default object reads 7, or 9 through its member object
class WithDefault;
  Obj a[int];
  rand int ai;
  rand int x;
  rand int y;
  constraint c {
    ai inside {[0 : 9]};
    x == a[ai].nr;
    y == a[ai].sub.nr;
  }
  function new();
    Obj d = new(7, 9);
    a = '{default: d};
    a[3] = new(1, 2);
    a[5] = null;
  endfunction
endclass

// Without a default, only a stored object has members
class NoDefault;
  Obj a[int];
  rand int ai;
  rand int x;
  rand int y;
  constraint c {
    ai inside {[0 : 9]};
    x == a[ai].nr;
    y == a[ai].sub.nr;
  }
  function new();
    a[3] = new(1, 2);
    a[5] = null;
  endfunction
endclass

module t;
  initial begin
    automatic WithDefault wd = new;
    automatic NoDefault nd = new;
    automatic int ok;
    repeat (10) begin
      ok = wd.randomize() with {
        x == 7;
      };
      `checkd(ok, 1);
      `checkd(wd.a.exists(wd.ai), 0);
      `checkd(wd.y, 9);
      ok = wd.randomize() with {
        y == 9;
      };
      `checkd(ok, 1);
      `checkd(wd.a.exists(wd.ai), 0);
      `checkd(wd.x, 7);
      ok = wd.randomize() with {
        x == 1;
      };
      `checkd(ok, 1);
      `checkd(wd.ai, 3);
      `checkd(wd.y, 2);
      ok = nd.randomize();
      `checkd(ok, 1);
      `checkd(nd.ai, 3);
      `checkd(nd.x, 1);
      `checkd(nd.y, 2);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
