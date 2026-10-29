// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    if ($) $stop;
  end

  // A parameter of '$' may only be used where a literal '$' may (IEEE 1800-2023 6.20.2.1)
  parameter int P = $;
  int x;
  initial x = P + 1;
endmodule
