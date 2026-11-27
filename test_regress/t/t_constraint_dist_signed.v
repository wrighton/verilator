// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off WIDTH
// verilator lint_off UNSIGNED
class UnsignedBounds;
  rand bit signed [7:0] x;
  constraint c {
    x dist {[9'd0 : 9'd300] := 1};
    x < 0;
  }
endclass

class OneValue;
  rand bit signed [7:0] x;
  constraint c {x dist {[33'd0 : -128] := 1};}
endclass

class Weights;  // The range holds 6 values, as many as the weight of 50
  rand bit signed [7:0] x;
  constraint c {
    x dist {
      [9'd250 : 9'd300] := 1,
      8'sd50 := 6
    };
  }
endclass

class SameWidth;
  rand bit signed [7:0] x;
  constraint c {x dist {[8'd0 : 8'd200] :/ 1};}
endclass

class TwoPieces;  // 3, 4, 5 and -128 to -1
  rand bit signed [7:0] x;
  constraint c {
    x dist {
      [9'd3 : 8'sd5] :/ 2,
      8'sd100 := 1
    };
  }
endclass

class StateBounds;
  rand bit [7:0] u;
  rand bit signed [7:0] s;
  bit [15:0] ulo = 250;
  bit [15:0] uhi = 1000;
  shortint slo = -200;
  shortint shi = -120;
  constraint c {
    u dist {
      [ulo : uhi] := 1,
      8'd7 := 6
    };
    s dist {
      [slo : shi] := 1,
      8'sd50 := 9
    };
  }
endclass

class StateMixed;  // -3 to 127, and 3 to 5 with -128 to -1, both of 131 values
  rand bit signed [7:0] x;
  rand bit signed [7:0] y;
  bit [8:0] hi = 300;
  bit [8:0] lo = 3;
  constraint c {
    x dist {
      [-8'sd3 : hi] := 1,
      -8'sd100 := 131
    };
    y dist {
      [lo : 8'sd5] := 1,
      8'sd100 := 131
    };
  }
endclass

class WideBounds;  // 250 to 255 by 70-bit bounds, as many as the weight of 7
  rand bit [7:0] u;
  rand bit signed [7:0] s;
  constraint c {
    u dist {
      [70'd250 : 70'h3f_ffff_ffff_ffff_ffff] := 1,
      8'd7 := 6,
      [9'd300 : 9'd400] := 1000
    };
    s dist {[-70'sd200 : -70'sd127] := 1};
  }
endclass

class WideExpr;  // Each item holds 11 values
  rand bit [69:0] w;
  bit [63:0] hi = 64'd20;
  constraint c {
    w dist {
      [64'd10 : hi] := 1,
      [70'd30 : 70'd40] := 1,
      70'd1000 := 11
    };
  }
endclass

class EdgeWidths;  // Expressions of 64, 65, 70 and 128 bits
  rand bit signed [63:0] s64;  // 3, 4, 5 and the 2^63 negative values
  rand bit [64:0] u65;
  rand bit [69:0] u70;
  rand bit [127:0] u128;
  constraint c {
    s64 dist {
      [64'd3 : 64'sd5] := 1,
      64'sd100 := 1
    };
    u65 dist {
      [65'd10 : 65'd20] := 1,
      65'h1_0000_0000_0000_0000 := 11
    };
    u70 dist {
      [8'sd0 : 8'sd2] := 1,
      70'd100 := 3
    };
    u128 dist {
      [128'd5 : 128'd9] :/ 1,
      128'hffff_0000_0000_0000_0000_0000_0000_0000 := 1
    };
  }
endclass

class NonIntegral;
  rand int x;
  string s = "a";
  real r = 1.5;
  constraint c {
    s dist {
      "a" := 1,
      "b" := 2
    };
    r dist {[1.0 : 2.0] := 1};
    x == 3;
  }
endclass

module t;
  int ok;

  initial begin
    begin
      UnsignedBounds c;
      c = new;
      repeat (8) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x < 0, 1'b1);
      end
    end
    begin
      OneValue c;
      c = new;
      repeat (4) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x, -128);
      end
    end
    begin
      Weights c;
      int in_range;
      c = new;
      in_range = 0;
      repeat (400) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x inside {[9'd250 : 9'd300], 8'sd50}, 1'b1);
        if (c.x != 50) ++in_range;
      end
      `checkd(in_range > 120 && in_range < 280, 1'b1);
    end
    begin
      SameWidth c;
      int negative;
      c = new;
      negative = 0;
      repeat (100) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x >= 8'd0 && c.x <= 8'd200, 1'b1);
        if (c.x < 0) ++negative;
      end
      `checkd(negative > 0, 1'b1);
    end
    begin
      TwoPieces c;
      int low;
      int negative;
      c = new;
      low = 0;
      negative = 0;
      repeat (1000) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd((c.x >= 9'd3 && c.x <= 8'sd5) || c.x == 8'sd100, 1'b1);
        if (c.x < 0) ++negative;
        if (c.x > 0 && c.x < 6) ++low;
      end
      `checkd(negative > 550 && negative < 780, 1'b1);
      `checkd(low > 0, 1'b1);
    end
    begin
      StateBounds c;
      int u_range;
      int s_range;
      c = new;
      u_range = 0;
      s_range = 0;
      repeat (400) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.u inside {[c.ulo : c.uhi], 8'd7}, 1'b1);
        `checkd(c.s inside {[c.slo : c.shi], 8'sd50}, 1'b1);
        if (c.u != 7) ++u_range;
        if (c.s != 50) ++s_range;
      end
      `checkd(u_range > 120 && u_range < 280, 1'b1);
      `checkd(s_range > 120 && s_range < 280, 1'b1);
    end
    begin
      StateMixed c;
      int x_range;
      int y_range;
      int y_low;
      c = new;
      x_range = 0;
      y_range = 0;
      y_low = 0;
      repeat (400) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd((c.x >= -8'sd3 && c.x <= c.hi) || c.x == -8'sd100, 1'b1);
        `checkd((c.y >= c.lo && c.y <= 8'sd5) || c.y == 8'sd100, 1'b1);
        if (c.x != -100) ++x_range;
        if (c.y != 100) ++y_range;
        if (c.y > 0 && c.y < 6) ++y_low;
      end
      `checkd(x_range > 120 && x_range < 280, 1'b1);
      `checkd(y_range > 120 && y_range < 280, 1'b1);
      `checkd(y_low > 0, 1'b1);
    end

    begin
      WideBounds c;
      int u_range;
      c = new;
      u_range = 0;
      repeat (400) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.u inside {[250 : 255], 7}, 1'b1);
        `checkd(c.s inside {-128, -127}, 1'b1);
        if (c.u != 7) ++u_range;
      end
      `checkd(u_range > 120 && u_range < 280, 1'b1);
    end

    begin
      WideExpr c;
      int n_value;
      c = new;
      n_value = 0;
      repeat (400) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.w inside {[10 : 20], [30 : 40], 1000}, 1'b1);
        if (c.w == 1000) ++n_value;
      end
      `checkd(n_value > 70 && n_value < 200, 1'b1);
    end

    begin
      EdgeWidths c;
      int s64_negative;
      int u65_high;
      int u70_low;
      int u128_low;
      c = new;
      s64_negative = 0;
      u65_high = 0;
      u70_low = 0;
      u128_low = 0;
      repeat (200) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.s64 < 0 || c.s64 inside {3, 4, 5}, 1'b1);
        `checkd(c.u65 inside {[10 : 20], 65'h1_0000_0000_0000_0000}, 1'b1);
        `checkd(c.u70 inside {[0 : 2], 100}, 1'b1);
        `checkd(c.u128 inside {[5 : 9], 128'hffff_0000_0000_0000_0000_0000_0000_0000}, 1'b1);
        if (c.s64 < 0) ++s64_negative;
        if (c.u65 > 20) ++u65_high;
        if (c.u70 < 3) ++u70_low;
        if (c.u128 < 10) ++u128_low;
      end
      `checkd(s64_negative > 190, 1'b1);
      `checkd(u65_high > 50 && u65_high < 150, 1'b1);
      `checkd(u70_low > 50 && u70_low < 150, 1'b1);
      `checkd(u128_low > 50 && u128_low < 150, 1'b1);
    end

    begin
      NonIntegral c;
      c = new;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, 3);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
