// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  rand int x;
  constraint c_pos {x >= 0;}
endclass

// Its 'randomize() with' of Base is lowered before Derived, which then also has one of Base
class Driver;
  function int run(Base b);
    return b.randomize() with {x < 10;};
  endfunction
endclass

class Derived extends Base;
  Base inner;
  rand int y;
  constraint c_y {y == lim(x);}
  function int lim(int v);
    return v + 1;
  endfunction
  function int randomizeInner();
    inner = new;
    return inner.randomize() with {x > 3;};
  endfunction
endclass

module t;
  initial begin
    Driver drv;
    Base b;
    Derived d;
    drv = new;
    b = new;
    `checkd(drv.run(b), 1);
    `checkd(b.x >= 0 && b.x < 10, 1);
    d = new;
    `checkd(d.randomizeInner(), 1);
    `checkd(d.inner.x > 3, 1);
    `checkd(drv.run(d), 1);
    `checkd(d.y, d.x + 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
