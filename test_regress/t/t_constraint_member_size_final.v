// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// A base class reduction over a member object's array that a derived class sizes holds in
// the final solve of a sibling class call that resizes another array

class FinalLeaf;
  rand int q[$];
  constraint c_dom {foreach (q[i]) q[i] inside {[0 : 9]};}
  function new();
    q = '{1, 2};
  endfunction
endclass

class FinalBase;
  rand FinalLeaf sub;
  constraint c_sum {sub.q.sum() == 10;}
  function new();
    sub = new;
  endfunction
endclass
class FinalSized extends FinalBase;
  constraint c_size {sub.q.size() == 3;}
endclass
class FinalOther extends FinalBase;
  rand int other[$];
  constraint c_other {other.size() inside {[1 : 4]};}
endclass

module t;
  initial begin
    automatic FinalOther other = new;
    automatic FinalSized sized = new;
    int ok;
    automatic bit failed = 0;
    for (int turn = 0; turn < 6; ++turn) begin
      ok = other.randomize();
      `checkd(ok, 1);
      `checkd(other.sub.q.size(), 2);
      `checkd(other.sub.q.sum(), 10);
      ok = other.randomize() with {other.size() == 3;};
      `checkd(ok, 1);
      `checkd(other.other.size(), 3);
      `checkd(other.sub.q.size(), 2);
      `checkd(other.sub.q.sum(), 10);
      ok = sized.randomize();
      `checkd(ok, 1);
      `checkd(sized.sub.q.size(), 3);
      `checkd(sized.sub.q.sum(), 10);
    end
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
