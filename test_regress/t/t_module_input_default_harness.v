// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Default values of the top module's inputs, which the test's main reads before the first
// evaluation, and partly writes before it, including an unpacked array, and X bits, which
// --x-assign unique does not randomize in a default value, as it is a constant expression, and
// other unpacked types
typedef struct {
  logic [3:0] a;
  logic [3:0] b;
} pair_t;

module t (
    input clk,
    input logic [6:0] dflt_i = 7'd9,
    input logic [6:0] set_i = 7'd9,
    input logic [1:0] arr_dflt_i[2] = '{2'd1, 2'd2},
    input logic [1:0] arr_set_i[2] = '{2'd1, 2'd2},
    input logic [6:0] x_i = 7'b10x01x1,
    input pair_t pair_i = '{a: 4'd1, b: 4'd2},
    input int queue_i[$] = '{1, 2, 3},
    input logic [1:0] sparse_i[3] = '{0: 2'd1, default: 2'd2},
    input logic [3:0] z_dflt_i = 4'b1x0z,
    input logic [3:0] z_set_i = 4'b1x0z,
    output logic [6:0] dflt_o,
    output logic [6:0] set_o,
    output logic [3:0] arr_dflt_o,
    output logic [3:0] arr_set_o,
    output logic [6:0] x_o,
    output logic [7:0] other_o,
    output logic [7:0] z_o
);
  assign dflt_o = dflt_i;
  assign set_o = set_i;
  assign arr_dflt_o = {arr_dflt_i[0], arr_dflt_i[1]};
  assign arr_set_o = {arr_set_i[0], arr_set_i[1]};
  assign x_o = x_i;
  assign z_o = {z_dflt_i, z_set_i};
  assign other_o = {pair_i.a, pair_i.b} + 8'(queue_i.size()) + 8'({sparse_i[0], sparse_i[2]});
endmodule
