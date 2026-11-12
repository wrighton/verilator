// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

class SizeLeaf;
  rand int q[$];
  function new();
    q = '{1, 2};
  endfunction
endclass

class SharedReduction;
  rand SizeLeaf sub;
  int total;
  constraint c_sum {sub.q.sum() == total;}
  function new();
    sub = new;
  endfunction
endclass

// The base is never directly randomized; the first derived class alone has a sizer.
class SizedFirst extends SharedReduction;
  constraint c_size {sub.q.size() == 3;}
endclass
class UnsizedSecond extends SharedReduction;
endclass

class ReverseReduction;
  rand SizeLeaf sub;
  int total;
  constraint c_sum {sub.q.sum() == total;}
  function new();
    sub = new;
  endfunction
endclass
// Reverse the declaring order as well as the order of calls below.
class UnsizedFirst extends ReverseReduction;
endclass
class SizedSecond extends ReverseReduction;
  constraint c_size {sub.q.size() == 3;}
endclass

module t;
  initial begin
    automatic SizedFirst sized = new;
    automatic UnsizedSecond unsized = new;
    automatic UnsizedFirst reverse_unsized = new;
    automatic SizedSecond reverse_sized = new;
    int ok;
    automatic bit failed = 0;
    for (int turn = 0; turn < 8; ++turn) begin
      sized.total = 10 + turn;
      unsized.total = 20 + turn;
      sized.sub.q = '{1, 2};
      unsized.sub.q = '{1, 2};
      ok = sized.randomize();
      `checkd(ok, 1);
      `checkd(sized.sub.q.size(), 3);
      `checkd(sized.sub.q.sum(), sized.total);
      ok = unsized.randomize();
      `checkd(ok, 1);
      `checkd(unsized.sub.q.size(), 2);
      `checkd(unsized.sub.q.sum(), unsized.total);
      reverse_unsized.total = 30 + turn;
      reverse_sized.total = 40 + turn;
      reverse_unsized.sub.q = '{1, 2};
      reverse_sized.sub.q = '{1, 2};
      ok = reverse_unsized.randomize();
      `checkd(ok, 1);
      `checkd(reverse_unsized.sub.q.size(), 2);
      `checkd(reverse_unsized.sub.q.sum(), reverse_unsized.total);
      ok = reverse_sized.randomize();
      `checkd(ok, 1);
      `checkd(reverse_sized.sub.q.size(), 3);
      `checkd(reverse_sized.sub.q.sum(), reverse_sized.total);
    end
    // Complete the native solver log even on failure; the driver requires this success marker.
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
