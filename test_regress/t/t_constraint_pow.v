// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Integral powers in a constraint have the values of IEEE 1800-2023 Table 11-4,
// as in procedural code, with x as 0

class PowTable;
  rand bit signed [7:0] b, r_m1, r_m2, r_odd, r_even, r_p3, r_p2, r_z, r_p8, r_p1000;
  rand bit [7:0] u, ru_odd, ru_even;
  constraint c_pow {
    r_m1 == b ** -1;
    r_m2 == b ** -2;
    r_odd == b ** 4'sb1111;
    r_even == b ** 4'sb1110;
    r_p3 == b ** 3;
    r_p2 == b ** 2;
    r_z == b ** 0;
    r_p8 == b ** 8;
    r_p1000 == b ** 1000;
    ru_odd == u ** 4'sb1111;
    ru_even == u ** 4'sb1110;
  }

  task check(bit signed [7:0] base);
    int randomize_result;
    randomize_result = randomize() with {b == base; u == base;};
    `checkd(randomize_result, 1);
    `checkd(r_m1, b ** -1);
    `checkd(r_m2, b ** -2);
    `checkd(r_odd, b ** 4'sb1111);
    `checkd(r_even, b ** 4'sb1110);
    `checkd(r_p3, b ** 3);
    `checkd(r_p2, b ** 2);
    `checkd(r_z, b ** 0);
    `checkd(r_p8, b ** 8);
    `checkd(r_p1000, b ** 1000);
    `checkd(ru_odd, u ** 4'sb1111);
    `checkd(ru_even, u ** 4'sb1110);
  endtask
endclass

// An unsigned exponent with its top bit set is a large positive power, which wraps
// at the width of the result; only a signed one is negative
class PowHighBit;
  rand bit signed [7:0] b, r_u32, r_u32_all, r_s32, r_s32_all, r_u64, r_s64, r_u65, r_u65_hi;
  rand bit [7:0] u, ru_u32, ru_u32_all;
  rand bit signed [64:0] w, rw_u32, rw_u65;
  constraint c_pow {
    r_u32 == b ** 32'h8000_0000;
    r_u32_all == b ** 32'hffff_ffff;
    r_s32 == b ** 32'sh8000_0000;
    r_s32_all == b ** 32'shffff_ffff;
    r_u64 == b ** 64'h8000_0000_0000_0003;
    r_s64 == b ** 64'sh8000_0000_0000_0003;
    r_u65 == b ** 65'h1_0000_0000_0000_0005;
    r_u65_hi == b ** 65'h1_0000_0000_0000_0000;
    ru_u32 == u ** 32'h8000_0000;
    ru_u32_all == u ** 32'hffff_ffff;
    rw_u32 == w ** 32'hffff_ffff;
    rw_u65 == w ** 65'h1_8000_0000_0000_0007;
  }

  task check(bit signed [7:0] base);
    int randomize_result;
    randomize_result = randomize() with {
      b == base;
      u == base;
      w == 65'(base);
    };
    `checkd(randomize_result, 1);
    `checkd(r_u32, b ** 32'h8000_0000);
    `checkd(r_u32_all, b ** 32'hffff_ffff);
    `checkd(r_s32, b ** 32'sh8000_0000);
    `checkd(r_s32_all, b ** 32'shffff_ffff);
    `checkd(r_u64, b ** 64'h8000_0000_0000_0003);
    `checkd(r_s64, b ** 64'sh8000_0000_0000_0003);
    `checkd(r_u65, b ** 65'h1_0000_0000_0000_0005);
    `checkd(r_u65_hi, b ** 65'h1_0000_0000_0000_0000);
    `checkd(ru_u32, u ** 32'h8000_0000);
    `checkd(ru_u32_all, u ** 32'hffff_ffff);
    `checkd(rw_u32, w ** 32'hffff_ffff);
    `checkd(rw_u65, w ** 65'h1_8000_0000_0000_0007);
  endtask
endclass

class PowShift;
  rand int y, r;
  constraint c {
    y inside {[-3 : 40]};
    r == 2 ** y;
  }
endclass

class PowState;
  int base = 3;
  int exponent = 4;
  rand int r;
  constraint c {r == base ** exponent;}
endclass

// A constraint with a power the solver cannot express is ignored, alone
/* verilator lint_off CONSTRAINTIGN */
class PowIgnored;
  rand bit [3:0] n;
  rand int r, s, s2, t, t2, u, v, w, x, y;
  int state = 2;
  rand bit sel;
  rand int arr[3];
  constraint c_plain {
    r == 3 ** n;
    n inside {[1 : 5]};
    r > 100;
  }
  constraint c_nonconst {
    w == r ** n;
    w == 11;
  }
  constraint c_if {
    sel == 1'b1;
    if (sel) {
      s == 3 ** n;
      s2 == 5;
    }
    s == 7;
  }
  constraint c_impl {
    sel -> t == 3 ** n;
    sel -> {
      t == 3 ** n;
      t2 == 6;
    }
    t == 9;
  }
  constraint c_cond {
    if (3 ** n > 100) u == 1;
    else u == 2;
    v == 3;
  }
  constraint c_state {
    y == r ** state;
    y == 5;
  }
  constraint c_xexp {
    x == r ** (8'd1 / 8'd0);
    x == 4;
  }
  constraint c_foreach {
    foreach (arr[i]) arr[i] == 3 ** n;
    foreach (arr[i]) arr[i] == i;
  }
endclass
/* verilator lint_on CONSTRAINTIGN */

module t;
  initial begin
    begin
      PowTable p;
      p = new;
      for (int base = -3; base <= 3; ++base) p.check(8'(base));
    end

    begin
      PowHighBit p;
      p = new;
      for (int base = -3; base <= 3; ++base) p.check(8'(base));
      p.check(8'sd5);
      p.check(-8'sd128);
    end

    begin
      PowShift p;
      int randomize_result;
      p = new;
      repeat (20) begin
        randomize_result = p.randomize();
        `checkd(randomize_result, 1);
        `checkd(p.r, 2 ** p.y);
      end
    end

    begin
      PowState p;
      int randomize_result;
      p = new;
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(p.r, p.base ** p.exponent);
    end

    begin
      PowIgnored p;
      int randomize_result;
      p = new;
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(p.n inside {[1 : 5]}, 1'b1);
      `checkd(p.r > 100, 1'b1);
      `checkd(p.w, 11);
      `checkd(p.s, 7);
      `checkd(p.s2, 5);
      `checkd(p.t, 9);
      `checkd(p.t2, 6);
    `checkd(p.v, 3);
    `checkd(p.x, 4);
    `checkd(p.y, 5);
      foreach (p.arr[i]) `checkd(p.arr[i], i);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
