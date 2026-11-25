// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Blocks with their own clocks, each writing an element of a shared array, which the parallel
// schedule orders as a chain of writers, before logic reading the whole array
module blk #(
    parameter int ID = 0
) (
    input clk,
    input en,
    input rst_n,
    input [31:0] stat,
    output logic [31:0] dout
);
  logic gclk;
  assign gclk = clk & en;
  logic [31:0] r[8];
  for (genvar i = 0; i < 8; ++i) begin : g
    always_ff @(posedge gclk or negedge rst_n)
      if (!rst_n) r[i] <= 32'(ID * 8 + i);
      else r[i] <= r[i] + stat;
  end
  always_comb begin
    dout = 0;
    for (int i = 0; i < 8; ++i) dout ^= r[i];
  end
endmodule

module t (
    input clk,
    output logic [31:0] stat,
    output logic [31:0] probe
);
  localparam int B = 128;
  logic [B-1:0] en = '1;
  logic [B-1:0] rst_n = '0;
  always @(posedge clk) begin
    en <= {en[B-2:0], en[B-1]};
    rst_n <= '1;
  end
  logic [31:0] d[B];
  // Read at a runtime index, so the array is kept whole
  logic [$clog2(B)-1:0] sel = 0;
  always @(posedge clk) sel <= sel + 1;
  assign probe = d[sel];
  always_comb begin
    stat = 0;
    for (int b = 0; b < B; ++b) stat ^= d[b];
  end
  for (genvar b = 0; b < B; ++b) begin : g
    blk #(
        .ID(b)
    ) u (
        .clk,
        .en(en[b]),
        .rst_n(rst_n[b]),
        .stat,
        .dout(d[b])
    );
  end
endmodule
