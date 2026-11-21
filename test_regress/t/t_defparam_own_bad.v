// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  parameter P = 1;
  localparam L = 1;
  int v;
  defparam NONE = 2;  // Bad, not declared
  defparam L = 2;  // Bad, localparam
  defparam v = 2;  // Bad, variable
  if (1) begin : g
    defparam P = 2;  // Bad, outside the generate block (IEEE 1800-2023 23.10.1)
  end
endmodule
