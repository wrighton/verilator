// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// Many variables each fixed by a constraint, named by base-4 digits
`define FIXED(i) rand bit [15:0] x``i; constraint c``i {x``i == 16'(i + 91);}
`define FIXED4(i) `FIXED(i``0) `FIXED(i``1) `FIXED(i``2) `FIXED(i``3)
`define FIXED16(i) `FIXED4(i``0) `FIXED4(i``1) `FIXED4(i``2) `FIXED4(i``3)
`define FIXED64(i) `FIXED16(i``0) `FIXED16(i``1) `FIXED16(i``2) `FIXED16(i``3)
`define FIXED256(i) `FIXED64(i``0) `FIXED64(i``1) `FIXED64(i``2) `FIXED64(i``3)
// verilog_format: on

// Test: spreading the values of many variables the constraints fix, with others free

class Many;
  `FIXED256(0)
  rand bit [6:0] y;
  constraint cy {y < 7'd100;}
endclass

// A fixed variable beside coupled free ones, whose pairs are all spread
class Coupled;
  rand bit [15:0] x;
  rand bit [1:0] a;
  rand bit [1:0] z;
  rand bit [1:0] limit;
  constraint c {
    x == 16'd1234;
    a < limit;
    z < limit;
    a != z;
  }
endclass

module t;
  initial begin
    automatic Many m = new;
    automatic bit [6:0] ys[4];
    automatic int randomize_result;
    for (int i = 0; i < 4; ++i) begin
      randomize_result = m.randomize();
      `checkd(randomize_result, 1);
      `checkd(m.x00000, 16'd91);
      `checkd(m.x01230, 16'd1321);
      `checkd(m.x03333, 16'd3424);
      `checkd(m.y < 100, 1'b1);
      ys[i] = m.y;
    end
    `checkd(ys[0] == ys[1] && ys[1] == ys[2] && ys[2] == ys[3], 1'b0);
    begin
      automatic Coupled c = new;
      automatic int pairs[4][4] = '{default: 0};
      c.limit = 3;
      // Not randomized, so values are spread by assumptions on the bits
      c.limit.rand_mode(0);
      repeat (300) begin
        randomize_result = c.randomize();
        `checkd(randomize_result, 1);
        `checkd(c.x, 16'd1234);
        `checkd(c.a < 3 && c.z < 3 && c.a != c.z, 1'b1);
        ++pairs[c.a][c.z];
      end
      // Each of the 6 pairs, about 1/6 of the calls apart from the solver's bias
      foreach (pairs[i, j]) if (i < 3 && j < 3 && i != j) `checkd(pairs[i][j] > 6, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
