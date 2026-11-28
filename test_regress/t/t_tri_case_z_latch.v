// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A case statement on a tristate variable missing values infers a latch, as one on a two-state
// variable does, and one with all its two-state values does not

module t (
    input logic e,
    input logic [1:0] d,
    output int r,
    output int q,
    output int p
);
  wire [1:0] w;
  assign w = e ? d : 2'bzz;

  always_comb begin
    case (w)
      2'b00: r = 1;
      2'bzz: r = 2;
    endcase
  end
  always_comb begin
    casez (w)
      2'b1?: q = 1;
    endcase
  end
  always_comb begin
    case (w)
      2'b00: p = 1;
      2'b01: p = 2;
      2'b10: p = 3;
      2'b11: p = 4;
    endcase
  end
endmodule
