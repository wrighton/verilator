// DESCRIPTION: Verilator: DIST sites that keep procedural weighting
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
`define ZERO_TEN(n) \
  9'(n+0) := 0, 9'(n+1) := 0, 9'(n+2) := 0, 9'(n+3) := 0, 9'(n+4) := 0, \
  9'(n+5) := 0, 9'(n+6) := 0, 9'(n+7) := 0, 9'(n+8) := 0, 9'(n+9) := 0
`define ZERO_HUNDRED(n) \
  `ZERO_TEN(n), `ZERO_TEN(n+10), `ZERO_TEN(n+20), `ZERO_TEN(n+30), `ZERO_TEN(n+40), \
  `ZERO_TEN(n+50), `ZERO_TEN(n+60), `ZERO_TEN(n+70), `ZERO_TEN(n+80), `ZERO_TEN(n+90)
// verilog_format: on

class WidePick;
  rand bit [1024:0] value;
  constraint c {value dist {1025'd0 := 1, 1025'd1 := 65535};}
endclass

class WideAllZero;
  rand bit [2047:0] value;
  constraint c {value dist {2048'd0 := 0};}
endclass

class NarrowWideZero;
  rand bit [79:0] value;
  // verilator lint_off WIDTHEXPAND
  constraint c {value dist {2048'd0 := 0};}
  // verilator lint_on WIDTHEXPAND
endclass

// A zero-weight item with a random operand keeps procedural weighting.
class DependentZero;
  rand byte x, y;
  constraint c {x dist {y := 0};}
endclass

// So does a zero-weight [$:$] item.
class OpenZero;
  rand bit [7:0] values[4];
  constraint c {foreach (values[i]) values[i] dist {[$:$] := 0};}
endclass

// So does a zero-weight range whose endpoints compare in different widths.
class MixedZero;
  rand bit [7:0] x, offset;
  constraint c {
    offset == 8'd0;
    // verilator lint_off WIDTHEXPAND
    (x + offset) dist {[8'd0 : 16'd300] := 0, 8'd5 := 1};
    // verilator lint_on WIDTHEXPAND
  }
endclass

// So does a site with more items than the cap, even when their weights are all zero.
class ZeroOverCap;
  rand bit [8:0] x;
  constraint c {
    x dist {
      `ZERO_HUNDRED(0), `ZERO_HUNDRED(100), `ZERO_HUNDRED(200), `ZERO_TEN(300),
      `ZERO_TEN(310), `ZERO_TEN(320), `ZERO_TEN(330), 9'd340 := 0, 9'd341 := 0
    };
  }
endclass

// A random array size is solved in a phase of its own.
class SizedArray;
  rand byte values[];
  rand bit [3:0] kind, offset;
  constraint c_size {values.size() == 4;}
  constraint c_kind {
    offset == 0;
    (kind + offset) dist {4'd9 := 7, [4'd0:4'd8] :/ 1};
  }
endclass

class InlineSizedArray;
  rand byte values[];
  rand bit [3:0] kind, offset;
  constraint c_kind {
    offset == 0;
    (kind + offset) dist {4'd9 := 7, [4'd0:4'd8] :/ 1};
  }
endclass

module t;
  initial begin
    automatic WidePick obj = new;
    int favored;
    int ok;
    obj.srandom(239);
    repeat (8) begin
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd((obj.value inside {1025'd0, 1025'd1}), 1'b1);
      favored += int'(obj.value == 1025'd1);
    end
    `checkd(favored >= 7, 1'b1);
    begin
      automatic WideAllZero zero = new;
      automatic NarrowWideZero narrow = new;
      void'(zero.randomize());
      void'(narrow.randomize());
    end
    begin
      automatic DependentZero dependent = new;
      automatic OpenZero open_zero = new;
      automatic MixedZero mixed = new;
      ok = dependent.randomize();
      `checkd(ok, 1);
      ok = open_zero.randomize();
      `checkd(ok, 1);
      ok = mixed.randomize();
      `checkd(ok, 1);
      `checkd(mixed.x, 8'd5);
    end
    begin
      automatic ZeroOverCap over_cap = new;
      ok = over_cap.randomize();
      `checkd(ok, 1);
    end
    begin
      automatic SizedArray sized = new;
      automatic InlineSizedArray inline_sized = new;
      int heavy;
      heavy = 0;
      sized.srandom(3);
      repeat (64) begin
        ok = sized.randomize();
        `checkd(ok, 1);
        `checkd(sized.values.size(), 4);
        heavy += int'(sized.kind == 4'd9);
      end
      `checkd((heavy >= 48), 1'b1);
      heavy = 0;
      inline_sized.srandom(5);
      repeat (64) begin
        ok = inline_sized.randomize() with {values.size() == 3;};
        `checkd(ok, 1);
        `checkd(inline_sized.values.size(), 3);
        heavy += int'(inline_sized.kind == 4'd9);
      end
      `checkd((heavy >= 48), 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
