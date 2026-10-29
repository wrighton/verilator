// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// 'local::' in 'randomize() with' on another object of the caller's own class
// binds to the caller object, not the randomized one (IEEE 1800-2023 18.7.1)
class Cls;
  rand int x;
  int lim;
  function int rand_lim(Cls other);
    return other.randomize() with { x == local::lim; };
  endfunction
  function int rand_x(Cls other);
    return other.randomize() with { x == local::x + 1; };
  endfunction
endclass

// 'local::this' and 'local::super' (IEEE 1800-2023 18.7.1)
class Base;
  int blim;
endclass
class Sub extends Base;
  rand int x;
  int lim;
  Sub peer;
  function int get_lim();
    return lim;
  endfunction
  function int rand_this(Sub other);
    int lim = 99;  // Not found by local::this
    return other.randomize() with { x == local::this.lim; };
  endfunction
  function int rand_both(Sub other);
    return other.randomize() with { x == this.lim - local::this.lim; };
  endfunction
  function int rand_super(Sub other);
    return other.randomize() with { x == local::super.blim; };
  endfunction
  function int rand_this_super(Sub other);
    return other.randomize() with { x == local::this.super.blim + 1; };
  endfunction
  function int rand_chain(Sub other);
    return other.randomize() with { x == local::this.peer.lim + local::this.get_lim(); };
  endfunction
endclass
class Other;
  rand bit [6:0] x;
  bit [6:0] lim;
endclass
class ParamOther #(
    int W = 4
);
  rand bit [W-1:0] x;
  bit [W-1:0] lim;
endclass
class Caller;
  bit [6:0] lim;
  function int rand_other(Other other);
    return other.randomize() with { x == local::this.lim; };
  endfunction
  function int rand_param(ParamOther #(7) other);
    return other.randomize() with { x == local::this.lim; };
  endfunction
endclass

module t;
  initial begin
    automatic Cls a = new;
    automatic Cls b = new;
    for (int i = 0; i < 3; ++i) begin
      a.lim = i * 10 + 3;
      b.lim = i * 10 + 5;
      `checkd(a.rand_lim(b), 1);
      `checkd(b.x, i * 10 + 3);
      a.x = i * 7;
      `checkd(a.rand_x(b), 1);
      `checkd(b.x, i * 7 + 1);
      `checkd(a.x, i * 7);
    end
  end

  initial begin
    automatic Sub a = new;
    automatic Sub b = new;
    automatic Sub p = new;
    a.peer = p;
    for (int i = 0; i < 3; ++i) begin
      a.lim = i * 10 + 3;
      a.blim = i * 10 + 4;
      b.lim = i * 10 + 5;
      b.blim = i * 10 + 6;
      p.lim = i * 10 + 7;
      `checkd(a.rand_this(b), 1);
      `checkd(b.x, i * 10 + 3);
      `checkd(a.rand_both(b), 1);
      `checkd(b.x, 2);
      `checkd(a.rand_super(b), 1);
      `checkd(b.x, i * 10 + 4);
      `checkd(a.rand_this_super(b), 1);
      `checkd(b.x, i * 10 + 5);
      `checkd(a.rand_chain(b), 1);
      `checkd(b.x, i * 20 + 10);
    end
  end

  initial begin
    automatic Caller c = new;
    automatic Other o = new;
    automatic ParamOther #(7) po = new;
    for (bit [6:0] i = 0; i < 3; ++i) begin
      c.lim = i * 10 + 3;
      o.lim = i * 10 + 5;
      po.lim = i * 10 + 5;
      `checkd(c.rand_other(o), 1);
      `checkd(o.x, i * 10 + 3);
      `checkd(c.rand_param(po), 1);
      `checkd(po.x, i * 10 + 3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
