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

// A random key selecting an element of a rand associative array is solved, not its current value

typedef struct packed {
  bit [3:0] f;
  bit [3:0] g;
} ps_t;

typedef bit [4:0] k5_t;

class Sub;
  rand int unsigned aa[int];
  function new();
    aa[2] = 0;
    aa[4] = 0;
  endfunction
endclass

class Cls;
  rand int ki;
  rand int unsigned ai[int];
  rand k5_t k5;  // Narrower than the solver's 8-bit key
  rand int unsigned a5[k5_t];
  rand bit [39:0] k40;  // Narrower than the solver's 64-bit key
  rand int unsigned a40[bit [39:0]];
  rand bit [128:0] k129;  // Narrower than the solver's 160-bit key
  rand int unsigned a129[bit [128:0]];
  rand byte kb;
  rand int unsigned ab[byte];
  rand int ks;
  rand Sub sub;
  rand int kp;
  rand ps_t ap[int];
  int sel;  // Which of two elements to select, varied between calls

  function new();
    ai[1] = 0;
    ai[3] = 0;
    a5[2] = 0;
    a5[30] = 0;
    a40[5] = 0;
    a40[40'h80_0000_0001] = 0;
    a129[6] = 0;
    a129[129'h1_ffff_ffff_ffff_ffff_ffff_ffff] = 0;
    ab[1] = 0;
    ab[-1] = 0;
    sub = new;
    ap[1] = 0;
    ap[5] = 0;
  endfunction

  constraint c_values {
    ai[1] == 10;
    ai[3] == 11;
    a5[2] == 10;
    a5[30] == 11;
    a40[5] == 10;
    a40[40'h80_0000_0001] == 11;
    a129[6] == 10;
    a129[129'h1_ffff_ffff_ffff_ffff_ffff_ffff] == 11;
    ab[1] == 10;
    ab[-1] == 11;
    sub.aa[2] == 10;
    sub.aa[4] == 11;
    ap[1].f == 10;
    ap[5].f == 11;
  }
  constraint c_keys {
    ki inside {1, 3};
    k5 inside {2, 30};
    k40 inside {5, 40'h80_0000_0001};
    k129 inside {6, 129'h1_ffff_ffff_ffff_ffff_ffff_ffff};
    kb inside {1, -1};
    ks inside {2, 4};
    kp inside {1, 5};
    ai[ki] == 10 + sel;
    a5[k5] == 10 + sel;
    a40[k40] == 10 + sel;
    a129[k129] == 10 + sel;
    ab[kb] == 10 + sel;
    sub.aa[ks] == 10 + sel;
    ap[kp].f == 4'(10 + sel);
  }
endclass

module t;
  initial begin
    automatic Cls c = new;
    int randomize_result;
    repeat (4) begin
      for (int sel = 0; sel < 2; ++sel) begin
        c.sel = sel;
        randomize_result = c.randomize();
        `checkd(randomize_result, 1);
        `checkd(c.ki, sel == 1 ? 3 : 1);
        `checkd(c.k5, sel == 1 ? 30 : 2);
        `checkh(c.k40, sel == 1 ? 40'h80_0000_0001 : 40'd5);
        `checkh(c.k129, sel == 1 ? 129'h1_ffff_ffff_ffff_ffff_ffff_ffff : 129'd6);
        `checkd(c.kb, sel == 1 ? -1 : 1);
        `checkd(c.ks, sel == 1 ? 4 : 2);
        `checkd(c.kp, sel == 1 ? 5 : 1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
