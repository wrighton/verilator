// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  logic \s/v ;
endmodule

module t (
    input clk
);
  logic \a/b ;
  for (genvar i = 0; i < 2; ++i) begin : \g/b
    logic \v/x ;
    always @(posedge clk) \v/x <= ~\v/x ;
  end
  sub \u/s ();
  always @(posedge clk) \a/b <= \g/b [1].\v/x ^ \u/s .\s/v ;
endmodule
