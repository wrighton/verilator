// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Sub;
  rand int x;
  int y;
endclass

class Cls;
  int a;
  rand int b;
  rand int c;
  int d;
  int arr[4];
  rand int rarr[4];
  rand int q[$];
  rand Sub s;

  constraint c_lhs {solve a before b;}  // Illegal 18.5.9
  constraint c_rhs {solve b before c, d;}  // Illegal 18.5.9
  constraint c_arr {solve arr[1] before b;}  // Illegal 18.5.9
  constraint c_member {solve s.y before c;}  // Illegal 18.5.9
  constraint c_ok {
    solve s.x before b;
    solve rarr[0] before q[0];
    foreach (rarr[i]) {
      solve rarr[i] before c;
    }
  }
endclass

module t;
  Cls obj;

  initial begin
    obj = new;
    void'(obj.randomize(a) with {solve a before b;});
  end
endmodule
