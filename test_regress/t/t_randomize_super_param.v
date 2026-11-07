// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// super.randomize() in a class whose base class is parameterized

class PBase #(
    parameter int W = 8
);
  rand bit [W-1:0] px;
  rand bit [W-1:0] py;
  constraint c_base {px < 100;}
endclass

class PSub extends PBase #(16);
  rand bit [15:0] sz;
  constraint c_sub {sz == px + 1;}
  function int plain();
    return super.randomize();
  endfunction
  function int args();
    return super.randomize(py);
  endfunction
endclass

// Base class with its default parameter value
class PSubDefault extends PBase;
  function int plain();
    return super.randomize();
  endfunction
endclass

// Not parameterized
class NBase;
  rand bit [7:0] nx;
  constraint c_nbase {nx < 50;}
endclass

class NSub extends NBase;
  rand bit [7:0] ny;
  constraint c_nsub {ny == nx + 1;}
  function int plain();
    return super.randomize();
  endfunction
endclass

module t;
  initial begin
    automatic PSub ps = new;
    automatic PSubDefault pd = new;
    automatic NSub ns = new;
    repeat (10) begin
      `checkd(ps.plain(), 1);
      `checkd(ps.px < 100, 1'b1);
      `checkd(ps.sz, ps.px + 16'd1);
      `checkd(pd.plain(), 1);
      `checkd(pd.px < 100, 1'b1);
      `checkd(ns.plain(), 1);
      `checkd(ns.nx < 50, 1'b1);
      `checkd(ns.ny, ns.nx + 8'd1);
    end
    // Only py is randomized
    ps.px = 5;
    ps.sz = 6;
    `checkd(ps.args(), 1);
    `checkd(ps.px, 5);
    `checkd(ps.sz, 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
