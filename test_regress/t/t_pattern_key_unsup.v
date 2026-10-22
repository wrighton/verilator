// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Data type keys are legal in array patterns (IEEE 1800-2023 10.9.1), but not
  // supported in associative, wildcard and dynamic array patterns
  int assoc[int] = '{int : 2};
  int wild[*] = '{int : 3};
  int dyn[];
  initial dyn = new[2] ('{int : 6});
endmodule
