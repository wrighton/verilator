// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element of a dynamic array or queue reached through a class handle, or selected from
// another array, reads zero out of range (IEEE 1800-2023 7.4.6)

class Inner;
  rand bit [7:0] d[];
  function new();
    d = new[2];
  endfunction
endclass

class Holder;
  rand Inner b;
  function new();
    b = new;
  endfunction
endclass

class Nested;
  rand Inner h;
  rand Holder hh;  // Through two handles
  rand bit [7:0] m[2][];
  rand bit [7:0] dd[][];
  rand bit [7:0] qq[$][$];
  rand int j;
  int s;
  rand bit [7:0] yh, ym, ydd, yqq, sh, sm, sdd, sqq, yhh, shh;
  constraint c {
    j inside {[0 : 4]};
    yh == h.d[j];
    ym == m[0][j];
    ydd == dd[1][j];
    yqq == qq[1][j];
    sh == h.d[s];
    sm == m[1][s];
    sdd == dd[1][s];
    sqq == qq[0][s];
    yhh == hh.b.d[j];
    shh == hh.b.d[s];
  }
  function new();
    h = new;
    hh = new;
    m[0] = new[2];
    m[1] = new[3];
    dd = new[2];
    dd[1] = new[2];
    qq = '{'{8'h71, 8'h72, 8'h73}, '{8'h74, 8'h75}};
  endfunction
endclass

class Last;
  rand int q[$];
  constraint c {q[q.size() - 1] == 5;}
endclass

class LastHolder;
  rand Last l;
  function new();
    l = new;
  endfunction
endclass

module t;
  initial begin
    automatic Nested o = new;
    automatic int randomize_result;
    for (int n = 0; n < 25; ++n) begin
      automatic int want = n / 5;
      o.s = n % 5;
      randomize_result = o.randomize() with { j == want; };
      `checkh(randomize_result, 1);
      `checkh(o.yh, o.j < 2 ? o.h.d[o.j] : 8'h0);
      `checkh(o.ym, o.j < 2 ? o.m[0][o.j] : 8'h0);
      `checkh(o.ydd, o.j < 2 ? o.dd[1][o.j] : 8'h0);
      `checkh(o.yqq, o.j < 2 ? o.qq[1][o.j] : 8'h0);
      `checkh(o.sh, o.s < 2 ? o.h.d[o.s] : 8'h0);
      `checkh(o.sm, o.s < 3 ? o.m[1][o.s] : 8'h0);
      `checkh(o.sdd, o.s < 2 ? o.dd[1][o.s] : 8'h0);
      `checkh(o.sqq, o.s < 3 ? o.qq[0][o.s] : 8'h0);
      `checkh(o.yhh, o.j < 2 ? o.hh.b.d[o.j] : 8'h0);
      `checkh(o.shh, o.s < 2 ? o.hh.b.d[o.s] : 8'h0);
    end
    // An element past the end of an empty queue of a member object, whose size is not
    // randomized, reads zero
    begin
      automatic LastHolder lh = new;
      randomize_result = lh.randomize();
      `checkh(randomize_result, 0);
      `checkh(lh.l.q.size(), 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
