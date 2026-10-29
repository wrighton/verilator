// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct {
  logic [1:0] p;
  logic [3:0] q;
} us_t;

typedef struct {
  us_t s;
  logic [1:0] r;
} nest_t;

typedef struct {
  logic [1:0] a[2];
  logic [3:0] b;
} sa_t;

module sub_arr (
    input logic [1:0] i,
    output logic [1:0] y[2]
);
  assign y[0] = i;
  assign y[1] = ~i;
endmodule

module sub_us (
    input logic [1:0] i,
    output us_t y
);
  assign y = '{i, {i, ~i}};
endmodule

module sub_nest (
    input logic [1:0] i,
    output nest_t y
);
  assign y = '{'{~i, {~i, i}}, i};
endmodule

module sub_arr_us (
    input logic [1:0] i,
    output us_t y[2]
);
  assign y[0] = '{i, 4'h5};
  assign y[1] = '{~i, 4'ha};
endmodule

module sub_sa (
    input logic [1:0] i,
    output sa_t y
);
  assign y.a[0] = ~i;
  assign y.a[1] = i;
  assign y.b = {i, i};
endmodule

module t (
    input clk
);
  int cyc = 0;
  logic [1:0] i;
  logic [1:0] a, b, c, e, g, k, m, o, p;
  logic [3:0] d, f, l, n, q;

  // Output ports connected to assignment patterns (IEEE 1800-2023 23.3.3)
  sub_arr u_arr (.i, .y('{a, b}));
  sub_us u_us (.i, .y('{c, d}));
  sub_nest u_nest (.i, .y('{'{e, f}, g}));
  sub_arr_us u_arr_us (.i, .y('{'{k, l}, '{m, n}}));
  sub_sa u_sa (.i, .y('{'{o, p}, q}));

  assign i = cyc[1:0];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc > 0) begin
      `checkh(a, i);
      `checkh(b, ~i);
      `checkh(c, i);
      `checkh(d, {i, ~i});
      `checkh(e, ~i);
      `checkh(f, {~i, i});
      `checkh(g, i);
      `checkh(k, i);
      `checkh(l, 4'h5);
      `checkh(m, ~i);
      `checkh(n, 4'ha);
      `checkh(o, ~i);
      `checkh(p, i);
      `checkh(q, {i, i});
    end
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
