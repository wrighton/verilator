// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// Struct elements of associative arrays inside and outside a fixed-size dimension

typedef struct {
  rand bit [7:0] f;
  rand bit [7:0] g;
} u2_t;

class Nested;
  rand u2_t ua[2][int];
  rand u2_t ub[int][2];
  constraint c {
    ua[1][5].f == 8'h15;
    ua[0][3].g == 8'h03;
    ub[7][1].f == 8'h71;
  }
  function new();
    ua[0][3].f = 8'h0;
    ua[1][5].f = 8'h0;
    ub[7][0].f = 8'h0;
  endfunction
endclass

module t;
  initial begin
    automatic Nested o = new;
    automatic int ok;
    repeat (3) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.ua[1][5].f, 8'h15);
      `checkh(o.ua[0][3].g, 8'h03);
      `checkh(o.ub[7][1].f, 8'h71);
      `checkh(o.ua[0].size() + o.ua[1].size() + o.ub.size(), 3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
