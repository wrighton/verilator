// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input [1:0] a,
    input [1:0] b,
    input d
);
  localparam int P0 = 0;
  localparam int P1 = 1;

  // An element select with a non-constant index writes the whole array (IEEE 1800-2023 11.5.3)

  logic m1[4];
  initial for (int i = 0; i < 4; i++) m1[i] = 1'b0;
  always_ff @(posedge clk) m1[a] <= d;  // <--- Warning

  logic m2[4];
  always_ff @(posedge clk) m2[a] <= d;
  always_ff @(posedge clk) m2[b] <= d;  // <--- Warning

  logic m3[4];
  always_comb m3[a] = d;
  initial m3[0] = 1'b0;  // <--- Warning

  logic m4[4];
  always_ff @(posedge clk) m4[a] <= d;
  assign m4[3] = 1'b0;  // <--- Warning

  logic m5[4][2];
  always_ff @(posedge clk) m5[a][0] <= d;
  always_ff @(posedge clk) m5[1][1] <= d;  // <--- Warning

  // Constant indices or slices write disjoint parts

  logic n1[4];
  always_ff @(posedge clk) n1[0] <= d;
  always_ff @(posedge clk) n1[P1] <= d;
  always_ff @(posedge clk) n1[2:3] <= '{d, d};

  logic n2[4][2];
  always_ff @(posedge clk) n2[0][a[0]] <= d;
  always_ff @(posedge clk) n2[1][b[0]] <= d;

  logic n3[4];
  for (genvar g = 0; g < 4; g++) begin : gen
    always_ff @(posedge clk) n3[g] <= d;
  end

  logic n4[4] = '{default: 0};
  always_ff @(posedge clk) n4[a] <= d;

  logic n5[4];
  always_ff @(posedge clk) begin
    n5[P0] <= d;
    n5[a] <= d;
  end

  logic n6[4];
  always @(posedge clk) n6[a] <= d;
  always @(posedge clk) n6[b] <= d;
endmodule
