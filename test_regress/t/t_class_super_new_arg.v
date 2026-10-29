// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

int unit_v = 2;

function int unit_fn();
  return unit_v * 3;
endfunction

function int unit_arg_fn(int k);
  int t;
  t = k + unit_v;
  return t * 10;
endfunction

class Base;
  int a;
  function new(int x);
    a = x;
  endfunction
endclass

// $unit function call argument
class UnitFn extends Base;
  function new();
    super.new(unit_fn());
  endfunction
endclass

// Function with arguments and locals, and a static method
class ArgFn extends Base;
  static function int sfn(int k);
    return k + 100;
  endfunction
  function new(int y);
    super.new(unit_arg_fn(y) + sfn(y));
  endfunction
endclass

// Arguments given in the extends clause
class ExtArgs extends Base(unit_fn() + 1);
endclass

// Wide argument expression
class WideBase;
  bit [127:0] w;
  function new(bit [127:0] x);
    w = x;
  endfunction
endclass
class Wide extends WideBase;
  function new(bit [127:0] y, bit [127:0] z);
    super.new(y + z);
  endfunction
endclass

// Property initializers run after super.new (IEEE 1800-2023 8.7)
class InitBase;
  function new();
    set_m();
  endfunction
  virtual function void set_m();
  endfunction
endclass
class InitOrder extends InitBase;
  int m = 5;
  function new();
    super.new();
  endfunction
  virtual function void set_m();
    m = 9;
  endfunction
endclass

module t;
  initial begin
    UnitFn u;
    ArgFn f;
    ExtArgs e;
    Wide w;
    InitOrder o;
    bit [127:0] wy;

    unit_v = $c(4);
    u = new;
    `checkd(u.a, 12);
    f = new(1);
    `checkd(f.a, 151);
    e = new;
    `checkd(e.a, 13);
    wy = {64'h1, 64'hffff_ffff_ffff_ffff};
    w = new(wy, 128'h2);
    `checkh(w.w, {64'h2, 64'h1});
    o = new;
    `checkd(o.m, 5);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
