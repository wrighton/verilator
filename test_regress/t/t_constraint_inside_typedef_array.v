// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  typedef int int_q[$];
  typedef int int_da[];
  typedef int int_up[4];
  typedef int int_up_desc[3:1];
  typedef int int_up_asc[1:3];
  typedef int int_up_neg[-1:-3];
  typedef int_q alias_q;

  class Bundle;
    int_q q;
    int_da d;
    int_up u;
    int_up_desc ud;
    int_up_asc ua;
    int_up_neg un;
  endclass
endpackage

// A class constraint on fixed-size arrays with a nonzero low bound, state or random
class InsideLowBound;
  bit [6:0] state_arr[3:1];
  rand bit [6:0] rand_arr[3:1];
  rand bit [6:0] x;
  rand bit [6:0] y;
  constraint c {
    foreach (rand_arr[i]) rand_arr[i] == 7'(i * 10);
    x inside {state_arr};
    y inside {rand_arr};
  }
endclass

module t;
  import pkg::*;

  initial begin
    automatic Bundle b = new();
    automatic int t_l = 0;
    automatic int rv;
    automatic alias_q a = '{32'd1, 32'd2, 32'd3};

    b.q = '{32'd10, 32'd20, 32'd30};
    b.d = new[3];
    b.d = '{32'd40, 32'd50, 32'd60};
    b.u = '{32'd70, 32'd80, 32'd90, 32'd100};

    // Original reported shape: typedef queue member of a class,
    // used as the array in `inside {...}` of a with-constraint.
    repeat (20) begin
      rv = std::randomize(t_l) with { t_l inside {b.q}; };
      `checkd(rv, 1);
      `checkd((t_l == 10 || t_l == 20 || t_l == 30), 1'b1);
    end

    // Typedef dynamic array.
    repeat (20) begin
      rv = std::randomize(t_l) with { t_l inside {b.d}; };
      `checkd(rv, 1);
      `checkd((t_l == 40 || t_l == 50 || t_l == 60), 1'b1);
    end

    // Typedef unpacked (fixed-size) array.
    repeat (20) begin
      rv = std::randomize(t_l) with { t_l inside {b.u}; };
      `checkd(rv, 1);
      `checkd((t_l == 70 || t_l == 80 || t_l == 90 || t_l == 100), 1'b1);
    end

    // Fixed-size arrays with a nonzero low bound, also negative, in either direction
    b.ud = '{32'd11, 32'd12, 32'd13};
    b.ua = '{32'd21, 32'd22, 32'd23};
    b.un = '{32'd31, 32'd32, 32'd33};
    repeat (20) begin
      rv = std::randomize(t_l) with { t_l inside {b.ud}; };
      `checkd(rv, 1);
      `checkd((t_l == 11 || t_l == 12 || t_l == 13), 1'b1);
      rv = std::randomize(t_l) with { t_l inside {b.ua}; };
      `checkd(rv, 1);
      `checkd((t_l == 21 || t_l == 22 || t_l == 23), 1'b1);
      rv = std::randomize(t_l) with { t_l inside {b.un}; };
      `checkd(rv, 1);
      `checkd((t_l == 31 || t_l == 32 || t_l == 33), 1'b1);
    end

    begin
      automatic InsideLowBound c = new();
      c.state_arr = '{7'd30, 7'd20, 7'd10};
      // The element at the low bound is the only one with this value; the state array shows a
      // wrong selection, the random one could also be satisfied by an element past the end
      rv = c.randomize() with { x == 7'd10; y == 7'd10; };
      `checkd(rv, 1);
      repeat (20) begin
        rv = c.randomize();
        `checkd(rv, 1);
        `checkd((c.x == 10 || c.x == 20 || c.x == 30), 1'b1);
        `checkd((c.y == 10 || c.y == 20 || c.y == 30), 1'b1);
      end
    end

    // Chained typedef (AstRefDType -> AstRefDType -> QueueDType) must
    // also be unwrapped by skipRefp().
    repeat (20) begin
      rv = std::randomize(t_l) with { t_l inside {a}; };
      `checkd(rv, 1);
      `checkd((t_l == 1 || t_l == 2 || t_l == 3), 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
