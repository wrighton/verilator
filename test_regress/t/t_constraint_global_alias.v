// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Rand handles to the same object: the constraints through each apply to its one set of
// variables (IEEE 1800-2023 18.5.8)

class Q;
  rand bit [7:0] x;
endclass

class M;
  rand Q q;
endclass

class P;
  rand Q a;
  rand Q b;
  rand M m;
  rand bit [3:0] arr[2];  // Not an alias of anything
  constraint c_arr {foreach (arr[i]) arr[i] < 4'd3;}
  constraint c_a {a.x < 8'd10;}
  constraint c_b {b.x > 8'd5;}
  constraint c_m {m.q.x != 8'd7;}
endclass

module t;
  initial begin
    automatic P p = new;
    automatic Q q = new;
    int randomize_result;
    p.a = q;
    p.b = q;
    p.m = new;
    p.m.q = q;
    repeat (20) begin
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(q.x inside {8'd6, 8'd8, 8'd9}, 1'b1);
      `checkd(p.arr[1] < 4'd3, 1'b1);
    end
    // No value satisfies all constraints
    randomize_result = p.randomize() with {b.x == 8'd200;};
    `checkd(randomize_result, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
