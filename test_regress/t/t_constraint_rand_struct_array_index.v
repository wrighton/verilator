// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A member of the struct that a random index selects from an array of unpacked structs. An
// element out of range reads the default of the struct (IEEE 1800-2023 7.4.6).

typedef struct {
  bit [6:0] tag;
  struct {bit [3:0] lo;} in;
} tag_t;

class RandIndexItem;
  rand bit [14:0] val;
endclass

class RandIndexMemberTest;
  rand int idx;
  rand tag_t tags[3];
  rand RandIndexItem items[3];
  constraint member_c {
    tags[idx].tag == 7'h5;
    items[idx].val == 15'h6;
  }
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
endclass

// verilator lint_off WIDTHTRUNC
class Holder;
  rand bit [3:0] idx;
  rand tag_t tags[3];
  rand tag_t dyn[];
  rand tag_t que[$];
  tag_t st[3];
  int which;
  constraint c {
    which == 0 -> {
      tags[idx].tag == 7'h5;
      foreach (tags[i]) tags[i].tag != 7'h5 || i == 1;
    }
    // Only an element out of range reads zero
    which == 1 -> {
      tags[idx].tag == 0;
      foreach (tags[i]) tags[i].tag != 0;
    }
    which == 2 -> st[idx].tag == 9;
    which == 3 -> st[idx].tag == 0;
    which == 4 -> {
      tags[idx].in.lo == 4'd7;
      foreach (tags[i]) tags[i].in.lo != 4'd7 || i == 2;
    }
    which == 5 -> {
      dyn[idx].tag == 7'h11;
      foreach (dyn[i]) dyn[i].tag != 7'h11 || i == 3;
    }
    which == 6 -> {
      que[idx].in.lo == 4'd3;
      foreach (que[i]) que[i].in.lo != 4'd3 || i == 0;
    }
  }
  function new();
    st[0].tag = 3;
    st[1].tag = 9;
    st[2].tag = 4;
    dyn = new[5];
    que = '{'{default: 0}, '{default: 0}};
  endfunction
endclass

// A narrower signed index into arrays not based at zero
class NegLo;
  rand bit signed [5:0] k;
  rand tag_t desc[2:-2];
  rand tag_t asc[-2:2];
  int which;
  constraint c {
    which == 0 -> {
      desc[k].tag == 7'h5;
      foreach (desc[i]) desc[i].tag != 7'h5 || i == -2;
    }
    which == 1 -> {
      asc[k].tag == 7'h6;
      foreach (asc[i]) asc[i].tag != 7'h6 || i == -1;
    }
  }
endclass
// verilator lint_on WIDTHTRUNC

// The runtime names an element of an array of structs by its index padded to a power of two of
// bits, so of 9 to 16 elements by two hex digits, of 129 to 256 by four
// verilator lint_off WIDTHTRUNC
class Sizes;
  rand tag_t t9[9];
  rand tag_t t129[129];
  rand tag_t t1[1];
  rand tag_t m[9][3];
  rand bit [7:0] i9;
  rand bit [7:0] i129;
  rand bit i1;
  constraint c {
    t9[i9].tag == 7'h15;
    foreach (t9[i]) t9[i].tag != 7'h15 || i == 8;
    t129[i129].tag == 7'h16;
    foreach (t129[i]) t129[i].tag != 7'h16 || i == 128;
    t1[i1].tag == 7'h17;
    // Constant indices
    t9[8].in.lo == 4'd9;
    m[8][2].tag == 7'h18;
  }
endclass
// verilator lint_on WIDTHTRUNC

module t;
  initial begin
    automatic RandIndexMemberTest m = new;
    automatic Holder h = new;
    automatic NegLo n = new;
    automatic Sizes sz = new;
    automatic int ok;
    automatic bit seen[int];
    repeat (10) begin
      ok = m.randomize();
      `checkd(ok, 1);
      `checkd(m.idx inside {[0 : 2]}, 1'b1);
      `checkd(m.tags[m.idx].tag, 7'h5);
      `checkd(m.items[m.idx].val, 15'h6);
    end
    for (int which = 0; which <= 6; ++which) begin
      h.which = which;
      seen.delete();
      repeat (40) begin
        ok = h.randomize();
        `checkd(ok, 1);
        seen[int'(h.idx)] = 1;
        if (which == 0 || which == 2) begin
          `checkd(h.idx, 1);
        end else if (which == 1 || which == 3) begin
          `checkd(h.idx >= 3, 1'b1);
        end else if (which == 4) begin
          `checkd(h.idx, 2);
        end else if (which == 5) begin
          `checkd(h.idx, 3);
        end else begin
          `checkd(h.idx, 0);
        end
      end
      // Out of range, the index is free over its 13 values
      if (which == 1 || which == 3) begin
        `checkd(seen.size() > 4, 1'b1);
      end
    end
    // Out of range in an inline constraint too
    h.which = 99;
    seen.delete();
    repeat (40) begin
      // verilator lint_off WIDTHTRUNC
      ok = h.randomize() with {
        idx inside {[0 : 12]};
        tags[idx].tag == 0;
        foreach (tags[i]) tags[i].tag != 0;
      };
      // verilator lint_on WIDTHTRUNC
      `checkd(ok, 1);
      `checkd(h.idx >= 3, 1'b1);
      seen[int'(h.idx)] = 1;
    end
    `checkd(seen.size() > 4, 1'b1);
    repeat (5) begin
      ok = sz.randomize();
      `checkd(ok, 1);
      `checkd(sz.i9, 8);
      `checkd(sz.i129, 128);
      `checkd(sz.t1[0].tag, 7'h17);
      `checkd(sz.t9[8].in.lo, 4'd9);
      `checkd(sz.m[8][2].tag, 7'h18);
    end
    for (int which = 0; which <= 1; ++which) begin
      n.which = which;
      repeat (10) begin
        ok = n.randomize();
        `checkd(ok, 1);
        `checkd(n.k, which == 0 ? -2 : -1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
