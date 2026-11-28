// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A member of a member object of the object a random index selects from an array not
// randomized is read as of that object; a null handle on the path selects no object

class Sub;
  int nr;
  function new(int n);
    nr = n;
  endfunction
endclass

class Obj;
  Sub sub;
  function new(int s);
    if (s >= 0) sub = new(s);
  endfunction
endclass

class Fixed;
  Obj a[4];
  rand bit [1:0] k;
  rand int y;
  constraint c {y == a[k].sub.nr;}
  function new();
    foreach (a[i]) a[i] = new(10 + i);
    // No member object
    a[1] = new(-1);
  endfunction
endclass

class Dyn;
  Obj a[];
  rand int k;
  rand int y;
  constraint c {
    k inside {[0 : 5]};
    y == a[k].sub.nr;
  }
  function new();
    a = new[4];
    foreach (a[i]) a[i] = new(20 + i);
    a[2] = null;
  endfunction
endclass

class Assoc;
  Obj a[int];
  rand int k;
  rand int y;
  rand bit c3;
  constraint c {
    k inside {[0 : 9]};
    y == a[k].sub.nr;
  }
  // Where k need not select an object, a null on the path reads zero
  constraint c_if {if (a[k].sub.nr == 0) c3 == 1'b1;}
  function new();
    a[2] = new(32);
    a[6] = new(36);
    a[7] = new(-1);
  endfunction
endclass

// Through a rand member object of the objects of an array not randomized, read as a value too
class RandSubObj;
  rand Sub sub;
  function new(int s);
    sub = new(s);
  endfunction
endclass

class RandSub;
  RandSubObj a[4];
  rand bit [1:0] k;
  rand int y;
  constraint c {y == a[k].sub.nr;}
  function new();
    foreach (a[i]) a[i] = new(40 + i);
  endfunction
endclass

module t;
  initial begin
    automatic Fixed fx = new;
    automatic Dyn dy = new;
    automatic Assoc as = new;
    automatic RandSub rs = new;
    automatic int ok;
    repeat (10) begin
      ok = fx.randomize();
      `checkd(ok, 1);
      `checkd(fx.k != 1, 1'b1);
      `checkd(fx.y, 10 + int'(fx.k));
      ok = dy.randomize();
      `checkd(ok, 1);
      `checkd(dy.k inside {0, 1, 3}, 1'b1);
      `checkd(dy.y, 20 + dy.k);
      ok = as.randomize();
      `checkd(ok, 1);
      `checkd(as.k == 2 || as.k == 6, 1'b1);
      `checkd(as.y, 30 + as.k);
    end
    ok = fx.randomize() with {
      y == 12;
    };
    `checkd(ok, 1);
    `checkd(fx.k, 2);
    ok = fx.randomize() with {
      y == 11;
    };
    `checkd(ok, 0);
    ok = rs.randomize() with {
      y == 42;
    };
    `checkd(ok, 1);
    `checkd(rs.k, 2);
    `checkd(rs.a[2].sub.nr, 42);
    ok = as.randomize() with {
      y == 36;
    };
    `checkd(ok, 1);
    `checkd(as.k, 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
