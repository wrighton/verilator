// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A rand class handle compared in a constraint guard is state; only the rand
// members of the object it refers to are solved (IEEE 1800-2023 18.5.13)
class Sub;
  rand int x;
endclass

class Holder;
  rand int y;
  rand Sub s;
  constraint c_y {y inside {[0 : 100]};}
  constraint c_member {if (s != null) s.x > y;}
endclass

class NullGuard;
  rand int y;
  rand Sub s;
  constraint c {
    (s == null) -> y == 9;
    (s != null) -> y == 5;
  }
endclass

module t;
  initial begin
    int res;

    begin
      automatic Holder h = new;
      h.s = new;
      repeat (10) begin
        res = h.randomize();
        `checkd(res, 1);
        `checkd(h.s.x > h.y, 1);
      end
    end

    begin
      automatic NullGuard g = new;
      res = g.randomize();
      `checkd(res, 1);
      `checkd(g.y, 9);
      g.s = new;
      res = g.randomize();
      `checkd(res, 1);
      `checkd(g.y, 5);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
