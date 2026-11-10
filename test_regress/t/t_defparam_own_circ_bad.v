// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  parameter W = 1;
  defparam W = W + 1;  // Bad, circular
  initial $display("%0d", W);
endmodule
