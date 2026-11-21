// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Packet;
  rand int one;
  constraint a {one > 0 && one < 2;}
endclass

// Its constraint and value are longer than a pipe buffer
class Long;
  rand bit [19999:0] w;
  constraint c {w != 0;}
endclass

// Operators over the elements of a one-element container: SMT-LIB 2.6 has no
// single-operand application of a bit-vector operator, so each is the element's term
class Single;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] sum_a[];
  rand bit [6:0] prod_a[];
  rand bit [6:0] and_a[];
  rand bit [6:0] or_a[];
  rand bit [6:0] xor_a[];
  rand bit [6:0] fixed[1];
  rand bit [6:0] grid[1][1];
  rand bit sel;
  bit [6:0] vals[$];
  function new;
    sum_a = new[1];
    prod_a = new[1];
    and_a = new[1];
    or_a = new[1];
    xor_a = new[1];
    vals.push_back(7'd17);
  endfunction
  constraint c {
    x inside {vals};
    !(y inside {vals});
    y > 7'd15 && y < 7'd19;
    sum_a.sum() == 7'd9;
    prod_a.product() == 7'd10;
    and_a.and() == 7'd11;
    or_a.or() == 7'd12;
    xor_a.xor() == 7'd13;
    sel -> foreach (fixed[i]) fixed[i] == 7'd5;
    sel -> foreach (grid[i, j]) grid[i][j] == 7'd6;
    sel == 1'b1;
  }
endclass

module t;

  Packet p;
  Long l;

  int v;

  initial begin
    p = new;
    v = p.randomize();
    if (v != 1) $stop;
    if (p.one != 1) $stop;
    l = new;
    v = l.randomize();
    if (v != 1) $stop;
    if (l.w == 0) $stop;

    begin
      automatic Single s = new;
      for (int i = 0; i < 4; ++i) begin
        v = s.randomize();
        `checkd(v, 1);
        `checkd(s.x, 7'd17);
        `checkd(s.y != 7'd17, 1'b1);
        `checkd(s.sum_a[0], 7'd9);
        `checkd(s.prod_a[0], 7'd10);
        `checkd(s.and_a[0], 7'd11);
        `checkd(s.or_a[0], 7'd12);
        `checkd(s.xor_a[0], 7'd13);
        `checkd(s.fixed[0], 7'd5);
        `checkd(s.grid[0][0], 7'd6);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
