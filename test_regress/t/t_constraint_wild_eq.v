// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Wildcard equality operators in constraints, with 2-state operands;
// the signed operands differ in width, so are sign extended
class Narrow;
  rand bit [6:0] x;
  rand bit [6:0] y;
  constraint c_upper {x[6:1] == y[6:1];}
  constraint c_ne {x !=? y;}
endclass

class Equal;
  rand bit [6:0] x;
  rand bit [6:0] y;
  constraint c_eq {x ==? y;}
endclass

// verilator lint_off WIDTHEXPAND
class Signed;
  rand bit signed [3:0] s;
  rand bit signed [7:0] t;
  constraint c_t {t == -1;}
  constraint c_s {s inside {-1, 0};}
  constraint c_ne {s !=? t;}
endclass
// verilator lint_on WIDTHEXPAND

class Wide;
  rand bit [94:0] w;
  rand bit [94:0] v;
  constraint c_upper {w[94:1] == v[94:1];}
  constraint c_ne {w !=? v;}
endclass

class Unsat;
  rand bit [3:0] u;
  rand bit [3:0] w;
  constraint c_eq {u == w;}
  constraint c_ne {u !=? w;}
endclass

module t;
  initial begin
    automatic Narrow narrow = new;
    automatic Equal equal = new;
    automatic Signed sgn = new;
    automatic Wide wide = new;
    automatic Unsat unsat = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = narrow.randomize();
      `checkd(randomize_result, 1);
      `checkd(narrow.x !=? narrow.y, 1'b1);
      `checkd(narrow.x != narrow.y, 1'b1);
      randomize_result = equal.randomize();
      `checkd(randomize_result, 1);
      `checkd(equal.x ==? equal.y, 1'b1);
      randomize_result = sgn.randomize();
      `checkd(randomize_result, 1);
      // verilator lint_off WIDTHEXPAND
      `checkd(sgn.s !=? sgn.t, 1'b1);
      // verilator lint_on WIDTHEXPAND
      `checkd(sgn.s, 4'sd0);
      randomize_result = wide.randomize();
      `checkd(randomize_result, 1);
      `checkd(wide.w !=? wide.v, 1'b1);
      `checkd(wide.w != wide.v, 1'b1);
    end
    randomize_result = unsat.randomize();
    `checkd(randomize_result, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
