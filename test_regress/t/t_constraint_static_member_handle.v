// DESCRIPTION: Verilator: Static rand members of objects reached through rand class handles
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// Two constraints name the static member; a derived class overrides one of them
class over_obj;
  static rand int s;
  rand int x;
endclass

class over_base;
  rand over_obj d;
  constraint c1 {
    d.s > 5;
    d.x > 5;
  }
  constraint c2 {
    d.s < 9;
    d.x < 9;
  }
  function new;
    d = new;
  endfunction
endclass

class over_derived extends over_base;
  constraint c1 {d.x > 6;}
endclass

// Only a derived class holds the handle; the static member's own constraint applies too
class leaf_cfg;
  static rand bit [3:0] g;
  constraint leaf_c {g < 5;}
endclass

class leaf_base;
  rand bit [3:0] y;
  constraint c {
    leaf_cfg::g == 7;
    y == leaf_cfg::g;
  }
endclass

class leaf_derived extends leaf_base;
  rand leaf_cfg s;
  function new();
    s = new;
  endfunction
endclass

module t;
  initial begin
    over_base b;
    over_derived d;
    leaf_derived l;
    int ok;
    b = new;
    d = new;
    l = new;
    repeat (10) begin
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.d.s > 5 && b.d.s < 9, 1);
      `checkd(b.d.x > 5 && b.d.x < 9, 1);
      over_obj::s = 100;
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.d.x > 6 && d.d.x < 9, 1);
      `checkd(d.d.s < 9, 1);
    end
    // g == 7 contradicts g < 5
    ok = l.randomize();
    `checkd(ok, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
