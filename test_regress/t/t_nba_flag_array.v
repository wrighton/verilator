// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%p exp=%p (%s != %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Unpacked arrays written element by element by NBAs at constant indices
module t (
    input clk
);
  localparam int BIG = 1000;

  typedef struct packed {
    logic [3:0] a;
    logic [2:0] b;
  } pair_t;
  typedef logic [5:0] row_t[3];
  typedef struct {
    logic [3:0] a;
    logic [3:0] b;
  } upair_t;

  int cyc = 0;
  wire [31:0] in = cyc * 32'h9e3779b9;
  // One-hot write enables, some cycles none, all in cycle 0 to initialize
  wire [7:0] wr = cyc == 0 ? '1 : cyc[3] ? '0 : 8'(1) << (cyc % 7);
  wire [BIG-1:0] wrBig = cyc == 0 ? '1 : BIG'(1) << (in % BIG);

  // Flop based FIFO storage, each entry written by its own process
  logic [2:0] fifo[5];
  // Elements wider than 64 bits
  logic [99:0] wide[3];
  // Two dimensions
  logic [7:0] grid[2][3];
  // Descending range not starting at 0
  logic [7:0] dsc[7:4];
  // Packed struct elements
  pair_t pairs[2];
  // Many elements, the shared flag scheme would make 2 variables per element
  logic [1:0] big[BIG];
  // Written by NBAs in one process, twice to the same element
  logic [7:0] two[2];
  // Typedef element type
  row_t typed[2];
  // Written a whole sub-array at a time, uses the shared flag scheme
  logic [7:0] rows[2][2];
  // Also written by a blocking assignment on the other clock edge, which a commit must not
  // overwrite unless the element was written by an NBA again
  logic [3:0] mixed[2];
  for (genvar i = 0; i < 2; ++i) begin : g_mixed
    always @(posedge clk) if (wr[i]) mixed[i] <= in[3:0];
  end
  logic [3:0] mixedExp[2];
  always @(negedge clk) begin
    if (cyc[1]) begin
      mixed[0] = ~in[3:0];
      mixedExp[0] = ~in[3:0];
    end
  end
  // Instances of the same FIFO
  logic [3:0] subOut[2];
  sub u_sub0 (.clk, .wr(wr[3:0]), .in(in[3:0]), .out(subOut[0]));
  sub u_sub1 (.clk, .wr(wr[4:1]), .in(in[7:4]), .out(subOut[1]));
  // Non-packed elements
  real reals[2];
  string strs[2];
  // Unpacked struct elements use the shadow variable scheme
  upair_t upairs[2];

  for (genvar i = 0; i < 5; ++i) begin : g_fifo
    always_ff @(posedge clk) if (wr[i]) fifo[i] <= in[2:0];
  end
  for (genvar i = 0; i < 3; ++i) begin : g_wide
    always_ff @(posedge clk) if (wr[i]) wide[i] <= {in, in, in, in[3:0]} + 100'(i);
  end
  for (genvar i = 0; i < 2; ++i) begin : g_grid_i
    for (genvar j = 0; j < 3; ++j) begin : g_grid_j
      always_ff @(posedge clk) if (wr[i*3+j]) grid[i][j] <= in[7:0] ^ 8'(i * 16 + j);
    end
  end
  for (genvar i = 4; i <= 7; ++i) begin : g_dsc
    always_ff @(posedge clk) if (wr[i-4]) dsc[i] <= in[15:8] + 8'(i);
  end
  for (genvar i = 0; i < 2; ++i) begin : g_pairs
    always_ff @(posedge clk) if (wr[i]) pairs[i] <= pair_t'(in[6:0] + 7'(i));
  end
  for (genvar i = 0; i < BIG; ++i) begin : g_big
    always_ff @(posedge clk) if (wrBig[i]) big[i] <= in[1:0] ^ 2'(i);
  end
  for (genvar i = 0; i < 2; ++i) begin : g_other
    for (genvar j = 0; j < 3; ++j) begin : g_typed
      always_ff @(posedge clk) if (wr[i*3+j]) typed[i][j] <= in[5:0] + 6'(j);
    end
    always_ff @(posedge clk) if (wr[i]) rows[i] <= '{in[7:0], in[15:8]};
    always_ff @(posedge clk) if (wr[i]) reals[i] <= real'(in[15:0]) / 4.0;
    always_ff @(posedge clk) if (wr[i]) upairs[i] <= '{in[3:0], in[7:4]};
    always_ff @(posedge clk) if (wr[i]) strs[i] <= $sformatf("%0d", in[15:0]);
  end
  always_ff @(posedge clk) begin
    if (wr[0]) two[0] <= in[7:0];
    two[1] <= in[15:8];
    if (wr[1] || wr[2]) two[0] <= in[23:16];
  end

  // Expected values, from the same inputs
  logic [2:0] fifoExp[5];
  logic [99:0] wideExp[3];
  logic [7:0] gridExp[2][3];
  logic [7:0] dscExp[7:4];
  pair_t pairsExp[2];
  logic [1:0] bigExp[BIG];
  logic [7:0] twoExp[2];
  row_t typedExp[2];
  logic [7:0] rowsExp[2][2];
  logic [3:0] subExp[2][4];
  real realsExp[2];
  string strsExp[2];
  upair_t upairsExp[2];

  always @(posedge clk) begin
    if (cyc > 0) begin
      `checkp(fifo, fifoExp);
      `checkp(wide, wideExp);
      `checkp(grid, gridExp);
      `checkp(dsc, dscExp);
      `checkp(pairs, pairsExp);
      `checkp(big, bigExp);
      `checkp(two, twoExp);
      `checkp(mixed, mixedExp);
      `checkp(typed, typedExp);
      `checkp(rows, rowsExp);
      `checkp(subOut[0], subExp[0][cyc%4]);
      `checkp(subOut[1], subExp[1][cyc%4]);
      `checkp(reals, realsExp);
      `checkp(strs, strsExp);
      `checkp(upairs, upairsExp);
    end
    for (int i = 0; i < 5; ++i) if (wr[i]) fifoExp[i] = in[2:0];
    for (int i = 0; i < 3; ++i) if (wr[i]) wideExp[i] = {in, in, in, in[3:0]} + 100'(i);
    for (int i = 0; i < 2; ++i)
    for (int j = 0; j < 3; ++j) if (wr[i*3+j]) gridExp[i][j] = in[7:0] ^ 8'(i * 16 + j);
    for (int i = 4; i <= 7; ++i) if (wr[i-4]) dscExp[i] = in[15:8] + 8'(i);
    for (int i = 0; i < 2; ++i) if (wr[i]) pairsExp[i] = pair_t'(in[6:0] + 7'(i));
    for (int i = 0; i < BIG; ++i) if (wrBig[i]) bigExp[i] = in[1:0] ^ 2'(i);
    for (int i = 0; i < 2; ++i)
    for (int j = 0; j < 3; ++j) if (wr[i*3+j]) typedExp[i][j] = in[5:0] + 6'(j);
    for (int i = 0; i < 2; ++i) if (wr[i]) rowsExp[i] = '{in[7:0], in[15:8]};
    for (int i = 0; i < 2; ++i) if (wr[i]) mixedExp[i] = in[3:0];
    for (int i = 0; i < 4; ++i) if (wr[i]) subExp[0][i] = in[3:0];
    for (int i = 0; i < 4; ++i) if (wr[i+1]) subExp[1][i] = in[7:4];
    for (int i = 0; i < 2; ++i) if (wr[i]) realsExp[i] = real'(in[15:0]) / 4.0;
    for (int i = 0; i < 2; ++i) if (wr[i]) upairsExp[i] = '{in[3:0], in[7:4]};
    for (int i = 0; i < 2; ++i) if (wr[i]) strsExp[i] = $sformatf("%0d", in[15:0]);
    if (wr[0]) twoExp[0] = in[7:0];
    twoExp[1] = in[15:8];
    if (wr[1] || wr[2]) twoExp[0] = in[23:16];
    cyc <= cyc + 1;
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub (
    input clk,
    input [3:0] wr,
    input [3:0] in,
    output [3:0] out
);
  int cyc = 0;
  logic [3:0] data[4];
  for (genvar i = 0; i < 4; ++i) begin : g_data
    always_ff @(posedge clk) if (wr[i]) data[i] <= in;
  end
  always_ff @(posedge clk) cyc <= cyc + 1;
  assign out = data[cyc%4];
endmodule
