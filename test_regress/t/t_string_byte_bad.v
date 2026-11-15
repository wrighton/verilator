// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Only a string literal is converted to an unpacked array of bytes, not a string-typed
  // constant
  byte bytes[0:2];
  initial bytes = $typename(bytes);

  // A numeric constant is not converted to an unpacked array of bytes
  byte numeric_bytes[0:1];
  initial numeric_bytes = 16'h6162;
endmodule
