// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef union {
  logic [2:0] a;
  logic [2:0] b;
} uunion_t;

module t;
  wire [2:0] o;
  // verilator lint_off PINMISSING
  sub sub (.o);
  // verilator lint_on PINMISSING
endmodule

`unconnected_drive pull1
module sub (
    input uunion_t iu,
    output wire [2:0] o
);
  assign o = iu.a;
endmodule
`nounconnected_drive
