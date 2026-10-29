// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct {logic [7:0] a;} us_t;

  us_t us;
  string s;

  initial begin
    s = "A";
    us = us_t'(s);  // Bit-stream cast (IEEE 1800-2023 6.24.3)
  end

endmodule
