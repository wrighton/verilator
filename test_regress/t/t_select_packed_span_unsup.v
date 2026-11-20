// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic [3:0] data,
    input logic [1:0][65535:0] elements,
    output logic nonzero,
    output logic indexed_plus,
    output logic indexed_minus,
    output logic neighbor,
    output logic widest,
    output logic too_wide,
    input logic [1:0][1:0][268435455:0] composed,
    output logic composed_range,
    output logic composed_indexed,
    output logic composed_overflow
);
  // The constant endpoints describe an oversized result, not a wide source object.
  assign nonzero = |data[64'h2_0000_0002:0];
  assign indexed_plus = |elements[0 +: 65536];
  assign indexed_minus = |elements[1 -: 65536];
  assign neighbor = |elements[0 +: 2];
  // The widest supported result, as for a declared packed range, and one bit more
  // verilator lint_off SELRANGE
  assign widest = |data[268435455:0];
  // verilator lint_on SELRANGE
  assign too_wide = |data[268435456:0];
  // An element of 2**29 bits allows no element at all, in either form
  assign composed_range = |composed[1:0];
  assign composed_indexed = |composed[0+:2];
  assign composed_overflow = |composed[3:0];
endmodule
