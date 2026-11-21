// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    output o,
    output logic ol
);
  wire [3:0] w;
  logic a;

  // verilator lint_off IEEEMAYDEPRECATE
  initial begin
    assign ol = 1'b1;  // OK
    assign w = 4'h1;  // Bad
    assign o = 1'b1;  // Bad
    assign {a, w} = 5'h11;  // Bad on 'w'
  end
endmodule
