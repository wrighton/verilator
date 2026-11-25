// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Wide assignments of the operations split by word ranges, of whole words, and copies of
// variables and aligned selects of them with a partial top word
module sub (
    input bit clk,
    input logic [1023:0] a,
    input logic [1023:0] b,
    input logic c,
    input logic [2048:0] d,
    output logic [1023:0] x,
    output logic [1023:0] y,
    output logic [1023:0] z,
    output logic [2048:0] v,
    output logic [1000:0] w
);
  /* verilator no_inline_module */
  always @(posedge clk) begin
    x <= a ^ b;
    y <= c ? {a[499:0], b[1023:500]} : ~(a | b);
    z <= {b[3:0], a[1023:4]} ^ 1024'(a[700:0]) & {1024{c}};
    v <= d;
    w <= d[1024+:1001];
  end
endmodule

module t;
  bit clk = 0;
  int cyc = 0;
  logic [1023:0] a[2];
  logic [1023:0] b[2];
  logic c[2];
  logic [2048:0] d[2];
  logic [1023:0] x[2];
  logic [1023:0] y[2];
  logic [1023:0] z[2];
  logic [2048:0] v[2];
  logic [1000:0] w[2];

  for (genvar n = 0; n < 2; ++n) begin : gen
    sub u (
        .clk(clk),
        .a(a[n]),
        .b(b[n]),
        .c(c[n]),
        .d(d[n]),
        .x(x[n]),
        .y(y[n]),
        .z(z[n]),
        .v(v[n]),
        .w(w[n])
    );
  end

  initial forever #1 clk = ~clk;

  always @(negedge clk) begin
    if (cyc > 0) begin
      for (int n = 0; n < 2; ++n) begin
        logic [1023:0] xe;
        logic [1023:0] ye;
        logic [1023:0] ze;
        for (int i = 0; i < 1024; ++i) begin
          xe[i] = a[n][i] ^ b[n][i];
          ye[i] = c[n] ? (i < 524 ? b[n][500+i] : a[n][i-524]) : ~(a[n][i] | b[n][i]);
          ze[i] = (i < 1020 ? a[n][i+4] : b[n][i-1020]) ^ ((i < 701 ? a[n][i] : 1'b0) & c[n]);
        end
        `checkh(x[n], xe);
        `checkh(y[n], ye);
        `checkh(z[n], ze);
        `checkh(v[n], d[n]);
        `checkh(w[n], d[n][2024:1024]);
      end
    end
    cyc <= cyc + 1;
    for (int n = 0; n < 2; ++n) begin
      for (int k = 0; k < 32; ++k) begin
        a[n][32*k+:32] <= 32'(cyc * 7919 + k * 104729 + n * 31);
        b[n][32*k+:32] <= ~32'(cyc * 6271 + k * 15485863 + n * 17);
      end
      d[n] <= {1'b1, a[n] ^ 1024'(cyc), b[n]};
      c[n] <= cyc[n];
    end
    if (cyc == 12) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
