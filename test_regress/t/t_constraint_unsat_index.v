// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

class Packet;
  rand bit [7:0] a;
  rand bit [7:0] b;
  constraint c_pad {
    b > 8'd1;
    b > 8'd2;
    b > 8'd3;
    b > 8'd4;
    b > 8'd5;
    b > 8'd6;
    b > 8'd7;
    b > 8'd8;
    b > 8'd9;
    b > 8'd10;
  }
  constraint c_a {
    a > 8'd200;
    a < 8'd100;
  }
endclass

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class FrozenField;
  rand bit b;
endclass

class FrozenArray;
  rand FrozenField arr[];
  constraint c { arr[1].b == 1; }
  function new();
    arr = new[3];
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

module t;
  initial begin
    automatic Packet p = new;
    repeat (3) begin
      p.c_a.constraint_mode(0);
      if (p.randomize() == 0) $stop;
      if (!(p.b > 8'd10)) $stop;
      p.c_a.constraint_mode(1);
      if (p.randomize() != 0) $stop;
    end
    begin
      automatic FrozenArray f = new;
      int result;
      f.arr[1].b.rand_mode(0);
      result = f.randomize();
      `checkd(result, 0);
      `checkd(f.arr[1].b, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
