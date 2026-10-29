// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A long sequence: NFA link resolution must stay linear in its length

`define S1 (a ##1 !a)
`define S2 (`S1 ##1 `S1)
`define S3 (`S2 ##1 `S2)
`define S4 (`S3 ##1 `S3)
`define S5 (`S4 ##1 `S4)
`define S6 (`S5 ##1 `S5)

module t (
    input clk,
    input a,
    input b
);
  assert property (@(posedge clk) `S6 ##1 b);
endmodule
