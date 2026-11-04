// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A random key selecting an element of a non-random associative array reads the array's
// current elements; a key that does not exist reads the default element

typedef struct {
  int a;
  int b;
} s_t;

typedef bit [4:0] k5_t;

class Item;
  int x;
  function new(int x);
    this.x = x;
  endfunction
endclass

class Cls;
  rand int ki;
  int unsigned ai[int];
  rand k5_t k5;  // Narrower than the solver's 8-bit key
  int unsigned a5[k5_t];
  rand bit [39:0] k40;  // Narrower than the solver's 64-bit key
  int unsigned a40[bit [39:0]];
  rand bit [128:0] k129;  // Narrower than the solver's 160-bit key
  int unsigned a129[bit [128:0]];
  rand byte kb;
  int unsigned ab[byte];
  rand int ko;
  Item ao[int];

  constraint c_keys {
    ki inside {[0 : 9]};
    ai[ki] > 0;
    k5 inside {2, 30};
    a5[k5] > 0;
    k40 inside {5, 40'h80_0000_0001};
    a40[k40] > 0;
    k129 inside {6, 129'h1_ffff_ffff_ffff_ffff_ffff_ffff};
    a129[k129] > 0;
    kb inside {1, -1};
    ab[kb] > 0;
    ko inside {[0 : 9]};
    ao[ko].x > 0;
  }
endclass

module t;
  initial begin
    automatic Cls c = new;
    int randomize_result;
    for (int sel = 0; sel < 2; ++sel) begin
      // Only the selected one of two keys has a nonzero element
      c.ai = '{1: 1 - sel, 7: sel};
      c.a5 = '{2: 1 - sel, 30: sel};
      c.a40 = '{5: 1 - sel, 40'h80_0000_0001: sel};
      c.a129 = '{6: 1 - sel, 129'h1_ffff_ffff_ffff_ffff_ffff_ffff: sel};
      c.ab = '{1: 1 - sel, -1: sel};
      c.ao.delete();
      c.ao[3] = new(1 - sel);
      c.ao[8] = new(sel);
      repeat (4) begin
        randomize_result = c.randomize();
        `checkd(randomize_result, 1);
        `checkd(c.ki, sel == 1 ? 7 : 1);
        `checkd(c.k5, sel == 1 ? 30 : 2);
        `checkh(c.k40, sel == 1 ? 40'h80_0000_0001 : 40'd5);
        `checkh(c.k129, sel == 1 ? 129'h1_ffff_ffff_ffff_ffff_ffff_ffff : 129'd6);
        `checkd(c.kb, sel == 1 ? -1 : 1);
        `checkd(c.ko, sel == 1 ? 8 : 3);
      end
    end
    begin
      automatic int unsigned aa[int] = '{4: 0, 6: 9};
      automatic int idx;
      repeat (4) begin
        randomize_result = std::randomize(idx) with {aa[idx] == 9;};
        `checkd(randomize_result, 1);
        `checkd(idx, 6);
      end
    end
    begin
      // A key that does not exist reads the default element
      automatic int unsigned aa[int] = '{default: 5, 1: 0};
      automatic s_t sa[int] = '{default: '{5, 0}, 2: '{0, 5}};
      automatic int idx;
      repeat (4) begin
        randomize_result = std::randomize(idx) with {idx inside {[0 : 3]}; aa[idx] == 5;};
        `checkd(randomize_result, 1);
        if (idx == 1) `stop;
        randomize_result = std::randomize(idx) with {idx inside {[0 : 3]}; sa[idx].a == 5;};
        `checkd(randomize_result, 1);
        if (idx == 2) `stop;
      end
      randomize_result = std::randomize(idx) with {idx inside {[0 : 3]}; aa[idx] == 0;};
      `checkd(randomize_result, 1);
      `checkd(idx, 1);
      randomize_result = std::randomize(idx) with {idx inside {[0 : 3]}; sa[idx].b == 5;};
      `checkd(randomize_result, 1);
      `checkd(idx, 2);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
