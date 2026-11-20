// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Nets forced from each other form a cycle of forced nets only
  // verilator lint_off UNOPTFLAT
  wire [6:0] a;
  wire [6:0] b;
  // verilator lint_on UNOPTFLAT
  initial begin
    force a = b;
    force b = a;
  end
endmodule
