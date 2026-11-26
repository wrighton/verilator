// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Guards whose value depends on random variables, with a constant or state operand nested
// under '&&' or '||'

// verilator lint_off WIDTHEXPAND
// verilator lint_off WIDTHTRUNC
class Repro;
  rand bit signed [3:0] v0;
  rand bit signed [4:0] v1;
  constraint c {if (v0 && (v1 || 1'b1)) {v1;}}
endclass

class NestedElse;
  rand bit v0;
  constraint c2 {
    if (((-6 || v0) && v0)) {(v0 >> $unsigned(v0));}
    else {((6 == v0)) -> {((1'd0) ? v0 : v0);}}
  }
endclass
// verilator lint_on WIDTHTRUNC
// verilator lint_on WIDTHEXPAND

class ConstLeft;
  rand bit [6:0] a;
  rand bit [6:0] b;
  constraint c {if (a > 7'd20 && (1'b1 || b < 7'd9)) b == 7'd77;}
endclass

class ConstFalse;
  rand bit [6:0] a;
  rand bit [6:0] b;
  constraint c {if (a < 7'd100 || (b > 7'd3 && 1'b0)) b == 7'd5;}
endclass

class Deep;
  rand bit [14:0] a;
  rand bit [14:0] b;
  constraint c {if (a[0] && (b[1] && (a[2] || (1'b1 && b[3])))) b > 15'd1000;}
endclass

class Implication;
  rand bit [6:0] a;
  rand bit [6:0] b;
  constraint c {(a[0] && (b[1] || 1'b1)) -> b == 7'd33;}
endclass

class IfElse;
  rand bit [6:0] a;
  rand bit [6:0] b;
  constraint c {
    if (a > 7'd63 && (1'b1 || b[0])) b inside {[7'd10 : 7'd19]};
    else b inside {[7'd100 : 7'd109]};
  }
endclass

class Foreach;
  rand bit [6:0] arr[3];
  rand bit [6:0] b;
  constraint c {foreach (arr[i]) if (arr[i] > 7'd50 && (b[0] || 1'b1)) arr[i] < 7'd60;}
endclass

class StateOperand;
  rand bit [6:0] a;
  rand bit [6:0] b;
  bit en;
  constraint c {if (a[1] && (b[2] || en)) b > 7'd90;}
endclass

class StateFalse;
  rand bit [6:0] a;
  rand bit [6:0] b;
  bit dis;
  constraint c {if (a < 7'd100 || (b[0] && dis)) b > 7'd100;}
endclass

module t;
  initial begin
    automatic Repro o = new;
    int res;
    repeat (10) begin
      res = o.randomize();
      `checkd(res, 1)
      if (o.v0 != 0) `checkd(o.v1 != 0, 1)
      res = o.randomize() with {v0 != 0;};
      `checkd(res, 1)
      `checkd(o.v1 != 0, 1)
    end
  end

  initial begin
    automatic NestedElse o = new;
    int res;
    repeat (10) begin
      // The 'if' branch cannot hold, so v0 is 0, taking the 'else' branch
      res = o.randomize();
      `checkd(res, 1)
      `checkd(o.v0, 0)
    end
  end

  initial begin
    automatic ConstLeft o = new;
    int res;
    repeat (10) begin
      res = o.randomize();
      `checkd(res, 1)
      if (o.a > 20) `checkd(o.b, 77)
      res = o.randomize() with {a > 7'd20;};
      `checkd(res, 1)
      `checkd(o.b, 77)
    end
  end

  initial begin
    automatic ConstFalse o = new;
    int res;
    repeat (10) begin
      res = o.randomize();
      `checkd(res, 1)
      if (o.a < 100) `checkd(o.b, 5)
      res = o.randomize() with {a < 7'd100;};
      `checkd(res, 1)
      `checkd(o.b, 5)
    end
  end

  initial begin
    automatic Deep o = new;
    int res;
    repeat (10) begin
      res = o.randomize();
      `checkd(res, 1)
      if (o.a[0] && o.b[1] && (o.a[2] || o.b[3])) `checkd(o.b > 1000, 1)
      res = o.randomize() with {a[0] && b[1] && a[2];};
      `checkd(res, 1)
      `checkd(o.b > 1000, 1)
    end
  end

  initial begin
    automatic Implication o = new;
    int res;
    repeat (10) begin
      res = o.randomize();
      `checkd(res, 1)
      if (o.a[0]) `checkd(o.b, 33)
      res = o.randomize() with {a[0];};
      `checkd(res, 1)
      `checkd(o.b, 33)
    end
  end

  initial begin
    automatic IfElse o = new;
    int res;
    repeat (10) begin
      res = o.randomize() with {a > 7'd63;};
      `checkd(res, 1)
      `checkd(o.b inside {[10 : 19]}, 1)
      res = o.randomize() with {a <= 7'd63;};
      `checkd(res, 1)
      `checkd(o.b inside {[100 : 109]}, 1)
    end
  end

  initial begin
    automatic Foreach o = new;
    int res;
    repeat (10) begin
      res = o.randomize() with {arr[1] > 7'd50;};
      `checkd(res, 1)
      foreach (o.arr[i]) if (o.arr[i] > 50) `checkd(o.arr[i] < 60, 1)
      `checkd(o.arr[1] inside {[51 : 59]}, 1)
    end
  end

  initial begin
    automatic StateOperand o = new;
    int res;
    repeat (10) begin
      o.en = 1;
      res = o.randomize() with {a[1];};
      `checkd(res, 1)
      `checkd(o.b > 90, 1)
      // With the state operand clear, the guard holds only when b[2] is set
      o.en = 0;
      res = o.randomize() with {a[1]; b < 7'd90;};
      `checkd(res, 1)
      `checkd(o.b[2], 0)
    end
  end

  initial begin
    automatic StateFalse o = new;
    int res;
    repeat (10) begin
      o.dis = 0;
      res = o.randomize() with {a < 7'd100;};
      `checkd(res, 1)
      `checkd(o.b > 100, 1)
      // With the state operand set, the guard is false only when b[0] is clear
      o.dis = 1;
      res = o.randomize() with {a >= 7'd100; b < 7'd100;};
      `checkd(res, 1)
      `checkd(o.b[0], 0)
    end
  end

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
