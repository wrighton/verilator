// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Every element of fixed-size arrays is randomized, whatever their bounds

class Cls;
  rand bit [6:0] a[-2:1];
  rand bit [6:0] b[-3:-5];
  rand bit [6:0] c[1:-1];
  rand bit [6:0] d[0:0];
  rand bit [6:0] e[-1:1][1:-2];
endclass

module t;
  initial begin
    automatic Cls obj = new;
    bit [6:0] a[-2:1];
    bit [6:0] b[-3:-5];
    bit [6:0] c[1:-1];
    bit [6:0] d[0:0];
    bit [6:0] e[-1:1][1:-2];
    int changed[string];
    int randomize_result;
    repeat (20) begin
      a = obj.a;
      b = obj.b;
      c = obj.c;
      d = obj.d;
      e = obj.e;
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      foreach (a[i]) if (obj.a[i] != a[i]) changed[$sformatf("a%0d", i)] = 1;
      foreach (b[i]) if (obj.b[i] != b[i]) changed[$sformatf("b%0d", i)] = 1;
      foreach (c[i]) if (obj.c[i] != c[i]) changed[$sformatf("c%0d", i)] = 1;
      foreach (d[i]) if (obj.d[i] != d[i]) changed[$sformatf("d%0d", i)] = 1;
      foreach (e[i, j]) if (obj.e[i][j] != e[i][j]) changed[$sformatf("e%0d_%0d", i, j)] = 1;
    end
    `checkd(changed.size(), 23);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
