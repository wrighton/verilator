// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  localparam int DEPTH = 191;

  int cyc = 0;
  logic [7:0] wr_ptr = 0;
  logic push;
  always_comb push = cyc[0];

  // Exclude from inline a wide expression read in a loop, as the loop would
  // recompute it in every iteration
  logic [DEPTH-1:0] one_hot;
  logic [7:0] data[DEPTH];
  always_comb one_hot = push ? DEPTH'(1) << wr_ptr : '0;
  always_ff @(posedge clk)
    for (int i = 0; i < DEPTH; ++i) if (one_hot[i]) data[i] <= 8'(cyc);

  // Same, when the read in the loop is through a cheap intermediate signal
  logic [DEPTH-1:0] one_hot2;
  logic [DEPTH-65:0] one_hot2_upper;
  logic [7:0] data2[DEPTH-64];
  always_comb one_hot2 = push ? DEPTH'(1) << wr_ptr : '0;
  assign one_hot2_upper = one_hot2[DEPTH-1:64];
  always_ff @(posedge clk)
    for (int i = 0; i < DEPTH - 64; ++i) if (one_hot2_upper[i]) data2[i] <= 8'(cyc);

  // Reference model without a loop
  logic [7:0] data_ref[DEPTH];
  always_ff @(posedge clk) if (push) data_ref[wr_ptr] <= 8'(cyc);

  always_ff @(posedge clk) begin
    cyc <= cyc + 1;
    if (push) wr_ptr <= (wr_ptr == 8'(DEPTH - 1)) ? '0 : wr_ptr + 1;
    if (cyc == 2 * DEPTH + 2) begin
      for (int i = 0; i < DEPTH; ++i) begin
        `checkd(data[i], data_ref[i]);
        if (i >= 64) `checkd(data2[i-64], data_ref[i]);
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
