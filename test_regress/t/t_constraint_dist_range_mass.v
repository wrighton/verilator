// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 18.5.3: a := range weighs all its values, also those the expression
// cannot take or other constraints exclude

// [100:200] weighs 101, though x takes only 100 to 127
class Widened;
  rand bit [6:0] x;
  constraint c {x dist {[100 : 200] := 1, 50 := 1};}
endclass

// [-100:-50] weighs 51, though x takes only -64 to -50
class WidenedSigned;
  rand bit signed [6:0] x;
  constraint c {x dist {[-100 : -50] := 1, 0 := 1};}
endclass

// A range inside the type
class Inside;
  rand bit [6:0] x;
  constraint c {x dist {[100 : 110] := 1, 50 := 1};}
endclass

// [100:102] weighs 3, though only 102 is not excluded
class Excluded;
  rand bit [7:0] x;
  constraint c {
    x > 8'd101;
    x dist {[8'd100 : 8'd102] := 1, 8'd103 := 1};
  }
endclass

// The same on an expression, which the solver draws
class ExcludedSwapped;
  rand bit [7:0] x;
  constraint c {
    {x[3:0], x[7:4]} > 8'd101;
    {x[3:0], x[7:4]} dist {[8'd100 : 8'd102] := 1, 8'd103 := 1};
  }
endclass

// Other constraints leave 100, 104 and 109 of the range, which keeps its weight of 10
class Survivors;
  rand bit [7:0] x;
  constraint c {
    x inside {8'd50, 8'd100, 8'd104, 8'd109};
    x dist {[8'd100 : 8'd109] := 1, 8'd50 := 1};
  }
endclass

// A dist's weights constrain nothing, so a compatible soft constraint holds wherever it is
// declared (IEEE 1800-2023 18.5.13)
class SoftBefore;
  rand bit [6:0] x;
  constraint s {soft x == 7'd50;}
  constraint d {x dist {[100 : 200] := 1, 50 := 1};}
endclass

class SoftAfter;
  rand bit [6:0] x;
  constraint d {x dist {[100 : 200] := 1, 50 := 1};}
  constraint s {soft x == 7'd50;}
endclass

// On an expression, which the solver draws
class SoftBeforeSum;
  rand bit [6:0] x;
  bit [6:0] k = 7'd1;
  constraint s {soft x == 7'd50;}
  constraint d {(x + k) dist {[101 : 201] := 1, 51 := 1};}
endclass

// disable soft removes the dist's picks with the soft constraints on x
class DisableSum;
  rand bit [6:0] x;
  bit [6:0] k = 7'd1;
  constraint d {(x + k) dist {[101 : 111] := 1, 51 := 1};}
  constraint s {soft x == 7'd105;}
  constraint ds {disable soft x;}
endclass

// A member object's dist picks stay below the soft constraints of its container
class InnerSum;
  rand bit [6:0] x;
  bit [6:0] k = 7'd1;
  constraint d {(x + k) dist {[101 : 201] := 1, 51 := 1};}
endclass

class OuterSoft;
  rand InnerSum inner;
  constraint s {soft inner.x == 7'd50;}
  function new;
    inner = new;
  endfunction
endclass

// So do those of an object of a derived class, held by a handle of its base class
class BaseValue;
  rand bit [6:0] x;
endclass

class DerivedSum extends BaseValue;
  bit [6:0] k = 7'd1;
  constraint d {(x + k) dist {[101 : 201] := 1, 51 := 1};}
endclass

class HolderSoft;
  rand BaseValue held;
  constraint s {soft held.x == 7'd50;}
  function new;
    DerivedSum derived = new;
    held = derived;
  endfunction
endclass

// No value of these ranges can be picked: x is 64 bits, or takes none of them
class Wide;
  rand longint x;
  constraint c {x dist {[-100 : 100] := 1, 0 := 1};}
endclass

class Outside;
  rand bit signed [6:0] x;
  constraint c {x dist {[100 : 200] := 1, 0 := 1};}
endclass

class Empty;
  rand bit [6:0] x;
  constraint c {x dist {[-5 : 100] := 1, 0 := 1};}
endclass

module t;
  localparam int N = 1020;
  initial begin
    automatic Widened widened = new;
    automatic WidenedSigned widened_signed = new;
    automatic Inside inside_type = new;
    automatic Excluded excluded = new;
    automatic ExcludedSwapped swapped = new;
    automatic Survivors survivors = new;
    automatic SoftBefore soft_before = new;
    automatic SoftAfter soft_after = new;
    automatic SoftBeforeSum soft_before_sum = new;
    automatic DisableSum disable_sum = new;
    automatic OuterSoft outer_soft = new;
    automatic HolderSoft holder_soft = new;
    automatic int hits[6] = '{0, 0, 0, 0, 0, 0};
    automatic int range_hits[100:127];
    automatic int randomize_result;
    foreach (range_hits[i]) range_hits[i] = 0;
    widened.srandom(1);
    widened_signed.srandom(1);
    inside_type.srandom(1);
    excluded.srandom(1);
    swapped.srandom(1);
    survivors.srandom(1);
    repeat (N) begin
      randomize_result = widened.randomize();
      `checkd(randomize_result, 1);
      if (widened.x == 7'd50) hits[0]++;
      else range_hits[widened.x]++;
      randomize_result = widened_signed.randomize();
      `checkd(randomize_result, 1);
      `checkd(widened_signed.x inside {7'sd0, [-7'sd64 : -7'sd50]}, 1);
      hits[1] += int'(widened_signed.x == 7'sd0);
      randomize_result = inside_type.randomize();
      `checkd(randomize_result, 1);
      `checkd(inside_type.x inside {7'd50, [7'd100 : 7'd110]}, 1);
      hits[2] += int'(inside_type.x == 7'd50);
      randomize_result = excluded.randomize();
      `checkd(randomize_result, 1);
      `checkd(excluded.x inside {8'd102, 8'd103}, 1);
      hits[3] += int'(excluded.x == 8'd102);
      randomize_result = swapped.randomize();
      `checkd(randomize_result, 1);
      `checkd({swapped.x[3:0], swapped.x[7:4]} inside {8'd102, 8'd103}, 1);
      hits[4] += int'({swapped.x[3:0], swapped.x[7:4]} == 8'd102);
      randomize_result = survivors.randomize();
      `checkd(randomize_result, 1);
      `checkd(survivors.x inside {8'd50, 8'd100, 8'd104, 8'd109}, 1);
      hits[5] += int'(survivors.x == 8'd50);
    end
    repeat (100) begin
      randomize_result = soft_before.randomize();
      `checkd(randomize_result, 1);
      `checkd(soft_before.x, 50);
      randomize_result = soft_after.randomize();
      `checkd(randomize_result, 1);
      `checkd(soft_after.x, 50);
      randomize_result = soft_before_sum.randomize();
      `checkd(randomize_result, 1);
      `checkd(soft_before_sum.x, 50);
      randomize_result = disable_sum.randomize();
      `checkd(randomize_result, 1);
      `checkd(disable_sum.x inside {[7'd100 : 7'd110], 7'd50}, 1);
      randomize_result = outer_soft.randomize();
      `checkd(randomize_result, 1);
      `checkd(outer_soft.inner.x, 50);
      randomize_result = holder_soft.randomize();
      `checkd(randomize_result, 1);
      `checkd(holder_soft.held.x, 50);
    end
    // 1/102, 1/52, 1/12, 3/4, 3/4 and 1/11 of the draws. Of independent draws, all these
    // bounds hold but with probability below 1e-8.
    `check_range(hits[0], 0, 35);
    `check_range(hits[1], 0, 53);
    `check_range(hits[2], 35, 146);
    `check_range(hits[3], 675, 849);
    `check_range(hits[4], 675, 849);
    `check_range(hits[5], 41, 155);
    // The values of x in the range alike, each 1/28 of the other draws
    foreach (range_hits[i]) `check_range(range_hits[i], 6, 79);
    begin
      automatic Wide wide = new;
      automatic Outside outside = new;
      automatic Empty empty = new;
      randomize_result = wide.randomize();
      `checkd(randomize_result, 1);
      `checkd(wide.x >= -100 && wide.x <= 100, 1);
      randomize_result = outside.randomize();
      `checkd(randomize_result, 1);
      `checkd(outside.x, 0);
      // -5 is above 100 as the unsigned comparison reads it
      randomize_result = empty.randomize();
      `checkd(randomize_result, 1);
      `checkd(empty.x, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
