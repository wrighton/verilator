// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam in another source file than t's, which IEEE 1800-2023 23.10.1 leaves undefined
module other_file;
  defparam t.u_i.s.W = 91;
endmodule
