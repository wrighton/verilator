// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element select of a dynamic array, and of a fixed-size one, by a random index that is
// itself such a select, which the solver checks against the array's size: the index is read
// once in the constraint text, so the text grows linearly with the depth of the nesting (see
// the .py)

// A 3-bit index selects among four elements
// verilator lint_off WIDTHTRUNC

class Nested;
  rand bit [7:0] tbl[];
  rand bit [1:0] j;
  rand bit [7:0] yone, yfour;
  rand bit [7:0] ftbl[4];
  rand bit [2:0] k;  // Up to twice the elements
  rand bit [7:0] zone, zfour;
  constraint c {
    yone == tbl[j];
    yfour == tbl[tbl[tbl[tbl[j] % 4] % 4] % 4];
    zone == ftbl[k];
    zfour == ftbl[ftbl[ftbl[ftbl[k] % 4] % 4] % 4];
  }
  function new();
    tbl = new[4];
  endfunction
endclass

module t;
  initial begin
    automatic Nested o = new;
    automatic int randomize_result;
    repeat (5) begin
      randomize_result = o.randomize();
      `checkh(randomize_result, 1);
      `checkh(o.yone, o.tbl[o.j]);
      `checkh(o.yfour, o.tbl[o.tbl[o.tbl[o.tbl[o.j] % 4] % 4] % 4]);
      `checkh(o.zone, o.k < 4 ? o.ftbl[o.k] : 8'h0);
      `checkh(o.zfour, o.ftbl[o.ftbl[o.ftbl[(o.k < 4 ? o.ftbl[o.k] : 8'h0) % 4] % 4] % 4]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// verilator lint_on WIDTHTRUNC
