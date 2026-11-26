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

// A product of two random variables
class Factors;
  rand bit [15:0] factor_a;
  rand bit [15:0] factor_b;
  constraint c {
    factor_a * factor_b == 32'd391;
    factor_a > 16'd1;
    factor_b > 16'd1;
  }
endclass

// Products of a random variable and a literal
class Tripled;
  rand bit [7:0] tripled;
  constraint c {
    tripled * 8'd3 == 8'd9;
    8'd5 * tripled == 8'd15;
  }
endclass

module t;

  Packet p;

  int v;

  initial begin
    p = new;
    v = p.randomize();
    if (v != 1) $stop;
    if (p.one != 1) $stop;

    begin
      automatic Factors f = new;
      v = f.randomize();
      `checkd(v, 1);
      `checkd(f.factor_a * f.factor_b, 391);
    end

    begin
      automatic Tripled t = new;
      v = t.randomize();
      `checkd(v, 1);
      `checkd(t.tripled, 3);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
