// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic go
);
  parameter int ArraySize = 512;

  logic [7:0] mem[0:ArraySize-1]  /*verilator forceable*/;
  logic [7:0] mat[0:ArraySize/8-1][0:7]  /*verilator forceable*/;

  always @(posedge go) force mem = mem;
  always @(posedge go) force mat = mat;

  // One force per element, each reading another element of the same array
  logic [7:0] disj[0:2*ArraySize-1];
  logic [7:0] disjrd[0:ArraySize-1];
  for (genvar i = 0; i < ArraySize; ++i) begin : gen_disj
    assign disjrd[i] = disj[i];
    initial force disj[i] = disj[ArraySize+i];
  end

  // One force per bit of a vector, each reading another bit, plus one of the whole vector,
  // which supplies every bit
  logic [2*ArraySize-1:0] vec;
  logic [ArraySize-1:0] vecrd;
  initial force vec = {2*ArraySize{1'b0}};
  for (genvar i = 0; i < ArraySize; ++i) begin : gen_vec
    assign vecrd[i] = vec[i];
    initial force vec[i] = vec[ArraySize+i];
  end
endmodule
