// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define EXPORT(n) \
  export "DPI-C" function dpix_other_``n; \
  function int dpix_other_``n(); return n; endfunction
// verilog_format: on

module other;
  `EXPORT(0)
  `EXPORT(1)
  `EXPORT(2)
  `EXPORT(3)
  `EXPORT(4)
  `EXPORT(5)
  `EXPORT(6)
  `EXPORT(7)
  `EXPORT(8)
  `EXPORT(9)
  `EXPORT(10)
  `EXPORT(11)
  `EXPORT(12)
  `EXPORT(13)
  `EXPORT(14)
  `EXPORT(15)
endmodule
