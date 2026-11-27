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
class SameWidth;  // 0 to 127 and -128 to -56
  rand bit signed [7:0] x;
  constraint c {x dist {[8'd0 : 8'd200] := 1};}
endclass

class TwoPieces;  // 3, 4, 5 and -128 to -1, 131 values, as many as the weight of 100
  rand bit signed [7:0] x;
  constraint c {
    x dist {
      [9'd3 : 8'sd5] := 1,
      8'sd100 := 131
    };
  }
endclass

class WholeSplit;  // A :/ range of 0 to 127 and -128 to -56
  rand bit signed [7:0] x;
  constraint c {x dist {[8'd0 : 8'd200] :/ 1};}
endclass

class WholeAll;  // A :/ range of all 2^64 values
  rand bit [63:0] w;
  constraint c {w dist {[64'd0 : 64'hffff_ffff_ffff_ffff] :/ 1};}
endclass

class NarrowState;  // 2 to 9
  rand bit [7:0] x;
  bit [3:0] hi = 9;
  constraint c {x dist {[4'd2 : hi] := 1};}
endclass

class StateBound;  // Needs the solver
  rand bit signed [7:0] x;
  bit [7:0] hi = 200;
  constraint c {x dist {[8'd0 : hi] :/ 1};}
endclass

module t;
  int ok;

  initial begin
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
      `checkd(negative > 400 && negative < 580, 1'b1);
      `checkd(low > 0, 1'b1);
    end
    begin
      // IEEE 1800-2023 weighs a :/ range once, which the sampler cannot split between runs
      WholeSplit c;
      int negative;
      c = new;
      negative = 0;
      repeat (100) begin
        ok = c.randomize();
`ifdef TEST_1800_2017
        `checkd(ok, 1);
        `checkd(c.x >= 8'd0 && c.x <= 8'd200, 1'b1);
        if (c.x < 0) ++negative;
`else
        `checkd(ok, 0);
`endif
      end
`ifdef TEST_1800_2017
      `checkd(negative > 0, 1'b1);
`endif
    end
    begin
      // The sampler cannot count 2^64 values, so it leaves the dist to the solver
      WholeAll c;
      c = new;
      ok = c.randomize();
      `checkd(ok, 0);
    end
    begin
      NarrowState c;
      c = new;
      repeat (20) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x >= 2 && c.x <= 9, 1'b1);
      end
    end
    begin
      StateBound c;
      c = new;
      ok = c.randomize();
      `checkd(ok, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
