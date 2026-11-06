// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d: got=%p exp=%p (%s != %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0x exp=%0x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;
  wire [31:0] in = cyc * 32'h9e3779b9;
  wire [7:0] wr = cyc == 0 ? '1 : cyc[3] ? '0 : 8'(1) << (cyc % 7);

  // Bounded sizes expose member scaling; none of these writes execute in the first cycle.
  dense #(.N(16)) u_dense16 (.clk, .cyc);
  dense #(.N(64)) u_dense64 (.clk, .cyc);
  dense #(.N(256)) u_dense256 (.clk, .cyc);
  dense #(.N(16)) u_dense16_copy (.clk, .cyc);

  typedef struct packed {
    logic [3:0] a;
    logic [2:0] b;
  } pair_t;
  typedef logic [5:0] row_t[3];
  typedef struct {
    logic [3:0] a;
    logic [3:0] b;
  } upair_t;

  logic [2:0] fifo[5];
  logic [94:0] wide[3];
  // Nonzero, negative, and mixed ascending/descending bounds on both axes.
  logic [6:0] grid[2:4][-2:-3];
  logic [6:0] dsc[7:4];
  pair_t pairs[2];
  row_t typed[2];
  logic [7:0] rows[2][2];
  real reals[2];
  string strs[2];
  upair_t upairs[2];
  logic [6:0] two[2];

  for (genvar i = 0; i < 5; ++i) begin : g_fifo
    always @(posedge clk) if (wr[i]) fifo[i] <= in[2:0];
  end
  for (genvar i = 0; i < 3; ++i) begin : g_wide
    always @(posedge clk) if (wr[i]) wide[i] <= {in, in, in[30:0]} + 95'(i);
  end
  for (genvar i = 2; i <= 4; ++i) begin : g_grid_i
    for (genvar j = -3; j <= -2; ++j) begin : g_grid_j
      always @(posedge clk) if (wr[(i-2)*2+j+3]) grid[i][j] <= in[6:0] ^ 7'(i*16+j);
    end
  end
  for (genvar i = 4; i <= 7; ++i) begin : g_dsc
    always @(posedge clk) if (wr[i-4]) dsc[i] <= in[14:8] + 7'(i);
  end
  for (genvar i = 0; i < 2; ++i) begin : g_other
    always @(posedge clk) if (wr[i]) pairs[i] <= pair_t'(in[6:0] + 7'(i));
    for (genvar j = 0; j < 3; ++j) begin : g_typed
      always @(posedge clk) if (wr[i*3+j]) typed[i][j] <= in[5:0] + 6'(j);
    end
    // Whole rows, real/string elements, and unpacked structs retain their existing schemes.
    always @(posedge clk) if (wr[i]) rows[i] <= '{in[7:0], in[15:8]};
    always @(posedge clk) if (wr[i]) reals[i] <= real'(in[15:0]) / 4.0;
    always @(posedge clk) if (wr[i]) strs[i] <= $sformatf("%0d", in[15:0]);
    always @(posedge clk) if (wr[i]) upairs[i] <= '{in[3:0], in[7:4]};
  end
  // Two writes to the same element capture each RHS and retain last-write order.
  always @(posedge clk) begin
    if (wr[0]) two[0] <= in[6:0];
    two[1] <= in[14:8];
    if (wr[1] || wr[2]) two[0] <= in[22:16];
  end

  // An unexecuted NBA must not overwrite a blocking update on the other edge.
  logic [3:0] mixed[2];
  logic [3:0] mixedExp[2];
  for (genvar i = 0; i < 2; ++i) begin : g_mixed
    always @(posedge clk) if (wr[i]) mixed[i] <= in[3:0];
  end
  always @(negedge clk) begin
    if (cyc[1]) begin
      mixed[0] = ~in[3:0];
      mixedExp[0] = ~in[3:0];
    end
  end

  // Different clocks/processes update different entries in the same flag array.
  // verilator lint_off MULTIDRIVEN
  logic [6:0] edges[2] = '{7'h31, 7'h32};
  // verilator lint_on MULTIDRIVEN
  logic [6:0] edgesExp[2] = '{7'h31, 7'h32};
  always @(posedge clk) if (cyc > 0 && wr[0]) edges[0] <= in[6:0];
  always @(negedge clk) if (cyc > 0 && wr[1]) edges[1] <= in[14:8];
  always @(negedge clk) begin
    `checkh(edges[0], edgesExp[0]);
    // Runtime selection keeps both entries in one array, so clocks share the flag arrays.
    `checkh(edges[cyc%2], edgesExp[cyc%2]);
    if (cyc > 0 && wr[1]) edgesExp[1] = in[14:8];
  end

  // A side-effectful RHS is evaluated once per executed NBA, even when overwritten.
  int calls = 0;
  function automatic logic [6:0] nextVal();
    calls = calls + 1;
    return 7'(calls);
  endfunction
  logic [6:0] effect[2];
  logic [6:0] effectExp[2];
  int callsExp = 0;
  always @(posedge clk) begin
    if (wr[0]) effect[0] <= nextVal();
    if (wr[1]) effect[1] <= nextVal();
    if (wr[2]) effect[0] <= nextVal();
  end

  always @(negedge clk) `checkh(calls, callsExp);

  // A dynamic index and a partial-element NBA exclude the entire respective target.
  logic [6:0] dynamic[2];
  logic [6:0] dynamicExp[2];
  logic [6:0] partial[2];
  logic [6:0] partialExp[2];
  always @(posedge clk) begin
    if (wr[0]) dynamic[0] <= in[6:0];
    if (wr[1]) dynamic[1] <= in[14:8];
    if (wr[2]) dynamic[cyc%2] <= in[22:16];
    if (wr[0]) partial[0] <= in[6:0];
    if (wr[1]) partial[1] <= in[14:8];
    if (wr[2]) partial[0][2:0] <= in[18:16];
  end

  // A whole-array NBA in init code requires the generic global queue for every NBA.
  logic [6:0] generic[2];
  logic [6:0] genericExp[2];
  initial generic <= '{7'h11, 7'h22};
  for (genvar i = 0; i < 2; ++i) begin : g_generic
    always @(posedge clk) if (wr[i]) generic[i] <= in[6:0] + 7'(i);
  end

  // Adjacent NBAs to one target retain the shared flag rather than full arrays.
  logic [6:0] adjacent[2];
  logic [6:0] adjacentExp[2];
  always @(posedge clk) begin
    adjacent[0] <= in[6:0];
    adjacent[1] <= in[14:8];
  end

  // Sparse and single-site writes must not allocate full flag/value arrays.
  logic [6:0] sparse[64] = '{default: 7'h55};
  logic [6:0] sparseExp[64] = '{default: 7'h55};
  logic [6:0] single[1] = '{7'h55};
  logic [6:0] singleExp[1] = '{7'h55};
  always @(posedge clk) if (cyc > 0 && wr[0]) sparse[3] <= in[6:0];
  always @(posedge clk) if (cyc > 0 && wr[1]) sparse[61] <= in[14:8];
  always @(posedge clk) if (cyc > 0 && wr[2]) single[0] <= in[22:16];

  logic [2:0] fifoExp[5];
  logic [94:0] wideExp[3];
  logic [6:0] gridExp[2:4][-2:-3];
  logic [6:0] dscExp[7:4];
  pair_t pairsExp[2];
  row_t typedExp[2];
  logic [7:0] rowsExp[2][2];
  real realsExp[2];
  string strsExp[2];
  upair_t upairsExp[2];
  logic [6:0] twoExp[2];

  always @(posedge clk) begin
    if (cyc > 0) begin
      `checkp(fifo, fifoExp);
      `checkp(wide, wideExp);
      `checkp(grid, gridExp);
      `checkp(dsc, dscExp);
      `checkp(pairs, pairsExp);
      `checkp(typed, typedExp);
      `checkp(rows, rowsExp);
      `checkp(reals, realsExp);
      `checkp(strs, strsExp);
      `checkp(upairs, upairsExp);
      `checkp(two, twoExp);
      `checkp(mixed, mixedExp);
      `checkp(effect, effectExp);
      `checkp(dynamic, dynamicExp);
      `checkp(partial, partialExp);
      `checkp(generic, genericExp);
      `checkp(adjacent, adjacentExp);
    end
    `checkp(sparse, sparseExp);
    `checkp(single, singleExp);
    `checkh(edges[1], edgesExp[1]);
    for (int i = 0; i < 5; ++i) if (wr[i]) fifoExp[i] = in[2:0];
    for (int i = 0; i < 3; ++i) if (wr[i]) wideExp[i] = {in, in, in[30:0]} + 95'(i);
    for (int i = 2; i <= 4; ++i)
      for (int j = -3; j <= -2; ++j)
        if (wr[(i-2)*2+j+3]) gridExp[i][j] = in[6:0] ^ 7'(i*16+j);
    for (int i = 4; i <= 7; ++i) if (wr[i-4]) dscExp[i] = in[14:8] + 7'(i);
    for (int i = 0; i < 2; ++i) if (wr[i]) pairsExp[i] = pair_t'(in[6:0] + 7'(i));
    for (int i = 0; i < 2; ++i)
      for (int j = 0; j < 3; ++j) if (wr[i*3+j]) typedExp[i][j] = in[5:0] + 6'(j);
    for (int i = 0; i < 2; ++i) if (wr[i]) rowsExp[i] = '{in[7:0], in[15:8]};
    for (int i = 0; i < 2; ++i) if (wr[i]) realsExp[i] = real'(in[15:0]) / 4.0;
    for (int i = 0; i < 2; ++i) if (wr[i]) strsExp[i] = $sformatf("%0d", in[15:0]);
    for (int i = 0; i < 2; ++i) if (wr[i]) upairsExp[i] = '{in[3:0], in[7:4]};
    if (wr[0]) twoExp[0] = in[6:0];
    twoExp[1] = in[14:8];
    if (wr[1] || wr[2]) twoExp[0] = in[22:16];
    for (int i = 0; i < 2; ++i) if (wr[i]) mixedExp[i] = in[3:0];
    if (cyc > 0 && wr[0]) edgesExp[0] = in[6:0];
    if (wr[0]) begin callsExp = callsExp + 1; effectExp[0] = 7'(callsExp); end
    if (wr[1]) begin callsExp = callsExp + 1; effectExp[1] = 7'(callsExp); end
    if (wr[2]) begin callsExp = callsExp + 1; effectExp[0] = 7'(callsExp); end
    if (wr[0]) dynamicExp[0] = in[6:0];
    if (wr[1]) dynamicExp[1] = in[14:8];
    if (wr[2]) dynamicExp[cyc%2] = in[22:16];
    if (wr[0]) partialExp[0] = in[6:0];
    if (wr[1]) partialExp[1] = in[14:8];
    if (wr[2]) partialExp[0][2:0] = in[18:16];
    for (int i = 0; i < 2; ++i) if (wr[i]) genericExp[i] = in[6:0] + 7'(i);
    adjacentExp[0] = in[6:0];
    adjacentExp[1] = in[14:8];
    if (cyc > 0 && wr[0]) sparseExp[3] = in[6:0];
    if (cyc > 0 && wr[1]) sparseExp[61] = in[14:8];
    if (cyc > 0 && wr[2]) singleExp[0] = in[22:16];
    cyc <= cyc + 1;
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module dense #(parameter int N = 16) (input clk, input int cyc);
  logic [6:0] data[N] = '{default: 7'h55};
  logic [6:0] expected[N] = '{default: 7'h55};
  wire [6:0] value = 7'(cyc * 17);
  for (genvar i = 0; i < N; ++i) begin : g_data
    always @(posedge clk)
      if (cyc > 0 && !cyc[2] && (cyc[0] || cyc%N == i)) data[i] <= value ^ 7'(i);
  end
  always @(posedge clk) begin
    `checkp(data, expected);
    for (int i = 0; i < N; ++i)
      if (cyc > 0 && !cyc[2] && (cyc[0] || cyc%N == i)) expected[i] = value ^ 7'(i);
  end
endmodule
