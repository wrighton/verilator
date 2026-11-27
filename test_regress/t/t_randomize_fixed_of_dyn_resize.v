// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The arrays of a fixed-size array resized after new() are solved with their current
// elements (IEEE 1800-2023 18.4)

typedef struct {
  rand bit [7:0] f;
  rand bit [7:0] g;
} us_t;

class Resized;
  rand bit [7:0] m[2][];
  rand bit [7:0] q[2][$];
  rand bit [7:0] am[2][int];
  rand us_t us[2][];
  constraint c {
    us[0][1].f == 8'h11;
    us[1][2].g == 8'h22;
    m[0][1] == 8'h5a;
    m[1][0] == 8'h33;
    q[1][2] == 8'h44;
    am[0][5] == 8'h66;
  }
  function new();
    m[0] = new[2];
    m[1] = new[1];
    q[1] = '{8'd0, 8'd0, 8'd0};
    am[0][5] = 8'd0;
    us[0] = new[2];
    us[1] = new[3];
  endfunction
endclass

// Struct elements of an array emptied after new(), so the solver must not write them
class Shrunk;
  rand us_t s[2][];
  constraint c {s[0][1].f == 8'h11;}
  function new();
    s[0] = new[2];
    s[1] = new[3];
  endfunction
endclass

module t;
  initial begin
    automatic Resized o = new;
    automatic int ok;
    ok = o.randomize();
    `checkh(ok, 1);
    `checkh(o.m[0][1], 8'h5a);
    o.m[0] = new[4];
    o.m[1] = new[3];
    o.q[1] = '{8'd1, 8'd2, 8'd3, 8'd4};
    o.am[0][9] = 8'd0;
    o.us[0] = new[4];
    o.us[1] = new[3];
    repeat (3) begin
      ok = o.randomize();
      `checkh(ok, 1);
      `checkh(o.m[0].size(), 4);
      `checkh(o.m[0][1], 8'h5a);
      `checkh(o.m[1][0], 8'h33);
      `checkh(o.q[1][2], 8'h44);
      `checkh(o.am[0][5], 8'h66);
      `checkh(o.am[0].size(), 2);
      `checkh(o.us[0][1].f, 8'h11);
      `checkh(o.us[1][2].g, 8'h22);
    end
    begin
      automatic Shrunk sh = new;
      ok = sh.randomize();
      `checkh(ok, 1);
      sh.s[1] = new[0];
      sh.s[0] = new[4];
      repeat (3) begin
        ok = sh.randomize();
        `checkh(ok, 1);
        `checkh(sh.s[0][1].f, 8'h11);
        `checkh(sh.s[1].size(), 0);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
