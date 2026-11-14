// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// randomize(null) checks a base class reduction over a member object's array at its
// current size, also where a derived class sizes that array

class CheckLeaf;
  rand int q[$];
  function new();
    q = '{1, 2};
  endfunction
endclass

class CheckBase;
  rand CheckLeaf sub;
  int want = 3;
  constraint c_count {sub.q.sum() with (32'(1)) == want;}
  function new();
    sub = new;
  endfunction
endclass
class CheckSized extends CheckBase;
  constraint c_size {sub.q.size() == 3;}
endclass
class CheckUnsized extends CheckBase;
endclass

module t;
  initial begin
    automatic CheckUnsized unsized = new;
    automatic CheckSized sized = new;
    int ok;
    automatic bit failed = 0;
    ok = unsized.randomize(null);
    `checkd(ok, 0);
    unsized.want = 2;
    ok = unsized.randomize(null);
    `checkd(ok, 1);
    // The check follows a size the user changed
    unsized.sub.q.push_back(7);
    ok = unsized.randomize(null);
    `checkd(ok, 0);
    unsized.want = 3;
    ok = unsized.randomize(null);
    `checkd(ok, 1);
    `checkd(unsized.sub.q.size(), 3);
    `checkd(unsized.sub.q[2], 7);
    ok = sized.randomize(null);
    `checkd(ok, 0);
    sized.sub.q.push_back(9);
    ok = sized.randomize(null);
    `checkd(ok, 1);
    `checkd(sized.sub.q[2], 9);
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
