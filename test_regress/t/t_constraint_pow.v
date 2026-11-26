// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A constraint with a power the solver cannot express is ignored, alone
/* verilator lint_off CONSTRAINTIGN */
class PowIgnored;
  rand bit [3:0] n;
  rand int r, s, s2, t, t2, u, v, w;
  rand bit sel;
  rand int arr[3];
  constraint c_plain {
    r == 3 ** n;
    n inside {[1 : 5]};
    r > 100;
  }
  constraint c_nonconst {
    w == r ** n;
    w == 11;
  }
  constraint c_if {
    sel == 1'b1;
    if (sel) {
      s == 3 ** n;
      s2 == 5;
    }
    s == 7;
  }
  constraint c_impl {
    sel -> t == 3 ** n;
    sel -> {
      t == 3 ** n;
      t2 == 6;
    }
    t == 9;
  }
  constraint c_cond {
    if (3 ** n > 100) u == 1;
    else u == 2;
    v == 3;
  }
  constraint c_foreach {
    foreach (arr[i]) arr[i] == 3 ** n;
    foreach (arr[i]) arr[i] == i;
  }
endclass
/* verilator lint_on CONSTRAINTIGN */

module t;
  initial begin
    PowIgnored p;
    int randomize_result;
    p = new;
    randomize_result = p.randomize();
    `checkd(randomize_result, 1);
    `checkd(p.n inside {[1 : 5]}, 1'b1);
    `checkd(p.r > 100, 1'b1);
    `checkd(p.w, 11);
    `checkd(p.s, 7);
    `checkd(p.s2, 5);
    `checkd(p.t, 9);
    `checkd(p.t2, 6);
    `checkd(p.v, 3);
    foreach (p.arr[i]) `checkd(p.arr[i], i);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
