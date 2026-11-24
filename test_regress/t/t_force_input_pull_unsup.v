// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module pulled_input (
    input wire p
);
  pullup (p);
  initial begin
    #1 force p = 1'bz;
    #1 release p;
  end
endmodule

module t;
  logic enabled = 0;
  wire n;
  assign n = enabled ? 1'b0 : 1'bz;
  pulled_input u (.p(n));
  initial begin
    #3;
    enabled = 1;
    #1;
    $finish;
  end
endmodule
