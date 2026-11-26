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

// A product of a random variable and a state variable, a literal to the solver
class Scaled;
  rand bit [7:0] scaled;
  bit [7:0] k = 8'd3;
  constraint c {scaled * k == 8'd9;}
endclass

// A quotient of two random variables
class Quotient;
  rand bit [15:0] quot_a;
  rand bit [15:0] quot_b;
  constraint c {
    quot_a / quot_b == 16'd7;
    quot_b > 16'd1;
    quot_a < 16'd100;
  }
endclass

// A product of two random variables in a disabled constraint
class Disabled;
  rand bit [15:0] dis_a;
  rand bit [15:0] dis_b;
  constraint prod {dis_a * dis_b == 32'd391;}
  constraint lin {dis_a == 16'd17;}
endclass

// Products of two random variables under a condition
class Guarded;
  rand bit [7:0] grd_x;
  rand bit [7:0] grd_y;
  int lane = 2;
  constraint c {
    if (lane == 2) grd_x * grd_y == 8'd12;
    grd_x > 8'd1;
    grd_y > 8'd1;
  }
endclass

class Implied;
  rand bit [7:0] imp_x;
  rand bit [7:0] imp_y;
  int lane = 2;
  constraint c {
    (lane == 2) -> (imp_x * imp_y == 8'd12);
    imp_x > 8'd1;
    imp_y > 8'd1;
  }
endclass

class IfElse;
  rand bit [7:0] ie_x;
  rand bit [7:0] ie_y;
  int lane = 2;
  constraint c {
    if (lane == 1) ie_x == 8'd1;
    else ie_x * ie_y == 8'd12;
    ie_x > 8'd1;
    ie_y > 8'd1;
  }
endclass

class Nested;
  rand bit [7:0] ne_x;
  rand bit [7:0] ne_y;
  int lane = 2;
  constraint c {
    if (lane > 0) {
      if (lane == 2) ne_x * ne_y == 8'd12;
    }
    ne_x > 8'd1;
    ne_y > 8'd1;
  }
endclass

class ImpliedSet;
  rand bit [7:0] is_x;
  rand bit [7:0] is_y;
  int lane = 2;
  constraint c {
    (lane == 2) -> {is_x * is_y == 8'd12;}
    is_x > 8'd1;
    is_y > 8'd1;
  }
endclass

class ForeachBody;
  rand bit [7:0] fe_x;
  rand bit [7:0] fe_y;
  int lanes[3] = '{0, 2, 0};
  constraint c {
    foreach (lanes[i]) if (lanes[i] == 2) fe_x * fe_y == 8'd12;
    fe_x > 8'd1;
    fe_y > 8'd1;
  }
endclass

class DistProduct;
  rand bit [7:0] dp_x;
  rand bit [7:0] dp_y;
  constraint c {
    (dp_x * dp_y) dist {8'd12 := 1, 8'd15 := 1};
    dp_x > 8'd1;
    dp_y > 8'd1;
  }
endclass

class SoftGuarded;
  rand bit [7:0] sg_x;
  rand bit [7:0] sg_y;
  int lane = 2;
  constraint c {
    if (lane == 2) soft sg_x * sg_y == 8'd12;
    sg_x > 8'd1;
    sg_y > 8'd1;
  }
endclass

// A product of two random variables in an inline constraint
class Inline;
  rand bit [15:0] inl_a;
  rand bit [15:0] inl_b;
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
      automatic Scaled s = new;
      automatic Quotient q = new;
      automatic Disabled d = new;
      automatic Inline i = new;
      automatic Guarded g = new;
      automatic Implied im = new;
      automatic IfElse ie = new;
      automatic Nested ne = new;
      automatic ImpliedSet is = new;
      automatic ForeachBody fe = new;
      automatic DistProduct dp = new;
      automatic SoftGuarded sg = new;
      v = s.randomize();
      `checkd(v, 1);
      `checkd(s.scaled * s.k, 9);
      v = q.randomize();
      `checkd(v, 1);
      `checkd(q.quot_a / q.quot_b, 7);
      d.prod.constraint_mode(0);
      v = d.randomize();
      `checkd(v, 1);
      `checkd(d.dis_a, 17);
      v = i.randomize() with {
        inl_a * inl_b == 32'd391;
        inl_a > 16'd1;
        inl_b > 16'd1;
      };
      `checkd(v, 1);
      `checkd(i.inl_a * i.inl_b, 391);
      v = g.randomize();
      `checkd(v, 1);
      `checkd(8'(g.grd_x * g.grd_y), 12);
      v = im.randomize();
      `checkd(v, 1);
      `checkd(8'(im.imp_x * im.imp_y), 12);
      v = ie.randomize();
      `checkd(v, 1);
      `checkd(8'(ie.ie_x * ie.ie_y), 12);
      v = ne.randomize();
      `checkd(v, 1);
      `checkd(8'(ne.ne_x * ne.ne_y), 12);
      v = is.randomize();
      `checkd(v, 1);
      `checkd(8'(is.is_x * is.is_y), 12);
      v = fe.randomize();
      `checkd(v, 1);
      `checkd(8'(fe.fe_x * fe.fe_y), 12);
      v = dp.randomize();
      `checkd(v, 1);
      `checkd(8'(dp.dp_x * dp.dp_y) inside {8'd12, 8'd15}, 1);
      v = sg.randomize();
      `checkd(v, 1);
      `checkd(8'(sg.sg_x * sg.sg_y), 12);
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
