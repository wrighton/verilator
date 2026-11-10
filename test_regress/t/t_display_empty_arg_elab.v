// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Empty arguments of elaboration-time severity tasks (IEEE 1800-2023 20.10, 21.2.1)
module t;
  $info(, "empty first");
  $info("a", , "b");
endmodule
