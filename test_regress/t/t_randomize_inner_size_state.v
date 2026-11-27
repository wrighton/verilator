// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The size of an element of an array in a constraint is unsupported and treated as state, so
// randomize() fails unless the elements have sizes satisfying the constraints

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Sizes;
  rand bit [7:0] dd[][];
  constraint c {
    dd.size() == 2;
    foreach (dd[i]) dd[i].size() == 3;
  }
endclass

class Elems;
  rand bit [7:0] dd[][];
  constraint c {
    dd.size() == 2;
    foreach (dd[i]) dd[i].size() == 3;
    foreach (dd[i, j]) dd[i][j] > 5;
  }
endclass

module t;
  initial begin
    automatic Sizes s = new;
    automatic Elems e = new;
    int ok;
    // The empty elements of the resized array do not have size 3
    ok = s.randomize();
    `checkd(ok, 0);
    `checkd(s.dd.size(), 0);
    ok = e.randomize();
    `checkd(ok, 0);
    `checkd(e.dd.size(), 0);
    // Elements of size 3 satisfy the constraints
    s.dd = new[2];
    foreach (s.dd[i]) s.dd[i] = new[3];
    ok = s.randomize();
    `checkd(ok, 1);
    `checkd(s.dd.size(), 2);
    `checkd(s.dd[1].size(), 3);
    e.dd = new[2];
    foreach (e.dd[i]) e.dd[i] = new[3];
    ok = e.randomize();
    `checkd(ok, 1);
    foreach (e.dd[i, j]) if (e.dd[i][j] <= 5) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
