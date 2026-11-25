// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  looped looped ();

endmodule

module leaf #(
    parameter int P = 0
);
endmodule

module looped;
  leaf s ();
  defparam s.P = 1;
  looped looped ();
endmodule
