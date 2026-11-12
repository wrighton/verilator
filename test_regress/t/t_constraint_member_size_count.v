// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

// A base class reduction depending on the number of elements of a member object's array,
// which only some derived classes size

class CountLeaf;
  rand int q[$];
  function new();
    q = '{1, 2};
  endfunction
endclass

class CountBase;
  rand CountLeaf sub;
  int want = 3;
  constraint c_count {sub.q.sum() with (32'(1)) == want;}
  constraint c_bound {sub.q.sum() with (32'(1)) <= 4;}
  function new();
    sub = new;
  endfunction
endclass
// The sized class is declared first here, and last for the reverse base below
class CountSized extends CountBase;
  constraint c_size {sub.q.size() == 3;}
endclass
class CountUnsized extends CountBase;
endclass
// Sizes an array of its own member of the same type, not the base class's
class CountExtra extends CountBase;
  rand CountLeaf extra;
  constraint c_extra {extra.q.size() == 3;}
  function new();
    super.new();
    extra = new;
  endfunction
endclass

class ReverseBase;
  rand CountLeaf sub;
  int want = 3;
  constraint c_count {sub.q.sum() with (32'(1)) == want;}
  function new();
    sub = new;
  endfunction
endclass
class ReverseUnsized extends ReverseBase;
endclass
class ReverseSized extends ReverseBase;
  constraint c_size {sub.q.size() == 3;}
endclass

module t;
  initial begin
    automatic CountSized sized = new;
    automatic CountUnsized unsized = new;
    automatic ReverseUnsized reverse_unsized = new;
    automatic ReverseSized reverse_sized = new;
    automatic CountBase base = new;
    automatic CountExtra extra = new;
    int ok;
    automatic bit failed = 0;
    for (int turn = 0; turn < 2; ++turn) begin
      // The unsized classes keep two elements
      unsized.want = 3;
      ok = unsized.randomize();
      `checkd(ok, 0);
      `checkd(unsized.sub.q.size(), 2);
      unsized.want = 2;
      ok = unsized.randomize();
      `checkd(ok, 1);
      reverse_unsized.want = 3;
      ok = reverse_unsized.randomize();
      `checkd(ok, 0);
      `checkd(reverse_unsized.sub.q.size(), 2);
      base.want = 3;
      ok = base.randomize();
      `checkd(ok, 0);
      `checkd(base.sub.q.size(), 2);
      extra.want = 3;
      extra.extra.q = '{1, 2};
      ok = extra.randomize();
      `checkd(ok, 0);
      `checkd(extra.sub.q.size(), 2);
      extra.want = 2;
      ok = extra.randomize();
      `checkd(ok, 1);
      `checkd(extra.sub.q.size(), 2);
      `checkd(extra.extra.q.size(), 3);
      // The sized classes resize to three before the count holds
      sized.want = 3;
      sized.c_size.constraint_mode(1);
      sized.sub.q = '{1, 2};
      ok = sized.randomize();
      `checkd(ok, 1);
      `checkd(sized.sub.q.size(), 3);
      reverse_sized.sub.q = '{1, 2};
      ok = reverse_sized.randomize();
      `checkd(ok, 1);
      `checkd(reverse_sized.sub.q.size(), 3);
      // With the size constraint off the array keeps its size
      sized.c_size.constraint_mode(0);
      sized.sub.q = '{1, 2};
      ok = sized.randomize();
      `checkd(ok, 0);
      `checkd(sized.sub.q.size(), 2);
      sized.want = 2;
      ok = sized.randomize();
      `checkd(ok, 1);
      `checkd(sized.sub.q.size(), 2);
    end
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
